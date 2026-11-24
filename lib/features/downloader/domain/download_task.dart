import '../../../core/platform/media_platform.dart';
import '../../extractor/domain/media_format.dart';
import '../../extractor/domain/media_info.dart';
import 'download_progress.dart';

/// A download in the queue or the history. Immutable; every change produces a
/// new instance through [copyWith] or [applyProgress]. Persisted as a plain
/// map so no generated adapters are needed.
class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.url,
    required this.title,
    required this.platform,
    required this.format,
    required this.createdAt,
    this.uploader,
    this.thumbnail,
    this.duration,
    this.mediaId,
    this.caption,
    this.postedAt,
    this.tonight = false,
    this.status = DownloadStatus.queued,
    this.progressPercent = 0,
    this.speed = '',
    this.eta = -1,
    this.filePaths = const [],
    this.fileSize,
    this.error,
    this.completedAt,
    this.savedToGallery = false,
    this.exported = const {},
    this.stage = '',
    this.sizeText = '',
  });

  /// Creates a queued task for [format] of the media described by [info].
  factory DownloadTask.create({
    required String id,
    required MediaInfo info,
    required MediaFormat format,
    DateTime? now,
  }) {
    return DownloadTask(
      id: id,
      url: info.url,
      title: info.title,
      platform: info.platform,
      format: format,
      createdAt: now ?? DateTime.now(),
      uploader: info.uploader,
      thumbnail: info.thumbnail,
      duration: info.duration,
      mediaId: info.id,
      caption: info.caption,
      postedAt: info.postedAt,
    );
  }

  final String id;
  final String url;
  final String title;
  final MediaPlatform platform;

  /// The option the user picked; kept so a failed task can be retried as is.
  final MediaFormat format;
  final DateTime createdAt;
  final String? uploader;
  final String? thumbnail;
  final int? duration;

  /// The platform's own id for the media, used to spot a repeat download.
  final String? mediaId;

  /// The post's own text, for searching the Vault; null when unknown.
  final String? caption;

  /// When the post was published, when the site said.
  final DateTime? postedAt;

  /// Waits until the night begins, on Wi-Fi, before starting.
  final bool tonight;

  final DownloadStatus status;
  final double progressPercent;
  final String speed;
  final int eta;

  /// Finished files in the app's download folder.
  final List<String> filePaths;
  final int? fileSize;
  final String? error;
  final DateTime? completedAt;

  /// Whether the finished files were exported to the public gallery.
  final bool savedToGallery;

  /// For each exported file, where its gallery copy lives (file path ->
  /// address), so the copy can be deleted with the download. Empty for
  /// downloads exported by older versions, whose copies are found by name.
  final Map<String, String> exported;

  /// What a running download is doing right now (see
  /// [DownloadProgress.stage]), and how much of its file has arrived. Not
  /// stored: they only describe a download in progress.
  final String stage;
  final String sizeText;

  String? get filePath => filePaths.isEmpty ? null : filePaths.first;
  bool get isActive => status.isActive;
  bool get canResume => status == DownloadStatus.paused;
  bool get canRetry =>
      status == DownloadStatus.failed || status == DownloadStatus.canceled;

  /// Folds a progress event into the task.
  DownloadTask applyProgress(DownloadProgress progress, {DateTime? now}) {
    final finished = progress.status == DownloadStatus.completed;
    return copyWith(
      status: progress.status,
      progressPercent: finished ? 100 : progress.progressPercent,
      speed: progress.speed,
      eta: progress.eta,
      stage: progress.stage,
      sizeText: progress.sizeText,
      filePaths: finished ? progress.filePaths : null,
      fileSize: finished ? progress.fileSize : null,
      error: progress.status == DownloadStatus.failed ? progress.error : null,
      clearError: progress.status != DownloadStatus.failed,
      completedAt: finished ? (now ?? DateTime.now()) : null,
    );
  }

  DownloadTask copyWith({
    DownloadStatus? status,
    double? progressPercent,
    String? speed,
    int? eta,
    List<String>? filePaths,
    int? fileSize,
    String? error,
    bool clearError = false,
    DateTime? completedAt,
    bool? savedToGallery,
    Map<String, String>? exported,
    bool? tonight,
    String? stage,
    String? sizeText,
  }) {
    return DownloadTask(
      id: id,
      url: url,
      title: title,
      platform: platform,
      format: format,
      createdAt: createdAt,
      uploader: uploader,
      thumbnail: thumbnail,
      duration: duration,
      mediaId: mediaId,
      caption: caption,
      postedAt: postedAt,
      tonight: tonight ?? this.tonight,
      status: status ?? this.status,
      progressPercent: progressPercent ?? this.progressPercent,
      speed: speed ?? this.speed,
      eta: eta ?? this.eta,
      filePaths: filePaths ?? this.filePaths,
      fileSize: fileSize ?? this.fileSize,
      error: clearError ? null : (error ?? this.error),
      completedAt: completedAt ?? this.completedAt,
      savedToGallery: savedToGallery ?? this.savedToGallery,
      exported: exported ?? this.exported,
      stage: stage ?? (status == null ? this.stage : ''),
      sizeText: sizeText ?? (status == null ? this.sizeText : ''),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'url': url,
    'title': title,
    'platform': platform.id,
    'format': format.toMap(),
    'createdAt': createdAt.millisecondsSinceEpoch,
    'uploader': uploader,
    'thumbnail': thumbnail,
    'duration': duration,
    'mediaId': mediaId,
    'tonight': tonight,
    'status': status.name,
    'progressPercent': progressPercent,
    'speed': speed,
    'eta': eta,
    'filePaths': filePaths,
    'fileSize': fileSize,
    'error': error,
    'completedAt': completedAt?.millisecondsSinceEpoch,
    'savedToGallery': savedToGallery,
    'exported': exported,
    'caption': caption,
    'postedAt': postedAt?.millisecondsSinceEpoch,
  };

  factory DownloadTask.fromMap(Map<Object?, Object?> source) {
    final map = Map<String, dynamic>.from(source);
    final completedAt = (map['completedAt'] as num?)?.toInt();
    return DownloadTask(
      id: map['id'] as String,
      url: map['url'] as String? ?? '',
      title: map['title'] as String? ?? 'Untitled',
      platform: MediaPlatform.fromId(map['platform'] as String?),
      format: MediaFormat.fromMap(
        Map<String, dynamic>.from(map['format'] as Map? ?? const {}),
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['createdAt'] as num?)?.toInt() ?? 0,
      ),
      uploader: map['uploader'] as String?,
      thumbnail: map['thumbnail'] as String?,
      duration: (map['duration'] as num?)?.toInt(),
      mediaId: map['mediaId'] as String?,
      caption: map['caption'] as String?,
      postedAt: map['postedAt'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['postedAt'] as num).toInt(),
            )
          : null,
      tonight: map['tonight'] as bool? ?? false,
      status: DownloadStatus.fromName(map['status'] as String?),
      progressPercent: (map['progressPercent'] as num?)?.toDouble() ?? 0,
      speed: map['speed'] as String? ?? '',
      eta: (map['eta'] as num?)?.toInt() ?? -1,
      filePaths:
          (map['filePaths'] as List?)?.whereType<String>().toList() ?? const [],
      fileSize: (map['fileSize'] as num?)?.toInt(),
      error: map['error'] as String?,
      completedAt: completedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(completedAt),
      savedToGallery: map['savedToGallery'] as bool? ?? false,
      exported: {
        for (final entry in (map['exported'] as Map? ?? const {}).entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      },
    );
  }
}
