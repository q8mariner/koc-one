package com.koc.koc_one

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * KOC ONE native alarm layer:
 *  - plays the signal tone on the ALARM stream at full volume (sounds in silent/vibrate mode)
 *  - lifts Do Not Disturb for the duration of the alarm (needs "Do Not Disturb access")
 *  - brings the app over whatever the employee is using (needs "Display over other apps")
 *  - shows over the lock screen and turns the screen on
 *  - creates the signal notification channels with setBypassDnd(true)
 */
class MainActivity : FlutterActivity() {
    companion object {
        private var player: MediaPlayer? = null
        private var savedVolume = -1
        private var savedFilter = -1
    }

    private val nm by lazy { getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager }
    private val am by lazy { getSystemService(Context.AUDIO_SERVICE) as AudioManager }
    private val alarmAttrs: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ALARM)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "koc/alarm").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(status())
                    "ensureChannels" -> result.success(ensureChannels())
                    "openDnd" -> { open(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)); result.success(null) }
                    "openOverlay" -> { open(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))); result.success(null) }
                    "openFullScreen" -> {
                        if (Build.VERSION.SDK_INT >= 34) open(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:$packageName")))
                        result.success(null)
                    }
                    "start" -> { startAlarm(call.argument<String>("kind") ?: "signal2", call.argument<Boolean>("loop") ?: true); result.success(null) }
                    "stop" -> { stopAlarm(); result.success(null) }
                    "bringToFront" -> { bringToFront(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("koc", e.message, null)
            }
        }
    }

    private fun open(i: Intent) = startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))

    private fun status(): Map<String, Boolean> = mapOf(
        "dnd" to nm.isNotificationPolicyAccessGranted,
        "overlay" to (Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(this)),
        "fullScreen" to (Build.VERSION.SDK_INT < 34 || nm.canUseFullScreenIntent()),
    )

    /** Channels are created once with their behaviour fixed; a DND-bypassing set is made after access is granted. */
    private fun ensureChannels(): String {
        if (Build.VERSION.SDK_INT < 26) return "std"
        val dnd = nm.isNotificationPolicyAccessGranted
        val suffix = if (dnd) "dnd" else "std"
        val labels = mapOf(
            "signal1" to "الإشارة 1 · طوارئ",
            "signal2" to "الإشارة 2 · إخلاء",
            "signal3" to "الإشارة 3 · زوال الخطر",
        )
        for ((kind, label) in labels) {
            val id = "koc_${kind}_$suffix"
            if (nm.getNotificationChannel(id) == null) {
                val ch = NotificationChannel(id, label, NotificationManager.IMPORTANCE_HIGH)
                ch.setSound(Uri.parse("android.resource://$packageName/raw/$kind"), alarmAttrs)
                ch.enableVibration(true)
                ch.vibrationPattern = longArrayOf(0, 800, 400, 800, 400, 800)
                ch.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                if (dnd) ch.setBypassDnd(true)
                nm.createNotificationChannel(ch)
            }
            // remove superseded channels
            nm.deleteNotificationChannel(kind)
            if (dnd) nm.deleteNotificationChannel("koc_${kind}_std")
        }
        return suffix
    }

    private fun startAlarm(kind: String, loop: Boolean) {
        stopPlayer()
        if (nm.isNotificationPolicyAccessGranted && nm.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL) {
            if (savedFilter < 0) savedFilter = nm.currentInterruptionFilter
            nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)
        }
        try {
            if (savedVolume < 0) savedVolume = am.getStreamVolume(AudioManager.STREAM_ALARM)
            am.setStreamVolume(AudioManager.STREAM_ALARM, am.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0)
        } catch (_: Exception) {}
        val resId = resources.getIdentifier(kind, "raw", packageName)
        if (resId != 0) {
            player = MediaPlayer().apply {
                setAudioAttributes(alarmAttrs)
                setDataSource(this@MainActivity, Uri.parse("android.resource://$packageName/$resId"))
                isLooping = loop
                prepare()
                start()
            }
        }
        vibrate(if (loop) 0 else -1)
        runOnUiThread { window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) }
        bringToFront()
    }

    private fun stopPlayer() {
        try { player?.stop() } catch (_: Exception) {}
        player?.release()
        player = null
        vibrator()?.cancel()
    }

    private fun stopAlarm() {
        stopPlayer()
        try {
            if (savedVolume >= 0) am.setStreamVolume(AudioManager.STREAM_ALARM, savedVolume, 0)
        } catch (_: Exception) {}
        savedVolume = -1
        if (savedFilter > 0 && nm.isNotificationPolicyAccessGranted) nm.setInterruptionFilter(savedFilter)
        savedFilter = -1
        runOnUiThread { window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) }
    }

    @Suppress("DEPRECATION")
    private fun vibrate(repeat: Int) {
        val v = vibrator() ?: return
        if (Build.VERSION.SDK_INT >= 26) v.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 800, 400), repeat))
        else v.vibrate(longArrayOf(0, 800, 400), repeat)
    }

    @Suppress("DEPRECATION")
    private fun vibrator(): Vibrator? = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator

    /** Pull the app over whatever is on screen (allowed from background with "Display over other apps"). */
    private fun bringToFront() {
        val i = Intent(this, MainActivity::class.java).addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP
        )
        startActivity(i)
    }
}
