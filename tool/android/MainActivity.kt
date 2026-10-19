package com.koc.koc_one

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * ONE native layer:
 *  - alarm tone / DND / vibration through AlarmKit (shared with the background service)
 *  - brings the app over other apps, shows over the lock screen, keeps the screen on during an alarm
 *  - creates the signal notification channels with setBypassDnd(true)
 *  - registers the device with AlarmWatchService so alarms arrive while the app is closed
 */
class MainActivity : FlutterFragmentActivity() {
    private val nm by lazy { getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
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
                    "openBattery" -> {
                        @Suppress("BatteryLife")
                        val i = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
                        open(i)
                        result.success(null)
                    }
                    "start" -> {
                        AlarmKit.start(this, call.argument<String>("kind") ?: "signal2", call.argument<Boolean>("loop") ?: true)
                        AlarmKit.soundingId = call.argument<String>("id")
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        bringToFront()
                        result.success(null)
                    }
                    "stop" -> {
                        AlarmKit.stop(this)
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        result.success(null)
                    }
                    "bringToFront" -> { bringToFront(); result.success(null) }
                    "startRinging" -> { CallKit.startRinging(this, call.argument<String>("id")); result.success(null) }
                    "stopRinging" -> { CallKit.stopRinging(this); result.success(null) }
                    "callAudioStart" -> { CallKit.audioStart(this); result.success(null) }
                    "callAudioStop" -> { CallKit.audioStop(this); result.success(null) }
                    "registerDevice" -> {
                        getSharedPreferences(AlarmWatchService.PREFS, Context.MODE_PRIVATE).edit()
                            .putString("token", call.argument<String>("token"))
                            .putString("url", call.argument<String>("url"))
                            .putString("key", call.argument<String>("key"))
                            .apply()
                        AlarmWatchService.start(this)
                        result.success(null)
                    }
                    "refreshService" -> {
                        // e.g. location permission just granted → the service adds its location type
                        if (getSharedPreferences(AlarmWatchService.PREFS, Context.MODE_PRIVATE).getString("token", null) != null) AlarmWatchService.start(this)
                        result.success(null)
                    }
                    "unregisterDevice" -> {
                        getSharedPreferences(AlarmWatchService.PREFS, Context.MODE_PRIVATE).edit().clear().apply()
                        AlarmWatchService.stop(this)
                        AlarmKit.stop(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("koc", e.message, null)
            }
        }
    }

    private fun open(i: Intent) = startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))

    private fun status(): Map<String, Boolean> {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return mapOf(
            "dnd" to nm.isNotificationPolicyAccessGranted,
            "overlay" to (Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(this)),
            "fullScreen" to (Build.VERSION.SDK_INT < 34 || nm.canUseFullScreenIntent()),
            "battery" to pm.isIgnoringBatteryOptimizations(packageName),
        )
    }

    /** Channels are created once with their behaviour fixed; a DND-bypassing set is made after access is granted. */
    private fun ensureChannels(): String {
        if (Build.VERSION.SDK_INT < 26) return "std"
        val dnd = nm.isNotificationPolicyAccessGranted
        val suffix = if (dnd) "dnd" else "std"
        val labels = mapOf(
            "signal1" to "Signal 1 · Emergency · الإشارة 1",
            "signal2" to "Signal 2 · Evacuate · الإشارة 2",
            "signal3" to "Signal 3 · All clear · الإشارة 3",
        )
        for ((kind, label) in labels) {
            val id = "koc_${kind}_$suffix"
            if (nm.getNotificationChannel(id) == null) {
                val ch = NotificationChannel(id, label, NotificationManager.IMPORTANCE_HIGH)
                ch.setSound(Uri.parse("android.resource://$packageName/raw/$kind"), AlarmKit.attrs)
                ch.enableVibration(true)
                ch.vibrationPattern = longArrayOf(0, 800, 400, 800, 400, 800)
                ch.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                if (dnd) ch.setBypassDnd(true)
                nm.createNotificationChannel(ch)
            }
            nm.deleteNotificationChannel(kind)
            if (dnd) nm.deleteNotificationChannel("koc_${kind}_std")
        }
        return suffix
    }

    /** Pull the app over whatever is on screen (allowed from background with "Display over other apps"). */
    private fun bringToFront() {
        startActivity(Intent(this, MainActivity::class.java).addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP))
    }
}
