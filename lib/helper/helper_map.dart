import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:visionmate/helper/helper_chat.dart'; // 🆕 ADDED IMPORT
import 'dart:async';

class HelperMap extends StatefulWidget {
  final String sosId;
  const HelperMap({super.key, required this.sosId});

  @override
  State<HelperMap> createState() => _HelperMapState();
}

class _HelperMapState extends State<HelperMap> {
  GoogleMapController? _mapController;
  LatLng? _seekerLocation;
  LatLng? _helperLocation;
  final Set<Marker> _markers = {};
  Timer? _helperLocationTimer;
  bool _isAcceptingHelper = false;

  @override
  void initState() {
    super.initState();
    _checkIfAcceptingHelper();
    _listenToSeekerLocation();
  }

  Future<void> _checkIfAcceptingHelper() async {
    final currentHelperUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentHelperUid == null) return;

    DocumentSnapshot doc = await FirebaseFirestore.instance
        .collection('sos_requests')
        .doc(widget.sosId)
        .get();

    if (doc.exists) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      String? acceptedHelperId = data['helperId'];
      setState(() {
        _isAcceptingHelper = acceptedHelperId == currentHelperUid;
      });

      if (_isAcceptingHelper) {
        _startHelperLocationTracking();
      }
    }
  }

  void _listenToSeekerLocation() {
    FirebaseFirestore.instance
        .collection('sos_requests')
        .doc(widget.sosId)
        .snapshots()
        .listen((doc) {
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        
        if (data['location'] != null) {
          double lat = data['location']['latitude'];
          double lng = data['location']['longitude'];
          setState(() {
            _seekerLocation = LatLng(lat, lng);
            _updateMarkers();
          });
        }

        if (data['helperLocation'] != null) {
          double lat = data['helperLocation']['latitude'];
          double lng = data['helperLocation']['longitude'];
          setState(() {
            _helperLocation = LatLng(lat, lng);
            _updateMarkers();
          });
        }

        if (_seekerLocation != null && _mapController != null) {
          _fitMapToMarkers();
        }
      }
    });
  }

  void _startHelperLocationTracking() {
    _helperLocationTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      try {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        await FirebaseFirestore.instance
            .collection('sos_requests')
            .doc(widget.sosId)
            .update({
          'helperLocation': {
            'latitude': position.latitude,
            'longitude': position.longitude,
          },
          'helperLocationUpdatedAt': FieldValue.serverTimestamp(),
        });

        setState(() {
          _helperLocation = LatLng(position.latitude, position.longitude);
          _updateMarkers();
        });
      } catch (e) {
        print('Error updating helper location: $e');
      }
    });

    _updateHelperLocationNow();
  }

  Future<void> _updateHelperLocationNow() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      await FirebaseFirestore.instance
          .collection('sos_requests')
          .doc(widget.sosId)
          .update({
        'helperLocation': {
          'latitude': position.latitude,
          'longitude': position.longitude,
        },
        'helperLocationUpdatedAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _helperLocation = LatLng(position.latitude, position.longitude);
        _updateMarkers();
      });
    } catch (e) {
      print('Error updating helper location: $e');
    }
  }

  void _updateMarkers() {
    _markers.clear();

    if (_seekerLocation != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('seeker'),
          position: _seekerLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(
            title: 'Help Seeker',
            snippet: 'Person needing assistance',
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
            title: _isAcceptingHelper ? 'You (Helper)' : 'Active Helper',
            snippet: 'Person providing assistance',
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

  @override
  void dispose() {
    _helperLocationTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isAcceptingHelper ? 'Navigate to Seeker' : 'Monitor Mode - Tracking Both',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: _isAcceptingHelper ? Colors.teal : Colors.orange,
      ),
      body: Stack(
        children: [
          _seekerLocation == null
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Colors.teal),
                      SizedBox(height: 16),
                      Text('Loading seeker location...'),
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
                    _fitMapToMarkers();
                  },
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  compassEnabled: true,
                  zoomControlsEnabled: true,
                ),
          
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('Help Seeker (Person needing help)',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isAcceptingHelper
                              ? 'You (Active Helper)'
                              : 'Active Helper (Providing assistance)',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    if (!_isAcceptingHelper) ...[
                      const SizedBox(height: 8),
                      const Text(
                        '👁️ Monitoring Mode: You can guide the helper if needed',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // 🆕 CHAT BUTTON ADDED
          Positioned(
            bottom: 80,
            right: 16,
            child: FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HelperChat(sosId: widget.sosId),
                  ),
                );
              },
              backgroundColor: Colors.teal,
              icon: const Icon(Icons.chat),
              label: const Text('Chat'),
            ),
          ),

          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              onPressed: _fitMapToMarkers,
              backgroundColor: Colors.teal,
              child: const Icon(Icons.center_focus_strong),
            ),
          ),
        ],
      ),
    );
  }
}