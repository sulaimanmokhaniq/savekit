package com.savekit.app

import android.content.Context
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.regex.Pattern

/**
 * Small edits of a video already on the phone, all done by the bundled FFmpeg:
 *
 *  - `split`    cut into parts of `seconds` each (for WhatsApp Status)
 *  - `vertical` crop the middle to 9:16
 *  - `compress` re-encode to about `targetMb` megabytes (needs `duration`), optionally
 *               with the picture's shorter side reduced to `shortSide` pixels
 *  - `gif`      turn `length` seconds from `start` into an animated GIF
 *  - `frame`    save the picture at `at` seconds as a JPEG
 *  - `clip`     copy `length` seconds from `start` (video or audio), without re-encoding
 *
 * Nothing is uploaded. [DownloadEngine] must have initialised FFmpeg first.
 */
object EditorEngine {

    class EditException(message: String) : Exception(message)

    class CanceledException : Exception()

    private val DURATION = Pattern.compile("Duration:\\s*(\\d+):(\\d+):(\\d+(?:\\.\\d+)?)")
    private val TIME = Pattern.compile("time=(\\d+):(\\d+):(\\d+(?:\\.\\d+)?)")

    private val processes = ConcurrentHashMap<String, Process>()
    private val canceled: MutableSet<String> = ConcurrentHashMap.newKeySet()

    /**
     * Runs [operation] on [input] and returns the files it made, in [outputDir].
     * [onProgress] gets 0..100.
     */
    fun edit(
        context: Context,
        taskId: String,
        input: File,
        outputDir: File,
        operation: String,
        options: Map<String, String>,
        onProgress: (percent: Double) -> Unit,
    ): List<File> {
        if (!input.isFile) throw EditException("The video file could not be found.")
        if (!outputDir.exists() && !outputDir.mkdirs()) {
            throw EditException("Cannot create the folder ${outputDir.path}.")
        }
        if (canceled.remove(taskId)) throw CanceledException()

        // Work happens in a private folder, so a canceled edit leaves nothing behind.
        val work = File(outputDir, ".savekit-$taskId").apply {
            deleteRecursively()
            mkdirs()
        }
        val base = safeName(input.nameWithoutExtension)
        try {
            val made: List<File> = when (operation) {
                "split" -> split(context, taskId, input, work, options, onProgress)
                "vertical" -> encodeVideo(
                    context, taskId, input, File(work, "$base vertical.mp4"),
                    listOf(
                        "-vf",
                        "crop=trunc(min(iw\\,ih*9/16)/2)*2:trunc(min(ih\\,iw*16/9)/2)*2",
                    ),
                    quality = listOf("-crf", "23"),
                    onProgress = onProgress,
                )
                "compress" -> {
                    val targetMb = options["targetMb"]?.toDoubleOrNull() ?: 16.0
                    val duration = options["duration"]?.toDoubleOrNull()
                        ?: throw EditException("The video's length is unknown.")
                    // Leave room for 96 kbps audio and a little container overhead.
                    val totalKbps = targetMb * 8 * 1024 * 0.95 / duration
                    val videoKbps = (totalKbps - 96).toInt().coerceAtLeast(150)
                    // Optionally shrink the picture so its shorter side is at most
                    // `shortSide` pixels; never enlarges.
                    val shortSide = options["shortSide"]?.toIntOrNull()
                    val filters = if (shortSide == null) {
                        emptyList()
                    } else {
                        listOf(
                            "-vf",
                            "scale=if(gt(iw\\,ih)\\,-2\\,min(iw\\,$shortSide)):" +
                                "if(gt(iw\\,ih)\\,min(ih\\,$shortSide)\\,-2)",
                        )
                    }
                    encodeVideo(
                        context, taskId, input, File(work, "$base small.mp4"),
                        // Keep the recording date, so the Gallery files it where it was.
                        filters + listOf("-map_metadata", "0"),
                        quality = listOf(
                            "-b:v", "${videoKbps}k",
                            "-maxrate", "${videoKbps}k",
                            "-bufsize", "${videoKbps * 2}k",
                        ),
                        audioKbps = 96,
                        onProgress = onProgress,
                    )
                }
                "gif" -> {
                    val start = options["start"]?.toDoubleOrNull() ?: 0.0
                    val length = (options["length"]?.toDoubleOrNull() ?: 4.0).coerceIn(1.0, 15.0)
                    val output = File(work, "$base.gif")
                    run(
                        context, taskId,
                        listOf(
                            "-ss", seconds(start), "-t", seconds(length), "-i", input.absolutePath,
                            "-vf",
                            "fps=12,scale=480:-1:flags=lanczos,split[a][b];" +
                                "[a]palettegen[p];[b][p]paletteuse",
                            "-loop", "0", output.absolutePath,
                        ),
                        knownDuration = length,
                        onProgress = onProgress,
                    )
                    listOf(output)
                }
                "clip" -> {
                    // A short piece, copied as it is (no re-encoding): quick, and the
                    // cut lands on the nearest keyframe, a second or two out at most.
                    val start = options["start"]?.toDoubleOrNull() ?: 0.0
                    val length = (options["length"]?.toDoubleOrNull() ?: 30.0)
                        .coerceIn(1.0, 600.0)
                    val extension = input.extension.ifEmpty { "mp4" }
                    val output = File(
                        work,
                        "$base clip ${seconds(start).replace('.', '_')}.$extension",
                    )
                    run(
                        context, taskId,
                        listOf(
                            "-ss", seconds(start), "-t", seconds(length),
                            "-i", input.absolutePath,
                            "-map", "0", "-c", "copy", "-avoid_negative_ts", "make_zero",
                            output.absolutePath,
                        ),
                        knownDuration = length,
                        onProgress = onProgress,
                    )
                    listOf(output)
                }
                "frame" -> {
                    val at = options["at"]?.toDoubleOrNull() ?: 0.0
                    val output = File(work, "$base frame ${seconds(at).replace('.', '_')}.jpg")
                    run(
                        context, taskId,
                        listOf(
                            "-ss", seconds(at), "-i", input.absolutePath,
                            "-frames:v", "1", "-q:v", "2", output.absolutePath,
                        ),
                        knownDuration = null,
                        onProgress = onProgress,
                    )
                    listOf(output)
                }
                else -> throw EditException("Unknown edit: $operation")
            }
            if (canceled.remove(taskId)) throw CanceledException()
            val results = made.filter { it.isFile && it.length() > 0 }
            if (results.isEmpty()) throw EditException("The edit produced no file.")
            return results.map { file ->
                val target = uniqueTarget(outputDir, file.name)
                if (!file.renameTo(target)) file.copyTo(target, overwrite = true)
                target
            }
        } finally {
            canceled.remove(taskId)
            work.deleteRecursively()
        }
    }

    /** Kills the task's FFmpeg process. Returns false when the task is not editing. */
    fun cancel(taskId: String): Boolean {
        val process = processes[taskId] ?: return false
        canceled.add(taskId)
        process.destroy()
        return true
    }

    private fun split(
        context: Context,
        taskId: String,
        input: File,
        work: File,
        options: Map<String, String>,
        onProgress: (Double) -> Unit,
    ): List<File> {
        val partSeconds = (options["seconds"]?.toDoubleOrNull() ?: 60.0).coerceIn(5.0, 600.0)
        // Copying (no re-encoding) is fast but can only cut where the video has a
        // keyframe, so parts are aimed a little short of the limit.
        val aim = (partSeconds - 2).coerceAtLeast(3.0)
        run(
            context, taskId,
            listOf(
                "-i", input.absolutePath, "-map", "0:v:0", "-map", "0:a?", "-c", "copy",
                "-f", "segment", "-segment_time", seconds(aim),
                "-reset_timestamps", "1", "-segment_format", "mp4",
                File(work, "part_%03d.mp4").absolutePath,
            ),
            knownDuration = null,
            onProgress = onProgress,
        )
        val parts = work.listFiles { file -> file.name.startsWith("part_") }
            ?.sortedBy { it.name }
            .orEmpty()
        val base = safeName(input.nameWithoutExtension)
        return parts.mapIndexed { index, part ->
            val named = File(work, "$base part ${index + 1} of ${parts.size}.mp4")
            part.renameTo(named)
            named
        }
    }

    /**
     * Re-encodes video with H.264, or with MPEG-4 Part 2 when this FFmpeg has no H.264
     * encoder, keeping the audio as AAC.
     */
    private fun encodeVideo(
        context: Context,
        taskId: String,
        input: File,
        output: File,
        filters: List<String>,
        quality: List<String>,
        audioKbps: Int = 128,
        onProgress: (Double) -> Unit,
    ): List<File> {
        val audio = listOf("-c:a", "aac", "-b:a", "${audioKbps}k")
        val h264 = listOf("-i", input.absolutePath) + filters +
            listOf("-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p") +
            quality + audio + listOf("-movflags", "+faststart", output.absolutePath)
        try {
            run(context, taskId, h264, knownDuration = null, onProgress = onProgress)
        } catch (e: EditException) {
            val missingEncoder = e.message.orEmpty().let {
                it.contains("libx264") || it.contains("Unknown encoder") ||
                    it.contains("Encoder not found")
            }
            if (!missingEncoder) throw e
            output.delete()
            val mpeg4Quality = if (quality.contains("-crf")) listOf("-q:v", "4") else quality
            val fallback = listOf("-i", input.absolutePath) + filters +
                listOf("-c:v", "mpeg4") + mpeg4Quality + audio + listOf(output.absolutePath)
            run(context, taskId, fallback, knownDuration = null, onProgress = onProgress)
        }
        return listOf(output)
    }

    /** Runs FFmpeg with [args]; throws [EditException] with its last words on failure. */
    private fun run(
        context: Context,
        taskId: String,
        args: List<String>,
        knownDuration: Double?,
        onProgress: (Double) -> Unit,
    ) {
        val nativeDir = File(context.applicationInfo.nativeLibraryDir)
        val packages = File(File(context.noBackupFilesDir, "youtubedl-android"), "packages")
        val command = ArrayList<String>()
        command.add(File(nativeDir, "libffmpeg.so").absolutePath)
        command.addAll(listOf("-hide_banner", "-nostdin", "-y"))
        command.addAll(args)

        val builder = ProcessBuilder(command).redirectErrorStream(true)
        builder.environment().apply {
            this["LD_LIBRARY_PATH"] = listOf(
                File(packages, "ffmpeg/usr/lib"),
                File(packages, "python/usr/lib"),
                File(packages, "aria2c/usr/lib"),
            ).joinToString(":") { it.absolutePath }
            this["TMPDIR"] = context.cacheDir.absolutePath
        }

        val process = builder.start()
        processes[taskId] = process
        val log = ArrayDeque<String>()
        var duration = knownDuration ?: 0.0
        val exitCode: Int
        try {
            val reader = process.inputStream.bufferedReader(Charsets.UTF_8)
            val line = StringBuilder()
            while (true) {
                val next = reader.read()
                if (next == -1) break
                if (next != '\r'.code && next != '\n'.code) {
                    line.append(next.toChar())
                    continue
                }
                val text = line.toString()
                line.setLength(0)
                if (text.isBlank()) continue
                log.addLast(text)
                if (log.size > 40) log.removeFirst()
                if (duration == 0.0) {
                    val match = DURATION.matcher(text)
                    if (match.find()) duration = seconds(match)
                }
                val time = TIME.matcher(text)
                if (time.find() && duration > 0) {
                    onProgress((seconds(time) / duration * 100).coerceIn(0.0, 99.0))
                }
            }
            exitCode = process.waitFor()
        } finally {
            processes.remove(taskId)
        }
        if (canceled.contains(taskId)) throw CanceledException()
        if (exitCode != 0) {
            val text = log.joinToString("\n")
            throw EditException(
                when {
                    text.contains("No space left") ->
                        "There is not enough free space on the phone."
                    text.contains("Invalid data found") ->
                        "This file is not a video FFmpeg can read."
                    else -> log.lastOrNull { it.isNotBlank() && !it.startsWith("size=") }
                        ?: "The edit failed."
                },
            )
        }
    }

    private fun seconds(match: java.util.regex.Matcher): Double =
        match.group(1)!!.toDouble() * 3600 + match.group(2)!!.toDouble() * 60 +
            match.group(3)!!.toDouble()

    private fun seconds(value: Double): String = String.format(java.util.Locale.US, "%.2f", value)

    private fun safeName(name: String): String =
        name.replace(Regex("[\\\\/:*?\"<>|]"), "_").ifBlank { "video" }.take(80)

    private fun uniqueTarget(directory: File, name: String): File {
        var target = File(directory, name)
        if (!target.exists()) return target
        val base = name.substringBeforeLast('.', name)
        val extension = name.substringAfterLast('.', "")
        var index = 1
        while (target.exists()) {
            target = File(directory, if (extension.isEmpty()) "$base ($index)" else "$base ($index).$extension")
            index++
        }
        return target
    }
}
