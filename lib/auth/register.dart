import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:visionmate/auth/login.dart';
import 'package:visionmate/seeker/seeker_home.dart';
import 'package:visionmate/helper/link_code_screen.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();
  final FlutterTts _tts = FlutterTts();
  String role = 'seeker';
  bool loading = false;
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    _initializeTts();
    _speak('Registration page opened. Enter your details to register.');
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

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  Future<void> register() async {
    if (_formKey.currentState!.validate()) {
      setState(() => loading = true);
      try {
        UserCredential userCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );

        String uid = userCred.user!.uid;
        String? token = await FirebaseMessaging.instance.getToken();

        if (role == 'seeker') {
          String inviteCode = _generateInviteCode().trim();

          Map<String, dynamic> seekerData = {
            'email': emailController.text.trim(),
            'role': 'seeker',
            'inviteCode': inviteCode,
            'helpers': [],
            'fcmToken': token ?? '',
            'displayName': nameController.text.trim(),
          };
          await FirebaseFirestore.instance.collection('users').doc(uid).set(seekerData);

          _speak('Registration successful. Your invite code is $inviteCode. Share it with your family.');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Registered! Your invite code is $inviteCode'),
              action: SnackBarAction(
                label: 'Copy',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: inviteCode));
                  _speak('Invite code copied to clipboard.');
                },
              ),
            ),
          );
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => SeekerHome(inviteCode: inviteCode),
              transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
            ),
          );
        } else {
          Map<String, dynamic> helperData = {
            'email': emailController.text.trim(),
            'role': 'helper',
            'linkedSeeker': null,
            'fcmToken': token ?? '',
            'displayName': nameController.text.trim(),
            'helpers': [],
          };
          await FirebaseFirestore.instance.collection('users').doc(uid).set(helperData);

          _speak('Registration successful. Please enter your invite code on the next screen.');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Registered! Please link with an invite code.')),
          );
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const LinkCodeScreen(),
              transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
            ),
          );
        }
      } on FirebaseAuthException catch (e) {
        _speak('Error registering: ${e.message ?? "Authentication failed"}');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message ?? "Authentication failed"}')));
      } catch (e) {
        _speak('Error registering: $e');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      } finally {
        setState(() => loading = false);
      }
    }
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random();
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register', style: TextStyle(color: Colors.white)),
        backgroundColor: Theme.of(context).colorScheme.primary,
        elevation: 0,
      ),
      body: AnimatedOpacity(
        opacity: _isVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 500),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  Text('Create Account', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.person, color: Colors.teal),
                      filled: true,
                      fillColor: Colors.teal[50],
                    ),
                    validator: (value) => value == null || value.isEmpty ? 'Enter your name' : null,
                    onTap: () => _speak('Name field selected.'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: emailController,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.email, color: Colors.teal),
                      filled: true,
                      fillColor: Colors.teal[50],
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Enter email';
                      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                        return 'Invalid email';
                      }
                      return null;
                    },
                    onTap: () => _speak('Email field selected.'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.lock, color: Colors.teal),
                      filled: true,
                      fillColor: Colors.teal[50],
                    ),
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Enter password';
                      if (value.length < 6) return 'At least 6 characters';
                      return null;
                    },
                    onTap: () => _speak('Password field selected.'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.person_outline, color: Colors.teal),
                      filled: true,
                      fillColor: Colors.teal[50],
                    ),
                    items: const [
                      DropdownMenuItem(value: 'seeker', child: Text('Seeker (Blind Person)')),
                      DropdownMenuItem(value: 'helper', child: Text('Helper (Family/Friend)')),
                    ],
                    validator: (value) => value == null ? 'Select a role' : null,
                    onChanged: (value) => setState(() => role = value!),
                  ),
                  const SizedBox(height: 20),
                  loading
                      ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                      : ElevatedButton(
                          onPressed: register,
                          child: const Text('Register'),
                        ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (_, __, ___) => const LoginPage(),
                          transitionsBuilder: (_, animation, __, child) => SlideTransition(
                            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(animation),
                            child: child,
                          ),
                        ),
                      );
                      _speak('Navigating to login page.');
                    },
                    child: const Text('Already have an account? Log in', style: TextStyle(color: Colors.teal)),
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