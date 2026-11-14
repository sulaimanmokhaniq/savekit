/// Lifecycle of a download. The names match the `status` values the native
/// engine emits; [queued] exists only on the Dart side, before a task starts.
enum DownloadStatus {
  queued,
  starting,
  downloading,
  processing,
  completed,
  failed,
  canceled;

  static DownloadStatus fromName(String? name) =>
      values.firstWhere((status) => status.name == name, orElse: () => queued);

  /// Finished one way or another; no more progress will arrive.
  bool get isTerminal =>
      this == completed || this == failed || this == canceled;

  /// Waiting or running.
  bool get isActive => !isTerminal;

  /// Occupying an extractor process right now.
  bool get isRunning =>
      this == starting || this == downloading || this == processing;
}

/// One progress update for a task, from the native engine's event stream or
/// from the direct downloader.
class DownloadProgress {
  const DownloadProgress({
    required this.taskId,
    required this.status,
    this.progressPercent = 0,
    this.speed = '',
    this.eta = -1,
    this.filePath,
    this.filePaths = const [],
    this.fileSize,
    this.error,
  });

  final String taskId;
  final DownloadStatus status;

  /// 0–100 across the whole task.
  final double progressPercent;

  /// Human-readable rate, e.g. "3.2MiB/s" or "2/5 files"; empty when unknown.
  final String speed;

  /// Seconds remaining, or -1 when unknown.
  final int eta;

  /// First finished file, on [DownloadStatus.completed].
  final String? filePath;

  /// Every finished file; several for multi-item posts.
  final List<String> filePaths;
  final int? fileSize;

  /// Reason, on [DownloadStatus.failed].
  final String? error;

  factory DownloadProgress.fromMap(Map<Object?, Object?> map) {
    return DownloadProgress(
      taskId: map['taskId'] as String? ?? '',
      status: DownloadStatus.fromName(map['status'] as String?),
      progressPercent: (map['progressPercent'] as num?)?.toDouble() ?? 0,
      speed: map['speed'] as String? ?? '',
      eta: (map['eta'] as num?)?.toInt() ?? -1,
      filePath: map['filePath'] as String?,
      filePaths:
          (map['filePaths'] as List?)?.whereType<String>().toList() ??
          const [],
      fileSize: (map['fileSize'] as num?)?.toInt(),
      error: map['error'] as String?,
    );
  }
}
