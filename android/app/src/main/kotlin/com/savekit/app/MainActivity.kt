package com.savekit.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Bridges Flutter to the on-device extraction engine.
 *
 * MethodChannel `com.app.downloader/engine`:
 *  - initEngine()
 *  - getEngineVersion()
 *  - updateEngine()
 *  - getMediaInfo(url, cookiesFilePath?)
 *  - getPlaylistInfo(url, cookiesFilePath?)
 *  - getAccountMedia(url, cookiesFilePath?, start, count)
 *  - startDownload(taskId, url, formatSelection, outputDir, cookiesFilePath?, extractAudio,
 *                  formatSort?, audioFormat?, engine?, itemCount?, clipStart?, clipEnd?,
 *                  subtitleLanguage?, autoSubtitles?)
 *  - cancelDownload(taskId)
 *  - updateDownloadService(activeCount, title, text, progress)
 *  - notifyDownloadFinished(taskId, title, success)
 *  - exportToMediaStore(path, kind)                 -> address of the gallery copy
 *  - deleteFromMediaStore(locations, names)         -> true when every copy is gone
 *  - setLauncherIcon(theme)                          home-screen icon follows the theme
 *  - pickVideo()                                    -> {path, name, size} or null
 *  - grantStatusFolder(business), statusFolderGranted(), forgetStatusFolder()
 *  - listStatuses(), statusThumbnail(uri, size), importStatuses(uris, outputDir)
 *
 * EventChannel `com.app.downloader/progress` streams maps of
 * `{taskId, status, progressPercent, speed, eta, ...}`; see [DownloadEngine].
 *
 * Every call is answered on the main thread; the work itself runs on the engine's
 * background executor, so no call blocks the UI.
 */
// A FragmentActivity is required by the biometric prompt used for the Vault lock.
class MainActivity : FlutterFragmentActivity() {

    private var engineChannel: MethodChannel? = null
    private var progressChannel: EventChannel? = null
    private var pendingPicker: MethodChannel.Result? = null

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

    /**
     * Removes exported gallery copies. Copies made by an earlier installation of the app
     * need the user's confirmation, which Android collects in its own dialog; the call
     * answers `true` only when every copy is gone.
     */
    private fun deleteExported(
        locations: List<String>,
        names: List<String>,
        result: MethodChannel.Result,
    ) {
        Thread {
            val outcome = try {
                MediaStoreExporter.delete(applicationContext, locations, names)
            } catch (e: Exception) {
                runOnUiThread { result.error("DELETE_FAILED", e.message, null) }
                return@Thread
            }
            runOnUiThread {
                if (outcome.needConsent.isEmpty()) {
                    result.success(true)
                    return@runOnUiThread
                }
                val request = MediaStoreExporter.deleteRequest(
                    applicationContext,
                    outcome.needConsent,
                )
                if (request == null || pendingPicker != null) {
                    result.success(false)
                    return@runOnUiThread
                }
                pendingPicker = result
                try {
                    startIntentSenderForResult(
                        request.intentSender,
                        REQUEST_DELETE_MEDIA,
                        null,
                        0,
                        0,
                        0,
                    )
                } catch (e: Exception) {
                    pendingPicker = null
                    result.success(false)
                }
            }
        }.start()
    }

    /** Opens a system picker; the answer is delivered in [onActivityResult]. */
    private fun launchPicker(requestCode: Int, intent: Intent, result: MethodChannel.Result) {
        if (pendingPicker != null) {
            result.error("PICKER_BUSY", "Another picker is already open.", null)
            return
        }
        pendingPicker = result
        try {
            startActivityForResult(intent, requestCode)
        } catch (e: Exception) {
            pendingPicker = null
            result.error("PICKER_UNAVAILABLE", "This phone has no file picker.", null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != DeviceFiles.REQUEST_PICK_VIDEO &&
            requestCode != DeviceFiles.REQUEST_STATUS_FOLDER &&
            requestCode != REQUEST_DELETE_MEDIA
        ) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingPicker ?: return
        pendingPicker = null
        if (requestCode == REQUEST_DELETE_MEDIA) {
            // The user allowed (or refused) removing the gallery copies.
            result.success(resultCode == Activity.RESULT_OK)
            return
        }
        val uri = DeviceFiles.pickedUri(resultCode, data)
        val pickingVideo = requestCode == DeviceFiles.REQUEST_PICK_VIDEO

        if (uri == null) {
            // Closed without choosing anything.
            result.success(if (pickingVideo) null else false)
            return
        }
        if (pickingVideo) {
            DownloadEngine.runInBackground(result, "PICK_FAILED") {
                DeviceFiles.importPickedVideo(applicationContext, uri)
            }
            return
        }
        try {
            result.success(DeviceFiles.saveStatusFolder(applicationContext, uri))
        } catch (e: Exception) {
            result.error("STATUS_FAILED", e.message ?: "Access was not granted.", null)
        }
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

            "getPlaylistInfo" -> {
                val url = call.argument<String>("url")?.trim()
                if (url.isNullOrEmpty()) {
                    result.error(ERROR_BAD_ARGS, "getPlaylistInfo requires a non-empty 'url'.", null)
                    return
                }
                DownloadEngine.getPlaylistInfo(
                    url = url,
                    cookiesFilePath = call.argument<String>("cookiesFilePath"),
                    result = result,
                )
            }

            "getAccountMedia" -> {
                val url = call.argument<String>("url")?.trim()
                if (url.isNullOrEmpty()) {
                    result.error(ERROR_BAD_ARGS, "getAccountMedia requires a non-empty 'url'.", null)
                    return
                }
                DownloadEngine.getAccountMedia(
                    url = url,
                    cookiesFilePath = call.argument<String>("cookiesFilePath"),
                    start = (call.argument<Number>("start")?.toInt() ?: 1).coerceAtLeast(1),
                    count = (call.argument<Number>("count")?.toInt() ?: 100).coerceIn(1, 300),
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
                        clipStart = call.argument<Number>("clipStart")?.toDouble(),
                        clipEnd = call.argument<Number>("clipEnd")?.toDouble(),
                        subtitleLanguage = call.argument<String>("subtitleLanguage")
                            ?.trim()?.ifEmpty { null },
                        autoSubtitles = call.argument<Boolean>("autoSubtitles") ?: false,
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

            "updateDownloadService" -> {
                DownloadService.update(
                    context = applicationContext,
                    activeCount = call.argument<Number>("activeCount")?.toInt() ?: 0,
                    title = call.argument<String>("title") ?: "Downloading",
                    text = call.argument<String>("text").orEmpty(),
                    progress = call.argument<Number>("progress")?.toInt() ?: -1,
                )
                result.success(null)
            }

            "notifyDownloadFinished" -> {
                DownloadService.notifyFinished(
                    context = applicationContext,
                    taskId = call.argument<String>("taskId").orEmpty(),
                    title = call.argument<String>("title").orEmpty(),
                    success = call.argument<Boolean>("success") ?: true,
                )
                result.success(null)
            }

            "exportToMediaStore" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrEmpty()) {
                    result.error(ERROR_BAD_ARGS, "exportToMediaStore requires a 'path'.", null)
                    return
                }
                DownloadEngine.exportToMediaStore(
                    path = path,
                    kind = call.argument<String>("kind") ?: "other",
                    result = result,
                )
            }

            "deleteFromMediaStore" -> deleteExported(
                locations = call.argument<List<String>>("locations").orEmpty(),
                names = call.argument<List<String>>("names").orEmpty(),
                result = result,
            )

            "setLauncherIcon" -> {
                try {
                    LauncherIcon.apply(applicationContext, call.argument<String>("theme").orEmpty())
                    result.success(null)
                } catch (e: Exception) {
                    result.error("ICON_FAILED", e.message, null)
                }
            }

            "pickVideo" -> launchPicker(
                DeviceFiles.REQUEST_PICK_VIDEO,
                DeviceFiles.pickVideoIntent(),
                result,
            )

            "grantStatusFolder" -> launchPicker(
                DeviceFiles.REQUEST_STATUS_FOLDER,
                DeviceFiles.statusFolderIntent(call.argument<Boolean>("business") ?: false),
                result,
            )

            "statusFolderGranted" ->
                result.success(DeviceFiles.statusFolder(applicationContext) != null)

            "forgetStatusFolder" -> {
                DeviceFiles.forgetStatusFolder(applicationContext)
                result.success(null)
            }

            "listStatuses" -> DownloadEngine.runInBackground(result, "STATUS_FAILED") {
                DeviceFiles.listStatuses(applicationContext)
            }

            "statusThumbnail" -> {
                val uri = call.argument<String>("uri")
                val size = call.argument<Number>("size")?.toInt() ?: 320
                if (uri.isNullOrEmpty()) {
                    result.error(ERROR_BAD_ARGS, "statusThumbnail requires a 'uri'.", null)
                    return
                }
                DownloadEngine.runInBackground(result, "STATUS_FAILED") {
                    DeviceFiles.statusThumbnail(applicationContext, Uri.parse(uri), size)
                }
            }

            "previewStatus" -> {
                val uri = call.argument<String>("uri")
                if (uri.isNullOrEmpty()) {
                    result.error(ERROR_BAD_ARGS, "previewStatus requires a 'uri'.", null)
                    return
                }
                DownloadEngine.runInBackground(result, "STATUS_FAILED") {
                    DeviceFiles.cacheStatusForPreview(applicationContext, Uri.parse(uri))
                }
            }

            "importStatuses" -> {
                val uris = call.argument<List<String>>("uris").orEmpty()
                val outputDir = call.argument<String>("outputDir")
                if (outputDir.isNullOrEmpty()) {
                    result.error(ERROR_BAD_ARGS, "importStatuses requires an 'outputDir'.", null)
                    return
                }
                DownloadEngine.runInBackground(result, "STATUS_FAILED") {
                    DeviceFiles.importStatuses(applicationContext, uris, File(outputDir))
                }
            }

            else -> result.notImplemented()
        }
    }

    companion object {
        const val ENGINE_CHANNEL = "com.app.downloader/engine"
        const val PROGRESS_CHANNEL = "com.app.downloader/progress"
        private const val ERROR_BAD_ARGS = "BAD_ARGS"
        private const val REQUEST_DELETE_MEDIA = 7303
    }
}
