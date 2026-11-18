package com.example.visionmate

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.content.IntentFilter
import android.content.BroadcastReceiver
import android.content.Context
import android.view.KeyEvent
import android.os.Handler
import android.os.Looper
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.util.Log

class MainActivity: FlutterActivity() {
    private val CHANNEL = "vision_mate/power_button"
    private val VOICE_CHANNEL = "vision_mate/voice_launch"
    private val SOUND_CHANNEL = "com.visionmate/sound"
    private var powerButtonReceiver: PowerButtonReceiver? = null
    private var lastPowerPress = 0L
    private val DOUBLE_PRESS_INTERVAL = 500L
    private var mediaPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Power Button Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initPowerButton" -> {
                    initPowerButtonListener()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        
        // Voice Launch Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOICE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkVoiceLaunch" -> {
                    checkVoiceLaunch()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Sound Player Channel - NATIVE SOUND FOR NOTIFICATIONS
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SOUND_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "playSOSSound" -> {
                    playSOSAlert()
                    result.success(true)
                }
                "stopSOSSound" -> {
                    stopSound()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun playSOSAlert() {
        try {
            // Stop any existing playback
            mediaPlayer?.release()
            mediaPlayer = null

            Log.d("MainActivity", "🔊 Starting SOS Alert sound playback...")

            // Create new MediaPlayer
            mediaPlayer = MediaPlayer.create(this, R.raw.sos_alert).apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .build()
                )
                
                // Set volume to maximum
                setVolume(1.0f, 1.0f)
                
                // Play the sound
                start()
                
                setOnCompletionListener {
                    Log.d("MainActivity", "✅ SOS Alert sound completed")
                    release()
                    mediaPlayer = null
                }
            }
            
            Log.d("MainActivity", "🔊 SOS Alert sound played successfully")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error playing SOS sound: ${e.message}")
            e.printStackTrace()
        }
    }

    private fun stopSound() {
        mediaPlayer?.release()
        mediaPlayer = null
        Log.d("MainActivity", "⏹️ SOS Alert sound stopped")
    }

    private fun initPowerButtonListener() {
        powerButtonReceiver = PowerButtonReceiver()
        powerButtonReceiver?.setCallback { onPowerButtonDoublePress() }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
        }
        registerReceiver(powerButtonReceiver, filter)
    }

    private fun onPowerButtonDoublePress() {
        Handler(Looper.getMainLooper()).post {
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, CHANNEL).invokeMethod("powerButtonDoublePress", null)
            }
        }
    }

    private fun checkVoiceLaunch() {
        val action = intent?.action
        if (action == Intent.ACTION_VOICE_COMMAND || action == Intent.ACTION_ASSIST) {
            Handler(Looper.getMainLooper()).post {
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, VOICE_CHANNEL).invokeMethod("voiceLaunch", null)
                }
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_POWER) {
            val currentTime = System.currentTimeMillis()
            if (currentTime - lastPowerPress < DOUBLE_PRESS_INTERVAL) {
                onPowerButtonDoublePress()
            }
            lastPowerPress = currentTime
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onDestroy() {
        super.onDestroy()
        stopSound()
        powerButtonReceiver?.let { unregisterReceiver(it) }
    }
}

class PowerButtonReceiver : BroadcastReceiver() {
    private var lastPressTime = 0L
    private val DOUBLE_PRESS_INTERVAL = 500L
    private var callback: (() -> Unit)? = null
    
    fun setCallback(callback: () -> Unit) {
        this.callback = callback
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_SCREEN_OFF, Intent.ACTION_SCREEN_ON -> {
                val currentTime = System.currentTimeMillis()
                if (currentTime - lastPressTime < DOUBLE_PRESS_INTERVAL) {
                    callback?.invoke()
                }
                lastPressTime = currentTime
            }
        }
    }
}
