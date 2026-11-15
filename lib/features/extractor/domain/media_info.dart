import '../../../core/platform/media_platform.dart';
import 'media_format.dart';

/// A single photo or clip inside a multi-item post, for preview thumbnails.
class GalleryItem {
  const GalleryItem({
    required this.url,
    this.extension = '',
    this.width,
    this.height,
    this.isVideo = false,
    this.thumbnail,
  });

  final String url;
  final String extension;
  final int? width;
  final int? height;
  final bool isVideo;
  final String? thumbnail;

  factory GalleryItem.fromMap(Map<String, dynamic> map) => GalleryItem(
    url: map['url'] as String? ?? '',
    extension: map['extension'] as String? ?? '',
    width: (map['width'] as num?)?.toInt(),
    height: (map['height'] as num?)?.toInt(),
    isVideo: map['isVideo'] as bool? ?? false,
    thumbnail: map['thumbnail'] as String?,
  );
}

/// Everything known about a link before downloading: its metadata and the
/// download options the format picker offers.
class MediaInfo {
  const MediaInfo({
    required this.url,
    required this.title,
    required this.platform,
    this.id,
    this.webpageUrl,
    this.uploader,
    this.thumbnail,
    this.duration,
    this.entryCount = 0,
    this.videoOptions = const [],
    this.noWatermarkOption,
    this.audioOptions = const [],
    this.galleryOption,
    this.galleryItems = const [],
  });

  /// The link the user supplied.
  final String url;
  final String title;
  final MediaPlatform platform;
  final String? id;
  final String? webpageUrl;
  final String? uploader;
  final String? thumbnail;

  /// Length in seconds, for video and audio.
  final int? duration;

  /// Number of items when the link is a multi-item post.
  final int entryCount;

  /// Video qualities, best first (4K, 1080p, 720p, …).
  final List<MediaFormat> videoOptions;

  /// Watermark-free stream, offered for TikTok and Snapchat.
  final MediaFormat? noWatermarkOption;

  /// Audio-only formats (MP3, M4A).
  final List<MediaFormat> audioOptions;

  /// "Photos (N)" when the post has photos.
  final MediaFormat? galleryOption;
  final List<GalleryItem> galleryItems;

  bool get hasVideo => videoOptions.isNotEmpty || noWatermarkOption != null;
  bool get hasAudio => audioOptions.isNotEmpty;
  bool get hasGallery => galleryOption != null;

  /// Every option, in the order the picker should prefer them.
  List<MediaFormat> get allOptions => [
    ?noWatermarkOption,
    ...videoOptions,
    ?galleryOption,
    ...audioOptions,
  ];

  /// The option to preselect.
  MediaFormat? get defaultOption =>
      allOptions.isEmpty ? null : allOptions.first;

  factory MediaInfo.fromMap(Map<String, dynamic> map) {
    List<MediaFormat> formats(String key) =>
        _maps(map[key]).map(MediaFormat.fromMap).toList(growable: false);
    MediaFormat? format(String key) {
      final value = _map(map[key]);
      return value == null ? null : MediaFormat.fromMap(value);
    }

    return MediaInfo(
      url: map['url'] as String? ?? '',
      title: map['title'] as String? ?? 'Untitled',
      platform: MediaPlatform.fromId(map['platform'] as String?),
      id: map['id'] as String?,
      webpageUrl: map['webpageUrl'] as String?,
      uploader: map['uploader'] as String?,
      thumbnail: map['thumbnail'] as String?,
      duration: (map['duration'] as num?)?.toInt(),
      entryCount: (map['entryCount'] as num?)?.toInt() ?? 0,
      videoOptions: formats('videoOptions'),
      noWatermarkOption: format('noWatermarkOption'),
      audioOptions: formats('audioOptions'),
      galleryOption: format('galleryOption'),
      galleryItems: _maps(map['galleryItems'])
          .map(GalleryItem.fromMap)
          .toList(growable: false),
    );
  }
}

/// Platform channels deliver nested maps as `Map<Object?, Object?>`.
Map<String, dynamic>? _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

Iterable<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value.whereType<Map>().map((item) => Map<String, dynamic>.from(item))
    : const [];
