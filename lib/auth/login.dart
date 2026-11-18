import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:visionmate/seeker/seeker_home.dart';
import 'package:visionmate/helper/helper_home.dart';
import 'package:visionmate/auth/register.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final FlutterTts _tts = FlutterTts();
  bool loading = false;
  bool _isVisible = false;  // For fade-in animation

  @override
  void initState() {
    super.initState();
    _initializeTts();
    _speak('Login page opened. Enter your email and password.');
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

  Future<void> login() async {
    if (_formKey.currentState!.validate()) {
      setState(() => loading = true);
      try {
        UserCredential userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );

        DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(userCred.user!.uid).get();
        String role = userDoc['role'] ?? 'seeker';
        String inviteCode = (role == 'seeker') ? (userDoc['inviteCode'] ?? '') : '';

        if (role == 'seeker') {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => SeekerHome(inviteCode: inviteCode),
              transitionsBuilder: (_, animation, __, child) => SlideTransition(
                position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(animation),
                child: child,
              ),
            ),
          );
        } else {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const HelperHome(),
              transitionsBuilder: (_, animation, __, child) => SlideTransition(
                position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(animation),
                child: child,
              ),
            ),
          );
        }
        _speak('Login successful. Welcome ${userCred.user!.displayName ?? userCred.user!.email}.');
      } on FirebaseAuthException catch (e) {
        String errorMsg = e.message ?? 'Login failed. Try again.';
        _speak('Error logging in: $errorMsg');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $errorMsg')));
      } catch (e) {
        String errorMsg = e.toString();
        _speak('Error logging in: $errorMsg');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $errorMsg')));
      } finally {
        setState(() => loading = false);
      }
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login', style: TextStyle(color: Colors.white)),
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
                  Text('Login', style: Theme.of(context).textTheme.titleLarge),
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
                      if (value == null || value.isEmpty) return 'Please enter your email';
                      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                        return 'Please enter a valid email';
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
                      if (value == null || value.isEmpty) return 'Please enter your password';
                      return null;
                    },
                    onTap: () => _speak('Password field selected.'),
                  ),
                  const SizedBox(height: 20),
                  loading
                      ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                      : AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          child: ElevatedButton(
                            onPressed: login,
                            child: const Text('Login'),
                          ),
                        ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (_, __, ___) => const RegisterPage(),
                          transitionsBuilder: (_, animation, __, child) => SlideTransition(
                            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(animation),
                            child: child,
                          ),
                        ),
                      );
                      _speak('Navigating to registration page.');
                    },
                    child: const Text('Don\'t have an account? Register', style: TextStyle(color: Colors.teal)),
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