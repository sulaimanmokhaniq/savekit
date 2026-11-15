import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/settings/app_settings.dart';
import '../../downloader/application/download_queue_controller.dart';
import '../domain/quality_selection.dart';
import '../../../core/l10n/l10n.dart';

/// A link the batch could not queue, and why.
class BatchFailure {
  const BatchFailure(this.url, this.message);

  final String url;
  final String message;
}

/// Progress of looking up several links and queueing each at a chosen quality.
class BatchState {
  const BatchState({
    this.total = 0,
    this.done = 0,
    this.queued = 0,
    this.running = false,
    this.failures = const [],
  });

  /// Links in the current or last batch.
  final int total;

  /// Links handled so far, whether queued or failed.
  final int done;

  /// Links that were added to the download queue.
  final int queued;
  final bool running;
  final List<BatchFailure> failures;

  /// Nothing to show: no batch ran, or it was dismissed.
  bool get isEmpty => total == 0;
}

/// Looks up links one after another without showing the picker: used for
/// several pasted links, playlists, and one-tap sharing. Each link is queued
/// at the given quality; ones that cannot be read are kept as failures so the
/// user can open them in the picker.
class BatchController extends Notifier<BatchState> {
  int _run = 0;

  @override
  BatchState build() => const BatchState();

  /// Adds [urls] to the batch being processed, or starts a new one.
  Future<void> start(List<String> urls, QualityPreference preference) async {
    if (urls.isEmpty) return;
    assert(preference != QualityPreference.ask);

    if (state.running) {
      // Joining: the loop below belongs to the batch already running.
      _pending.addAll(urls.map((url) => (url, preference)));
      state = BatchState(
        total: state.total + urls.length,
        done: state.done,
        queued: state.queued,
        running: true,
        failures: state.failures,
      );
      return;
    }

    final run = ++_run;
    _pending
      ..clear()
      ..addAll(urls.map((url) => (url, preference)));
    state = BatchState(total: urls.length, running: true);

    final extractor = ref.read(mediaExtractorProvider);
    while (_pending.isNotEmpty) {
      final (url, quality) = _pending.removeAt(0);
      String? failure;
      try {
        final info = await extractor.fetch(url);
        if (run != _run || !ref.mounted) return;
        final format = pickPreferredFormat(info, quality);
        if (format == null) {
          failure = tr('No ${quality.label} option for this link.');
        } else {
          ref
              .read(downloadQueueControllerProvider.notifier)
              .enqueue(info, format);
        }
      } catch (error) {
        if (run != _run || !ref.mounted) return;
        failure = error.toString();
      }
      state = BatchState(
        total: state.total,
        done: state.done + 1,
        queued: state.queued + (failure == null ? 1 : 0),
        running: _pending.isNotEmpty,
        failures: [
          ...state.failures,
          if (failure != null) BatchFailure(url, failure),
        ],
      );
    }
  }

  final _pending = <(String, QualityPreference)>[];

  /// Stops looking up the remaining links. Downloads already queued stay.
  void cancel() {
    _run++;
    _pending.clear();
    state = BatchState(
      total: state.done,
      done: state.done,
      queued: state.queued,
      failures: state.failures,
    );
  }

  /// Clears the finished batch's summary.
  void dismiss() {
    if (state.running) return;
    state = const BatchState();
  }

  /// Drops one failure, once the user has dealt with it.
  void removeFailure(String url) {
    state = BatchState(
      total: state.total,
      done: state.done,
      queued: state.queued,
      running: state.running,
      failures: [
        for (final failure in state.failures)
          if (failure.url != url) failure,
      ],
    );
  }
}

final batchControllerProvider = NotifierProvider<BatchController, BatchState>(
  BatchController.new,
);
