package com.savekit.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Flutter to the on-device extraction engine.
 *
 * MethodChannel `com.app.downloader/engine`:
 *  - initEngine()
 *  - getEngineVersion()
 *  - updateEngine()
 *  - getMediaInfo(url, cookiesFilePath?)
 *  - startDownload(taskId, url, formatSelection, outputDir, cookiesFilePath?, extractAudio,
 *                  formatSort?, audioFormat?, engine?, itemCount?)
 *  - cancelDownload(taskId)
 *
 * EventChannel `com.app.downloader/progress` streams maps of
 * `{taskId, status, progressPercent, speed, eta, ...}`; see [DownloadEngine].
 *
 * Every call is answered on the main thread; the work itself runs on the engine's
 * background executor, so no call blocks the UI.
 */
class MainActivity : FlutterActivity() {

    private var engineChannel: MethodChannel? = null
    private var progressChannel: EventChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        DownloadEngine.attach(applicationContext)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        engineChannel = MethodChannel(messenger, ENGINE_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result -> handleCall(call, result) }
        }

        progressChannel = EventChannel(messenger, PROGRESS_CHANNEL).also { channel ->
            channel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    DownloadEngine.setProgressSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    DownloadEngine.setProgressSink(null)
                }
            })
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        engineChannel?.setMethodCallHandler(null)
        progressChannel?.setStreamHandler(null)
        engineChannel = null
        progressChannel = null
        DownloadEngine.setProgressSink(null)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initEngine" -> DownloadEngine.initEngine(result)

            "getEngineVersion" -> DownloadEngine.getEngineVersion(result)

            "updateEngine" -> DownloadEngine.updateEngine(result)

            "getMediaInfo" -> {
                val url = call.argument<String>("url")?.trim()
                if (url.isNullOrEmpty()) {
                    result.error(ERROR_BAD_ARGS, "getMediaInfo requires a non-empty 'url'.", null)
                    return
                }
                DownloadEngine.getMediaInfo(
                    url = url,
                    cookiesFilePath = call.argument<String>("cookiesFilePath"),
                    result = result,
                )
            }

            "startDownload" -> {
                val taskId = call.argument<String>("taskId")?.trim()
                val url = call.argument<String>("url")?.trim()
                val formatSelection = call.argument<String>("formatSelection")?.trim()
                val outputDir = call.argument<String>("outputDir")?.trim()
                if (taskId.isNullOrEmpty() || url.isNullOrEmpty() ||
                    formatSelection.isNullOrEmpty() || outputDir.isNullOrEmpty()
                ) {
                    result.error(
                        ERROR_BAD_ARGS,
                        "startDownload requires 'taskId', 'url', 'formatSelection' and 'outputDir'.",
                        null,
                    )
                    return
                }
                DownloadEngine.startDownload(
                    request = DownloadEngine.DownloadRequest(
                        taskId = taskId,
                        url = url,
                        formatSelection = formatSelection,
                        formatSort = call.argument<String>("formatSort")?.trim().orEmpty(),
                        outputDir = outputDir,
                        cookiesFilePath = call.argument<String>("cookiesFilePath"),
                        extractAudio = call.argument<Boolean>("extractAudio") ?: false,
                        audioFormat = call.argument<String>("audioFormat")?.trim()
                            ?.ifEmpty { null } ?: "mp3",
                        engine = call.argument<String>("engine")?.trim()
                            ?.ifEmpty { null } ?: DownloadEngine.ENGINE_YTDLP,
                        itemCount = call.argument<Number>("itemCount")?.toInt() ?: 0,
                    ),
                    result = result,
                )
            }

            "cancelDownload" -> {
                val taskId = call.argument<String>("taskId")?.trim()
                if (taskId.isNullOrEmpty()) {
                    result.error(ERROR_BAD_ARGS, "cancelDownload requires a 'taskId'.", null)
                    return
                }
                result.success(DownloadEngine.cancelDownload(taskId))
            }

            else -> result.notImplemented()
        }
    }

    companion object {
        const val ENGINE_CHANNEL = "com.app.downloader/engine"
        const val PROGRESS_CHANNEL = "com.app.downloader/progress"
        private const val ERROR_BAD_ARGS = "BAD_ARGS"
    }
}
