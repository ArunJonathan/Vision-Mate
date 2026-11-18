package com.example.visionmate

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.util.Log

class SoundPlayer(private val context: Context) {
    private var mediaPlayer: MediaPlayer? = null

    fun playSOSAlert() {
        try {
            // Stop any existing playback
            mediaPlayer?.release()
            mediaPlayer = null

            // Create new MediaPlayer
            mediaPlayer = MediaPlayer.create(context, R.raw.sos_alert).apply {
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
                    release()
                    mediaPlayer = null
                }
            }
            
            Log.d("SoundPlayer", "🔊 SOS Alert sound played successfully")
        } catch (e: Exception) {
            Log.e("SoundPlayer", "❌ Error playing SOS sound: ${e.message}")
        }
    }

    fun stop() {
        mediaPlayer?.release()
        mediaPlayer = null
    }
}
