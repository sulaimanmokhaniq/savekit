package com.savekit.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Point
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * Access to files outside the app through Android's document picker:
 *  - picking a video anywhere on the phone, for the converter;
 *  - the WhatsApp status folder, which the user grants once and SaveKit then reads to list
 *    and copy the statuses WhatsApp has already downloaded for viewing.
 *
 * Nothing here touches WhatsApp itself or the network; it only reads files the user chose
 * to share with the app.
 */
object DeviceFiles {

    const val REQUEST_PICK_VIDEO = 7301
    const val REQUEST_STATUS_FOLDER = 7302

    private const val PREFS = "savekit_device_files"
    private const val PREF_STATUS_TREE = "statusTree"
    private const val EXTERNAL_AUTHORITY = "com.android.externalstorage.documents"

    /** Where WhatsApp and WhatsApp Business keep viewed statuses, newest layout first. */
    private val STATUS_FOLDERS = listOf(
        "Android/media/com.whatsapp/WhatsApp/Media/.Statuses",
        "Android/media/com.whatsapp.w4b/WhatsApp Business/Media/.Statuses",
    )

    private val VIDEO_EXTENSIONS = setOf("mp4", "3gp", "mkv", "webm", "mov")
    private val IMAGE_EXTENSIONS = setOf("jpg", "jpeg", "png", "webp", "gif")

    // region video picker

    fun pickVideoIntent(): Intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
        .addCategory(Intent.CATEGORY_OPENABLE)
        .setType("video/*")

    /**
     * Copies the picked video into the app's cache so FFmpeg can read it as a plain file.
     * Returns `{path, name, size}`.
     */
    fun importPickedVideo(context: Context, uri: Uri): Map<String, Any?> {
        var name = "video"
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) name = cursor.getString(0)
            }
        val directory = File(context.cacheDir, "converter").apply { mkdirs() }
        // One video at a time is staged; older copies are leftovers of abandoned picks.
        directory.listFiles()?.forEach { file ->
            if (System.currentTimeMillis() - file.lastModified() > 24 * 60 * 60 * 1000L) file.delete()
        }
        val target = File(directory, name.replace(Regex("[\\\\/:*?\"<>|]"), "_"))
        val input = context.contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("The video could not be opened.")
        input.use { source -> target.outputStream().use { source.copyTo(it) } }
        return mapOf("path" to target.absolutePath, "name" to name, "size" to target.length())
    }

    // endregion

    // region WhatsApp statuses

    /** Opens the folder picker, pointed at WhatsApp's status folder where Android allows. */
    fun statusFolderIntent(business: Boolean): Intent {
        val folder = if (business) STATUS_FOLDERS[1] else STATUS_FOLDERS[0]
        val initial = DocumentsContract.buildDocumentUri(EXTERNAL_AUTHORITY, "primary:$folder")
        return Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
            .putExtra(DocumentsContract.EXTRA_INITIAL_URI, initial)
            .addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
    }

    /** Remembers the granted folder. Returns false when it is not a status folder. */
    fun saveStatusFolder(context: Context, tree: Uri): Boolean {
        val documentId = DocumentsContract.getTreeDocumentId(tree)
        if (!documentId.endsWith(".Statuses")) return false
        context.contentResolver.takePersistableUriPermission(
            tree,
            Intent.FLAG_GRANT_READ_URI_PERMISSION,
        )
        prefs(context).edit().putString(PREF_STATUS_TREE, tree.toString()).apply()
        return true
    }

    fun statusFolder(context: Context): Uri? {
        val stored = prefs(context).getString(PREF_STATUS_TREE, null) ?: return null
        val tree = Uri.parse(stored)
        val granted = context.contentResolver.persistedUriPermissions.any {
            it.uri == tree && it.isReadPermission
        }
        return if (granted) tree else null
    }

    fun forgetStatusFolder(context: Context) {
        val tree = statusFolder(context)
        if (tree != null) {
            try {
                context.contentResolver.releasePersistableUriPermission(
                    tree,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            } catch (_: SecurityException) {
                // Already released.
            }
        }
        prefs(context).edit().remove(PREF_STATUS_TREE).apply()
    }

    /** The photos and videos in the granted folder, newest first. */
    fun listStatuses(context: Context): List<Map<String, Any?>> {
        val tree = statusFolder(context) ?: return emptyList()
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        val items = ArrayList<Map<String, Any?>>()
        context.contentResolver.query(
            children,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val name = cursor.getString(1) ?: continue
                val extension = name.substringAfterLast('.', "").lowercase()
                val isVideo = extension in VIDEO_EXTENSIONS
                if (!isVideo && extension !in IMAGE_EXTENSIONS) continue
                items.add(
                    mapOf(
                        "uri" to DocumentsContract
                            .buildDocumentUriUsingTree(tree, cursor.getString(0)).toString(),
                        "name" to name,
                        "size" to (if (cursor.isNull(2)) 0L else cursor.getLong(2)),
                        "modified" to (if (cursor.isNull(3)) 0L else cursor.getLong(3)),
                        "isVideo" to isVideo,
                    ),
                )
            }
        }
        items.sortByDescending { it["modified"] as Long }
        return items
    }

    /** A JPEG preview of a status, or null when Android cannot make one. */
    fun statusThumbnail(context: Context, uri: Uri, size: Int): ByteArray? {
        val bitmap = try {
            DocumentsContract.getDocumentThumbnail(
                context.contentResolver,
                uri,
                Point(size, size),
                null,
            )
        } catch (_: Exception) {
            null
        } ?: return null
        val bytes = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 82, bytes)
        bitmap.recycle()
        return bytes.toByteArray()
    }

    /**
     * Copies one status into the app's cache so it can be shown full screen before the
     * user decides to save it. Returns the cached file's path.
     */
    fun cacheStatusForPreview(context: Context, uri: Uri): String {
        val directory = File(context.cacheDir, "status_preview").apply { mkdirs() }
        // Previews are throwaway; keep the folder from growing.
        directory.listFiles()?.forEach { file ->
            if (System.currentTimeMillis() - file.lastModified() > 60 * 60 * 1000L) file.delete()
        }
        var name = "status"
        context.contentResolver.query(
            uri,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) name = cursor.getString(0)
        }
        val target = File(directory, name.replace(Regex("[\\\\/:*?\"<>|]"), "_"))
        if (target.isFile && target.length() > 0) return target.absolutePath
        val input = context.contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("The status could not be opened.")
        input.use { source -> target.outputStream().use { source.copyTo(it) } }
        return target.absolutePath
    }

    /** Copies the chosen statuses into [outputDir] and returns the new file paths. */
    fun importStatuses(context: Context, uris: List<String>, outputDir: File): List<String> {
        if (!outputDir.exists()) outputDir.mkdirs()
        val saved = ArrayList<String>()
        for (text in uris) {
            val uri = Uri.parse(text)
            var name = "status"
            context.contentResolver.query(
                uri,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) name = cursor.getString(0)
            }
            val base = name.substringBeforeLast('.', name)
            val extension = name.substringAfterLast('.', "jpg")
            var target = File(outputDir, "WhatsApp $base.$extension")
            var index = 1
            while (target.exists()) {
                target = File(outputDir, "WhatsApp $base ($index).$extension")
                index++
            }
            try {
                val input = context.contentResolver.openInputStream(uri) ?: continue
                input.use { source -> target.outputStream().use { source.copyTo(it) } }
                if (target.length() > 0) saved.add(target.absolutePath) else target.delete()
            } catch (_: Exception) {
                target.delete()
            }
        }
        return saved
    }

    // endregion

    /** Whether [resultCode] and [data] carry a picked document. */
    fun pickedUri(resultCode: Int, data: Intent?): Uri? =
        if (resultCode == Activity.RESULT_OK) data?.data else null

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
