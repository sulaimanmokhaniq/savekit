package com.savekit.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import com.yausername.aria2c.Aria2c
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.regex.Pattern

/**
 * The on-device extraction engine: embedded yt-dlp for video and audio, aria2c for
 * multi-connection downloading, FFmpeg for merging, and gallery-dl ([GalleryEngine]) for photo
 * posts. Nothing leaves the device except the requests the extractors make to the media sites
 * themselves (and to GitHub / PyPI when the user updates them).
 *
 * It is a process-wide singleton so running downloads survive the activity being recreated.
 * Progress events are maps:
 *
 * ```
 * taskId           String
 * status           "starting" | "downloading" | "processing" | "completed" | "failed" | "canceled"
 * progressPercent  Double, 0..100 across all streams of the task
 * speed            String, e.g. "3.2MiB/s", or "2/5 files" for photo posts (empty when unknown)
 * eta              Int seconds, -1 when unknown
 * filePath         String, on "completed"
 * filePaths        List<String>, on "completed" (several for multi-item posts)
 * fileSize         Long bytes, on "completed"
 * error            String, on "failed"
 * ```
 */
object DownloadEngine {

    data class DownloadRequest(
        val taskId: String,
        val url: String,
        val formatSelection: String,
        val formatSort: String,
        val outputDir: String,
        val cookiesFilePath: String?,
        val extractAudio: Boolean,
        val audioFormat: String,
        /** [ENGINE_YTDLP], [ENGINE_GALLERY] or [ENGINE_CONVERT]. */
        val engine: String,
        /** Files expected from a photo post, for its progress percentage; 0 when unknown. */
        val itemCount: Int,
        /** Download only this part of the video, in seconds; null for the whole video. */
        val clipStart: Double? = null,
        val clipEnd: Double? = null,
        /** Language of the subtitles to embed in the video; null for none. */
        val subtitleLanguage: String? = null,
        /** Take the machine-made captions rather than uploaded subtitles. */
        val autoSubtitles: Boolean = false,
        /** Settings of a local edit, for [ENGINE_EDIT]. */
        val options: Map<String, String> = emptyMap(),
    )

    const val ENGINE_YTDLP = "ytdlp"
    const val ENGINE_GALLERY = "gallerydl"

    /** Local video-to-audio conversion; the task's `url` is the video's file path. */
    const val ENGINE_CONVERT = "convert"

    /**
     * Local video edit; `url` is the video's file path, `formatSelection` names the edit
     * and `options` holds its settings. See [EditorEngine].
     */
    const val ENGINE_EDIT = "edit"

    private const val TAG = "SaveKitEngine"

    private const val ERROR_NOT_READY = "ENGINE_NOT_READY"
    private const val ERROR_INIT = "ENGINE_INIT_FAILED"
    private const val ERROR_UPDATE = "ENGINE_UPDATE_FAILED"
    private const val ERROR_EXTRACT = "EXTRACTION_FAILED"
    private const val ERROR_DOWNLOAD = "DOWNLOAD_FAILED"
    private const val ERROR_EXPORT = "EXPORT_FAILED"

    private const val STATUS_STARTING = "starting"
    private const val STATUS_DOWNLOADING = "downloading"
    private const val STATUS_PROCESSING = "processing"
    private const val STATUS_COMPLETED = "completed"
    private const val STATUS_FAILED = "failed"
    private const val STATUS_CANCELED = "canceled"

    /** The library switches on aria2c when the command names its bundled binary. */
    private const val ARIA2C_BINARY = "libaria2c.so"
    private const val CONNECTIONS = 8
    private const val MAX_PLAYLIST_ENTRIES = 500
    private const val PROGRESS_INTERVAL_MS = 300L

    private val YTDLP_SPEED = Pattern.compile("\\bat\\s+(\\S+/s)")
    private val ARIA2C_SPEED = Pattern.compile("\\bDL:([0-9.]+[A-Za-z]+)")

    /** aria2c's summary line: "[#2089b0 40.0MiB/133.2MiB(30%) CN:8 DL:3.1MiB ETA:30s]". */
    private val ARIA2C_PROGRESS = Pattern.compile(
        "\\[#\\w+\\s+([0-9.]+[KMGT]?i?B)/([0-9.]+[KMGT]?i?B)\\((\\d+)%\\)" +
            "(?:.*?ETA:((?:\\d+h)?(?:\\d+m)?(?:\\d+s)?))?",
    )
    private val ARIA2C_ETA = Pattern.compile("(?:(\\d+)h)?(?:(\\d+)m)?(?:(\\d+)s)?")

    /** yt-dlp's own line: "[download]  45.3% of ~ 120.00MiB at ...". */
    private val YTDLP_TOTAL = Pattern.compile("\\[download\\]\\s+([0-9.]+)% of\\s+~?\\s*([0-9.]+)([KMGT]?i?B)")

    /** Lines yt-dlp prints while it reads the page and works out the formats. */
    private val READING_INFO = Pattern.compile(
        "^\\[[\\w:]+\\] .*(Downloading|Extracting|Fetching|Solving)",
    )
    private val SUBTITLE_FILE = Pattern.compile("\\.(vtt|srt|ass|ttml|srv\\d|json3)$")
    private val FORMAT_COUNT = Pattern.compile("Downloading \\d+ format\\(s\\):\\s*(\\S+)")
    private val POST_PROCESSORS = listOf(
        "[Merger]", "[ExtractAudio]", "[VideoConvertor]", "[VideoRemuxer]",
        "[Fixup", "[Metadata]", "[MoveFiles]", "[EmbedThumbnail]",
    )

    private lateinit var appContext: Context
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newCachedThreadPool()

    private val initLock = Any()
    @Volatile
    private var initialized = false

    private var progressSink: EventChannel.EventSink? = null
    private val activeTasks: MutableSet<String> = ConcurrentHashMap.newKeySet()
    private val canceledTasks: MutableSet<String> = ConcurrentHashMap.newKeySet()

    /** Latest event per task, replayed when Flutter (re)subscribes after a restart. */
    private val latestEvents: MutableMap<String, Map<String, Any?>> =
        Collections.synchronizedMap(LinkedHashMap())

    fun attach(context: Context) {
        if (!::appContext.isInitialized) appContext = context.applicationContext
    }

    // region channel plumbing

    /** Called on the main thread by the EventChannel stream handler. */
    fun setProgressSink(sink: EventChannel.EventSink?) {
        progressSink = sink
        if (sink == null) return
        val pending = synchronized(latestEvents) { latestEvents.values.toList() }
        pending.forEach { deliver(it) }
    }

    private fun emit(event: Map<String, Any?>) {
        latestEvents[event["taskId"] as String] = event
        mainHandler.post { deliver(event) }
    }

    private fun deliver(event: Map<String, Any?>) {
        val sink = progressSink ?: return
        sink.success(event)
        val status = event["status"]
        if (status == STATUS_COMPLETED || status == STATUS_FAILED || status == STATUS_CANCELED) {
            // A terminal event has reached Flutter, which now owns the task's final state.
            latestEvents.remove(event["taskId"] as String)
        }
    }

    private fun succeed(result: MethodChannel.Result, value: Any?) {
        mainHandler.post { result.success(value) }
    }

    private fun fail(result: MethodChannel.Result, code: String, error: Throwable) {
        Log.e(TAG, code, error)
        val message = readableError(error)
        mainHandler.post { result.error(code, message, null) }
    }

    // endregion

    // region engine lifecycle

    /** Unpacks Python, yt-dlp, FFmpeg and aria2c on first run; cheap afterwards. */
    fun initEngine(result: MethodChannel.Result) {
        executor.execute {
            try {
                ensureInitialized()
                succeed(
                    result,
                    mapOf(
                        "initialized" to true,
                        "version" to readVersion(),
                        "galleryVersion" to GalleryEngine.version(appContext),
                    ),
                )
            } catch (e: Throwable) {
                fail(result, ERROR_INIT, e)
            }
        }
    }

    fun getEngineVersion(result: MethodChannel.Result) {
        executor.execute {
            try {
                ensureInitialized()
                succeed(result, readVersion())
            } catch (e: Throwable) {
                fail(result, ERROR_NOT_READY, e)
            }
        }
    }

    /**
     * Pulls the newest nightly yt-dlp and the newest gallery-dl so extractors can be fixed
     * without a new APK. A gallery-dl failure is reported but does not fail the yt-dlp update.
     */
    fun updateEngine(result: MethodChannel.Result) {
        executor.execute {
            try {
                ensureInitialized()
                val status = YoutubeDL.getInstance()
                    .updateYoutubeDL(appContext, YoutubeDL.UpdateChannel.NIGHTLY)
                var galleryUpdated = false
                var galleryError: String? = null
                try {
                    galleryUpdated = GalleryEngine.update(appContext)
                } catch (e: Throwable) {
                    Log.w(TAG, "gallery-dl update failed", e)
                    galleryError = readableError(e)
                }
                succeed(
                    result,
                    mapOf(
                        "status" to (status?.name ?: YoutubeDL.UpdateStatus.ALREADY_UP_TO_DATE.name),
                        "updated" to (status == YoutubeDL.UpdateStatus.DONE),
                        "version" to readVersion(),
                        "galleryUpdated" to galleryUpdated,
                        "galleryVersion" to GalleryEngine.version(appContext),
                        "galleryError" to galleryError,
                    ),
                )
            } catch (e: Throwable) {
                fail(result, ERROR_UPDATE, e)
            }
        }
    }

    private fun ensureInitialized() {
        if (initialized) return
        synchronized(initLock) {
            if (initialized) return
            YoutubeDL.getInstance().init(appContext)
            FFmpeg.getInstance().init(appContext)
            Aria2c.getInstance().init(appContext)
            GalleryEngine.ensureReady(appContext)
            initialized = true
        }
    }

    /** Asks the yt-dlp actually on disk, so it is right both before and after an update. */
    private fun readVersion(): String {
        return try {
            val request = YoutubeDLRequest(emptyList()).addOption("--version")
            YoutubeDL.getInstance().execute(request, null, null).out.trim()
                .ifEmpty { YoutubeDL.getInstance().versionName(appContext).orEmpty() }
        } catch (e: Throwable) {
            Log.w(TAG, "Could not read the yt-dlp version", e)
            YoutubeDL.getInstance().versionName(appContext).orEmpty()
        }
    }

    // endregion

    // region extraction

    /**
     * Asks both extractors at once: yt-dlp for video and audio, gallery-dl for photos. The
     * result carries whatever each found, so a post can offer video qualities, a photo
     * download, or both.
     */
    fun getMediaInfo(url: String, cookiesFilePath: String?, result: MethodChannel.Result) {
        executor.execute {
            var videoCookies: File? = null
            var galleryCookies: File? = null
            try {
                ensureInitialized()
                val stamp = System.nanoTime()
                videoCookies = snapshotCookies(cookiesFilePath, "info-$stamp")
                galleryCookies = snapshotCookies(cookiesFilePath, "gallery-$stamp")

                val galleryCookiesFile = galleryCookies
                val galleryLookup = executor.submit<GalleryEngine.Info?> {
                    GalleryEngine.getInfo(appContext, url, galleryCookiesFile)
                }

                var video: Map<String, Any?>? = null
                var videoError: Throwable? = null
                try {
                    video = extractVideoInfo(url, videoCookies)
                } catch (e: Throwable) {
                    videoError = e
                }

                var gallery: GalleryEngine.Info? = null
                var galleryError: Throwable? = null
                try {
                    gallery = galleryLookup.get()
                } catch (e: Throwable) {
                    galleryError = e.cause ?: e
                    Log.w(TAG, "gallery-dl lookup failed", galleryError)
                }

                val info = mergeMediaInfo(url, video, gallery)
                if (info != null) {
                    succeed(result, info)
                } else {
                    fail(result, ERROR_EXTRACT, pickExtractionError(videoError, galleryError))
                }
            } catch (e: Throwable) {
                fail(result, ERROR_EXTRACT, e)
            } finally {
                videoCookies?.delete()
                galleryCookies?.delete()
            }
        }
    }

    /** Lists the videos of a playlist or channel page without resolving each one. */
    fun getPlaylistInfo(url: String, cookiesFilePath: String?, result: MethodChannel.Result) {
        executor.execute {
            var cookies: File? = null
            try {
                ensureInitialized()
                cookies = snapshotCookies(cookiesFilePath, "playlist-${System.nanoTime()}")
                val request = YoutubeDLRequest(url)
                    .addOption("--flat-playlist")
                    .addOption("--dump-single-json")
                    .addOption("--no-warnings")
                    .addOption("--playlist-end", MAX_PLAYLIST_ENTRIES)
                if (cookies != null) request.addOption("--cookies", cookies.absolutePath)

                val response = YoutubeDL.getInstance().execute(request, null, null)
                val json = response.out.trim()
                if (json.isEmpty()) {
                    throw YoutubeDLException(
                        response.err.ifBlank { "No playlist information was returned." },
                    )
                }
                succeed(result, MediaInfoParser.parsePlaylist(json, url))
            } catch (e: Throwable) {
                fail(result, ERROR_EXTRACT, e)
            } finally {
                cookies?.delete()
            }
        }
    }

    /**
     * Lists the media of an account page (a channel, a profile, a user's timeline), a page
     * at a time: items [start] to [start] + [count] - 1. Photo-first platforms go through
     * gallery-dl, which returns direct file addresses; everything else, and anything
     * gallery-dl cannot read, through yt-dlp, which returns video page addresses.
     */
    fun getAccountMedia(
        url: String,
        cookiesFilePath: String?,
        start: Int,
        count: Int,
        result: MethodChannel.Result,
    ) {
        executor.execute {
            var cookies: File? = null
            try {
                ensureInitialized()
                cookies = snapshotCookies(cookiesFilePath, "account-${System.nanoTime()}")
                val end = start + count - 1
                val isYoutube = url.contains("youtube.com/") || url.contains("youtu.be/")

                var galleryError: Throwable? = null
                if (!isYoutube) {
                    try {
                        val info = GalleryEngine.listAccount(appContext, url, cookies, start, end)
                        if (info != null) {
                            succeed(
                                result,
                                mapOf(
                                    "url" to url,
                                    "title" to info.uploader,
                                    "uploader" to info.uploader,
                                    "platform" to info.platform,
                                    "items" to info.items.map { it.toMap() },
                                    "hasMore" to (info.items.size >= count),
                                ),
                            )
                            return@execute
                        }
                    } catch (e: Throwable) {
                        galleryError = e
                    }
                }

                try {
                    val request = YoutubeDLRequest(url)
                        .addOption("--flat-playlist")
                        .addOption("--dump-single-json")
                        .addOption("--no-warnings")
                        .addOption("--playlist-start", start)
                        .addOption("--playlist-end", end)
                    if (cookies != null) request.addOption("--cookies", cookies.absolutePath)
                    val response = YoutubeDL.getInstance().execute(request, null, null)
                    val json = response.out.trim()
                    if (json.isEmpty()) {
                        throw YoutubeDLException(
                            response.err.ifBlank { "No media was found on this account." },
                        )
                    }
                    val playlist = MediaInfoParser.parsePlaylist(json, url)
                    @Suppress("UNCHECKED_CAST")
                    val entries = playlist["entries"] as List<Map<String, Any?>>
                    succeed(
                        result,
                        mapOf(
                            "url" to url,
                            "title" to playlist["title"],
                            "uploader" to playlist["uploader"],
                            "platform" to playlist["platform"],
                            "items" to entries.map { entry ->
                                mapOf(
                                    "url" to entry["url"],
                                    "extension" to "",
                                    "width" to null,
                                    "height" to null,
                                    "isVideo" to true,
                                    "thumbnail" to entry["thumbnail"],
                                    "title" to entry["title"],
                                    "needsExtractor" to true,
                                )
                            },
                            "hasMore" to (entries.size >= count),
                        ),
                    )
                } catch (e: Throwable) {
                    // gallery-dl's reason (often "login required") is the more useful one
                    // for the platforms it handles.
                    throw galleryError ?: e
                }
            } catch (e: Throwable) {
                fail(result, ERROR_EXTRACT, e)
            } finally {
                cookies?.delete()
            }
        }
    }

    private fun extractVideoInfo(url: String, cookies: File?): Map<String, Any?> {
        val request = YoutubeDLRequest(url)
            .addOption("--dump-single-json")
            .addOption("--no-playlist")
            .addOption("--no-warnings")
        if (cookies != null) request.addOption("--cookies", cookies.absolutePath)

        val response = YoutubeDL.getInstance().execute(request, null, null)
        val json = response.out.trim()
        if (json.isEmpty()) {
            throw YoutubeDLException(
                response.err.ifBlank { "No media information was returned for this link." },
            )
        }
        return MediaInfoParser.parse(json, url)
    }

    /**
     * Combines both lookups. The photo option is offered when the post has at least one photo,
     * or when gallery-dl is the only extractor that could read the link at all.
     */
    private fun mergeMediaInfo(
        url: String,
        video: Map<String, Any?>?,
        gallery: GalleryEngine.Info?,
    ): Map<String, Any?>? {
        val offerGallery = gallery != null && (gallery.imageCount > 0 || video == null)
        if (video == null && !offerGallery) return null

        val galleryFields: Map<String, Any?> = if (gallery != null && offerGallery) {
            val count = gallery.items.size
            val label = when {
                gallery.videoCount == 0 -> if (count == 1) "Photo" else "Photos ($count)"
                else -> "All media ($count)"
            }
            mapOf(
                "galleryOption" to mapOf(
                    "id" to "gallery",
                    "kind" to "gallery",
                    "label" to label,
                    "engine" to ENGINE_GALLERY,
                    "formatSelection" to "gallery",
                    "formatSort" to "",
                    "extractAudio" to false,
                    "audioFormat" to null,
                    "ext" to gallery.items.first().extension,
                    "height" to null,
                    "fileSize" to null,
                    "itemCount" to count,
                    "imageCount" to gallery.imageCount,
                    "videoCount" to gallery.videoCount,
                ),
                "galleryItems" to gallery.items.map { it.toMap() },
            )
        } else {
            mapOf("galleryOption" to null, "galleryItems" to emptyList<Map<String, Any?>>())
        }

        if (video != null) return video + galleryFields

        val photos = gallery!!
        return mapOf(
            "id" to photos.id,
            "url" to url,
            "webpageUrl" to url,
            "title" to (photos.title ?: photos.uploader?.let { "Post by $it" } ?: "Untitled"),
            "uploader" to photos.uploader,
            "thumbnail" to photos.items.firstNotNullOfOrNull { it.thumbnail },
            "duration" to null,
            "platform" to photos.platform,
            "extractor" to "gallery-dl",
            "entryCount" to photos.items.size,
            "videoOptions" to emptyList<Map<String, Any?>>(),
            "noWatermarkOption" to null,
            "audioOptions" to emptyList<Map<String, Any?>>(),
            "formats" to emptyList<Map<String, Any?>>(),
        ) + galleryFields
    }

    /**
     * When nothing could be extracted, prefer gallery-dl's reason if yt-dlp only said the link
     * has no video: for a photo post, "login required" is the useful message.
     */
    private fun pickExtractionError(videoError: Throwable?, galleryError: Throwable?): Throwable {
        if (videoError == null) {
            return galleryError ?: YoutubeDLException("No downloadable media was found.")
        }
        if (galleryError == null) return videoError
        val message = videoError.message.orEmpty()
        val noVideo = listOf("no video", "unsupported url", "no media", "no formats")
            .any { message.contains(it, ignoreCase = true) }
        return if (noVideo) galleryError else videoError
    }

    // endregion

    // region downloading

    fun startDownload(request: DownloadRequest, result: MethodChannel.Result) {
        if (!activeTasks.add(request.taskId)) {
            result.error(ERROR_DOWNLOAD, "Task ${request.taskId} is already running.", null)
            return
        }
        canceledTasks.remove(request.taskId)
        emit(progressEvent(request.taskId, STATUS_STARTING, 0.0, "", -1))
        result.success(true)
        executor.execute { runDownload(request) }
    }

    /** Kills the task's extractor process; the terminal "canceled" event follows on the stream. */
    fun cancelDownload(taskId: String): Boolean {
        if (!activeTasks.contains(taskId)) return false
        canceledTasks.add(taskId)
        return try {
            ConverterEngine.cancel(taskId) || EditorEngine.cancel(taskId) ||
                GalleryEngine.cancel(taskId) ||
                YoutubeDL.getInstance().destroyProcessById(taskId)
        } catch (e: Throwable) {
            Log.w(TAG, "Failed to destroy process $taskId", e)
            false
        }
    }

    private fun runDownload(request: DownloadRequest) {
        val taskId = request.taskId
        val pathFile = File(appContext.cacheDir, "savekit-$taskId.paths")
        var cookies: File? = null
        val progress = ProgressTracker(taskId, audioOnly = request.extractAudio)

        try {
            ensureInitialized()
            if (canceledTasks.contains(taskId)) throw YoutubeDL.CanceledException()

            val outputDir = File(request.outputDir)
            if (!outputDir.exists() && !outputDir.mkdirs()) {
                throw YoutubeDLException("Cannot create the download folder ${outputDir.path}.")
            }
            pathFile.delete()
            cookies = snapshotCookies(request.cookiesFilePath, "task-$taskId")

            if (request.engine == ENGINE_CONVERT) {
                val file = convertToAudio(request, outputDir)
                emit(completedEvent(taskId, listOf(file)))
                return
            }

            if (request.engine == ENGINE_EDIT) {
                var lastEmit = 0L
                val files = EditorEngine.edit(
                    appContext, taskId, File(request.url), outputDir,
                    request.formatSelection, request.options,
                ) { percent ->
                    val now = SystemClock.elapsedRealtime()
                    if (now - lastEmit >= PROGRESS_INTERVAL_MS) {
                        lastEmit = now
                        emit(progressEvent(taskId, STATUS_DOWNLOADING, percent, "", -1))
                    }
                }
                emit(completedEvent(taskId, files))
                return
            }

            if (request.engine == ENGINE_GALLERY) {
                val files = downloadGallery(request, outputDir, cookies)
                emit(completedEvent(taskId, files))
                return
            }

            val ytRequest = YoutubeDLRequest(request.url)
                .addOption("--no-playlist")
                .addOption("--newline")
                .addOption("--no-mtime")
                .addOption("--windows-filenames")
                .addOption("-f", request.formatSelection)
                .addOption("-o", File(outputDir, "%(title).120B [%(id)s].%(ext)s").absolutePath)
                // Multi-connection downloading: aria2c for direct files, parallel fragments
                // for the HLS/DASH streams yt-dlp fetches itself.
                .addOption("--downloader", ARIA2C_BINARY)
                .addOption(
                    "--external-downloader-args",
                    "aria2c:--max-connection-per-server=$CONNECTIONS --split=$CONNECTIONS " +
                        "--min-split-size=1M",
                )
                .addOption("-N", CONNECTIONS)
                // Where each finished file ended up, written once post-processing is done.
                .addCommands(
                    listOf("--print-to-file", "after_move:filepath", pathFile.absolutePath),
                )

            if (request.formatSort.isNotEmpty()) ytRequest.addOption("-S", request.formatSort)
            if (request.clipStart != null || request.clipEnd != null) {
                // Cuts at the nearest keyframes: fast, and accurate to a few seconds.
                val from = request.clipStart?.let { formatSeconds(it) } ?: "0"
                val to = request.clipEnd?.let { formatSeconds(it) } ?: "inf"
                ytRequest.addOption("--download-sections", "*$from-$to")
            }
            if (!request.extractAudio && !request.subtitleLanguage.isNullOrBlank()) {
                ytRequest
                    .addOption(if (request.autoSubtitles) "--write-auto-subs" else "--write-subs")
                    .addOption("--sub-langs", request.subtitleLanguage)
                    .addOption("--embed-subs")
            }
            if (request.extractAudio) {
                ytRequest
                    .addOption("-x")
                    .addOption("--audio-format", request.audioFormat)
                    .addOption("--audio-quality", "0")
            } else {
                // FFmpeg merges the separate DASH video and audio streams into one MP4.
                ytRequest.addOption("--merge-output-format", "mp4")
            }
            if (cookies != null) ytRequest.addOption("--cookies", cookies.absolutePath)

            YoutubeDL.getInstance().execute(ytRequest, taskId) { percent, etaSeconds, line ->
                progress.onOutput(percent, etaSeconds, line)
            }

            if (canceledTasks.contains(taskId)) throw YoutubeDL.CanceledException()

            val files = readFinishedFiles(pathFile)
            if (files.isEmpty()) {
                throw YoutubeDLException("The download finished but no output file was produced.")
            }
            emit(completedEvent(taskId, files))
        } catch (e: Throwable) {
            if (e is YoutubeDL.CanceledException || e is GalleryEngine.CanceledException ||
                e is ConverterEngine.CanceledException ||
                e is EditorEngine.CanceledException || canceledTasks.contains(taskId)
            ) {
                emit(progressEvent(taskId, STATUS_CANCELED, progress.lastPercent, "", -1))
            } else {
                Log.e(TAG, "Download $taskId failed", e)
                emit(
                    progressEvent(taskId, STATUS_FAILED, progress.lastPercent, "", -1) +
                        mapOf("error" to readableError(e)),
                )
            }
        } finally {
            pathFile.delete()
            cookies?.delete()
            activeTasks.remove(taskId)
            canceledTasks.remove(taskId)
        }
    }

    /** Converter: turns a video already on the phone into an audio file with FFmpeg. */
    private fun convertToAudio(request: DownloadRequest, outputDir: File): File {
        val taskId = request.taskId
        val input = File(request.url)
        var lastEmit = 0L
        val output = ConverterEngine.convert(
            appContext, taskId, input, outputDir, request.audioFormat,
        ) { percent, speed ->
            val now = SystemClock.elapsedRealtime()
            if (now - lastEmit >= PROGRESS_INTERVAL_MS) {
                lastEmit = now
                emit(progressEvent(taskId, STATUS_DOWNLOADING, percent, speed, -1))
            }
        }
        // A video picked from elsewhere on the phone was copied into the cache first;
        // that copy is no longer needed. Files in the user's own folders are never touched.
        if (input.absolutePath.startsWith(appContext.cacheDir.absolutePath)) input.delete()
        return output
    }

    /** Photo posts: gallery-dl saves the files one by one, so progress is counted per file. */
    private fun downloadGallery(request: DownloadRequest, outputDir: File, cookies: File?): List<File> {
        val taskId = request.taskId
        val total = request.itemCount
        return GalleryEngine.download(
            appContext, taskId, request.url, outputDir, cookies, request.options["range"],
        ) { finished ->
            val percent = if (total > 0) (finished * 100.0 / total).coerceIn(0.0, 99.0) else 0.0
            val label = if (total > 0) "$finished/$total files" else "$finished files"
            emit(progressEvent(taskId, STATUS_DOWNLOADING, percent, label, -1))
        }
    }

    private fun completedEvent(taskId: String, files: List<File>): Map<String, Any?> =
        progressEvent(taskId, STATUS_COMPLETED, 100.0, "", 0) + mapOf(
            "filePath" to files.first().absolutePath,
            "filePaths" to files.map { it.absolutePath },
            "fileSize" to files.sumOf { it.length() },
        )

    private fun formatSeconds(seconds: Double): String =
        if (seconds == Math.floor(seconds)) seconds.toLong().toString() else seconds.toString()

    private fun readFinishedFiles(pathFile: File): List<File> {
        if (!pathFile.exists()) return emptyList()
        return pathFile.readLines()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .distinct()
            .map { File(it) }
            .filter { it.exists() }
    }

    private fun progressEvent(
        taskId: String,
        status: String,
        percent: Double,
        speed: String,
        eta: Int,
    ): Map<String, Any?> = mapOf(
        "taskId" to taskId,
        "status" to status,
        "progressPercent" to percent,
        "speed" to speed,
        "eta" to eta,
    )

    /**
     * Converts yt-dlp's output into throttled progress events with the stage the download
     * is in. yt-dlp hands the file transfer to aria2c, whose progress lines differ from its
     * own, so both are read. A merged download fetches the video and then the audio, each
     * reporting 0..100; the overall percentage weighs the video more, being far larger.
     *
     * Stages: `connecting`, `info` (reading the page), `video`, `audio`, `file` (a single
     * stream), `subtitles`, `merge`, `convert` and `finishing`.
     */
    private class ProgressTracker(private val taskId: String, private val audioOnly: Boolean) {
        private var streamCount = 1
        private var streamIndex = 0
        private var speed = ""
        private var status = STATUS_STARTING
        private var stage = "connecting"
        private var sizeText = ""
        private var eta = -1
        private var lastEmit = 0L

        @Volatile
        var lastPercent = 0.0
            private set

        /** Share of the whole download each stream stands for, by position. */
        private fun weights(): List<Double> = when {
            streamCount == 2 && !audioOnly -> listOf(0.85, 0.15)
            else -> List(streamCount) { 1.0 / streamCount }
        }

        private fun streamStage(): String = when {
            audioOnly -> "audio"
            streamCount == 1 -> "file"
            streamIndex <= 1 -> "video"
            else -> "audio"
        }

        fun onOutput(rawPercent: Float, etaSeconds: Long, line: String) {
            val formatCount = FORMAT_COUNT.matcher(line)
            if (formatCount.find()) {
                streamCount = formatCount.group(1)!!.split('+').size.coerceAtLeast(1)
                streamIndex = 0
            }
            var streamPercent = if (rawPercent >= 0f) rawPercent.toDouble() else -1.0
            eta = if (etaSeconds >= 0) etaSeconds.toInt() else eta

            if (line.startsWith("[download] Destination:")) {
                if (SUBTITLE_FILE.matcher(line.trim()).find()) {
                    stage = "subtitles"
                } else {
                    streamIndex = (streamIndex + 1).coerceAtMost(streamCount)
                    stage = streamStage()
                }
                sizeText = ""
            } else if (status == STATUS_STARTING && READING_INFO.matcher(line).find()) {
                stage = "info"
            }

            val aria = ARIA2C_PROGRESS.matcher(line)
            if (aria.find()) {
                streamPercent = aria.group(3)!!.toDouble()
                sizeText = "${readableSize(aria.group(1)!!)} of ${readableSize(aria.group(2)!!)}"
                eta = aria.group(4)?.let { parseAriaEta(it) } ?: eta
                if (stage == "connecting" || stage == "info") stage = streamStage()
            } else {
                val own = YTDLP_TOTAL.matcher(line)
                if (own.find()) {
                    val total = own.group(2)!!.toDouble()
                    val unit = own.group(3)!!
                    val done = total * own.group(1)!!.toDouble() / 100
                    sizeText = "${readableSize("%.1f$unit".format(java.util.Locale.US, done))} " +
                        "of ${readableSize(own.group(2)!! + unit)}"
                    if (stage == "connecting" || stage == "info") stage = streamStage()
                }
            }

            val postProcessor = POST_PROCESSORS.firstOrNull { line.startsWith(it) }
            if (postProcessor != null) {
                stage = when (postProcessor) {
                    "[Merger]" -> "merge"
                    "[ExtractAudio]", "[VideoConvertor]" -> "convert"
                    else -> "finishing"
                }
                sizeText = ""
            }
            val newStatus = when {
                postProcessor != null -> STATUS_PROCESSING
                status == STATUS_PROCESSING -> STATUS_PROCESSING
                streamPercent >= 0 && stage != "subtitles" -> STATUS_DOWNLOADING
                else -> status
            }

            val ytSpeed = YTDLP_SPEED.matcher(line)
            val ariaSpeed = ARIA2C_SPEED.matcher(line)
            when {
                ytSpeed.find() -> speed = ytSpeed.group(1)!!
                ariaSpeed.find() -> speed = ariaSpeed.group(1)!! + "/s"
            }

            val percent = when {
                newStatus == STATUS_PROCESSING -> 99.0
                streamPercent < 0 || stage == "subtitles" -> lastPercent
                else -> {
                    val shares = weights()
                    val index = (streamIndex - 1).coerceIn(0, shares.size - 1)
                    val before = shares.take(index).sum()
                    val overall = (before + shares[index] * streamPercent / 100) * 100
                    // Never report backwards when a new stream restarts at 0%.
                    maxOf(lastPercent, overall.coerceIn(0.0, 99.0))
                }
            }

            val now = SystemClock.elapsedRealtime()
            val changed = newStatus != status
            status = newStatus
            lastPercent = percent
            if (!changed && now - lastEmit < PROGRESS_INTERVAL_MS) return
            lastEmit = now

            emit(
                progressEvent(
                    taskId = taskId,
                    status = status,
                    percent = percent,
                    speed = if (status == STATUS_PROCESSING) "" else speed,
                    eta = if (status == STATUS_PROCESSING) -1 else eta,
                ) + mapOf("stage" to stage, "sizeText" to sizeText),
            )
        }

        /** "40.0MiB" -> "40.0 MB": the units people know. */
        private fun readableSize(raw: String): String {
            val match = Regex("([0-9.]+)\\s*([KMGT]?)i?B").find(raw) ?: return raw
            val unit = match.groupValues[2].ifEmpty { "" } + "B"
            return "${match.groupValues[1]} $unit"
        }

        private fun parseAriaEta(text: String): Int? {
            val match = ARIA2C_ETA.matcher(text)
            if (!match.matches()) return null
            val hours = match.group(1)?.toInt() ?: 0
            val minutes = match.group(2)?.toInt() ?: 0
            val seconds = match.group(3)?.toInt() ?: 0
            return hours * 3600 + minutes * 60 + seconds
        }
    }

    // endregion

    /** Runs [work] off the main thread and answers [result] with its value or its error. */
    fun runInBackground(result: MethodChannel.Result, errorCode: String, work: () -> Any?) {
        executor.execute {
            try {
                succeed(result, work())
            } catch (e: Throwable) {
                fail(result, errorCode, e)
            }
        }
    }

    // region shared storage

    /** Copies a finished file into the device's shared storage; answers with its address. */
    fun exportToMediaStore(path: String, kind: String, result: MethodChannel.Result) {
        runInBackground(result, ERROR_EXPORT) {
            MediaStoreExporter.export(appContext, path, kind)
        }
    }

    // endregion

    // region helpers

    /**
     * yt-dlp rewrites the cookie file it is given when it exits. Each run gets a private copy
     * so parallel tasks never corrupt the shared `cookies.txt` exported by the WebView.
     */
    private fun snapshotCookies(cookiesFilePath: String?, name: String): File? {
        if (cookiesFilePath.isNullOrBlank()) return null
        val source = File(cookiesFilePath)
        if (!source.isFile || source.length() == 0L) return null
        val copy = File(appContext.cacheDir, "savekit-cookies-$name.txt")
        source.copyTo(copy, overwrite = true)
        return copy
    }

    /** yt-dlp reports failures on stderr as `ERROR: ...`; surface that line, not the whole log. */
    private fun readableError(error: Throwable): String {
        val raw = error.message?.trim().orEmpty()
        if (raw.isEmpty()) return error.javaClass.simpleName
        val errorLine = raw.lineSequence()
            .map { it.trim() }
            .lastOrNull { it.startsWith("ERROR:") }
        return (errorLine?.removePrefix("ERROR:")?.trim() ?: raw.lines().last().trim())
            .ifEmpty { raw }
    }

    // endregion
}
