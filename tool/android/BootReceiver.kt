package com.koc.koc_one

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Restarts alarm delivery after a reboot or an app update (only for a signed-in device). */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val signedIn = context.getSharedPreferences(AlarmWatchService.PREFS, Context.MODE_PRIVATE).getString("token", null) != null
        if (signedIn) AlarmWatchService.start(context)
    }
}
