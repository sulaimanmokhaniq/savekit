import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../native/youtube_dl_native_service.dart';
import '../providers.dart';

/// State of the on-device extractors.
class EngineState {
  const EngineState({
    required this.version,
    required this.galleryVersion,
    this.isUpdating = false,
    this.lastUpdateMessage,
    this.lastUpdateFailed = false,
  });

  /// yt-dlp version.
  final String version;

  /// gallery-dl version.
  final String galleryVersion;
  final bool isUpdating;

  /// Outcome of the most recent "Update Engine", for a snackbar or status line.
  final String? lastUpdateMessage;
  final bool lastUpdateFailed;

  EngineState copyWith({
    String? version,
    String? galleryVersion,
    bool? isUpdating,
    String? lastUpdateMessage,
    bool? lastUpdateFailed,
  }) => EngineState(
    version: version ?? this.version,
    galleryVersion: galleryVersion ?? this.galleryVersion,
    isUpdating: isUpdating ?? this.isUpdating,
    lastUpdateMessage: lastUpdateMessage ?? this.lastUpdateMessage,
    lastUpdateFailed: lastUpdateFailed ?? this.lastUpdateFailed,
  );
}

/// Boots the native engine when first watched and runs over-the-air updates
/// of yt-dlp, gallery-dl and the page-extraction rules.
class EngineController extends AsyncNotifier<EngineState> {
  @override
  Future<EngineState> build() async {
    final status = await ref.read(nativeServiceProvider).initEngine();
    return EngineState(
      version: status.version,
      galleryVersion: status.galleryVersion,
    );
  }

  /// Updates everything that can be updated without a new APK. Returns the
  /// message describing what happened.
  Future<String> updateEngine() async {
    final current = state.value;
    if (current == null) return 'The engine is not ready yet.';
    if (current.isUpdating) return 'An update is already running.';
    state = AsyncData(current.copyWith(isUpdating: true));

    final native = ref.read(nativeServiceProvider);
    final rules = ref.read(webExtractionRulesStoreProvider);

    EngineUpdateResult? result;
    String? engineError;
    try {
      result = await native.updateEngine();
    } on EngineException catch (error) {
      engineError = error.message;
    }

    var rulesUpdated = false;
    try {
      rulesUpdated = await rules.updateFromRemote();
    } catch (_) {
      // The rules file is optional; a failed refresh keeps the current set.
    }

    final updated = <String>[
      if (result?.updated ?? false) 'yt-dlp ${result!.version}',
      if (result?.galleryUpdated ?? false)
        'gallery-dl ${result!.galleryVersion}',
      if (rulesUpdated) 'page rules',
    ];
    final String message;
    if (engineError != null) {
      message = 'Update failed: $engineError';
    } else if (updated.isEmpty) {
      message = 'Everything is already up to date.';
    } else {
      message = 'Updated ${updated.join(', ')}.';
    }

    state = AsyncData(
      EngineState(
        version: result?.version ?? current.version,
        galleryVersion: result?.galleryVersion ?? current.galleryVersion,
        lastUpdateMessage: message,
        lastUpdateFailed: engineError != null,
      ),
    );
    return message;
  }
}

final engineControllerProvider =
    AsyncNotifierProvider<EngineController, EngineState>(
      EngineController.new,
      // Unpacking the engine is expensive; retry only when the user asks.
      retry: (_, _) => null,
    );
