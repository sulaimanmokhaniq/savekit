package com.savekit.app

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.zip.ZipInputStream

/**
 * Photo extraction with gallery-dl, the image-focused counterpart to yt-dlp.
 *
 * gallery-dl is pure Python, so it runs on the Python runtime youtubedl-android already ships:
 * a bundle of gallery-dl and its dependencies is unpacked from the APK assets on first use and
 * started with `libpython.so -m gallery_dl`. Like the rest of the engine it runs entirely on
 * the device and reads the same Netscape `cookies.txt`.
 *
 * [DownloadEngine] must have initialised YoutubeDL (which unpacks Python) before any call here.
 */
object GalleryEngine {

    data class Item(
        val url: String,
        val extension: String,
        val width: Int?,
        val height: Int?,
        val isVideo: Boolean,
        val thumbnail: String?,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "url" to url,
            "extension" to extension,
            "width" to width,
            "height" to height,
            "isVideo" to isVideo,
            "thumbnail" to thumbnail,
        )
    }

    data class Info(
        val id: String?,
        val title: String?,
        val uploader: String?,
        val platform: String,
        val items: List<Item>,
    ) {
        val imageCount: Int get() = items.count { !it.isVideo }
        val videoCount: Int get() = items.count { it.isVideo }
    }

    class Result(val exitCode: Int, val out: String, val err: String)

    class GalleryException(message: String) : Exception(message)

    class CanceledException : Exception()

    private const val TAG = "SaveKitGallery"

    private const val ASSET_DIR = "gallerydl"
    private const val ASSET_BUNDLE = "$ASSET_DIR/site.zip"
    private const val ASSET_VERSION = "$ASSET_DIR/version.txt"
    private const val PREFS = "savekit_gallery"
    private const val PREF_BUNDLE_VERSION = "bundleVersion"

    private const val PYPI_METADATA = "https://pypi.org/pypi/gallery-dl/json"
    private const val MODULE_DIR = "gallery_dl"

    /** gallery-dl message types in `--dump-json` output. */
    private const val MESSAGE_ERROR = -1
    private const val MESSAGE_DIRECTORY = 2
    private const val MESSAGE_URL = 3

    private const val MAX_ITEMS = 300
    private val VIDEO_EXTENSIONS = setOf("mp4", "mov", "webm", "m4v", "mkv", "m3u8")

    private val BASE_ARGS = listOf(
        "--config-ignore", "--no-colors", "--no-input",
        "--retries", "3", "--http-timeout", "30",
    )

    private val setupLock = Any()
    @Volatile
    private var ready = false
    private val processes = ConcurrentHashMap<String, Process>()
    private val canceled: MutableSet<String> = ConcurrentHashMap.newKeySet()

    // region setup and updates

    private fun rootDir(context: Context) = File(context.noBackupFilesDir, "savekit-gallery")

    private fun siteDir(context: Context) = File(rootDir(context), "site")

    /** Unpacks the bundled gallery-dl once per bundle version; cheap afterwards. */
    fun ensureReady(context: Context) {
        if (ready) return
        synchronized(setupLock) {
            if (ready) return
            val bundleVersion = context.assets.open(ASSET_VERSION)
                .bufferedReader().use { it.readText().trim() }
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val site = siteDir(context)
            val installed = prefs.getString(PREF_BUNDLE_VERSION, null)

            if (installed != bundleVersion || !File(site, MODULE_DIR).isDirectory) {
                val staging = File(rootDir(context), "site.staging")
                staging.deleteRecursively()
                staging.mkdirs()
                context.assets.open(ASSET_BUNDLE).use { unzip(it, staging, prefix = null) }
                site.deleteRecursively()
                if (!staging.renameTo(site)) {
                    throw GalleryException("Could not install the photo extractor.")
                }
                prefs.edit().putString(PREF_BUNDLE_VERSION, bundleVersion).apply()
            }
            ready = true
        }
    }

    fun version(context: Context): String {
        return try {
            ensureReady(context)
            run(context, listOf("--version"), null, null).out.trim()
        } catch (e: Throwable) {
            Log.w(TAG, "Could not read the gallery-dl version", e)
            ""
        }
    }

    /**
     * Replaces the installed gallery-dl with the newest release on PyPI, so photo extractors
     * can be fixed without shipping a new APK. Returns true when a newer version was installed.
     */
    fun update(context: Context): Boolean {
        ensureReady(context)
        val current = version(context)

        val metadata = JSONObject(httpGet(PYPI_METADATA).bufferedReader().use { it.readText() })
        val latest = metadata.getJSONObject("info").getString("version")
        if (latest == current) return false

        val files = metadata.getJSONArray("urls")
        var wheelUrl: String? = null
        for (i in 0 until files.length()) {
            val file = files.getJSONObject(i)
            if (file.optString("packagetype") == "bdist_wheel") {
                wheelUrl = file.getString("url")
                break
            }
        }
        val downloadUrl = wheelUrl
            ?: throw GalleryException("No installable gallery-dl release was found.")

        synchronized(setupLock) {
            val staging = File(rootDir(context), "module.staging")
            staging.deleteRecursively()
            staging.mkdirs()
            httpGet(downloadUrl).use { unzip(it, staging, prefix = "$MODULE_DIR/") }
            val newModule = File(staging, MODULE_DIR)
            if (!File(newModule, "__main__.py").isFile) {
                staging.deleteRecursively()
                throw GalleryException("The downloaded gallery-dl release is incomplete.")
            }

            val module = File(siteDir(context), MODULE_DIR)
            val backup = File(rootDir(context), "module.backup")
            backup.deleteRecursively()
            if (module.exists() && !module.renameTo(backup)) {
                staging.deleteRecursively()
                throw GalleryException("Could not replace the installed photo extractor.")
            }
            if (!newModule.renameTo(module)) {
                backup.renameTo(module)
                staging.deleteRecursively()
                throw GalleryException("Could not install the new photo extractor.")
            }
            backup.deleteRecursively()
            staging.deleteRecursively()
        }
        return true
    }

    private fun httpGet(url: String): InputStream {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 20_000
        connection.readTimeout = 60_000
        connection.instanceFollowRedirects = true
        val code = connection.responseCode
        if (code !in 200..299) {
            connection.disconnect()
            throw GalleryException("Update server answered HTTP $code.")
        }
        return connection.inputStream
    }

    /** Extracts a zip, optionally only the entries under [prefix], refusing path traversal. */
    private fun unzip(input: InputStream, target: File, prefix: String?) {
        val root = target.canonicalFile
        ZipInputStream(input.buffered()).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                if (prefix != null && !entry.name.startsWith(prefix)) continue
                val file = File(root, entry.name).canonicalFile
                if (!file.path.startsWith(root.path + File.separator)) {
                    throw GalleryException("Unsafe path in archive: ${entry.name}")
                }
                if (entry.isDirectory) {
                    file.mkdirs()
                } else {
                    file.parentFile?.mkdirs()
                    file.outputStream().use { zip.copyTo(it) }
                }
            }
        }
    }

    // endregion

    // region extraction

    /**
     * Lists the files in a post without downloading them. Returns null when gallery-dl has no
     * extractor for the URL or the post holds nothing it can fetch itself.
     */
    fun getInfo(context: Context, url: String, cookies: File?): Info? {
        ensureReady(context)
        val args = ArrayList(BASE_ARGS)
        args.add("--dump-json")
        if (cookies != null) args.addAll(listOf("--cookies", cookies.absolutePath))
        args.add(url)

        val result = run(context, args, null, null)
        val messages = try {
            JSONArray(result.out.trim().ifEmpty { "[]" })
        } catch (e: Exception) {
            throw GalleryException(errorFrom(result.err) ?: "Unreadable photo extractor output.")
        }

        var directory: JSONObject? = null
        var reportedError: String? = null
        val items = ArrayList<Item>()
        for (i in 0 until messages.length()) {
            val message = messages.optJSONArray(i) ?: continue
            when (message.optInt(0, 0)) {
                MESSAGE_DIRECTORY -> if (directory == null) directory = message.optJSONObject(1)
                MESSAGE_URL -> {
                    if (items.size >= MAX_ITEMS) continue
                    val itemUrl = message.optString(1)
                    // "ytdl:" entries are streams gallery-dl hands to yt-dlp; that path
                    // already goes through the video engine.
                    if (!itemUrl.startsWith("http")) continue
                    val meta = message.optJSONObject(2) ?: JSONObject()
                    val extension = meta.string("extension")?.lowercase().orEmpty()
                    val isVideo = extension in VIDEO_EXTENSIONS
                    items.add(
                        Item(
                            url = itemUrl,
                            extension = extension,
                            width = meta.int("width"),
                            height = meta.int("height"),
                            isVideo = isVideo,
                            thumbnail = if (isVideo) {
                                meta.string("display_url")
                                    ?: meta.string("thumbnail")
                                    ?: meta.string("preview")
                            } else {
                                itemUrl
                            },
                        ),
                    )
                }
                MESSAGE_ERROR -> {
                    val error = message.optJSONObject(1)
                    reportedError = error?.string("message") ?: error?.string("error")
                }
            }
        }

        if (items.isEmpty()) {
            val error = reportedError ?: errorFrom(result.err)
            if (error == null || error.contains("Unsupported URL", ignoreCase = true)) return null
            throw GalleryException(error)
        }

        val meta = directory ?: JSONObject()
        return Info(
            id = meta.string("post_id") ?: meta.string("tweet_id") ?: meta.string("id"),
            title = titleOf(meta),
            uploader = uploaderOf(meta),
            platform = platformOf(meta.string("category").orEmpty()),
            items = items,
        )
    }

    private fun titleOf(meta: JSONObject): String? {
        val text = meta.string("title")
            ?: meta.string("description")
            ?: meta.string("content")
            ?: meta.string("caption")
            ?: meta.string("desc")
            ?: return null
        val line = text.lineSequence().map { it.trim() }.firstOrNull { it.isNotEmpty() }
            ?: return null
        return if (line.length > 120) line.take(117).trimEnd() + "…" else line
    }

    private fun uploaderOf(meta: JSONObject): String? {
        meta.string("username")?.let { return it }
        meta.string("fullname")?.let { return it }
        for (key in listOf("author", "user", "owner")) {
            val nested = meta.optJSONObject(key)
            if (nested != null) {
                (nested.string("name")
                    ?: nested.string("nick")
                    ?: nested.string("username")
                    ?: nested.string("uniqueId")
                    ?: nested.string("nickname"))?.let { return it }
            } else {
                meta.string(key)?.let { return it }
            }
        }
        return meta.string("uploader")
    }

    private fun platformOf(category: String): String = when (category.lowercase()) {
        "twitter" -> "x"
        "" -> "generic"
        else -> category.lowercase()
    }

    // endregion

    // region downloading

    /**
     * Downloads every file of the post into [outputDir] and returns them. [onProgress] gets
     * the number of files finished so far. Throws [CanceledException] after [cancel].
     */
    fun download(
        context: Context,
        taskId: String,
        url: String,
        outputDir: File,
        cookies: File?,
        onProgress: (finished: Int) -> Unit,
    ): List<File> {
        ensureReady(context)
        if (canceled.contains(taskId)) {
            canceled.remove(taskId)
            throw CanceledException()
        }

        // gallery-dl writes into a private folder first, so the finished files are known
        // exactly and a canceled task leaves nothing behind in the download folder.
        val staging = File(outputDir, ".savekit-$taskId")
        staging.deleteRecursively()
        if (!staging.mkdirs()) {
            throw GalleryException("Cannot create the download folder ${outputDir.path}.")
        }

        try {
            val args = ArrayList(BASE_ARGS)
            args.addAll(listOf("--no-mtime", "--directory", staging.absolutePath))
            if (cookies != null) args.addAll(listOf("--cookies", cookies.absolutePath))
            args.add(url)

            var finished = 0
            val result = run(context, args, taskId) { line ->
                // One line per saved file; "# path" marks a file that already existed.
                if (line.isNotBlank()) {
                    finished++
                    onProgress(finished)
                }
            }
            if (canceled.contains(taskId)) throw CanceledException()

            val downloaded = staging.listFiles()
                ?.filter { it.isFile && it.length() > 0 && !it.name.endsWith(".part") }
                ?.sortedBy { it.name }
                .orEmpty()
            if (downloaded.isEmpty()) {
                throw GalleryException(
                    errorFrom(result.err) ?: "No files could be downloaded from this post.",
                )
            }
            return downloaded.map { file ->
                val target = uniqueTarget(outputDir, file.name)
                if (!file.renameTo(target)) file.copyTo(target, overwrite = true)
                target
            }
        } finally {
            canceled.remove(taskId)
            staging.deleteRecursively()
        }
    }

    /** Kills the task's gallery-dl process. Returns false when the task is not running here. */
    fun cancel(taskId: String): Boolean {
        val process = processes[taskId] ?: return false
        canceled.add(taskId)
        process.destroy()
        return true
    }

    fun isRunning(taskId: String): Boolean = processes.containsKey(taskId)

    private fun uniqueTarget(directory: File, name: String): File {
        var target = File(directory, name)
        if (!target.exists()) return target
        val base = name.substringBeforeLast('.', name)
        val extension = name.substringAfterLast('.', "")
        var index = 1
        while (target.exists()) {
            val candidate = if (extension.isEmpty()) "$base ($index)" else "$base ($index).$extension"
            target = File(directory, candidate)
            index++
        }
        return target
    }

    // endregion

    // region process

    /**
     * Runs `python -m gallery_dl` with the environment youtubedl-android uses for yt-dlp, plus
     * PYTHONPATH pointing at the unpacked bundle.
     */
    private fun run(
        context: Context,
        args: List<String>,
        taskId: String?,
        onStdoutLine: ((String) -> Unit)?,
    ): Result {
        val nativeDir = File(context.applicationInfo.nativeLibraryDir)
        val packages = File(File(context.noBackupFilesDir, "youtubedl-android"), "packages")
        val pythonHome = File(packages, "python/usr")
        val home = rootDir(context).also { it.mkdirs() }

        val command = ArrayList<String>()
        command.add(File(nativeDir, "libpython.so").absolutePath)
        command.addAll(listOf("-m", MODULE_DIR))
        command.addAll(args)

        val builder = ProcessBuilder(command)
        builder.environment().apply {
            this["LD_LIBRARY_PATH"] = listOf(
                File(pythonHome, "lib"),
                File(packages, "ffmpeg/usr/lib"),
                File(packages, "aria2c/usr/lib"),
            ).joinToString(":") { it.absolutePath }
            this["SSL_CERT_FILE"] = File(pythonHome, "etc/tls/cert.pem").absolutePath
            this["PYTHONHOME"] = pythonHome.absolutePath
            this["PYTHONPATH"] = siteDir(context).absolutePath
            this["PYTHONIOENCODING"] = "utf-8"
            this["PATH"] = System.getenv("PATH").orEmpty() + ":" + nativeDir.absolutePath
            this["HOME"] = home.absolutePath
            this["TMPDIR"] = context.cacheDir.absolutePath
        }

        val process = builder.start()
        if (taskId != null) processes[taskId] = process
        try {
            val out = StringBuilder()
            val err = StringBuilder()
            val outReader = Thread {
                process.inputStream.bufferedReader(Charsets.UTF_8).forEachLine { line ->
                    out.append(line).append('\n')
                    onStdoutLine?.invoke(line)
                }
            }
            val errReader = Thread {
                process.errorStream.bufferedReader(Charsets.UTF_8).forEachLine { line ->
                    err.append(line).append('\n')
                }
            }
            outReader.start()
            errReader.start()
            val exitCode = try {
                outReader.join()
                errReader.join()
                process.waitFor()
            } catch (e: InterruptedException) {
                process.destroy()
                throw e
            }
            return Result(exitCode, out.toString(), err.toString())
        } finally {
            if (taskId != null) processes.remove(taskId)
        }
    }

    /** gallery-dl logs failures as `[source][error] message`; return the last such message. */
    private fun errorFrom(stderr: String): String? {
        val line = stderr.lineSequence()
            .map { it.trim() }
            .lastOrNull { it.contains("[error]") }
            ?: return null
        return line.substringAfter("[error]").trim().ifEmpty { null }
    }

    private fun JSONObject.string(key: String): String? {
        if (!has(key) || isNull(key)) return null
        val value = opt(key)
        if (value is JSONObject || value is JSONArray) return null
        return value.toString().takeIf { it.isNotBlank() }
    }

    private fun JSONObject.int(key: String): Int? {
        if (!has(key) || isNull(key)) return null
        val value = optDouble(key)
        return if (value.isNaN() || value.isInfinite() || value <= 0) null else value.toInt()
    }

    // endregion
}
