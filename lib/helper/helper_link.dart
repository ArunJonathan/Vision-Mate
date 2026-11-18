import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'helper_home.dart';

class HelperLinkPage extends StatefulWidget {
  const HelperLinkPage({super.key});

  @override
  State<HelperLinkPage> createState() => _HelperLinkPageState();
}

class _HelperLinkPageState extends State<HelperLinkPage> {
  final inviteCodeController = TextEditingController();
  final FlutterTts _tts = FlutterTts();
  bool loading = false;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    _initializeTts();
    _speak('Link page opened. Enter the invite code from your seeker.');
    Future.delayed(const Duration(milliseconds: 300), () {
      setState(() => _isVisible = true);
    });
  }

  Future<void> _initializeTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
  }

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  Future<void> _linkHelper() async {
    final code = inviteCodeController.text.trim();
    if (code.isEmpty) {
      _speak('Please enter invite code.');
      return;
    }

    setState(() => loading = true);
    try {
      final result = await _functions.httpsCallable('linkHelperWithCode').call({
        'inviteCode': code,
      });
      if (result.data['success']) {
        _speak('Linked successfully.');
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const HelperHome(),
            transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
          ),
        );
      } else {
        _speak('Linking failed.');
      }
    } catch (e) {
      _speak('Error linking: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    inviteCodeController.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Link Helper', style: TextStyle(color: Colors.white)),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: AnimatedOpacity(
        opacity: _isVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 500),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Text('Enter Invite Code', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              TextField(
                controller: inviteCodeController,
                decoration: InputDecoration(
                  labelText: 'Invite Code',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.code, color: Colors.teal),
                  filled: true,
                  fillColor: Colors.teal[50],
                ),
                onTap: () => _speak('Invite code field selected.'),
              ),
              const SizedBox(height: 20),
              loading
                ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                : ElevatedButton(
                    onPressed: _linkHelper,
                    child: const Text('Link'),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}