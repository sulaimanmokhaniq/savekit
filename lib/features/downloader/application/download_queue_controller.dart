import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/native/youtube_dl_native_service.dart';
import '../../../core/platform/media_platform.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/providers.dart';
import '../../../core/settings/app_settings.dart';
import '../../extractor/domain/media_format.dart';
import '../../extractor/domain/media_info.dart';
import '../data/download_repository.dart';
import '../domain/download_progress.dart';
import '../domain/download_task.dart';

/// The download queue and history: every task, newest first.
///
/// It starts queued tasks (a few at a time), folds progress from the native
/// engine and the direct downloader into them, persists every change of
/// status, exports finished files to the gallery, and keeps the Android
/// background service informed so downloads survive the app being backgrounded.
class DownloadQueueController extends Notifier<List<DownloadTask>> {
  static const _serviceInterval = Duration(seconds: 1);

  final _starting = <String>{};

  /// Tasks whose process was told to stop (pause, or Wi-Fi lost) and whose
  /// final event has not arrived yet. They must not be restarted until it has.
  final _stopping = <String>{};
  bool _onWifi = true;
  final _random = Random();
  DateTime _lastServiceUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  bool _askedNotifications = false;
  bool _pumping = false;
  bool _pumpAgain = false;

  YoutubeDlNativeService get _native => ref.read(nativeServiceProvider);
  DownloadRepository get _repository => ref.read(downloadRepositoryProvider);

  @override
  List<DownloadTask> build() {
    final nativeEvents = _native.progressStream.listen(
      _onProgress,
      onError: (_) {},
    );
    final directEvents = ref
        .read(directDownloadServiceProvider)
        .progressStream
        .listen(_onProgress, onError: (_) {});
    ref.onDispose(nativeEvents.cancel);
    ref.onDispose(directEvents.cancel);

    // Settings (Wi-Fi only, downloads at once) and the connection itself
    // decide what may run.
    _onWifi = ref.read(onWifiProvider).value ?? true;
    ref.listen(onWifiProvider, (_, next) {
      _onWifi = next.value ?? true;
      _onConditionsChanged();
    });
    ref.listen(settingsControllerProvider, (_, _) => _onConditionsChanged());

    // A task stored as running belongs to a previous launch. Queue it again:
    // if its process is in fact still alive the engine says so and its
    // progress simply continues; otherwise the download restarts and yt-dlp
    // resumes from the partial file.
    final restored = <DownloadTask>[];
    for (final task in _repository.loadAll()) {
      if (task.status.isRunning) {
        final queued = task.copyWith(
          status: DownloadStatus.queued,
          speed: '',
          eta: -1,
        );
        unawaited(_repository.save(queued));
        restored.add(queued);
      } else {
        restored.add(task);
      }
    }
    restored.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    unawaited(Future<void>.microtask(_pump));
    return restored;
  }

  // region commands

  /// Adds a download of [format] for the media in [info] and returns its id.
  String enqueue(MediaInfo info, MediaFormat format) {
    final id =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '${_random.nextInt(1 << 20).toRadixString(36)}';
    final task = DownloadTask.create(id: id, info: info, format: format);
    state = [task, ...state];
    unawaited(_repository.save(task));

    if (!_askedNotifications) {
      _askedNotifications = true;
      unawaited(ref.read(notificationPermissionProvider)());
    }
    unawaited(_pump());
    return id;
  }

  /// Adds files that are already on the phone (saved WhatsApp statuses) to
  /// the vault as a finished download, and exports them to the gallery.
  Future<void> addCompleted({
    required String title,
    required MediaPlatform platform,
    required MediaFormat format,
    required List<String> filePaths,
  }) async {
    if (filePaths.isEmpty) return;
    final size = _sizeOf(filePaths);
    final now = DateTime.now();
    final task = DownloadTask(
      id:
          '${now.microsecondsSinceEpoch.toRadixString(36)}'
          '${_random.nextInt(1 << 20).toRadixString(36)}',
      url: '',
      title: title,
      platform: platform,
      format: format,
      createdAt: now,
      completedAt: now,
      status: DownloadStatus.completed,
      progressPercent: 100,
      filePaths: filePaths,
      fileSize: size,
    );
    state = [task, ...state];
    await _repository.save(task);

    var saved = false;
    try {
      saved = await ref.read(galleryExportServiceProvider).export(filePaths);
    } catch (_) {
      saved = false;
    }
    if (!ref.mounted) return;
    final current = _find(task.id);
    if (saved && current != null) {
      _replace(current.copyWith(savedToGallery: true));
    }
  }

  /// Stops a queued, running or paused task.
  Future<void> cancel(String id) async {
    final task = _find(id);
    if (task == null) return;
    if (task.status == DownloadStatus.paused) {
      _replace(
        task.copyWith(status: DownloadStatus.canceled, speed: '', eta: -1),
      );
      return;
    }
    if (!task.isActive) return;

    if (task.status == DownloadStatus.queued && !_starting.contains(id)) {
      _replace(
        task.copyWith(status: DownloadStatus.canceled, speed: '', eta: -1),
      );
      _syncService(force: true);
      return;
    }

    var stopping = false;
    try {
      stopping = task.format.engine == DownloadEngineKind.direct
          ? ref.read(directDownloadServiceProvider).cancel(id)
          : await _native.cancelDownload(id);
    } catch (_) {
      stopping = false;
    }
    // When a process was stopped its "canceled" event finishes the task.
    // Otherwise nothing is running for it, so finish it here.
    if (!stopping) {
      final current = _find(id);
      if (current != null && current.isActive) {
        _replace(
          current.copyWith(status: DownloadStatus.canceled, speed: '', eta: -1),
        );
        _syncService(force: true);
        unawaited(_pump());
      }
    }
  }

  /// Stops a task but keeps its partial file, so [resume] continues it.
  Future<void> pause(String id) async {
    final task = _find(id);
    if (task == null || !task.isActive) return;
    await _halt(task, DownloadStatus.paused);
    _syncService(force: true);
    unawaited(_pump());
  }

  /// Puts a paused task back in the queue.
  void resume(String id) {
    final task = _find(id);
    if (task == null || !task.canResume) return;
    _replace(task.copyWith(status: DownloadStatus.queued));
    unawaited(_pump());
  }

  Future<void> pauseAll() async {
    for (final task in [...state]) {
      if (task.isActive) await _halt(task, DownloadStatus.paused);
    }
    _syncService(force: true);
  }

  void resumeAll() {
    for (final task in [...state]) {
      if (task.canResume) {
        _replace(task.copyWith(status: DownloadStatus.queued));
      }
    }
    unawaited(_pump());
  }

  /// Moves a task to [target] (paused, or back to queued) and stops its
  /// process if it has one. yt-dlp leaves the partial file in place.
  Future<void> _halt(DownloadTask task, DownloadStatus target) async {
    final id = task.id;
    final hadProcess = task.status.isRunning;
    _replace(task.copyWith(status: target, speed: '', eta: -1));
    if (!hadProcess) return;

    _stopping.add(id);
    var stopping = false;
    try {
      stopping = task.format.engine == DownloadEngineKind.direct
          ? ref.read(directDownloadServiceProvider).cancel(id)
          : await _native.cancelDownload(id);
    } catch (_) {
      stopping = false;
    }
    // Nothing was running after all, so no final event will come.
    if (!stopping) _stopping.remove(id);
  }

  bool get _blockedByWifi =>
      ref.read(settingsControllerProvider).wifiOnly && !_onWifi;

  /// Wi-Fi came or went, or a download setting changed.
  void _onConditionsChanged() {
    if (!ref.mounted) return;
    if (_blockedByWifi) {
      // Running downloads go back to waiting rather than use mobile data.
      for (final task in [...state]) {
        if (task.status.isRunning && !task.format.isConversion) {
          unawaited(_halt(task, DownloadStatus.queued));
        }
      }
      _syncService(force: true);
    } else {
      unawaited(_pump());
    }
  }

  /// Queues a failed or canceled task again with the same format.
  void retry(String id) {
    final task = _find(id);
    if (task == null || !task.canRetry) return;
    _replace(
      task.copyWith(
        status: DownloadStatus.queued,
        progressPercent: 0,
        speed: '',
        eta: -1,
        clearError: true,
      ),
    );
    unawaited(_pump());
  }

  /// Removes a task from the list. With [deleteFiles], SaveKit's own copies
  /// of its files are deleted too; copies exported to the gallery are kept.
  Future<void> remove(String id, {bool deleteFiles = true}) async {
    final task = _find(id);
    if (task == null) return;
    if (task.isActive) await cancel(id);
    state = [
      for (final other in state)
        if (other.id != id) other,
    ];
    await _repository.delete(id);
    if (deleteFiles) _deleteFiles(task.filePaths);
    _syncService(force: true);
  }

  /// Removes several finished downloads and their files at once.
  Future<void> removeAll(Iterable<String> ids) async {
    final targets = ids.toSet();
    final removed = [
      for (final task in state)
        if (targets.contains(task.id) && !task.isActive) task,
    ];
    if (removed.isEmpty) return;
    final removedIds = {for (final task in removed) task.id};
    state = [
      for (final task in state)
        if (!removedIds.contains(task.id)) task,
    ];
    for (final task in removed) {
      _deleteFiles(task.filePaths);
    }
    await _repository.deleteAll(removedIds);
  }

  /// Deletes individual files from the phone. A download whose files are all
  /// gone is removed from the list; one that keeps some is updated.
  Future<void> deleteFiles(Set<String> paths) async {
    if (paths.isEmpty) return;
    final removedIds = <String>[];
    final updated = <DownloadTask>[];
    final next = <DownloadTask>[];
    for (final task in state) {
      if (!task.filePaths.any(paths.contains)) {
        next.add(task);
        continue;
      }
      final remaining = [
        for (final path in task.filePaths)
          if (!paths.contains(path)) path,
      ];
      if (remaining.isEmpty) {
        removedIds.add(task.id);
      } else {
        final changed = task.copyWith(
          filePaths: remaining,
          fileSize: _sizeOf(remaining),
        );
        updated.add(changed);
        next.add(changed);
      }
    }
    if (!ref.mounted) return;
    state = next;
    await _repository.deleteAll(removedIds);
    for (final task in updated) {
      await _repository.save(task);
    }
    _deleteFiles(paths);
  }

  /// Removes every failed and canceled task.
  Future<void> clearFailed() async {
    final ids = [
      for (final task in state)
        if (task.canRetry) task.id,
    ];
    if (ids.isEmpty) return;
    state = [
      for (final task in state)
        if (!task.canRetry) task,
    ];
    await _repository.deleteAll(ids);
  }

  // endregion

  // region scheduling

  /// Starts queued tasks, oldest first, while slots are free.
  Future<void> _pump() async {
    if (_pumping) {
      _pumpAgain = true;
      return;
    }
    _pumping = true;
    try {
      do {
        _pumpAgain = false;
        while (ref.mounted) {
          // Conversions use no network, so Wi-Fi-only does not hold them.
          final offlineOnly = _blockedByWifi;
          final busy = {
            ..._starting,
            for (final task in state)
              if (task.status.isRunning) task.id,
          };
          final limit = ref.read(settingsControllerProvider).maxConcurrent;
          if (busy.length >= limit) break;
          final next = state.reversed
              .where(
                (task) =>
                    task.status == DownloadStatus.queued &&
                    !_starting.contains(task.id) &&
                    !_stopping.contains(task.id) &&
                    (!offlineOnly || task.format.isConversion),
              )
              .firstOrNull;
          if (next == null) break;
          _starting.add(next.id);
          // Not awaited: each start resolves folders and cookies on its own.
          unawaited(_start(next));
        }
      } while (_pumpAgain && ref.mounted);
    } finally {
      _pumping = false;
    }
  }

  Future<void> _start(DownloadTask task) async {
    final id = task.id;
    try {
      final outputDir = await ref.read(appPathsProvider).downloadDirectory();
      String? cookiesFilePath;
      try {
        cookiesFilePath = await ref
            .read(cookieExportServiceProvider)
            .exportAll();
      } catch (_) {
        cookiesFilePath = null;
      }
      if (!ref.mounted) return;

      // Canceled, paused or removed while preparing, or Wi-Fi was lost.
      final current = _find(id);
      if (current == null || current.status != DownloadStatus.queued) return;
      if (_blockedByWifi && !task.format.isConversion) return;
      _replace(current.copyWith(status: DownloadStatus.starting));
      _syncService(force: true);

      if (task.format.engine == DownloadEngineKind.direct) {
        ref
            .read(directDownloadServiceProvider)
            .start(
              taskId: id,
              urls: task.format.directUrls,
              outputDir: outputDir,
              referer: task.format.referer,
              namePrefix: task.platform.id,
            );
      } else {
        await _native.startDownload(
          taskId: id,
          url: task.url,
          format: task.format,
          outputDir: outputDir,
          cookiesFilePath: cookiesFilePath,
        );
      }
    } on EngineException catch (error) {
      // The process outlived the previous screen; its events are still coming.
      if (error.message.contains('already running')) return;
      _fail(id, error.message);
    } catch (error) {
      _fail(id, error.toString());
    } finally {
      _starting.remove(id);
    }
  }

  void _fail(String id, String message) {
    if (!ref.mounted) return;
    _onProgress(
      DownloadProgress(
        taskId: id,
        status: DownloadStatus.failed,
        error: message,
      ),
    );
  }

  // endregion

  // region progress

  void _onProgress(DownloadProgress progress) {
    if (!ref.mounted) return;
    final task = _find(progress.taskId);
    if (task == null) {
      _stopping.remove(progress.taskId);
      return;
    }
    // Late events for a task the user already finished or re-queued.
    if (task.status.isTerminal) return;

    if (_stopping.contains(task.id)) {
      // The process of a paused or suspended task has now ended.
      if (!progress.status.isTerminal) return;
      _stopping.remove(task.id);
      // It finished before the stop took effect: keep the result.
      if (progress.status != DownloadStatus.completed) {
        unawaited(_pump());
        return;
      }
    } else {
      if (task.status == DownloadStatus.paused) return;
      if (task.status == DownloadStatus.queued && !progress.status.isTerminal) {
        if (!_starting.contains(task.id)) return;
      }
    }

    final updated = task.applyProgress(progress);
    final statusChanged = updated.status != task.status;
    _replace(updated, persist: statusChanged);

    if (updated.status.isTerminal) {
      _syncService(force: true);
      unawaited(_finish(updated));
      unawaited(_pump());
    } else {
      _syncService(force: statusChanged);
    }
  }

  /// Gallery export and the "finished" notification for a task that just ended.
  Future<void> _finish(DownloadTask task) async {
    if (task.status == DownloadStatus.canceled) return;
    final succeeded = task.status == DownloadStatus.completed;

    if (succeeded && task.filePaths.isNotEmpty) {
      var saved = false;
      try {
        saved = await ref
            .read(galleryExportServiceProvider)
            .export(task.filePaths);
      } catch (_) {
        saved = false;
      }
      if (!ref.mounted) return;
      final current = _find(task.id);
      if (saved && current != null) {
        _replace(current.copyWith(savedToGallery: true));
      }
    }

    try {
      await _native.notifyDownloadFinished(
        taskId: task.id,
        title: task.title,
        success: succeeded,
      );
    } catch (_) {
      // Notifications are best effort.
    }
  }

  // endregion

  // region background service

  /// Tells the Android service what is in flight. Progress ticks are
  /// throttled; status changes go through at once.
  void _syncService({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastServiceUpdate) < _serviceInterval) return;
    _lastServiceUpdate = now;

    final active = state.where((task) => task.isActive).toList();
    final running = active.where((task) => task.status.isRunning).toList();

    var title = 'Downloading';
    var text = '';
    var progress = -1;
    if (active.length == 1) {
      title = active.single.title;
      text = _describe(active.single);
      progress = active.single.progressPercent.round();
    } else if (active.length > 1) {
      title = 'Downloading ${active.length} items';
      if (running.isNotEmpty) {
        progress =
            (running.fold<double>(0, (sum, t) => sum + t.progressPercent) /
                    running.length)
                .round();
      }
    }

    unawaited(
      _native
          .updateDownloadService(
            activeCount: active.length,
            title: title,
            text: text,
            progress: progress,
          )
          .catchError((_) {}),
    );
  }

  static String _describe(DownloadTask task) {
    switch (task.status) {
      case DownloadStatus.queued:
      case DownloadStatus.starting:
        return 'Starting…';
      case DownloadStatus.processing:
        return 'Finishing…';
      default:
        final percent = '${task.progressPercent.round()}%';
        return task.speed.isEmpty ? percent : '$percent · ${task.speed}';
    }
  }

  // endregion

  // region helpers

  DownloadTask? _find(String id) {
    for (final task in state) {
      if (task.id == id) return task;
    }
    return null;
  }

  void _replace(DownloadTask updated, {bool persist = true}) {
    state = [
      for (final task in state)
        if (task.id == updated.id) updated else task,
    ];
    if (persist) unawaited(_repository.save(updated));
  }

  /// Deletes files synchronously: a download has a handful at most, and the
  /// list must not be left half-updated while waiting on the disk.
  static void _deleteFiles(Iterable<String> paths) {
    for (final path in paths) {
      try {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {
        // Already gone or not ours to delete.
      }
    }
  }

  static int _sizeOf(Iterable<String> paths) {
    var size = 0;
    for (final path in paths) {
      try {
        size += File(path).lengthSync();
      } catch (_) {
        // Missing file: counts as zero.
      }
    }
    return size;
  }

  // endregion
}

final downloadQueueControllerProvider =
    NotifierProvider<DownloadQueueController, List<DownloadTask>>(
      DownloadQueueController.new,
    );

/// Queue screen: everything not finished successfully, newest first.
final activeDownloadsProvider = Provider<List<DownloadTask>>(
  (ref) => [
    for (final task in ref.watch(downloadQueueControllerProvider))
      if (task.status != DownloadStatus.completed) task,
  ],
);

/// Media vault: completed downloads, most recently finished first.
final completedDownloadsProvider = Provider<List<DownloadTask>>((ref) {
  final completed = [
    for (final task in ref.watch(downloadQueueControllerProvider))
      if (task.status == DownloadStatus.completed) task,
  ];
  completed.sort(
    (a, b) =>
        (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt),
  );
  return completed;
});

/// True while downloads are held back because "Wi-Fi only" is on and the
/// phone is not on Wi-Fi.
final waitingForWifiProvider = Provider<bool>((ref) {
  final wifiOnly = ref.watch(
    settingsControllerProvider.select((settings) => settings.wifiOnly),
  );
  if (!wifiOnly) return false;
  final onWifi = ref.watch(onWifiProvider).value ?? true;
  if (onWifi) return false;
  return ref
      .watch(downloadQueueControllerProvider)
      .any((task) => task.status == DownloadStatus.queued);
});

/// Number of downloads waiting or running, for the navigation badge.
final activeDownloadCountProvider = Provider<int>(
  (ref) => ref
      .watch(downloadQueueControllerProvider)
      .where((task) => task.isActive)
      .length,
);
