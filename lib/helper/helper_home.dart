import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:visionmate/helper/helper_map.dart';
import 'package:visionmate/helper/helper_chat.dart';
import 'package:visionmate/auth/login.dart';

class HelperHome extends StatefulWidget {
  const HelperHome({super.key});

  @override
  State<HelperHome> createState() => _HelperHomeState();
}

class _HelperHomeState extends State<HelperHome> {
  final FlutterTts _tts = FlutterTts();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isVisible = false;
  String? _monitoringRequestId;
  bool _hasAnnouncedMonitoring = false;

  @override
  void initState() {
    super.initState();
    _initializeTts();
    _checkAndSpeak();
    _listenForMonitoringMode();
    Future.delayed(const Duration(milliseconds: 300), () {
      setState(() => _isVisible = true);
    });
  }

  Future<void> _initializeTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> _checkAndSpeak() async {
    String? linkedSeekerUid = await _getLinkedSeekerUid();
    if (linkedSeekerUid != null && linkedSeekerUid.isNotEmpty) {
      _speak('Helper interface opened. Waiting for SOS requests.');
    } else {
      _speak('No seekers linked. Please link with an invite code first.');
    }
  }

  Future<String?> _getLinkedSeekerUid() async {
    final helperUid = _auth.currentUser?.uid;
    if (helperUid == null) return null;
    
    DocumentSnapshot doc = await _firestore.collection('users').doc(helperUid).get();
    if (doc.exists) {
      return doc['linkedSeeker'];
    }
    return null;
  }

  void _listenForMonitoringMode() async {
    String? linkedSeekerUid = await _getLinkedSeekerUid();
    if (linkedSeekerUid == null) return;

    _firestore
        .collection('sos_requests')
        .where('uid', isEqualTo: linkedSeekerUid)
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.modified) {
          var data = change.doc.data() as Map<String, dynamic>;
          String status = data['status'] ?? '';
          String? helperId = data['helperId'];
          String? helperName = data['helperName'];
          
          if (status == 'accepted' && helperId != _auth.currentUser?.uid) {
            setState(() => _monitoringRequestId = change.doc.id);
            
            if (!_hasAnnouncedMonitoring) {
              _speak('$helperName has accepted the help request. You are now in monitoring mode.');
              setState(() => _hasAnnouncedMonitoring = true);
            }
            
            _showMonitoringNotification(helperName ?? 'Another helper');
          }
        }
      }
    });
  }

  void _showMonitoringNotification(String helperName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$helperName accepted the request. You\'re in monitoring mode.'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Monitor',
          textColor: Colors.white,
          onPressed: () {
            if (_monitoringRequestId != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HelperMap(sosId: _monitoringRequestId!),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  Future<void> _logout() async {
    bool? confirmLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmLogout == true) {
      try {
        await _auth.signOut();
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error logging out: $e')),
        );
      }
    }
  }

  Future<void> _acceptRequest(String sosId) async {
    final helperUid = _auth.currentUser?.uid;
    if (helperUid == null) return;

    try {
      DocumentSnapshot helperDoc = await _firestore.collection('users').doc(helperUid).get();
      String helperName = helperDoc['displayName'] ?? 'Helper';

      await _firestore.collection('sos_requests').doc(sosId).update({
        'status': 'accepted',
        'helperId': helperUid,
        'helperName': helperName,
        'acceptedAt': FieldValue.serverTimestamp(),
        'helperLocation': null,
      });

      _speak('SOS request accepted successfully.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SOS request accepted successfully!')),
      );

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => HelperMap(sosId: sosId)),
      );
    } catch (e) {
      _speak('Error accepting request.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _completeRequest(String sosId) async {
    try {
      await _firestore.collection('sos_requests').doc(sosId).update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
      });
      _speak('Request fulfilled.');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request fulfilled!')));
    } catch (e) {
      _speak('Error completing request.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<bool> _isCurrentHelperAccepted(String sosId) async {
    try {
      final currentHelperUid = _auth.currentUser?.uid;
      if (currentHelperUid == null) return false;
      
      DocumentSnapshot doc = await _firestore.collection('sos_requests').doc(sosId).get();
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        String? acceptedHelperId = data['helperId'];
        return acceptedHelperId == currentHelperUid;
      }
      return false;
    } catch (e) {
      return false;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Helper Interface', style: TextStyle(color: Colors.white)),
          backgroundColor: Theme.of(context).colorScheme.primary,
          elevation: 0,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: _logout,
              tooltip: 'Logout',
            ),
          ],
        ),
        body: AnimatedOpacity(
          opacity: _isVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 500),
          child: Column(
            children: [
              if (_monitoringRequestId != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12.0),
                  color: Colors.orange.shade100,
                  child: Row(
                    children: [
                      const Icon(Icons.visibility, color: Colors.orange),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Monitoring Mode: Another helper is handling this request',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => HelperMap(sosId: _monitoringRequestId!),
                            ),
                          );
                        },
                        child: const Text('View Map'),
                      ),
                    ],
                  ),
                ),
              
              Expanded(
                child: FutureBuilder<String?>(
                  future: _getLinkedSeekerUid(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Colors.teal));
                    }

                    if (!snapshot.hasData || snapshot.data == null || snapshot.data!.isEmpty) {
                      return const Center(
                        child: Text('No seekers linked. Use an invite code to connect.', 
                          style: TextStyle(color: Colors.teal)),
                      );
                    }

                    final linkedSeekerUid = snapshot.data!;
                    return StreamBuilder<QuerySnapshot>(
                      stream: _firestore
                          .collection('sos_requests')
                          .where('uid', isEqualTo: linkedSeekerUid)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: Colors.teal));
                        }
                        if (snapshot.hasError) {
                          return Center(child: Text('Error: ${snapshot.error}', 
                            style: const TextStyle(color: Colors.red)));
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Center(child: Text('No SOS requests.', 
                            style: TextStyle(color: Colors.teal)));
                        }

                        return ListView.builder(
                          itemCount: snapshot.data!.docs.length,
                          itemBuilder: (context, index) {
                            QueryDocumentSnapshot doc = snapshot.data!.docs[index];
                            Map<String, dynamic> sosData = doc.data() as Map<String, dynamic>;
                            String sosId = doc.id;
                            String status = sosData['status'] ?? 'pending';
                            double? latitude = sosData['location']?['latitude'];
                            double? longitude = sosData['location']?['longitude'];
                            int? battery = sosData['battery'];
                            bool batteryLow = sosData['batteryLow'] ?? false;

                            return Card(
                              margin: const EdgeInsets.all(8.0),
                              color: batteryLow ? Colors.red.shade50 : null,
                              child: ListTile(
                                title: Row(
                                  children: [
                                    Text('SOS Request - $status', 
                                      style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
                                    if (batteryLow) ...[
                                      const SizedBox(width: 8),
                                      const Icon(Icons.battery_alert, color: Colors.red, size: 20),
                                      const Text(' LOW BATTERY!', 
                                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                                    ],
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Location: ${latitude?.toStringAsFixed(4) ?? 'N/A'}, ${longitude?.toStringAsFixed(4) ?? 'N/A'}'),
                                    Text('Battery: ${battery ?? 'N/A'}%', 
                                      style: TextStyle(color: batteryLow ? Colors.red : null, fontWeight: batteryLow ? FontWeight.bold : null)),
                                  ],
                                ),
                                trailing: status == 'pending'
                                    ? ElevatedButton(
                                        onPressed: () => _acceptRequest(sosId),
                                        child: const Text('Accept'),
                                      )
                                    : FutureBuilder<bool>(
                                        future: _isCurrentHelperAccepted(sosId),
                                        builder: (context, snapshot) {
                                          if (!snapshot.hasData) {
                                            return const SizedBox.shrink();
                                          }
                                          bool isCurrentHelper = snapshot.data!;
                                          if (status == 'accepted' && isCurrentHelper) {
                                            return Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                ElevatedButton(
                                                  onPressed: () {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) => HelperMap(sosId: sosId),
                                                      ),
                                                    );
                                                  },
                                                  child: const Text('View'),
                                                ),
                                                const SizedBox(width: 4),
                                                ElevatedButton(
                                                  onPressed: () {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) => HelperChat(sosId: sosId),
                                                      ),
                                                    );
                                                  },
                                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                                                  child: const Text('Chat'),
                                                ),
                                                const SizedBox(width: 4),
                                                ElevatedButton(
                                                  onPressed: () {
                                                    _completeRequest(sosId);
                                                  },
                                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                                  child: const Text('Done'),
                                                ),
                                              ],
                                            );
                                          } else if (status == 'accepted' && !isCurrentHelper) {
                                            return ElevatedButton(
                                              onPressed: () => Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => HelperMap(sosId: sosId),
                                                ),
                                              ),
                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                                              child: const Text('Monitor'),
                                            );
                                          }
                                          return const SizedBox.shrink();
                                        },
                                      ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}