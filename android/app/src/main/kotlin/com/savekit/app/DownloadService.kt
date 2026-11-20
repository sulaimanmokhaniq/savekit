package com.savekit.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * Foreground service that keeps the process alive while downloads run, so Android does not
 * kill a long download once the app is in the background. It does no work itself: the
 * extractor processes belong to [DownloadEngine] and the queue lives in Flutter, which reports
 * how many downloads are active through [update].
 */
class DownloadService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Downloading"
        val text = intent?.getStringExtra(EXTRA_TEXT).orEmpty()
        val progress = intent?.getIntExtra(EXTRA_PROGRESS, -1) ?: -1
        val waiting = intent?.getBooleanExtra(EXTRA_WAITING, false) ?: false
        val notification = buildProgressNotification(this, title, text, progress, waiting)

        // startForeground must follow every startForegroundService call, including a stop.
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE && waiting) {
                // Only waiting (for the night, Wi-Fi or the internet): nothing transfers, so
                // this is not a data sync, which Android stops after a few hours.
                startForeground(
                    PROGRESS_NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    PROGRESS_NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } else {
                startForeground(PROGRESS_NOTIFICATION_ID, notification)
            }
            running = true
            runningWaiting = waiting
        } catch (e: Exception) {
            Log.w(TAG, "Could not enter the foreground", e)
            running = false
            stopSelf()
            return START_NOT_STICKY
        }

        if (intent?.action == ACTION_STOP) {
            stopForegroundCompat()
            running = false
            runningWaiting = false
            stopSelf()
        }
        return START_NOT_STICKY
    }

    // Android 15 caps data-sync services at a few hours; leave quietly instead of crashing.
    override fun onTimeout(startId: Int) = leaveForeground()

    override fun onTimeout(startId: Int, fgsType: Int) = leaveForeground()

    private fun leaveForeground() {
        stopForegroundCompat()
        running = false
        stopSelf()
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    companion object {
        private const val TAG = "SaveKitService"
        private const val ACTION_STOP = "com.savekit.app.STOP_DOWNLOADS"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_PROGRESS = "progress"
        private const val EXTRA_WAITING = "waiting"

        private const val PROGRESS_CHANNEL = "downloads_progress"
        private const val FINISHED_CHANNEL = "downloads_finished"
        private const val PROGRESS_NOTIFICATION_ID = 4201

        @Volatile
        private var running = false

        /** Whether the service is in the foreground only to wait, not to transfer. */
        @Volatile
        private var runningWaiting = false

        /**
         * Starts, refreshes or stops the service. [activeCount] is the number of queued or
         * running downloads; zero stops it. [progress] is 0..100, or negative for unknown.
         * [waiting] means none is running: they wait for the night, Wi-Fi or the internet.
         * The process must stay alive meanwhile, or Android freezes it and nothing notices
         * when they may start.
         */
        fun update(
            context: Context,
            activeCount: Int,
            title: String,
            text: String,
            progress: Int,
            waiting: Boolean = false,
        ) {
            val appContext = context.applicationContext
            if (activeCount <= 0) {
                stop(appContext)
                return
            }
            val intent = Intent(appContext, DownloadService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TEXT, text)
                .putExtra(EXTRA_PROGRESS, progress)
                .putExtra(EXTRA_WAITING, waiting)
            try {
                if (running && runningWaiting != waiting) {
                    // Between waiting and transferring: enter the foreground again as the
                    // other kind of service. The app already has a foreground service, so
                    // Android allows this from the background too.
                    appContext.startService(intent)
                } else if (running) {
                    // Already in the foreground: only the notification needs refreshing.
                    notificationManager(appContext).notify(
                        PROGRESS_NOTIFICATION_ID,
                        buildProgressNotification(appContext, title, text, progress, waiting),
                    )
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    appContext.startForegroundService(intent)
                } else {
                    appContext.startService(intent)
                }
            } catch (e: Exception) {
                // Android refuses to start a foreground service from the background; the
                // download itself still runs for as long as the process lives.
                Log.w(TAG, "Could not start the download service", e)
            }
        }

        private fun stop(context: Context) {
            if (!running) return
            try {
                context.startService(
                    Intent(context, DownloadService::class.java).setAction(ACTION_STOP),
                )
            } catch (e: Exception) {
                context.stopService(Intent(context, DownloadService::class.java))
            }
        }

        /** Posts the "finished" or "failed" notification for one download. */
        fun notifyFinished(context: Context, taskId: String, title: String, success: Boolean) {
            val appContext = context.applicationContext
            ensureChannels(appContext)
            val builder = builder(appContext, FINISHED_CHANNEL)
                .setSmallIcon(
                    if (success) R.drawable.ic_stat_savekit
                    else android.R.drawable.stat_notify_error,
                )
                .setColor(LauncherIcon.accentColor(context))
                .setContentTitle(if (success) "Download complete" else "Download failed")
                .setContentText(title)
                .setAutoCancel(true)
                .setContentIntent(openAppIntent(appContext))
            try {
                notificationManager(appContext).notify(taskId.hashCode(), builder.build())
            } catch (e: Exception) {
                Log.w(TAG, "Could not post the finished notification", e)
            }
        }

        private fun buildProgressNotification(
            context: Context,
            title: String,
            text: String,
            progress: Int,
            waiting: Boolean = false,
        ): Notification {
            ensureChannels(context)
            val builder = builder(context, PROGRESS_CHANNEL)
                .setSmallIcon(R.drawable.ic_stat_savekit)
                .setColor(LauncherIcon.accentColor(context))
                .setContentTitle(title)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(openAppIntent(context))
            if (!waiting) builder.setProgress(100, progress.coerceIn(0, 100), progress < 0)
            if (text.isNotEmpty()) builder.setContentText(text)
            return builder.build()
        }

        private fun builder(context: Context, channel: String): Notification.Builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, channel)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }

        private fun openAppIntent(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            return PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun ensureChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = notificationManager(context)
            if (manager.getNotificationChannel(PROGRESS_CHANNEL) == null) {
                manager.createNotificationChannel(
                    NotificationChannel(
                        PROGRESS_CHANNEL,
                        "Active downloads",
                        NotificationManager.IMPORTANCE_LOW,
                    ).apply { setShowBadge(false) },
                )
            }
            if (manager.getNotificationChannel(FINISHED_CHANNEL) == null) {
                manager.createNotificationChannel(
                    NotificationChannel(
                        FINISHED_CHANNEL,
                        "Finished downloads",
                        NotificationManager.IMPORTANCE_DEFAULT,
                    ),
                )
            }
        }

        private fun notificationManager(context: Context): NotificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    }
}
