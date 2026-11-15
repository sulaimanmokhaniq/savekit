import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/providers.dart';
import '../../downloader/application/download_queue_controller.dart';
import '../../downloader/data/gallery_export_service.dart';
import '../../downloader/domain/download_progress.dart';

/// One file SaveKit keeps, with what it belongs to.
class StoredFile {
  const StoredFile({
    required this.path,
    required this.size,
    required this.modified,
    required this.kind,
    required this.title,
  });

  final String path;
  final int size;
  final DateTime modified;
  final SavedFileKind kind;

  /// Title of the download the file came from.
  final String title;

  String get name => p.basename(path);
}

/// Everything SaveKit is storing in its download folder.
class StorageSnapshot {
  const StorageSnapshot({
    this.files = const [],
    this.leftovers = const [],
    this.leftoverBytes = 0,
  });

  /// Files of finished downloads.
  final List<StoredFile> files;

  /// Partial and temporary files no download is using any more.
  final List<String> leftovers;
  final int leftoverBytes;

  int get fileBytes => files.fold(0, (sum, file) => sum + file.size);
  int get totalBytes => fileBytes + leftoverBytes;

  int bytesOf(SavedFileKind kind) => files
      .where((file) => file.kind == kind)
      .fold(0, (sum, file) => sum + file.size);

  int countOf(SavedFileKind kind) =>
      files.where((file) => file.kind == kind).length;
}

/// Measures the download folder. Recomputed whenever the queue changes, so
/// the numbers follow new downloads and deletions.
final storageSnapshotProvider = FutureProvider<StorageSnapshot>((ref) async {
  final tasks = ref.watch(downloadQueueControllerProvider);
  final directory = await ref.watch(appPathsProvider).downloadDirectory();

  final files = <StoredFile>[];
  final known = <String>{};
  for (final task in tasks) {
    if (task.status != DownloadStatus.completed) continue;
    for (final path in task.filePaths) {
      known.add(path);
      try {
        final stat = await File(path).stat();
        if (stat.type != FileSystemEntityType.file) continue;
        files.add(
          StoredFile(
            path: path,
            size: stat.size,
            modified: stat.modified,
            kind: savedFileKindOf(path),
            title: task.title,
          ),
        );
      } catch (_) {
        // Deleted outside the app; nothing to count.
      }
    }
  }

  // Partial files belong to a download while it can still continue. Once
  // nothing is waiting, running or paused, whatever is left is abandoned.
  final leftovers = <String>[];
  var leftoverBytes = 0;
  final resumable = tasks.any(
    (task) => task.isActive || task.canResume || task.canRetry,
  );
  if (!resumable) {
    try {
      await for (final entity in Directory(directory).list(recursive: true)) {
        if (entity is! File || known.contains(entity.path)) continue;
        leftovers.add(entity.path);
        leftoverBytes += await entity.length();
      }
    } catch (_) {
      // Folder not created yet.
    }
  }

  return StorageSnapshot(
    files: files,
    leftovers: leftovers,
    leftoverBytes: leftoverBytes,
  );
});

/// Deletes abandoned partial files and the empty folders they leave behind.
Future<void> cleanLeftovers(WidgetRef ref, StorageSnapshot snapshot) async {
  for (final path in snapshot.leftovers) {
    try {
      await File(path).delete();
    } catch (_) {
      // Already gone.
    }
  }
  try {
    final directory = Directory(
      await ref.read(appPathsProvider).downloadDirectory(),
    );
    await for (final entity in directory.list()) {
      if (entity is Directory && await entity.list().isEmpty) {
        await entity.delete();
      }
    }
  } catch (_) {
    // Best effort.
  }
  ref.invalidate(storageSnapshotProvider);
}
