package com.savekit.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.OpenableColumns
import java.io.File

/**
 * Photos and videos the user picks from the phone to add to the Vault: what each one is
 * and where it lives, then a copy of it in the app's own folder. Moving is a copy followed
 * by deleting the original through [MediaStoreExporter], which asks the user.
 */
object PhoneMedia {

    const val REQUEST_PICK_MEDIA = 7304

    fun pickIntent(): Intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
        .addCategory(Intent.CATEGORY_OPENABLE)
        .setType("*/*")
        .putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*"))
        .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)

    /** Every address the picker returned, one or many. */
    fun pickedUris(resultCode: Int, data: Intent?): List<Uri> {
        if (resultCode != Activity.RESULT_OK || data == null) return emptyList()
        val clips = data.clipData
        if (clips != null) return (0 until clips.itemCount).mapNotNull { clips.getItemAt(it).uri }
        return listOfNotNull(data.data)
    }

    /**
     * For each picked file: `uri` (to copy from), `name`, `size`, `isVideo`, and, when it is
     * in the phone's media library, `mediaUri` (to delete it after a move) and `folder`,
     * where it is, such as "DCIM/Camera/".
     */
    fun describe(context: Context, uris: List<Uri>): List<Map<String, Any?>> = uris.map { uri ->
        val resolver = context.contentResolver
        var name = "file"
        var size = 0L
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    if (!cursor.isNull(0)) name = cursor.getString(0)
                    if (!cursor.isNull(1)) size = cursor.getLong(1)
                }
            }
        val type = resolver.getType(uri).orEmpty()
        val mediaUri = mediaUriOf(context, uri)
        mapOf(
            "uri" to uri.toString(),
            "name" to name,
            "size" to size,
            "isVideo" to type.startsWith("video/"),
            "mediaUri" to mediaUri?.toString(),
            "folder" to mediaUri?.let { folderOf(context, it) },
        )
    }

    /** The media-library entry behind a picked document; null for files from elsewhere. */
    private fun mediaUriOf(context: Context, uri: Uri): Uri? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        if (uri.authority == MediaStore.AUTHORITY) return uri
        return try {
            MediaStore.getMediaUri(context, uri)
        } catch (e: Exception) {
            null
        }
    }

    private fun folderOf(context: Context, mediaUri: Uri): String? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            context.contentResolver.query(
                mediaUri, arrayOf(MediaStore.MediaColumns.RELATIVE_PATH), null, null, null,
            )?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getString(0) else null
            }
        } else {
            null
        }
    } catch (e: Exception) {
        null
    }

    /**
     * Copies each of [uris] into [outputDir], keeping its name (numbered when taken).
     * Returns one entry per file: `{uri, path}`, with `path` null when it could not be copied.
     */
    fun import(context: Context, uris: List<String>, outputDir: String): List<Map<String, Any?>> {
        val directory = File(outputDir).apply { mkdirs() }
        return uris.map { address ->
            val uri = Uri.parse(address)
            val path = try {
                val name = describe(context, listOf(uri)).first()["name"] as String
                val clean = name.replace(Regex("[\\\\/:*?\"<>|\\u0000-\\u001f]"), "_")
                    .trimStart('.')
                    .ifEmpty { "file" }
                val target = uniqueFile(directory, clean)
                val part = File(target.path + ".part")
                val input = context.contentResolver.openInputStream(uri)
                    ?: throw IllegalStateException("Could not open $name.")
                input.use { source -> part.outputStream().use { source.copyTo(it) } }
                if (!part.renameTo(target)) {
                    part.delete()
                    throw IllegalStateException("Could not save $name.")
                }
                target.absolutePath
            } catch (e: Exception) {
                null
            }
            mapOf("uri" to address, "path" to path)
        }
    }

    private fun uniqueFile(directory: File, name: String): File {
        var file = File(directory, name)
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val extension = if (dot > 0) name.substring(dot) else ""
        var copy = 1
        while (file.exists()) {
            file = File(directory, "$base ($copy)$extension")
            copy++
        }
        return file
    }
}
