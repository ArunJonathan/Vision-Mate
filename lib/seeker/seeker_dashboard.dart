import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';

class SeekerDashboard extends StatefulWidget {
  final String inviteCode;
  const SeekerDashboard({super.key, required this.inviteCode});

  @override
  State<SeekerDashboard> createState() => _SeekerDashboardState();
}

class _SeekerDashboardState extends State<SeekerDashboard> {
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _initializeTts();
  }

  Future<void> _initializeTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
  }

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  void _shareInviteCode() {
    Share.share('Join me on Vision Mate with invite code: ${widget.inviteCode}');
    _speak('Sharing invite code.');
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seeker Dashboard', style: TextStyle(color: Colors.white)),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Your Invite Code: ${widget.inviteCode}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _shareInviteCode,
              child: const Text('Share Invite Code'),
            ),
          ],
        ),
      ),
    );
  }
}