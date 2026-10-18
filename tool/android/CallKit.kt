package com.koc.koc_one

import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator

/**
 * Incoming ORT call: ringtone + vibration until answered, and proper call audio once connected
 * (communication mode, loudspeaker, full call volume) — so the employee always hears ORT.
 */
object CallKit {
    private var ringtone: Ringtone? = null
    @Volatile var ringingCallId: String? = null
    @Volatile var notifId: Int = 0
    private var savedMode = -1
    private var savedVoiceVolume = -1
    private var focus: AudioFocusRequest? = null

    @Synchronized
    fun startRinging(ctx: Context, callId: String?) {
        if (ringtone?.isPlaying == true && callId == ringingCallId) return
        stopRingtoneOnly(ctx)
        ringingCallId = callId
        try {
            val uri = RingtoneManager.getActualDefaultRingtoneUri(ctx, RingtoneManager.TYPE_RINGTONE)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            val r = RingtoneManager.getRingtone(ctx, uri)
            if (r != null) {
                r.audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                if (Build.VERSION.SDK_INT >= 28) r.isLooping = true
                r.play()
                ringtone = r
            }
        } catch (_: Exception) {}
        vibrate(ctx)
    }

    @Synchronized
    fun stopRinging(ctx: Context) {
        stopRingtoneOnly(ctx)
        if (notifId != 0) {
            (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(notifId)
            notifId = 0
        }
        ringingCallId = null
    }

    private fun stopRingtoneOnly(ctx: Context) {
        try { ringtone?.stop() } catch (_: Exception) {}
        ringtone = null
        vibrator(ctx)?.cancel()
    }

    /** Route call audio to the loudspeaker at full call volume while connected. */
    @Synchronized
    fun audioStart(ctx: Context) {
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        try {
            if (savedMode < 0) savedMode = am.mode
            am.mode = AudioManager.MODE_IN_COMMUNICATION
            if (Build.VERSION.SDK_INT >= 26) {
                val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                    .setAudioAttributes(AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                    .build()
                am.requestAudioFocus(req)
                focus = req
            }
            speaker(am, true)
            if (savedVoiceVolume < 0) savedVoiceVolume = am.getStreamVolume(AudioManager.STREAM_VOICE_CALL)
            am.setStreamVolume(AudioManager.STREAM_VOICE_CALL, am.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL), 0)
            am.isMicrophoneMute = false
        } catch (_: Exception) {}
    }

    @Synchronized
    fun audioStop(ctx: Context) {
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        try {
            speaker(am, false)
            if (savedVoiceVolume >= 0) am.setStreamVolume(AudioManager.STREAM_VOICE_CALL, savedVoiceVolume, 0)
            am.mode = if (savedMode >= 0) savedMode else AudioManager.MODE_NORMAL
            if (Build.VERSION.SDK_INT >= 26) focus?.let { am.abandonAudioFocusRequest(it) }
        } catch (_: Exception) {}
        savedMode = -1
        savedVoiceVolume = -1
        focus = null
    }

    @Suppress("DEPRECATION")
    private fun speaker(am: AudioManager, on: Boolean) {
        if (Build.VERSION.SDK_INT >= 31) {
            if (on) {
                val dev = am.availableCommunicationDevices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                if (dev != null) am.setCommunicationDevice(dev)
            } else {
                am.clearCommunicationDevice()
            }
        }
        am.isSpeakerphoneOn = on
    }

    @Suppress("DEPRECATION")
    private fun vibrate(ctx: Context) {
        val v = vibrator(ctx) ?: return
        val pattern = longArrayOf(0, 1000, 1000)
        if (Build.VERSION.SDK_INT >= 26) v.vibrate(VibrationEffect.createWaveform(pattern, 0)) else v.vibrate(pattern, 0)
    }

    @Suppress("DEPRECATION")
    private fun vibrator(ctx: Context): Vibrator? = ctx.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
}
