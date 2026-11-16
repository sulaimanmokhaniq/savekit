package com.savekit.app

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Why the app's process ended recently, as Android recorded it: a crash, a freeze ("not
 * responding") or a normal exit. For a freeze, the part of the thread dump that shows what
 * the main thread was doing is included, which is what a fix needs. Android 11 and later.
 */
object ExitReasons {

    private const val MAX_EXITS = 5
    private const val MAX_TRACE_LINES = 60

    fun recent(context: Context): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        val manager = context.getSystemService(ActivityManager::class.java) ?: return emptyList()
        val exits = try {
            manager.getHistoricalProcessExitReasons(context.packageName, 0, MAX_EXITS)
        } catch (e: Exception) {
            return emptyList()
        }
        val format = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
        return exits.map { exit ->
            mapOf(
                "time" to format.format(Date(exit.timestamp)),
                "reason" to reasonName(exit.reason),
                "description" to exit.description,
                "process" to exit.processName,
                "trace" to if (exit.reason == ApplicationExitInfo.REASON_ANR ||
                    exit.reason == ApplicationExitInfo.REASON_CRASH_NATIVE
                ) {
                    mainThreadTrace(exit)
                } else {
                    null
                },
            )
        }
    }

    /** The dump of the main thread only: the rest is noise for a freeze. */
    private fun mainThreadTrace(exit: ApplicationExitInfo): String? = try {
        exit.traceInputStream?.bufferedReader()?.use { reader ->
            val lines = reader.readLines()
            val start = lines.indexOfFirst { it.startsWith("\"main\"") }
            if (start < 0) {
                lines.take(MAX_TRACE_LINES).joinToString("\n")
            } else {
                lines.drop(start)
                    .takeWhile { it.isNotBlank() }
                    .take(MAX_TRACE_LINES)
                    .joinToString("\n")
            }
        }
    } catch (e: Exception) {
        null
    }

    private fun reasonName(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_ANR -> "not responding"
        ApplicationExitInfo.REASON_CRASH -> "crash"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "native crash"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "low memory"
        ApplicationExitInfo.REASON_EXIT_SELF -> "closed itself"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "closed by user"
        ApplicationExitInfo.REASON_USER_STOPPED -> "force stopped"
        ApplicationExitInfo.REASON_SIGNALED -> "killed by system"
        ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "used too many resources"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "dependency died"
        ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "failed to start"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "permission changed"
        ApplicationExitInfo.REASON_OTHER -> "other"
        else -> "unknown ($reason)"
    }
}
