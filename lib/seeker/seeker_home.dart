import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:visionmate/services/sos_service.dart';
import 'package:visionmate/services/notification_service.dart';
import 'package:visionmate/seeker/seeker_dashboard.dart';
import 'package:visionmate/seeker/seeker_help_session.dart';
import 'package:visionmate/history/history_screen.dart';
import 'package:visionmate/auth/login.dart';

class SeekerHome extends StatefulWidget {
  final String inviteCode;
  const SeekerHome({super.key, required this.inviteCode});

  @override
  State<SeekerHome> createState() => _SeekerHomeState();
}

class _SeekerHomeState extends State<SeekerHome> {
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _speech = SpeechToText();
  final Battery _battery = Battery();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isSosMode = false;
  bool _isListening = false;
  String? _sosId;
  Timer? _locationTimer;
  bool _hasNavigatedToSession = false; // 🆕 ADDED FLAG
  bool _hasAnnouncedAcceptance = false; // 🆕 ADDED FLAG
  int _announcementCount = 0; // 🆕 ADDED COUNTER

  @override
  void initState() {
    super.initState();
    _initializeTts();
    _initializeSpeech();
    NotificationService.initialize();
    _speak('Vision Mate app opened.');
    SosService.startShakeListener(_activateSosMode);
    
    _initializePowerButton();
    _checkVoiceLaunch();
  }

  Future<void> _initializeTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> _initializeSpeech() async {
    await _speech.initialize();
  }

  Future<void> _initializePowerButton() async {
    const MethodChannel channel = MethodChannel('vision_mate/power_button');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'powerButtonDoublePress') {
        _activateSosMode();
      }
    });
    try {
      await channel.invokeMethod('initPowerButton');
    } catch (e) {
      print('Power button initialization failed: $e');
    }
  }

  Future<void> _checkVoiceLaunch() async {
    const MethodChannel channel = MethodChannel('vision_mate/voice_launch');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'voiceLaunch') {
        _speak('App Vision Mate opened');
      }
    });
    try {
      await channel.invokeMethod('checkVoiceLaunch');
    } catch (e) {
      print('Voice launch check failed: $e');
    }
  }

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  Future<void> _activateSosMode() async {
    setState(() => _isSosMode = true);
    _speak('SOS mode activated. Double tap to send help request.');
  }

  Future<void> _sendSosRequest({bool isVoiceCommand = false}) async {
    try {
      // 🆕 RESET FLAGS WHEN NEW REQUEST IS SENT
      setState(() {
        _hasNavigatedToSession = false;
        _hasAnnouncedAcceptance = false;
        _announcementCount = 0;
      });

      Position position = await Geolocator.getCurrentPosition();
      int batteryLevel = await _battery.batteryLevel;
      bool batteryLow = batteryLevel < 20;

      final userUid = FirebaseAuth.instance.currentUser!.uid;
      
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userUid)
          .get();
      String seekerName = userDoc['displayName'] ?? 'Help Seeker';

      DocumentReference docRef = await FirebaseFirestore.instance
          .collection('sos_requests')
          .add({
        'uid': userUid,
        'location': {
          'latitude': position.latitude,
          'longitude': position.longitude
        },
        'battery': batteryLevel,
        'batteryLow': batteryLow,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
        'isVoiceCommand': isVoiceCommand,
      });

      _sosId = docRef.id;
      _speak('Help request sent.');

      await NotificationService.sendSosToAllHelpers(
        sosId: _sosId!,
        seekerUid: userUid,
        seekerName: seekerName,
        isVoiceCommand: isVoiceCommand,
      );

      _startLiveLocationUpdate();
      _listenForAcceptance();
    } catch (e) {
      _speak('Error sending request: $e');
    }
  }

  void _startLiveLocationUpdate() {
    _locationTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (_sosId == null) return;
      try {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('sos_requests')
            .doc(_sosId)
            .get();
        if (doc.exists && doc['status'] == 'accepted') {
          Position position = await Geolocator.getCurrentPosition();
          await doc.reference.update({
            'location': {
              'latitude': position.latitude,
              'longitude': position.longitude
            },
          });
        } else if (!doc.exists || doc['status'] == 'completed') {
          timer.cancel();
        }
      } catch (e) {
        print('Error updating location: $e');
      }
    });
  }

  void _listenForAcceptance() {
    if (_sosId == null) return;
    FirebaseFirestore.instance
        .collection('sos_requests')
        .doc(_sosId)
        .snapshots()
        .listen((doc) {
      if (doc.exists) {
        String status = doc['status'] ?? 'pending';
        String? helperName = doc['helperName'];
        
        if (status == 'accepted' && helperName != null) {
          // 🆕 LIMIT ANNOUNCEMENTS TO 2 TIMES ONLY
          if (!_hasAnnouncedAcceptance || _announcementCount < 2) {
            _speak('Help request accepted by $helperName.');
            setState(() {
              _hasAnnouncedAcceptance = true;
              _announcementCount++;
            });
          }
          
          // 🆕 NAVIGATE ONLY ONCE
          if (!_hasNavigatedToSession && mounted) {
            setState(() => _hasNavigatedToSession = true);
            
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SeekerHelpSession(
                  sosId: _sosId!,
                  helperName: helperName,
                ),
              ),
            ).then((_) {
              // 🆕 RESET FLAG WHEN RETURNING FROM SESSION
              if (mounted) {
                setState(() => _hasNavigatedToSession = false);
              }
            });
          }
        } else if (status == 'completed') {
          _speak('Help request completed. Thank you.');
          setState(() {
            _isSosMode = false;
            _hasNavigatedToSession = false;
            _hasAnnouncedAcceptance = false;
            _announcementCount = 0;
          });
          _locationTimer?.cancel();
        }
      }
    });
  }

  void _startVoiceListening() async {
    if (_isListening) return;
    setState(() => _isListening = true);
    _speak('Listening for voice command. Say ask for help.');
    
    bool available = await _speech.initialize();
    if (available) {
      _speech.listen(
        onResult: (result) {
          if (result.recognizedWords.toLowerCase().contains('ask for help')) {
            _sendSosRequest(isVoiceCommand: true);
          }
        },
        listenFor: const Duration(seconds: 5),
        pauseFor: const Duration(seconds: 3),
      );
      
      Future.delayed(const Duration(seconds: 6), () {
        if (mounted) setState(() => _isListening = false);
      });
    } else {
      setState(() => _isListening = false);
      _speak('Voice recognition not available.');
    }
  }

  Future<bool> _onWillPop() async {
    bool? shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout Confirmation'),
        content: const Text('Do you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await _auth.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      }
    }
    
    return false;
  }

  @override
  void dispose() {
    _tts.stop();
    _speech.stop();
    _locationTimer?.cancel();
    SosService.stopShakeListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Seeker Home', style: TextStyle(color: Colors.white)),
          backgroundColor: Theme.of(context).colorScheme.primary,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.dashboard),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          SeekerDashboard(inviteCode: widget.inviteCode))),
            ),
            IconButton(
              icon: const Icon(Icons.history),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const HistoryScreen())),
            ),
          ],
        ),
        body: GestureDetector(
          onTap: _startVoiceListening,
          onDoubleTap: () {
            if (_isSosMode) {
              _sendSosRequest(isVoiceCommand: false);
              setState(() => _isSosMode = false);
            } else {
              _speak('Double tap detected. Activating SOS mode first.');
              _activateSosMode();
            }
          },
          child: Container(
            width: double.infinity,
            height: double.infinity,
            color: _isSosMode
                ? Colors.red.withOpacity(0.9)
                : Colors.teal.withOpacity(0.8),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isSosMode ? Icons.sos : Icons.touch_app,
                    size: 200,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _isSosMode
                        ? 'SOS MODE ACTIVE\nDouble tap to send help'
                        : _isListening
                            ? 'LISTENING...\nSay "ask for help"'
                            : 'TAP FOR VOICE COMMAND\nShake or double-press power for SOS',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_isListening)
                    const Padding(
                      padding: EdgeInsets.only(top: 20),
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}