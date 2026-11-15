package com.savekit.app

import android.app.PendingIntent
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/**
 * Copies finished files into the phone's shared storage, so they appear in the Gallery and
 * music apps, and removes those copies again when the user deletes a download:
 *
 *  - photos  -> Pictures/SaveKit
 *  - videos  -> Movies/SaveKit
 *  - audio   -> Music/SaveKit
 *  - other   -> Download/SaveKit
 *
 * Each export returns the address of the copy, which the app stores so that "delete" can
 * remove exactly that copy later.
 */
object MediaStoreExporter {

    private const val FOLDER = "SaveKit"

    private val MIME_TYPES = mapOf(
        "jpg" to "image/jpeg", "jpeg" to "image/jpeg", "png" to "image/png",
        "webp" to "image/webp", "gif" to "image/gif", "heic" to "image/heic",
        "avif" to "image/avif",
        "mp4" to "video/mp4", "mov" to "video/quicktime", "webm" to "video/webm",
        "mkv" to "video/x-matroska", "m4v" to "video/mp4", "3gp" to "video/3gpp",
        "mp3" to "audio/mpeg", "m4a" to "audio/mp4", "aac" to "audio/aac",
        "opus" to "audio/ogg", "ogg" to "audio/ogg", "wav" to "audio/x-wav",
        "flac" to "audio/flac",
        "pdf" to "application/pdf",
    )

    private class Target(val collection: Uri, val directory: String, val fallbackMime: String)

    private fun targetFor(kind: String): Target = when (kind) {
        "image" -> Target(imageCollection(), Environment.DIRECTORY_PICTURES, "image/*")
        "video" -> Target(videoCollection(), Environment.DIRECTORY_MOVIES, "video/*")
        "audio" -> Target(audioCollection(), Environment.DIRECTORY_MUSIC, "audio/*")
        else -> Target(downloadCollection(), Environment.DIRECTORY_DOWNLOADS, "application/octet-stream")
    }

    private fun volume(): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) MediaStore.VOLUME_EXTERNAL_PRIMARY
        else "external"

    private fun imageCollection(): Uri = MediaStore.Images.Media.getContentUri(volume())
    private fun videoCollection(): Uri = MediaStore.Video.Media.getContentUri(volume())
    private fun audioCollection(): Uri = MediaStore.Audio.Media.getContentUri(volume())
    private fun downloadCollection(): Uri =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Downloads.getContentUri(volume())
        } else {
            MediaStore.Files.getContentUri(volume())
        }

    /**
     * Copies [path] into shared storage as [kind] ("image", "video", "audio" or "other").
     * Returns the content URI of the copy (Android 10+) or its file path (older versions).
     */
    fun export(context: Context, path: String, kind: String): String {
        val source = File(path)
        require(source.isFile) { "File not found: $path" }
        val target = targetFor(kind)
        val mimeType = MIME_TYPES[source.extension.lowercase()] ?: target.fallbackMime

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, source.name)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.RELATIVE_PATH, "${target.directory}/$FOLDER")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(target.collection, values)
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
        val publicDir = Environment.getExternalStoragePublicDirectory(target.directory)
        val targetDir = File(publicDir, FOLDER)
        if (!targetDir.exists() && !targetDir.mkdirs()) {
            throw IllegalStateException("Could not create ${targetDir.path}.")
        }
        var copy = File(targetDir, source.name)
        var index = 1
        while (copy.exists()) {
            copy = File(targetDir, "${source.nameWithoutExtension} ($index).${source.extension}")
            index++
        }
        source.copyTo(copy)
        MediaScannerConnection.scanFile(context, arrayOf(copy.absolutePath), arrayOf(mimeType), null)
        return copy.absolutePath
    }

    /** What happened to a delete request. */
    class DeleteOutcome(
        /** Copies removed. */
        val deleted: Int,
        /**
         * Copies Android will only remove after the user confirms a system dialog (they
         * were created by an earlier installation of the app). Empty when nothing is left.
         */
        val needConsent: List<Uri>,
    )

    /**
     * Removes exported copies from shared storage. [locations] are the values [export]
     * returned. [names] are file names of downloads exported before locations were recorded;
     * their copies are looked up in the SaveKit folders by name.
     */
    fun delete(context: Context, locations: List<String>, names: List<String>): DeleteOutcome {
        val resolver = context.contentResolver
        val uris = LinkedHashSet<Uri>()
        var deleted = 0

        for (location in locations) {
            if (location.startsWith("content://")) {
                uris.add(Uri.parse(location))
            } else {
                // A plain path from Android 9 or below.
                val file = File(location)
                if (file.exists() && file.delete()) {
                    deleted++
                    MediaScannerConnection.scanFile(context, arrayOf(location), null, null)
                }
            }
        }
        if (names.isNotEmpty()) uris.addAll(findByName(context, names))

        val needConsent = ArrayList<Uri>()
        for (uri in uris) {
            try {
                // Zero rows means the copy is already gone, which is what was asked for.
                resolver.delete(uri, null, null)
                deleted++
            } catch (e: SecurityException) {
                needConsent.add(uri)
            } catch (e: Exception) {
                // Unknown or malformed address: nothing to remove.
            }
        }
        return DeleteOutcome(deleted, needConsent)
    }

    /**
     * The system dialog asking the user to allow deleting [uris]; available from
     * Android 11. Null on older versions, where such copies have to be removed by hand.
     */
    fun deleteRequest(context: Context, uris: List<Uri>): PendingIntent? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && uris.isNotEmpty()) {
            MediaStore.createDeleteRequest(context.contentResolver, uris)
        } else {
            null
        }

    /** Finds SaveKit's exported copies whose file name is one of [names]. */
    private fun findByName(context: Context, names: List<String>): List<Uri> {
        val found = ArrayList<Uri>()
        val collections = listOf(
            imageCollection(), videoCollection(), audioCollection(), downloadCollection(),
        )
        // Our own folder only, so a same-named file elsewhere is never touched.
        val folderColumn: String
        val folderPattern: String
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            folderColumn = MediaStore.MediaColumns.RELATIVE_PATH
            folderPattern = "%/$FOLDER/%"
        } else {
            @Suppress("DEPRECATION")
            folderColumn = MediaStore.MediaColumns.DATA
            folderPattern = "%/$FOLDER/%"
        }

        for (chunk in names.distinct().chunked(50)) {
            val placeholders = chunk.joinToString(",") { "?" }
            val selection = "${MediaStore.MediaColumns.DISPLAY_NAME} IN ($placeholders) " +
                "AND $folderColumn LIKE ?"
            val arguments = (chunk + folderPattern).toTypedArray()
            for (collection in collections) {
                try {
                    context.contentResolver.query(
                        collection,
                        arrayOf(MediaStore.MediaColumns._ID),
                        selection,
                        arguments,
                        null,
                    )?.use { cursor ->
                        while (cursor.moveToNext()) {
                            found.add(ContentUris.withAppendedId(collection, cursor.getLong(0)))
                        }
                    }
                } catch (e: Exception) {
                    // A collection this Android version does not have.
                }
            }
        }
        return found
    }
}
