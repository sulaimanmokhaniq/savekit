/// What a download option produces.
enum MediaFormatKind {
  video('video'),
  noWatermark('noWatermark'),
  audio('audio'),
  gallery('gallery');

  const MediaFormatKind(this.id);
  final String id;

  static MediaFormatKind fromId(String? id) =>
      values.firstWhere((kind) => kind.id == id, orElse: () => video);
}

/// Which on-device extractor performs the download.
enum DownloadEngineKind {
  /// yt-dlp with aria2c and FFmpeg: video and audio.
  ytdlp('ytdlp'),

  /// gallery-dl: photo posts and carousels.
  gallerydl('gallerydl'),

  /// Plain HTTP download of addresses read from a page in the in-app WebView.
  direct('direct'),

  /// FFmpeg conversion of a video already on the phone into audio. Needs no
  /// network; the task's `url` is the video's file path.
  convert('convert');

  const DownloadEngineKind(this.id);
  final String id;

  static DownloadEngineKind fromId(String? id) =>
      values.firstWhere((engine) => engine.id == id, orElse: () => ytdlp);
}

/// One choice in the format picker: a video quality, the watermark-free stream,
/// an audio format, or the photos of a post.
class MediaFormat {
  const MediaFormat({
    required this.id,
    required this.kind,
    required this.label,
    this.engine = DownloadEngineKind.ytdlp,
    this.formatSelection = '',
    this.formatSort = '',
    this.extractAudio = false,
    this.audioFormat,
    this.ext,
    this.height,
    this.fileSize,
    this.itemCount = 0,
    this.imageCount = 0,
    this.videoCount = 0,
    this.directUrls = const [],
    this.referer,
    this.clipStart,
    this.clipEnd,
    this.subtitleLanguage,
    this.autoSubtitles = false,
  });

  final String id;
  final MediaFormatKind kind;

  /// Text for the chip, e.g. "1080p", "MP3", "Photos (4)".
  final String label;
  final DownloadEngineKind engine;

  /// yt-dlp `-f` selector and `-S` sort; unused by the other engines.
  final String formatSelection;
  final String formatSort;
  final bool extractAudio;
  final String? audioFormat;

  /// Expected file extension of the result.
  final String? ext;

  /// Quality tier (smaller video dimension), when known.
  final int? height;

  /// Estimated size in bytes, when the site reports one.
  final int? fileSize;

  /// Number of files a gallery download produces.
  final int itemCount;
  final int imageCount;
  final int videoCount;

  /// File addresses for [DownloadEngineKind.direct].
  final List<String> directUrls;

  /// Page the direct addresses were found on, sent as the `Referer` header.
  final String? referer;

  /// Download only this part, in seconds from the start; both null for the
  /// whole video.
  final int? clipStart;
  final int? clipEnd;

  /// Language of the subtitles to embed in the video; null for none.
  final String? subtitleLanguage;

  /// The subtitles are machine-made captions, not ones the uploader wrote.
  final bool autoSubtitles;

  bool get isClipped => clipStart != null || clipEnd != null;

  /// This option with a section to cut and subtitles to embed.
  MediaFormat withExtras({
    int? clipStart,
    int? clipEnd,
    String? subtitleLanguage,
    bool autoSubtitles = false,
    String? label,
  }) => MediaFormat(
    id: id,
    kind: kind,
    label: label ?? this.label,
    engine: engine,
    formatSelection: formatSelection,
    formatSort: formatSort,
    extractAudio: extractAudio,
    audioFormat: audioFormat,
    ext: ext,
    height: height,
    fileSize: clipStart == null && clipEnd == null ? fileSize : null,
    itemCount: itemCount,
    imageCount: imageCount,
    videoCount: videoCount,
    directUrls: directUrls,
    referer: referer,
    clipStart: clipStart,
    clipEnd: clipEnd,
    subtitleLanguage: subtitleLanguage,
    autoSubtitles: autoSubtitles,
  );

  bool get isAudio => kind == MediaFormatKind.audio;
  bool get isGallery => kind == MediaFormatKind.gallery;
  bool get isConversion => engine == DownloadEngineKind.convert;

  factory MediaFormat.fromMap(Map<String, dynamic> map) {
    return MediaFormat(
      id: map['id'] as String? ?? '',
      kind: MediaFormatKind.fromId(map['kind'] as String?),
      label: map['label'] as String? ?? '',
      engine: DownloadEngineKind.fromId(map['engine'] as String?),
      formatSelection: map['formatSelection'] as String? ?? '',
      formatSort: map['formatSort'] as String? ?? '',
      extractAudio: map['extractAudio'] as bool? ?? false,
      audioFormat: map['audioFormat'] as String?,
      ext: map['ext'] as String?,
      height: (map['height'] as num?)?.toInt(),
      fileSize: (map['fileSize'] as num?)?.toInt(),
      itemCount: (map['itemCount'] as num?)?.toInt() ?? 0,
      imageCount: (map['imageCount'] as num?)?.toInt() ?? 0,
      videoCount: (map['videoCount'] as num?)?.toInt() ?? 0,
      directUrls:
          (map['directUrls'] as List?)?.whereType<String>().toList() ??
          const [],
      referer: map['referer'] as String?,
      clipStart: (map['clipStart'] as num?)?.toInt(),
      clipEnd: (map['clipEnd'] as num?)?.toInt(),
      subtitleLanguage: map['subtitleLanguage'] as String?,
      autoSubtitles: map['autoSubtitles'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'kind': kind.id,
    'label': label,
    'engine': engine.id,
    'formatSelection': formatSelection,
    'formatSort': formatSort,
    'extractAudio': extractAudio,
    'audioFormat': audioFormat,
    'ext': ext,
    'height': height,
    'fileSize': fileSize,
    'itemCount': itemCount,
    'imageCount': imageCount,
    'videoCount': videoCount,
    'directUrls': directUrls,
    'referer': referer,
    'clipStart': clipStart,
    'clipEnd': clipEnd,
    'subtitleLanguage': subtitleLanguage,
    'autoSubtitles': autoSubtitles,
  };
}
