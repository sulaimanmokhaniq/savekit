import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../core/errors/friendly_error.dart';
import '../../core/network/connectivity_service.dart';
import '../../core/providers.dart';
import '../../core/settings/app_settings.dart';
import '../downloader/application/download_queue_controller.dart';
import '../downloader/domain/download_progress.dart';
import '../downloader/domain/download_task.dart';
import '../extractor/domain/quality_selection.dart';

/// A link saved for tonight that has not been read yet.
class TonightLink {
  const TonightLink({
    required this.url,
    required this.addedAt,
    this.reading = false,
    this.error,
  });

  final String url;
  final DateTime addedAt;

  /// Being read right now.
  final bool reading;

  /// Why it could not be read; null while it is still to be read.
  final String? error;

  TonightLink copyWith({
    bool? reading,
    String? error,
    bool clearError = false,
  }) => TonightLink(
    url: url,
    addedAt: addedAt,
    reading: reading ?? this.reading,
    error: clearError ? null : (error ?? this.error),
  );

  Map<String, dynamic> toMap() => {
    'url': url,
    'addedAt': addedAt.millisecondsSinceEpoch,
    'error': error,
  };

  factory TonightLink.fromMap(Map<dynamic, dynamic> map) => TonightLink(
    url: map['url'] as String,
    addedAt: DateTime.fromMillisecondsSinceEpoch(
      (map['addedAt'] as num?)?.toInt() ?? 0,
    ),
    error: map['error'] as String?,
  );
}

abstract interface class TonightRepository {
  List<TonightLink> load();
  Future<void> save(List<TonightLink> links);
}

class HiveTonightRepository implements TonightRepository {
  HiveTonightRepository(this._box);

  static const boxName = 'tonight';
  static const _key = 'links';
  final Box<List> _box;

  /// Call after `Hive.initFlutter()`.
  static Future<HiveTonightRepository> open() async =>
      HiveTonightRepository(await Hive.openBox<List>(boxName));

  @override
  List<TonightLink> load() {
    try {
      return [
        for (final map in _box.get(_key) ?? const [])
          TonightLink.fromMap(map as Map),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> save(List<TonightLink> links) =>
      _box.put(_key, [for (final link in links) link.toMap()]);
}

class InMemoryTonightRepository implements TonightRepository {
  InMemoryTonightRepository([this._links = const []]);

  List<TonightLink> _links;

  @override
  List<TonightLink> load() => _links;

  @override
  Future<void> save(List<TonightLink> links) async => _links = links;
}

/// Overridden in `main()` with the opened Hive repository.
final tonightRepositoryProvider = Provider<TonightRepository>(
  (ref) => InMemoryTonightRepository(),
);

/// Tonight's list: links collected during the day that download by
/// themselves at night, when the phone is charging on Wi-Fi.
///
/// A saved link is read straight away in the background (it only takes a
/// moment) and becomes a night download in the queue at the chosen quality,
/// so the queue's night rules start it. Links that cannot be read yet, such
/// as with no internet, wait here and are read once the phone is online.
class TonightController extends Notifier<List<TonightLink>> {
  bool _reading = false;

  /// Read links start straight away instead of waiting for the night.
  bool _startNow = false;

  @override
  List<TonightLink> build() {
    ref.listen(onlineProvider, (_, next) {
      if (next.value ?? false) unawaited(_readPending());
    });
    final saved = ref.read(tonightRepositoryProvider).load();
    unawaited(Future<void>.microtask(_readPending));
    return saved;
  }

  void _set(List<TonightLink> links) {
    state = links;
    unawaited(ref.read(tonightRepositoryProvider).save(links));
  }

  /// Saves [url] for tonight. False when it is already on the list or
  /// already waiting in the queue.
  bool add(String url) {
    final link = url.trim();
    if (link.isEmpty) return false;
    final queued = ref
        .read(downloadQueueControllerProvider)
        .any(
          (task) =>
              task.url == link &&
              task.tonight &&
              task.status == DownloadStatus.queued,
        );
    if (queued || state.any((saved) => saved.url == link)) return false;
    _set([...state, TonightLink(url: link, addedAt: DateTime.now())]);
    unawaited(_readPending());
    return true;
  }

  void remove(String url) => _set([
    for (final link in state)
      if (link.url != url) link,
  ]);

  /// Tries a link that could not be read again.
  void retry(String url) {
    _set([
      for (final link in state)
        link.url == url ? link.copyWith(clearError: true) : link,
    ]);
    unawaited(_readPending());
  }

  /// Starts everything on the list now, without waiting for the night.
  void downloadAllNow() {
    final queue = ref.read(downloadQueueControllerProvider.notifier);
    for (final task in ref.read(tonightTasksProvider)) {
      queue.startNow(task.id);
    }
    if (state.isNotEmpty) {
      _startNow = true;
      unawaited(_readPending());
    }
  }

  /// Reads the links still to be read, one after another.
  Future<void> _readPending() async {
    if (_reading || !ref.mounted) return;
    _reading = true;
    try {
      while (ref.mounted) {
        final next = state
            .where((link) => link.error == null && !link.reading)
            .firstOrNull;
        if (next == null) break;
        if (!(ref.read(onlineProvider).value ?? true)) break;

        _set([
          for (final link in state)
            link.url == next.url ? link.copyWith(reading: true) : link,
        ]);
        String? failure;
        var tryLater = false;
        try {
          final info = await ref.read(mediaExtractorProvider).fetch(next.url);
          if (!ref.mounted) return;
          final quality = ref.read(settingsControllerProvider).tonightQuality;
          final format =
              pickPreferredFormat(info, quality) ?? info.defaultOption;
          if (format == null) {
            failure = 'Nothing to download was found at this link.';
          } else {
            ref
                .read(downloadQueueControllerProvider.notifier)
                .enqueue(info, format, tonight: !_startNow);
          }
        } catch (error) {
          if (!ref.mounted) return;
          tryLater = isConnectionError('$error');
          failure = '$error';
        }

        if (failure == null) {
          remove(next.url);
        } else {
          _set([
            for (final link in state)
              if (link.url == next.url)
                tryLater
                    ? link.copyWith(reading: false)
                    : link.copyWith(reading: false, error: failure)
              else
                link,
          ]);
          // No connection: the rest wait until the phone is online again.
          if (tryLater) break;
        }
      }
    } finally {
      _reading = false;
      if (state.every((link) => link.error != null)) _startNow = false;
    }
  }
}

final tonightProvider = NotifierProvider<TonightController, List<TonightLink>>(
  TonightController.new,
);

/// Downloads in the queue that belong to tonight: waiting for the night, or
/// already running because it came.
final tonightTasksProvider = Provider<List<DownloadTask>>(
  (ref) => [
    for (final task in ref.watch(downloadQueueControllerProvider))
      if (task.tonight && task.status.isActive) task,
  ],
);

/// Everything on tonight's list: links still to be read and downloads
/// waiting in the queue.
final tonightCountProvider = Provider<int>(
  (ref) =>
      ref.watch(tonightProvider).length +
      ref.watch(tonightTasksProvider).length,
);
