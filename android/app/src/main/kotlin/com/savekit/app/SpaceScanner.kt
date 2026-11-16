package com.savekit.app

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Size
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Looks through every photo and video on the phone for space that can be freed:
 *
 *  - exact copies of the same file
 *  - photos that look alike (bursts, the same shot taken twice)
 *  - the videos themselves, with their size and length, so the big ones can be re-encoded
 *
 * Only reads; nothing is changed here. Needs the photos and videos permission.
 */
object SpaceScanner {

    /** One photo or video, as the scan found it. */
    private class Item(
        val uri: Uri,
        val path: String?,
        val name: String,
        val size: Long,
        val date: Long,
        val width: Int,
        val height: Int,
        val durationMs: Long,
        val isVideo: Boolean,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "uri" to uri.toString(),
            "path" to path,
            "name" to name,
            "size" to size,
            "date" to date,
            "width" to width,
            "height" to height,
            "durationMs" to durationMs,
            "isVideo" to isVideo,
        )
    }

    // What the running scan is doing, for the progress bar.
    @Volatile private var stage = "idle"
    private val done = AtomicInteger(0)
    @Volatile private var total = 0
    @Volatile private var canceled = false

    /** Photos compared for likeness; more would take minutes. The newest are used. */
    private const val MAX_COMPARED_PHOTOS = 6000

    /** Likeness is only checked between photos this close together by date. */
    private const val NEIGHBOURS = 24

    /** Bits (of 64) two photos' fingerprints may differ by and still count as alike. */
    private const val MAX_DISTANCE = 5

    private const val SAMPLE_BYTES = 64 * 1024

    fun progress(): Map<String, Any> =
        mapOf("stage" to stage, "done" to done.get(), "total" to total)

    fun cancel() {
        canceled = true
    }

    /**
     * Runs the whole scan. Returns `items` (every photo and video), `duplicates` and
     * `similar` (each a list of groups, each group a list of addresses).
     */
    fun scan(context: Context): Map<String, Any> {
        canceled = false
        try {
            setStage("listing", 0)
            val items = listMedia(context, video = false) + listMedia(context, video = true)

            val duplicates = findDuplicates(items)
            // A photo that is an extra exact copy is already reported; leave it out of
            // the likeness check so it is not listed twice.
            val extraCopies = HashSet<Uri>()
            for (group in duplicates) group.drop(1).forEach { extraCopies.add(it.uri) }
            val photos = items
                .filter { !it.isVideo && it.uri !in extraCopies }
                .sortedByDescending { it.date }
                .take(MAX_COMPARED_PHOTOS)
            val similar = findSimilar(context, photos)

            return mapOf(
                "items" to items.map { it.toMap() },
                "duplicates" to duplicates.map { group -> group.map { it.uri.toString() } },
                "similar" to similar.map { group -> group.map { it.uri.toString() } },
                "canceled" to canceled,
            )
        } finally {
            stage = "idle"
        }
    }

    private fun setStage(name: String, count: Int) {
        done.set(0)
        total = count
        stage = name
    }

    private fun listMedia(context: Context, video: Boolean): List<Item> {
        val volume =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) MediaStore.VOLUME_EXTERNAL
            else "external"
        val collection =
            if (video) MediaStore.Video.Media.getContentUri(volume)
            else MediaStore.Images.Media.getContentUri(volume)
        @Suppress("DEPRECATION")
        val columns = arrayListOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DATA,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.WIDTH,
            MediaStore.MediaColumns.HEIGHT,
            // The same column name for photos and videos.
            "datetaken",
        )
        if (video) columns.add(MediaStore.Video.Media.DURATION)

        val found = ArrayList<Item>()
        context.contentResolver.query(collection, columns.toTypedArray(), null, null, null)
            ?.use { cursor ->
                while (cursor.moveToNext()) {
                    val size = cursor.getLong(3)
                    if (size <= 0) continue
                    val taken = if (cursor.isNull(7)) 0L else cursor.getLong(7)
                    found.add(
                        Item(
                            uri = ContentUris.withAppendedId(collection, cursor.getLong(0)),
                            path = if (cursor.isNull(1)) null else cursor.getString(1),
                            name = cursor.getString(2) ?: "",
                            size = size,
                            // Seconds since 1970 for "modified", milliseconds for "taken".
                            date = if (taken > 0) taken else cursor.getLong(4) * 1000,
                            width = cursor.getInt(5),
                            height = cursor.getInt(6),
                            durationMs = if (video && !cursor.isNull(8)) cursor.getLong(8) else 0,
                            isVideo = video,
                        ),
                    )
                }
            }
        return found
    }

    // region exact copies

    /** Groups of files with identical content, oldest first in each group. */
    private fun findDuplicates(items: List<Item>): List<List<Item>> {
        val sameSize = items.filter { it.path != null }
            .groupBy { it.size }
            .values
            .filter { it.size > 1 }
        setStage("duplicates", sameSize.sumOf { it.size })

        val groups = ArrayList<List<Item>>()
        for (candidates in sameSize) {
            if (canceled) break
            val byContent = HashMap<String, MutableList<Item>>()
            for (item in candidates) {
                done.incrementAndGet()
                val print = fingerprint(File(item.path!!)) ?: continue
                byContent.getOrPut(print) { ArrayList() }.add(item)
            }
            for (group in byContent.values) {
                // The same file listed twice is not a copy.
                val distinct = group.distinctBy { it.path }
                if (distinct.size > 1) groups.add(distinct.sortedBy { it.date })
            }
        }
        return groups.sortedByDescending { it[0].size * (it.size - 1) }
    }

    /**
     * A digest of the file's start, middle and end. Together with the equal size this
     * identifies a photo or video without reading gigabytes.
     */
    private fun fingerprint(file: File): String? = try {
        RandomAccessFile(file, "r").use { reader ->
            val length = reader.length()
            val digest = MessageDigest.getInstance("MD5")
            val buffer = ByteArray(SAMPLE_BYTES)
            val offsets =
                if (length <= SAMPLE_BYTES * 3L) listOf(0L)
                else listOf(0L, length / 2, length - SAMPLE_BYTES)
            for (offset in offsets) {
                reader.seek(offset)
                var remaining = if (offsets.size == 1) length.toInt() else SAMPLE_BYTES
                while (remaining > 0) {
                    val read = reader.read(buffer, 0, minOf(buffer.size, remaining))
                    if (read <= 0) break
                    digest.update(buffer, 0, read)
                    remaining -= read
                }
            }
            digest.digest().joinToString("") { "%02x".format(it) }
        }
    } catch (e: Exception) {
        // Unreadable (removed meanwhile, or not ours to read): not a known copy.
        null
    }

    // endregion

    // region look-alike photos

    /** Groups of photos that look alike, best (largest) first in each group. */
    private fun findSimilar(context: Context, photos: List<Item>): List<List<Item>> {
        setStage("similar", photos.size)
        val pool = Executors.newFixedThreadPool(4)
        val prints: List<Long?> = try {
            pool.invokeAll(
                photos.map { photo ->
                    Callable {
                        val print = if (canceled) null else pictureFingerprint(context, photo.uri)
                        done.incrementAndGet()
                        print
                    }
                },
            ).map { it.get() }
        } finally {
            pool.shutdown()
        }

        // Join every pair of alike neighbours into one group.
        val parent = IntArray(photos.size) { it }
        fun root(index: Int): Int {
            var current = index
            while (parent[current] != current) {
                parent[current] = parent[parent[current]]
                current = parent[current]
            }
            return current
        }
        for (i in photos.indices) {
            val a = prints[i] ?: continue
            for (j in i + 1..minOf(i + NEIGHBOURS, photos.size - 1)) {
                val b = prints[j] ?: continue
                if (java.lang.Long.bitCount(a xor b) <= MAX_DISTANCE) parent[root(j)] = root(i)
            }
        }
        val groups = HashMap<Int, MutableList<Item>>()
        for (i in photos.indices) {
            if (prints[i] != null) groups.getOrPut(root(i)) { ArrayList() }.add(photos[i])
        }
        return groups.values
            .filter { it.size > 1 }
            .map { group ->
                group.sortedWith(
                    compareByDescending<Item> { it.width.toLong() * it.height }
                        .thenByDescending { it.size },
                )
            }
            .sortedByDescending { group -> group.drop(1).sumOf { it.size } }
    }

    /**
     * A 64-bit "difference hash": the picture shrunk to 9x8 grey dots, one bit for each
     * dot that is brighter than its right-hand neighbour. Alike pictures differ in few bits.
     */
    private fun pictureFingerprint(context: Context, uri: Uri): Long? = try {
        val small = thumbnail(context, uri, 96) ?: return null
        val scaled = Bitmap.createScaledBitmap(small, 9, 8, true)
        val pixels = IntArray(72)
        scaled.getPixels(pixels, 0, 9, 0, 0, 9, 8)
        if (scaled !== small) scaled.recycle()
        small.recycle()
        var bits = 0L
        var flat = true
        for (row in 0 until 8) {
            for (column in 0 until 8) {
                val left = grey(pixels[row * 9 + column])
                val right = grey(pixels[row * 9 + column + 1])
                bits = bits shl 1
                if (left > right) bits = bits or 1L
                if (left != right) flat = false
            }
        }
        // A blank picture matches every other blank one; not worth reporting.
        if (flat) null else bits
    } catch (e: Exception) {
        null
    }

    private fun grey(pixel: Int): Int =
        ((pixel shr 16 and 0xff) * 299 + (pixel shr 8 and 0xff) * 587 + (pixel and 0xff) * 114) / 1000

    private fun thumbnail(context: Context, uri: Uri, side: Int): Bitmap? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return context.contentResolver.loadThumbnail(uri, Size(side, side), null)
        }
        val options = BitmapFactory.Options().apply { inSampleSize = 8 }
        return context.contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, options)
        }
    }

    /** JPEG preview of a photo or video on the phone, for the lists. */
    fun preview(context: Context, uri: Uri, side: Int): ByteArray? = try {
        val bitmap = thumbnail(context, uri, side)
        if (bitmap == null) {
            null
        } else {
            val bytes = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, 80, bytes)
            bitmap.recycle()
            bytes.toByteArray()
        }
    } catch (e: Exception) {
        null
    }

    // endregion
}
