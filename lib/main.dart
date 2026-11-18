import 'dart:developer' as developer;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:visionmate/auth/login.dart';
import 'package:visionmate/helper/helper_home.dart';
import 'package:visionmate/seeker/seeker_home.dart';
import 'package:visionmate/helper/link_code_screen.dart';
import 'package:visionmate/history/history_screen.dart';
import 'package:visionmate/firebase_options.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const MethodChannel _soundChannel = MethodChannel('com.visionmate/sound');

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  developer.log('📩 Background message: ${message.messageId}');
  await _showNotification(message);
  await _playNativeSound();
}

Future<void> _playNativeSound() async {
  try {
    developer.log('🔊 Calling native sound player...');
    await _soundChannel.invokeMethod('playSOSSound');
    developer.log('✅ Native SOS sound triggered successfully');
  } catch (e) {
    developer.log('❌ Error playing native sound: $e');
  }
}

Future<void> _showNotification(RemoteMessage message) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'sos_emergency_final',
    'SOS Emergency Alerts',
    channelDescription: 'Critical SOS emergency alerts',
    importance: Importance.max,
    priority: Priority.high,
    playSound: false,
    enableVibration: true,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
    visibility: NotificationVisibility.public,
    showWhen: true,
    autoCancel: false,
    colorized: true,
    color: Color(0xFFFF0000),
  );

  const NotificationDetails notificationDetails = NotificationDetails(
    android: androidDetails,
  );

  await flutterLocalNotificationsPlugin.show(
    message.hashCode,
    message.notification?.title ?? '🆘 SOS ALERT',
    message.notification?.body ?? 'Someone needs help!',
    notificationDetails,
  );
  
  developer.log('📢 Notification shown');
}

Future<void> _handleAppLaunch() async {
  const MethodChannel channel = MethodChannel('vision_mate/voice_launch');
  channel.setMethodCallHandler((call) async {
    if (call.method == 'voiceLaunch') {
      FlutterTts tts = FlutterTts();
      await tts.setLanguage('en-US');
      await tts.setSpeechRate(0.5);
      await tts.speak('App Vision Mate opened');
      developer.log('Voice launch detected - TTS feedback provided');
    }
  });
}

Future<void> _saveFcmToken() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      developer.log('No user logged in, skipping FCM token save');
      return;
    }

    String? token = await FirebaseMessaging.instance.getToken();
    if (token == null) {
      developer.log('FCM token is null');
      return;
    }

    developer.log('FCM Token obtained: $token');

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({'fcmToken': token}, SetOptions(merge: true));

    developer.log('✅ FCM token saved to Firestore for user: ${user.uid}');
  } catch (e) {
    developer.log('❌ Error saving FCM token: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    developer.log('✅ Firebase initialized successfully');

    await _handleAppLaunch();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);
    await flutterLocalNotificationsPlugin.initialize(initSettings);

    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin != null) {
      try {
        await androidPlugin.deleteNotificationChannel('sos_channel_fcm');
        await androidPlugin.deleteNotificationChannel('sos_channel');
        await androidPlugin.deleteNotificationChannel('sos_channel_v2');
        await androidPlugin.deleteNotificationChannel('sos_emergency_v3');
        developer.log('✅ Old notification channels deleted');
      } catch (e) {
        developer.log('Old channels cleanup: $e');
      }

      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'sos_emergency_final',
        'SOS Emergency Alerts',
        description: 'Critical SOS emergency alerts',
        importance: Importance.max,
        sound: RawResourceAndroidNotificationSound('sos_alert'),
        enableVibration: true,
        enableLights: true,
        ledColor: Color(0xFFFF0000),
      );

      await androidPlugin.createNotificationChannel(channel);
      developer.log('✅ Notification channel created: sos_emergency_final');
    }

    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);

    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    developer.log('Notification permission: ${settings.authorizationStatus}');

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      developer.log('📩 Foreground message: ${message.notification?.title}');
      await _showNotification(message);
      await _playNativeSound();
    });

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      developer.log('🔄 FCM Token refreshed: $newToken');
      _saveFcmToken();
    });

    await _saveFcmToken();

  } catch (e) {
    developer.log('❌ Firebase initialization error: $e');
  }

  FlutterError.onError = (details) {
    developer.log('Flutter Error: ${details.exceptionAsString()}', stackTrace: details.stack);
  };

  developer.log('🚀 Starting VisionMate app...');
  runApp(const VisionMateApp());
}

class VisionMateApp extends StatefulWidget {
  const VisionMateApp({super.key});

  @override
  State<VisionMateApp> createState() => _VisionMateAppState();
}

class _VisionMateAppState extends State<VisionMateApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _saveFcmToken();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _saveFcmToken();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vision Mate',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          primary: Colors.teal[700],
          secondary: Colors.blue,
          background: Colors.grey[100],
        ),
        scaffoldBackgroundColor: Colors.grey[50],
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 16, color: Colors.black87),
          titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            elevation: 4,
          ),
        ),
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
          color: Colors.white,
        ),
      ),
      home: FutureBuilder<User?>(
        future: _getCurrentUser(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.teal),
                    SizedBox(height: 20),
                    Text('Loading Vision Mate...', style: TextStyle(fontSize: 18)),
                  ],
                ),
              ),
            );
          }
          
          final user = snapshot.data;
          if (user == null) {
            return const LoginPage();
          }
          
          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.teal),
                        SizedBox(height: 20),
                        Text('Preparing your interface...', style: TextStyle(fontSize: 18)),
                      ],
                    ),
                  ),
                );
              }
              
              if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
                return const LoginPage();
              }
              
              final data = snapshot.data!.data() as Map<String, dynamic>?;
              if (data == null || !data.containsKey('role')) {
                return const LinkCodeScreen();
              }
              
              if (data['role'] == 'seeker') {
                String inviteCode = data['inviteCode']?.toString().trim() ?? _generateInviteCode();
                if (data['inviteCode'] == null) {
                  FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                    'inviteCode': inviteCode,
                  }).catchError((e) {
                    developer.log('Error saving inviteCode: $e');
                  });
                }
                return SeekerHome(inviteCode: inviteCode);
              } else {
                if (data['linkedSeeker'] == null || data['linkedSeeker'].isEmpty) {
                  return const LinkCodeScreen();
                }
                return const HelperHome();
              }
            },
          );
        },
      ),
    );
  }

  Future<User?> _getCurrentUser() async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      return FirebaseAuth.instance.currentUser;
    } catch (e) {
      developer.log('Error getting current user: $e');
      return null;
    }
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(Iterable.generate(
      6,
      (_) => chars.codeUnitAt(random.nextInt(chars.length)),
    ));
  }
}
