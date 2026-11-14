package com.savekit.app

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/**
 * Copies finished files that are not photos or videos (which the gallery plugin handles) into
 * the device's shared storage: audio into Music/SaveKit, anything else into Download/SaveKit.
 */
object MediaStoreExporter {

    private const val FOLDER = "SaveKit"

    private val MIME_TYPES = mapOf(
        "mp3" to "audio/mpeg",
        "m4a" to "audio/mp4",
        "aac" to "audio/aac",
        "opus" to "audio/ogg",
        "ogg" to "audio/ogg",
        "wav" to "audio/x-wav",
        "flac" to "audio/flac",
        "pdf" to "application/pdf",
    )

    /** Returns the content URI (Android 10+) or file path of the exported copy. */
    fun export(context: Context, path: String, audio: Boolean): String {
        val source = File(path)
        require(source.isFile) { "File not found: $path" }
        val mimeType = MIME_TYPES[source.extension.lowercase()]
            ?: if (audio) "audio/*" else "application/octet-stream"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val collection = if (audio) {
                MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            }
            val directory = if (audio) Environment.DIRECTORY_MUSIC else Environment.DIRECTORY_DOWNLOADS
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, source.name)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.RELATIVE_PATH, "$directory/$FOLDER")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(collection, values)
                ?: throw IllegalStateException("Could not create the shared file.")
            try {
                val output = resolver.openOutputStream(uri)
                    ?: throw IllegalStateException("Could not open the shared file.")
                output.use { stream -> source.inputStream().use { it.copyTo(stream) } }
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } catch (e: Exception) {
                resolver.delete(uri, null, null)
                throw e
            }
            return uri.toString()
        }

        // Android 9 and below: write to the public folder directly (needs the legacy
        // storage permission) and let the media scanner index it.
        @Suppress("DEPRECATION")
        val publicDir = Environment.getExternalStoragePublicDirectory(
            if (audio) Environment.DIRECTORY_MUSIC else Environment.DIRECTORY_DOWNLOADS,
        )
        val targetDir = File(publicDir, FOLDER)
        if (!targetDir.exists() && !targetDir.mkdirs()) {
            throw IllegalStateException("Could not create ${targetDir.path}.")
        }
        var target = File(targetDir, source.name)
        var index = 1
        while (target.exists()) {
            target = File(targetDir, "${source.nameWithoutExtension} ($index).${source.extension}")
            index++
        }
        source.copyTo(target)
        MediaScannerConnection.scanFile(context, arrayOf(target.absolutePath), arrayOf(mimeType), null)
        return target.absolutePath
    }
}
