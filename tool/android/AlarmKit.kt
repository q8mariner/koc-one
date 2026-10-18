package com.koc.koc_one

import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator

/**
 * Shared alarm sound for the app and the background service:
 * alarm-stream tone at full volume, Do Not Disturb lifted while it sounds, continuous vibration.
 */
object AlarmKit {
    private var player: MediaPlayer? = null
    private var savedVolume = -1
    private var savedFilter = -1

    /** Alarm currently sounding, and the notification the background service showed for it. */
    @Volatile var soundingId: String? = null
    @Volatile var serviceNotifId: Int = 0

    val attrs: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ALARM)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    @Synchronized
    fun start(ctx: Context, kind: String, loop: Boolean) {
        stopPlayer(ctx)
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        try {
            if (nm.isNotificationPolicyAccessGranted && nm.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL) {
                if (savedFilter < 0) savedFilter = nm.currentInterruptionFilter
                nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)
            }
        } catch (_: Exception) {}
        try {
            if (savedVolume < 0) savedVolume = am.getStreamVolume(AudioManager.STREAM_ALARM)
            am.setStreamVolume(AudioManager.STREAM_ALARM, am.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0)
        } catch (_: Exception) {}
        val resId = ctx.resources.getIdentifier(kind, "raw", ctx.packageName)
        if (resId != 0) {
            try {
                val mp = MediaPlayer()
                mp.setAudioAttributes(attrs)
                mp.setDataSource(ctx, Uri.parse("android.resource://${ctx.packageName}/$resId"))
                mp.isLooping = loop
                mp.prepare()
                mp.start()
                player = mp
            } catch (_: Exception) {}
        }
        vibrate(ctx, if (loop) 0 else -1)
    }

    @Synchronized
    fun stop(ctx: Context) {
        stopPlayer(ctx)
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        try {
            if (savedVolume >= 0) am.setStreamVolume(AudioManager.STREAM_ALARM, savedVolume, 0)
        } catch (_: Exception) {}
        savedVolume = -1
        try {
            if (savedFilter > 0 && nm.isNotificationPolicyAccessGranted) nm.setInterruptionFilter(savedFilter)
        } catch (_: Exception) {}
        savedFilter = -1
        if (serviceNotifId != 0) {
            nm.cancel(serviceNotifId)
            serviceNotifId = 0
        }
        soundingId = null
    }

    private fun stopPlayer(ctx: Context) {
        try { player?.stop() } catch (_: Exception) {}
        try { player?.release() } catch (_: Exception) {}
        player = null
        vibrator(ctx)?.cancel()
    }

    @Suppress("DEPRECATION")
    private fun vibrate(ctx: Context, repeat: Int) {
        val v = vibrator(ctx) ?: return
        if (Build.VERSION.SDK_INT >= 26) v.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 800, 400), repeat))
        else v.vibrate(longArrayOf(0, 800, 400), repeat)
    }

    @Suppress("DEPRECATION")
    private fun vibrator(ctx: Context): Vibrator? = ctx.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
}
