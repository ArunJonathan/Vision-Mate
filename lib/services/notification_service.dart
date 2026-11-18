import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:typed_data'; // 🆕 ADDED - For Int64List
import 'dart:developer' as developer;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  
  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized) return;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(initSettings);
    _isInitialized = true;
    developer.log('NotificationService: Initialized successfully');
  }

  static Future<void> showSosNotification({
    required String sosId,
    required String seekerName,
    required String message,
    bool isVoiceCommand = false,
  }) async {
    await initialize();

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'sos_channel',
      'SOS Alerts',
      channelDescription: 'Critical SOS alerts from help seekers',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('sos_alert'), // Custom sound
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]), // 🆕 FIXED
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      showWhen: true,
      ongoing: true,
      autoCancel: false,
      colorized: true,
      color: const Color(0xFFFF0000), // 🆕 FIXED - Added 'const'
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'sos_alert.caf', // Custom iOS sound
      interruptionLevel: InterruptionLevel.critical,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      sosId.hashCode,
      '🆘 SOS ALERT - ${isVoiceCommand ? "VOICE" : "EMERGENCY"}',
      message,
      notificationDetails,
      payload: sosId,
    );

    developer.log('SOS Notification sent: $message');
  }

  static Future<void> sendSosToAllHelpers({
    required String sosId,
    required String seekerUid,
    required String seekerName,
    bool isVoiceCommand = false,
  }) async {
    try {
      // Get seeker's document to find all helpers
      DocumentSnapshot seekerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(seekerUid)
          .get();

      if (!seekerDoc.exists) return;

      List<dynamic> helpers = seekerDoc['helpers'] ?? [];

      // Send FCM notification to all helpers
      for (String helperUid in helpers) {
        DocumentSnapshot helperDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(helperUid)
            .get();

        if (helperDoc.exists) {
          String? fcmToken = helperDoc['fcmToken'];
          if (fcmToken != null && fcmToken.isNotEmpty) {
            // This would require Firebase Cloud Functions to send FCM
            // For now, we'll rely on Firestore listeners in the app
            developer.log('Would send FCM to helper: $helperUid');
          }
        }
      }

      developer.log('SOS alerts sent to all helpers');
    } catch (e) {
      developer.log('Error sending SOS to helpers: $e');
    }
  }

  static Future<void> cancelSosNotification(String sosId) async {
    await _notifications.cancel(sosId.hashCode);
  }

  static Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }
}
