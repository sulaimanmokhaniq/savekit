package com.savekit.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper

/**
 * Wakes the app when the night begins, so night downloads start even while the phone
 * sleeps (a sleeping phone pauses the app's own timers). The alarm is inexact but fires
 * in Android's deep sleep too; it then tells the Flutter side, which starts the downloads.
 */
object NightWake {

    private const val REQUEST_CODE = 7310

    /** How long the phone is kept awake after the alarm, for the downloads to start. */
    private const val AWAKE_MS = 20_000L

    private fun pending(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        REQUEST_CODE,
        Intent(context, NightWakeReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    fun schedule(context: Context, atMillis: Long) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending(context))
    }

    fun cancel(context: Context) {
        context.getSystemService(AlarmManager::class.java)?.cancel(pending(context))
    }

    internal fun onAlarm(receiver: BroadcastReceiver) {
        val result = receiver.goAsync()
        val main = Handler(Looper.getMainLooper())
        main.post {
            try {
                MainActivity.liveChannel?.invokeMethod("nightWake", null)
            } catch (e: Exception) {
                // The app's screen is gone; the downloads start when it is next opened.
            }
        }
        main.postDelayed({ result.finish() }, AWAKE_MS)
    }
}

class NightWakeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) = NightWake.onAlarm(this)
}
