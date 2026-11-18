import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';

class SeekerHelpSession extends StatefulWidget {
  final String sosId;
  final String helperName;
  
  const SeekerHelpSession({
    super.key,
    required this.sosId,
    required this.helperName,
  });

  @override
  State<SeekerHelpSession> createState() => _SeekerHelpSessionState();
}

class _SeekerHelpSessionState extends State<SeekerHelpSession> {
  final TextEditingController _messageController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FlutterTts _tts = FlutterTts();
  
  GoogleMapController? _mapController;
  LatLng? _helperLocation;
  LatLng? _seekerLocation;
  final Set<Marker> _markers = {};
  bool _isMapInitialized = false; // 🆕 ADDED FLAG

  @override
  void initState() {
    super.initState();
    _initializeTts();
    _speak('Help session started with ${widget.helperName}. You can now chat and see their location.');
    _listenToLocations();
  }

  Future<void> _initializeTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  void _listenToLocations() {
    _firestore
        .collection('sos_requests')
        .doc(widget.sosId)
        .snapshots()
        .listen((doc) {
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        bool shouldUpdateCamera = false; // 🆕 ADDED FLAG

        // Update seeker location
        if (data['location'] != null) {
          double lat = data['location']['latitude'];
          double lng = data['location']['longitude'];
          
          // 🆕 CHECK IF LOCATION ACTUALLY CHANGED
          if (_seekerLocation == null || 
              _seekerLocation!.latitude != lat || 
              _seekerLocation!.longitude != lng) {
            setState(() {
              _seekerLocation = LatLng(lat, lng);
              _updateMarkers();
            });
            
            // 🆕 ONLY FIT MAP ON FIRST LOAD OR SIGNIFICANT CHANGE
            if (!_isMapInitialized) {
              shouldUpdateCamera = true;
            }
          }
        }

        // Update helper location
        if (data['helperLocation'] != null) {
          double lat = data['helperLocation']['latitude'];
          double lng = data['helperLocation']['longitude'];
          
          // 🆕 CHECK IF LOCATION ACTUALLY CHANGED
          if (_helperLocation == null || 
              _helperLocation!.latitude != lat || 
              _helperLocation!.longitude != lng) {
            setState(() {
              _helperLocation = LatLng(lat, lng);
              _updateMarkers();
            });
            
            // 🆕 ONLY FIT MAP ON FIRST LOAD
            if (!_isMapInitialized && _mapController != null) {
              shouldUpdateCamera = true;
            }
          }
        }

        // 🆕 FIT MAP ONLY WHEN NECESSARY
        if (shouldUpdateCamera && _mapController != null) {
          _fitMapToMarkers();
          _isMapInitialized = true;
        }
      }
    });
  }

  void _updateMarkers() {
    _markers.clear();

    if (_seekerLocation != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('seeker'),
          position: _seekerLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(
            title: 'You (Seeker)',
            snippet: 'Your current location',
          ),
        ),
      );
    }

    if (_helperLocation != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('helper'),
          position: _helperLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: widget.helperName,
            snippet: 'Helper coming to assist',
          ),
        ),
      );
    }
  }

  void _fitMapToMarkers() {
    if (_seekerLocation == null || _mapController == null) return;

    if (_helperLocation != null) {
      LatLngBounds bounds = LatLngBounds(
        southwest: LatLng(
          _seekerLocation!.latitude < _helperLocation!.latitude
              ? _seekerLocation!.latitude
              : _helperLocation!.latitude,
          _seekerLocation!.longitude < _helperLocation!.longitude
              ? _seekerLocation!.longitude
              : _helperLocation!.longitude,
        ),
        northeast: LatLng(
          _seekerLocation!.latitude > _helperLocation!.latitude
              ? _seekerLocation!.latitude
              : _helperLocation!.latitude,
          _seekerLocation!.longitude > _helperLocation!.longitude
              ? _seekerLocation!.longitude
              : _helperLocation!.longitude,
        ),
      );
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
    } else {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_seekerLocation!, 15),
      );
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    try {
      await _firestore
          .collection('sos_requests')
          .doc(widget.sosId)
          .collection('messages')
          .add({
        'text': _messageController.text.trim(),
        'senderId': _auth.currentUser!.uid,
        'senderType': 'seeker',
        'timestamp': FieldValue.serverTimestamp(),
      });
      _messageController.clear();
      _speak('Message sent');
    } catch (e) {
      _speak('Error sending message');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending message: $e')),
      );
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _mapController?.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Help from ${widget.helperName}',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.teal,
      ),
      body: Column(
        children: [
          // MAP SECTION
          Expanded(
            flex: 2,
            child: _seekerLocation == null
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.teal),
                        SizedBox(height: 16),
                        Text('Loading map...'),
                      ],
                    ),
                  )
                : GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _seekerLocation!,
                      zoom: 15,
                    ),
                    markers: _markers,
                    onMapCreated: (controller) {
                      _mapController = controller;
                      // 🆕 FIT MAP ONCE ON CREATION
                      Future.delayed(const Duration(milliseconds: 500), () {
                        if (!_isMapInitialized) {
                          _fitMapToMarkers();
                          _isMapInitialized = true;
                        }
                      });
                    },
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    compassEnabled: true,
                    zoomControlsEnabled: false,
                  ),
          ),

          // CHAT SECTION
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(8.0),
                  color: Colors.teal.shade50,
                  child: Row(
                    children: [
                      const Icon(Icons.chat, color: Colors.teal),
                      const SizedBox(width: 8),
                      Text(
                        'Chat with ${widget.helperName} and monitors',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('sos_requests')
                        .doc(widget.sosId)
                        .collection('messages')
                        .orderBy('timestamp', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.teal),
                        );
                      }
                      return ListView.builder(
                        reverse: true,
                        itemCount: snapshot.data!.docs.length,
                        itemBuilder: (context, index) {
                          var msg = snapshot.data!.docs[index].data()
                              as Map<String, dynamic>;
                          bool isMe = msg['senderId'] == _auth.currentUser!.uid;
                          String senderType = msg['senderType'] ?? 'helper';

                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                  vertical: 4, horizontal: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? Colors.green[100]
                                    : senderType == 'seeker'
                                        ? Colors.green[100]
                                        : Colors.blue[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!isMe)
                                    Text(
                                      senderType == 'seeker'
                                          ? 'You'
                                          : 'Helper',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  Text(msg['text'] ?? ''),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: InputDecoration(
                            hintText: 'Type your message...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            filled: true,
                            fillColor: Colors.grey[100],
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          onTap: () => _speak('Message field selected'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: Colors.teal,
                        child: IconButton(
                          icon: const Icon(Icons.send, color: Colors.white),
                          onPressed: _sendMessage,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}