import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:async';

class SosService {
  static StreamSubscription<AccelerometerEvent>? _shakeSubscription;
  static bool _isInitialized = false;

  static Future<void> startShakeListener(VoidCallback onShake) async {
    try {
      // Check if accelerometer is available
      bool isAvailable = await _checkAccelerometerAvailability();
      if (!isAvailable) {
        if (kDebugMode) {
          print('SosService: Accelerometer not available on this device.');
        }
        throw Exception('Accelerometer not available.');
      }

      // Cancel any existing subscription to avoid duplicates
      await stopShakeListener();

      _shakeSubscription = accelerometerEvents.listen(
        (AccelerometerEvent event) {
          double acceleration = event.x.abs() + event.y.abs() + event.z.abs();
          if (kDebugMode) {
            print('SosService: Acceleration = $acceleration');
          }
          if (acceleration > 20) {
            if (kDebugMode) {
              print('SosService: Shake detected, triggering onShake callback.');
            }
            onShake();
          }
        },
        onError: (error) {
          if (kDebugMode) {
            print('SosService: Accelerometer error: $error');
          }
        },
        cancelOnError: true,
      );
      _isInitialized = true;
      if (kDebugMode) {
        print('SosService: Shake listener initialized successfully.');
      }
    } catch (e) {
      if (kDebugMode) {
        print('SosService: Failed to start shake listener: $e');
      }
      rethrow; // Allow caller to handle the error
    }
  }

  static Future<bool> _checkAccelerometerAvailability() async {
    try {
      await accelerometerEvents.first.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          throw Exception('Accelerometer timed out.');
        },
      );
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('SosService: Accelerometer availability check failed: $e');
      }
      return false;
    }
  }

  static Future<void> stopShakeListener() async {
    if (_shakeSubscription != null) {
      await _shakeSubscription?.cancel();
      _shakeSubscription = null;
      _isInitialized = false;
      if (kDebugMode) {
        print('SosService: Shake listener stopped.');
      }
    }
  }

  static bool get isInitialized => _isInitialized;

  static void dispose() {
    stopShakeListener();
  }
}