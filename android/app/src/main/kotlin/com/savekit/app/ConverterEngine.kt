package com.savekit.app

import android.content.Context
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.regex.Pattern

/**
 * Converts a video file already on the device into an audio file, using the FFmpeg binary
 * that youtubedl-android bundles. Nothing is uploaded: FFmpeg runs as a local process.
 *
 * [DownloadEngine] must have initialised YoutubeDL and FFmpeg (which unpack the binary's
 * libraries) before any call here.
 */
object ConverterEngine {

    class ConversionException(message: String) : Exception(message)

    class CanceledException : Exception()

    private val DURATION = Pattern.compile("Duration:\\s*(\\d+):(\\d+):(\\d+(?:\\.\\d+)?)")
    private val TIME = Pattern.compile("time=(\\d+):(\\d+):(\\d+(?:\\.\\d+)?)")
    private val SPEED = Pattern.compile("speed=\\s*([0-9.]+)x")

    private val processes = ConcurrentHashMap<String, Process>()
    private val canceled: MutableSet<String> = ConcurrentHashMap.newKeySet()

    /**
     * Writes the audio of [input] to [outputDir] as [format] ("mp3" or "m4a") and returns the
     * new file. [onProgress] gets 0..100 and FFmpeg's speed, e.g. "24x".
     */
    fun convert(
        context: Context,
        taskId: String,
        input: File,
        outputDir: File,
        format: String,
        onProgress: (percent: Double, speed: String) -> Unit,
    ): File {
        if (!input.isFile) throw ConversionException("The video file could not be found.")
        if (!outputDir.exists() && !outputDir.mkdirs()) {
            throw ConversionException("Cannot create the folder ${outputDir.path}.")
        }
        if (canceled.remove(taskId)) throw CanceledException()

        val extension = if (format == "m4a") "m4a" else "mp3"
        val codec = if (extension == "m4a") {
            listOf("-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart")
        } else {
            listOf("-c:a", "libmp3lame", "-q:a", "2")
        }
        // FFmpeg picks the container from the extension, so the temporary name keeps it.
        val temp = File(outputDir, ".savekit-$taskId.$extension")
        temp.delete()

        val nativeDir = File(context.applicationInfo.nativeLibraryDir)
        val packages = File(File(context.noBackupFilesDir, "youtubedl-android"), "packages")
        val command = ArrayList<String>()
        command.add(File(nativeDir, "libffmpeg.so").absolutePath)
        command.addAll(listOf("-hide_banner", "-nostdin", "-y", "-i", input.absolutePath, "-vn"))
        command.addAll(codec)
        command.add(temp.absolutePath)

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
        var durationSeconds = 0.0
        val exitCode: Int
        try {
            // FFmpeg rewrites its status line with carriage returns.
            val reader = process.inputStream.bufferedReader(Charsets.UTF_8)
            val line = StringBuilder()
            while (true) {
                val next = reader.read()
                if (next == -1) break
                if (next == '\r'.code || next == '\n'.code) {
                    val text = line.toString()
                    line.setLength(0)
                    if (text.isBlank()) continue
                    log.addLast(text)
                    if (log.size > 40) log.removeFirst()

                    if (durationSeconds == 0.0) {
                        val duration = DURATION.matcher(text)
                        if (duration.find()) durationSeconds = seconds(duration)
                    }
                    val time = TIME.matcher(text)
                    if (time.find() && durationSeconds > 0) {
                        val speed = SPEED.matcher(text)
                        onProgress(
                            (seconds(time) / durationSeconds * 100).coerceIn(0.0, 99.0),
                            if (speed.find()) "${speed.group(1)}x" else "",
                        )
                    }
                } else {
                    line.append(next.toChar())
                }
            }
            exitCode = process.waitFor()
        } catch (e: InterruptedException) {
            process.destroy()
            temp.delete()
            throw e
        } finally {
            processes.remove(taskId)
        }

        if (canceled.remove(taskId)) {
            temp.delete()
            throw CanceledException()
        }
        if (exitCode != 0 || !temp.isFile || temp.length() == 0L) {
            temp.delete()
            throw ConversionException(describeFailure(log))
        }

        val target = uniqueTarget(outputDir, input.nameWithoutExtension, extension)
        if (!temp.renameTo(target)) {
            temp.copyTo(target, overwrite = true)
            temp.delete()
        }
        return target
    }

    /** Kills the task's FFmpeg process. Returns false when the task is not converting. */
    fun cancel(taskId: String): Boolean {
        val process = processes[taskId] ?: return false
        canceled.add(taskId)
        process.destroy()
        return true
    }

    private fun seconds(match: java.util.regex.Matcher): Double =
        match.group(1)!!.toDouble() * 3600 + match.group(2)!!.toDouble() * 60 +
            match.group(3)!!.toDouble()

    private fun describeFailure(log: Collection<String>): String {
        val text = log.joinToString("\n")
        return when {
            text.contains("does not contain any stream") ||
                text.contains("matches no streams") -> "This video has no audio track."
            text.contains("Invalid data found") -> "This file is not a video FFmpeg can read."
            text.contains("No space left") -> "There is not enough free space on the phone."
            else -> log.lastOrNull { it.isNotBlank() && !it.startsWith("size=") }
                ?: "The conversion failed."
        }
    }

    private fun uniqueTarget(directory: File, baseName: String, extension: String): File {
        val safe = baseName.replace(Regex("[\\\\/:*?\"<>|]"), "_").ifBlank { "audio" }
        var target = File(directory, "$safe.$extension")
        var index = 1
        while (target.exists()) {
            target = File(directory, "$safe ($index).$extension")
            index++
        }
        return target
    }
}
