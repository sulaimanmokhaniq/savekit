import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/media_extractor.dart';
import '../domain/media_info.dart';

/// What the format picker is showing.
sealed class ExtractionState {
  const ExtractionState();
}

class ExtractionIdle extends ExtractionState {
  const ExtractionIdle();
}

class ExtractionLoading extends ExtractionState {
  const ExtractionLoading(this.url);
  final String url;
}

class ExtractionLoaded extends ExtractionState {
  const ExtractionLoaded(this.info);
  final MediaInfo info;
}

class ExtractionFailed extends ExtractionState {
  const ExtractionFailed(this.url, this.message, {this.loginRequired = false});
  final String url;
  final String message;

  /// Signing in under Platform Accounts is likely to fix it.
  final bool loginRequired;
}

/// Looks up a link and holds the result for the format picker.
class ExtractionController extends Notifier<ExtractionState> {
  int _request = 0;

  @override
  ExtractionState build() => const ExtractionIdle();

  /// Fetches [url]. A newer call supersedes an older one still in flight.
  Future<void> fetch(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.scheme.startsWith('http') || uri.host.isEmpty) {
      state = ExtractionFailed(trimmed, 'That does not look like a link.');
      return;
    }

    final request = ++_request;
    state = ExtractionLoading(trimmed);
    try {
      final info = await ref.read(mediaExtractorProvider).fetch(trimmed);
      if (request != _request) return;
      state = info.allOptions.isEmpty
          ? ExtractionFailed(
              trimmed,
              'Nothing downloadable was found at this link.',
            )
          : ExtractionLoaded(info);
    } on MediaExtractionException catch (error) {
      if (request != _request) return;
      state = ExtractionFailed(
        trimmed,
        error.message,
        loginRequired: error.loginRequired,
      );
    } catch (error) {
      if (request != _request) return;
      state = ExtractionFailed(trimmed, error.toString());
    }
  }

  /// Dismisses the current result and abandons any lookup in flight.
  void clear() {
    _request++;
    state = const ExtractionIdle();
  }
}

final extractionControllerProvider =
    NotifierProvider<ExtractionController, ExtractionState>(
      ExtractionController.new,
    );
