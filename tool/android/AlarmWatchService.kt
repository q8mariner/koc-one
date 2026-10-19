package com.koc.koc_one

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Keeps delivering alarms when the app is closed (swiped away) or after a reboot.
 * Every 20 s it asks the server for alarms that apply to this employee's last reported area,
 * sounds new ones on the alarm stream, shows a full-screen notification and opens the app.
 */
class AlarmWatchService : Service() {
    companion object {
        const val PREFS = "one_native"
        private const val FG_ID = 1601
        private const val INTERVAL_MS = 5_000L   // calls every 5 s, alarms every 4th tick (20 s)

        fun start(ctx: Context) {
            val i = Intent(ctx, AlarmWatchService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
            } catch (_: Exception) {}
        }

        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, AlarmWatchService::class.java))
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private val exec = Executors.newSingleThreadExecutor()
    private var ticks = 0
    private val tick = object : Runnable {
        override fun run() {
            val n = ticks++
            exec.execute {
                pollCalls()
                if (n % 4 == 0) poll()
                if (n % 12 == 0) heartbeat()
            }
            handler.postDelayed(this, INTERVAL_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        goForeground()
        handler.post(tick)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        goForeground()
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        exec.shutdownNow()
        super.onDestroy()
    }

    /** White "/1" notification icon (falls back to the launcher icon). */
    private fun statIcon(): Int = resources.getIdentifier("ic_stat_one", "drawable", packageName).takeIf { it != 0 } ?: applicationInfo.icon

    private fun prefs() = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private fun isEn() = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).getString("flutter.one.lang", "ar") == "en"
    private fun tr(ar: String, en: String) = if (isEn()) en else ar
    private fun nm() = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun openAppIntent(alarmId: String?): PendingIntent {
        val i = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (alarmId != null) i.putExtra("alarm_id", alarmId)
        return PendingIntent.getActivity(this, alarmId?.hashCode() ?: 0, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    @Suppress("DEPRECATION")
    private fun builder(channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channel) else Notification.Builder(this)

    private var fgTypes = -1 // service types currently in force; -1 = not foreground yet

    private fun hasLocation(): Boolean = Build.VERSION.SDK_INT < 23 ||
        checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED ||
        checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED

    /**
     * The one ONE notification Android requires for background work. It also covers location
     * (type "location"), so the app's GPS keeps working in the background without a second
     * notification. Posted once; reopening the app doesn't post it again unless the type changes.
     */
    private fun goForeground() {
        val types = if (Build.VERSION.SDK_INT >= 34) {
            if (hasLocation()) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE or ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            else ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        } else 0
        if (types == fgTypes) return
        if (Build.VERSION.SDK_INT >= 26 && nm().getNotificationChannel("one_watch") == null) {
            val ch = NotificationChannel("one_watch", "ONE · protection · الحماية", NotificationManager.IMPORTANCE_MIN)
            ch.setShowBadge(false)
            ch.setSound(null, null)
            ch.enableVibration(false)
            nm().createNotificationChannel(ch)
        }
        val n = builder("one_watch")
            .setSmallIcon(statIcon())
            .setContentTitle(tr("ONE · الحماية مفعّلة", "ONE · protection on"))
            .setContentText(tr("تصلك الإنذارات وتنبيهات الحدود حتى والتطبيق مغلق", "Alarms and boundary alerts reach you even when the app is closed"))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setContentIntent(openAppIntent(null))
            .build()
        try {
            if (Build.VERSION.SDK_INT >= 34) startForeground(FG_ID, n, types)
            else startForeground(FG_ID, n)
            fgTypes = types
        } catch (_: Exception) {
            // location type refused (e.g. started at boot without background location) → alarms only
            try {
                if (Build.VERSION.SDK_INT >= 34) startForeground(FG_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE) else startForeground(FG_ID, n)
                fgTypes = ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            } catch (_: Exception) {}
        }
    }

    private fun rpc(base: String, key: String, fn: String, body: JSONObject): String? {
        var c: HttpURLConnection? = null
        return try {
            c = URL("$base/rest/v1/rpc/$fn").openConnection() as HttpURLConnection
            c.requestMethod = "POST"
            c.connectTimeout = 10_000
            c.readTimeout = 10_000
            c.doOutput = true
            c.setRequestProperty("apikey", key)
            c.setRequestProperty("Content-Type", "application/json")
            c.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            if (c.responseCode in 200..299) c.inputStream.bufferedReader().use { it.readText() } else null
        } catch (_: Exception) {
            null
        } finally {
            c?.disconnect()
        }
    }

    private fun wasShown(id: String) = prefs().getStringSet("shown", emptySet())?.contains(id) == true

    private fun markShown(id: String) {
        val set = (prefs().getStringSet("shown", emptySet()) ?: emptySet()).toMutableList()
        set.add(id)
        prefs().edit().putStringSet("shown", set.takeLast(60).toSet()).apply()
    }

    /** Ringing ORT call → ringtone + full-screen call notification + open the app on the call screen. */
    private fun pollCalls() {
        val p = prefs()
        val token = p.getString("token", null) ?: return
        val base = p.getString("url", null) ?: return
        val key = p.getString("key", null) ?: return
        val raw = rpc(base, key, "pending_calls", JSONObject().put("p_token", token)) ?: return
        val arr = try { JSONArray(raw) } catch (_: Exception) { return }
        val c = arr.optJSONObject(0)
        if (c == null) {
            // answered elsewhere, missed or cancelled → stop ringing (only what the service started)
            if (CallKit.ringingCallId != null && CallKit.notifId != 0) CallKit.stopRinging(this)
            return
        }
        val id = c.optString("id")
        if (id == CallKit.ringingCallId) return
        val caller = if (c.isNull("caller_name")) "ORT · 160" else c.optString("caller_name")
        if (Build.VERSION.SDK_INT >= 26 && nm().getNotificationChannel("one_calls") == null) {
            val ch = NotificationChannel("one_calls", "ORT calls · مكالمات ORT", NotificationManager.IMPORTANCE_HIGH)
            ch.setSound(null, null) // the ringtone is played by CallKit
            nm().createNotificationChannel(ch)
        }
        val i = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra("call_id", id)
        val pi = PendingIntent.getActivity(this, id.hashCode(), i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notifId = (id.hashCode() and 0x7fffffff) or 1
        val b = builder("one_calls")
            .setSmallIcon(statIcon())
            .setContentTitle(tr("مكالمة من ", "Call from ") + caller)
            .setContentText(tr("اضغط للرد — مركز 160", "Tap to answer — 160 centre"))
            .setCategory(Notification.CATEGORY_CALL)
            .setOngoing(true)
            .setContentIntent(pi)
            .setFullScreenIntent(pi, true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
        if (Build.VERSION.SDK_INT < 26) legacyMaxPriority(b)
        nm().notify(notifId, b.build())
        CallKit.startRinging(this, id)
        CallKit.notifId = notifId
        try { startActivity(i) } catch (_: Exception) {}
    }

    /** Location-signal heartbeat every 60 s (also while the app is closed): phone alive + GPS on/off. */
    private fun heartbeat() {
        val p = prefs()
        val token = p.getString("token", null) ?: return
        val base = p.getString("url", null) ?: return
        val key = p.getString("key", null) ?: return
        val gps = try {
            val lm = getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
            val on = if (Build.VERSION.SDK_INT >= 28) lm.isLocationEnabled
                     else lm.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER)
            on && (Build.VERSION.SDK_INT < 23 ||
                checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED)
        } catch (_: Exception) { false }
        rpc(base, key, "device_heartbeat", JSONObject().put("p_token", token).put("p_gps", gps))
    }

    private fun poll() {
        val p = prefs()
        val token = p.getString("token", null) ?: return
        val base = p.getString("url", null) ?: return
        val key = p.getString("key", null) ?: return
        val raw = rpc(base, key, "pending_alarms", JSONObject().put("p_token", token)) ?: return
        val arr = try { JSONArray(raw) } catch (_: Exception) { return }

        var stillSounding = false
        for (i in 0 until arr.length()) {
            val a = arr.optJSONObject(i) ?: continue
            val id = a.optString("id")
            val status = if (a.isNull("status")) null else a.optString("status")
            val active = a.optBoolean("active")
            if (id == AlarmKit.soundingId && active && (status == null || status == "received")) stillSounding = true
            // Only alarms nobody has delivered yet (the open app acknowledges its own within a second).
            if (status == null && !wasShown(id)) {
                markShown(id)
                alert(a)
                rpc(base, key, "device_ack", JSONObject().put("p_token", token).put("p_alarm", id))
                val kind = a.optString("kind")
                if (kind == "signal1" || kind == "signal2") stillSounding = true
            }
        }
        // closed alarm, all clear, or the employee answered in the app → silence
        if (AlarmKit.soundingId != null && !stillSounding) AlarmKit.stop(this)
    }

    private fun text(a: JSONObject, field: String): String {
        val en = if (a.isNull("${field}_en")) "" else a.optString("${field}_en")
        val ar = if (a.isNull(field)) "" else a.optString(field)
        return if (isEn() && en.isNotBlank()) en else ar
    }

    @Suppress("DEPRECATION")
    private fun legacyMaxPriority(b: Notification.Builder) {
        b.setPriority(Notification.PRIORITY_MAX)
    }

    private fun alert(a: JSONObject) {
        val id = a.optString("id")
        val kind = a.optString("kind")
        val signal = kind.startsWith("signal")
        val suffix = if (Build.VERSION.SDK_INT >= 26 && nm().getNotificationChannel("koc_${kind}_dnd") != null) "dnd" else "std"
        var channel = if (signal) "koc_${kind}_$suffix" else "koc_msg"
        if (Build.VERSION.SDK_INT >= 26 && nm().getNotificationChannel(channel) == null) channel = "one_watch"
        val drill = if (a.optBoolean("drill")) tr(" (تمرين)", " (drill)") else ""
        val notifId = id.hashCode() and 0x7fffffff
        val pi = openAppIntent(id)
        val b = builder(channel)
            .setSmallIcon(statIcon())
            .setContentTitle(text(a, "title") + drill)
            .setContentText(text(a, "body"))
            .setStyle(Notification.BigTextStyle().bigText(text(a, "body")))
            .setContentIntent(pi)
            .setAutoCancel(!signal || kind == "signal3")
            .setOngoing(signal && kind != "signal3")
            .setCategory(if (signal) Notification.CATEGORY_ALARM else Notification.CATEGORY_MESSAGE)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
        if (signal && kind != "signal3") b.setFullScreenIntent(pi, true)
        if (Build.VERSION.SDK_INT < 26) legacyMaxPriority(b)
        nm().notify(notifId, b.build())

        if (signal) {
            AlarmKit.start(this, kind, kind != "signal3")
            AlarmKit.soundingId = id
            AlarmKit.serviceNotifId = notifId
            // Open the app on top (allowed with "Display over other apps"); the full-screen intent covers the lock screen.
            try {
                startActivity(Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                    .putExtra("alarm_id", id))
            } catch (_: Exception) {}
        }
    }
}
