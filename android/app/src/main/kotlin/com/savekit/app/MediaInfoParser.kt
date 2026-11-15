package com.savekit.app

import org.json.JSONArray
import org.json.JSONObject

/**
 * Turns the JSON printed by `yt-dlp --dump-single-json` into the plain maps sent to Flutter:
 * metadata plus ready-to-use download options grouped as video qualities, a watermark-free
 * stream (TikTok / Snapchat) and audio-only (MP3 / M4A).
 */
object MediaInfoParser {

    /** Quality buckets, keyed by the smaller video dimension so portrait clips rank correctly. */
    private val QUALITY_TIERS = listOf(
        2160 to "4K",
        1440 to "1440p",
        1080 to "1080p",
        720 to "720p",
        480 to "480p",
        360 to "360p",
        240 to "240p",
        144 to "144p",
    )

    /** Platforms whose default streams can carry a burned-in watermark. */
    private val WATERMARK_PLATFORMS = setOf("tiktok", "snapchat")

    private const val VIDEO_SELECTOR = "bv*+ba/b"
    private const val CODEC_SORT = "vcodec:h264,acodec:aac"
    private const val NO_WATERMARK_SELECTOR =
        "b[format_note!*=?watermark][format_id!*=?download]/" +
            "bv*[format_note!*=?watermark][format_id!*=?download]+ba/b"

    fun parse(json: String, requestedUrl: String): Map<String, Any?> {
        val root = JSONObject(json)

        // A post with several items (carousel, thread) is reported as a playlist.
        val entries = root.optJSONArray("entries")
        val entryCount = entries?.length() ?: 0
        val media = firstEntry(entries) ?: root

        val platform = platformOf(media, root)
        val formats = parseFormats(media.optJSONArray("formats"))
        val videoFormats = formats.filter { it.hasVideo }
        val audioFormats = formats.filter { it.hasAudio && !it.hasVideo }
        val bestAudioSize = audioFormats.maxByOrNull { it.bitrate }?.size

        val videoOptions = buildVideoOptions(videoFormats, bestAudioSize)
        val noWatermarkOption =
            if (platform in WATERMARK_PLATFORMS && videoFormats.isNotEmpty()) {
                mapOf(
                    "id" to "no_watermark",
                    "kind" to "noWatermark",
                    "label" to "Best No-Watermark",
                    "formatSelection" to NO_WATERMARK_SELECTOR,
                    "formatSort" to CODEC_SORT,
                    "extractAudio" to false,
                    "audioFormat" to null,
                    "ext" to "mp4",
                    "height" to null,
                    "fileSize" to null,
                )
            } else {
                null
            }
        val audioOptions =
            if (formats.isEmpty() || formats.any { it.hasAudio }) {
                buildAudioOptions(bestAudioSize)
            } else {
                emptyList()
            }

        return mapOf(
            "id" to media.optStringOrNull("id"),
            "url" to requestedUrl,
            "webpageUrl" to (media.optStringOrNull("webpage_url") ?: requestedUrl),
            "title" to (media.optStringOrNull("title")
                ?: root.optStringOrNull("title")
                ?: "Untitled"),
            "uploader" to (media.optStringOrNull("uploader")
                ?: media.optStringOrNull("channel")
                ?: media.optStringOrNull("creator")
                ?: media.optStringOrNull("uploader_id")
                ?: root.optStringOrNull("uploader")),
            "thumbnail" to thumbnailOf(media),
            "duration" to media.optDoubleOrNull("duration")?.toInt(),
            "platform" to platform,
            "extractor" to media.optStringOrNull("extractor_key"),
            "entryCount" to entryCount,
            "videoOptions" to videoOptions,
            "noWatermarkOption" to noWatermarkOption,
            "audioOptions" to audioOptions,
            "formats" to formats.map { it.toMap() },
        )
    }

    /**
     * Reads `yt-dlp --flat-playlist --dump-single-json` output: the playlist's title and the
     * address and title of each entry, without resolving the entries themselves.
     */
    fun parsePlaylist(json: String, requestedUrl: String): Map<String, Any?> {
        val root = JSONObject(json)
        val entries = root.optJSONArray("entries")
        val items = ArrayList<Map<String, Any?>>()
        if (entries != null) {
            for (i in 0 until entries.length()) {
                val entry = entries.optJSONObject(i) ?: continue
                val url = entry.optStringOrNull("webpage_url")
                    ?: entry.optStringOrNull("url")
                    ?: continue
                if (!url.startsWith("http")) continue
                items.add(
                    mapOf(
                        "url" to url,
                        "title" to (entry.optStringOrNull("title") ?: "Untitled"),
                        "duration" to entry.optDoubleOrNull("duration")?.toInt(),
                        "thumbnail" to thumbnailOf(entry),
                    ),
                )
            }
        }
        return mapOf(
            "url" to requestedUrl,
            "title" to (root.optStringOrNull("title") ?: "Playlist"),
            "uploader" to (root.optStringOrNull("uploader") ?: root.optStringOrNull("channel")),
            "platform" to platformOf(root, root),
            "entries" to items,
        )
    }

    private fun firstEntry(entries: JSONArray?): JSONObject? {
        if (entries == null) return null
        for (i in 0 until entries.length()) {
            val entry = entries.optJSONObject(i)
            if (entry != null) return entry
        }
        return null
    }

    private fun buildVideoOptions(
        videoFormats: List<Format>,
        bestAudioSize: Long?,
    ): List<Map<String, Any?>> {
        if (videoFormats.isEmpty()) return emptyList()

        val options = ArrayList<Map<String, Any?>>()
        val seenTiers = HashSet<Int>()

        for (format in videoFormats.sortedByDescending { it.resolution ?: 0 }) {
            val resolution = format.resolution ?: continue
            val tier = QUALITY_TIERS.firstOrNull { resolution >= it.first } ?: continue
            if (!seenTiers.add(tier.first)) continue

            // Largest stream in this bucket; add the separate audio track when it has none.
            val best = videoFormats
                .filter { (it.resolution ?: 0) in tier.first..resolution }
                .maxByOrNull { it.bitrate }
            val videoSize = best?.size
            val totalSize = when {
                videoSize == null -> null
                best?.hasAudio == true -> videoSize
                else -> videoSize + (bestAudioSize ?: 0L)
            }

            options.add(
                mapOf(
                    "id" to "video_${tier.first}",
                    "kind" to "video",
                    "label" to tier.second,
                    "formatSelection" to VIDEO_SELECTOR,
                    // `res` caps the smaller dimension; codecs keep the MP4 gallery-friendly.
                    "formatSort" to "res:${tier.first},$CODEC_SORT",
                    "extractAudio" to false,
                    "audioFormat" to null,
                    "ext" to "mp4",
                    "height" to tier.first,
                    "fileSize" to totalSize,
                ),
            )
        }

        if (options.isEmpty()) {
            // The site reported no dimensions; still offer its best stream.
            options.add(
                mapOf(
                    "id" to "video_best",
                    "kind" to "video",
                    "label" to "Best",
                    "formatSelection" to VIDEO_SELECTOR,
                    "formatSort" to CODEC_SORT,
                    "extractAudio" to false,
                    "audioFormat" to null,
                    "ext" to "mp4",
                    "height" to null,
                    "fileSize" to videoFormats.maxByOrNull { it.bitrate }?.size,
                ),
            )
        }
        return options
    }

    private fun buildAudioOptions(bestAudioSize: Long?): List<Map<String, Any?>> = listOf(
        mapOf(
            "id" to "audio_mp3",
            "kind" to "audio",
            "label" to "MP3",
            "formatSelection" to "ba/b",
            "formatSort" to "",
            "extractAudio" to true,
            "audioFormat" to "mp3",
            "ext" to "mp3",
            "height" to null,
            "fileSize" to bestAudioSize,
        ),
        mapOf(
            "id" to "audio_m4a",
            "kind" to "audio",
            "label" to "M4A",
            "formatSelection" to "ba[ext=m4a]/ba/b",
            "formatSort" to "",
            "extractAudio" to true,
            "audioFormat" to "m4a",
            "ext" to "m4a",
            "height" to null,
            "fileSize" to bestAudioSize,
        ),
    )

    private fun parseFormats(array: JSONArray?): List<Format> {
        if (array == null) return emptyList()
        val formats = ArrayList<Format>(array.length())
        for (i in 0 until array.length()) {
            val item = array.optJSONObject(i) ?: continue
            val formatId = item.optStringOrNull("format_id") ?: continue
            val ext = item.optStringOrNull("ext")
            // Storyboards and thumbnails-as-formats are not downloadable media.
            if (ext == "mhtml") continue

            val vcodec = item.optStringOrNull("vcodec")
            val acodec = item.optStringOrNull("acodec")
            val width = item.optIntOrNull("width")
            val height = item.optIntOrNull("height")
            // When a site omits codec info yt-dlp treats the format as audio + video.
            val hasVideo = vcodec != "none" && !(vcodec == null && acodec != null && height == null)
            val hasAudio = acodec != "none"

            formats.add(
                Format(
                    formatId = formatId,
                    ext = ext,
                    width = width,
                    height = height,
                    fps = item.optDoubleOrNull("fps"),
                    vcodec = vcodec,
                    acodec = acodec,
                    size = item.optLongOrNull("filesize") ?: item.optLongOrNull("filesize_approx"),
                    bitrate = item.optDoubleOrNull("tbr")
                        ?: item.optDoubleOrNull("vbr")
                        ?: item.optDoubleOrNull("abr")
                        ?: 0.0,
                    note = item.optStringOrNull("format_note"),
                    hasVideo = hasVideo,
                    hasAudio = hasAudio,
                ),
            )
        }
        return formats
    }

    private fun thumbnailOf(media: JSONObject): String? {
        media.optStringOrNull("thumbnail")?.let { return it }
        val thumbnails = media.optJSONArray("thumbnails") ?: return null
        // yt-dlp orders thumbnails worst to best.
        for (i in thumbnails.length() - 1 downTo 0) {
            thumbnails.optJSONObject(i)?.optStringOrNull("url")?.let { return it }
        }
        return null
    }

    private fun platformOf(media: JSONObject, root: JSONObject): String {
        val extractor = (media.optStringOrNull("extractor_key")
            ?: media.optStringOrNull("extractor")
            ?: root.optStringOrNull("extractor_key")
            ?: root.optStringOrNull("extractor")
            ?: "generic").lowercase()
        return when {
            extractor.startsWith("youtube") -> "youtube"
            extractor.contains("tiktok") -> "tiktok"
            extractor.startsWith("instagram") -> "instagram"
            extractor.startsWith("snapchat") -> "snapchat"
            extractor.startsWith("twitter") -> "x"
            extractor.startsWith("linkedin") -> "linkedin"
            extractor.startsWith("facebook") -> "facebook"
            else -> extractor.substringBefore(':')
        }
    }

    private data class Format(
        val formatId: String,
        val ext: String?,
        val width: Int?,
        val height: Int?,
        val fps: Double?,
        val vcodec: String?,
        val acodec: String?,
        val size: Long?,
        val bitrate: Double,
        val note: String?,
        val hasVideo: Boolean,
        val hasAudio: Boolean,
    ) {
        /** Smaller dimension, matching yt-dlp's `res` sort field. */
        val resolution: Int?
            get() = when {
                width != null && height != null -> minOf(width, height)
                else -> height ?: width
            }

        fun toMap(): Map<String, Any?> = mapOf(
            "formatId" to formatId,
            "ext" to ext,
            "width" to width,
            "height" to height,
            "fps" to fps,
            "vcodec" to vcodec,
            "acodec" to acodec,
            "fileSize" to size,
            "bitrate" to bitrate,
            "note" to note,
            "hasVideo" to hasVideo,
            "hasAudio" to hasAudio,
        )
    }

    private fun JSONObject.optStringOrNull(key: String): String? {
        if (!has(key) || isNull(key)) return null
        return optString(key).takeIf { it.isNotBlank() }
    }

    private fun JSONObject.optIntOrNull(key: String): Int? = optDoubleOrNull(key)?.toInt()

    private fun JSONObject.optLongOrNull(key: String): Long? = optDoubleOrNull(key)?.toLong()

    private fun JSONObject.optDoubleOrNull(key: String): Double? {
        if (!has(key) || isNull(key)) return null
        val value = optDouble(key)
        return if (value.isNaN() || value.isInfinite()) null else value
    }
}
