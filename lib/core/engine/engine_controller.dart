import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../native/youtube_dl_native_service.dart';
import '../network/connectivity_service.dart';
import '../providers.dart';
import '../settings/app_settings.dart';
import '../l10n/l10n.dart';

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
    // Sites change often; keep the extractors fresh without being asked.
    Future<void>.microtask(_autoUpdateIfDue);
    return EngineState(
      version: status.version,
      galleryVersion: status.galleryVersion,
    );
  }

  /// How old the extractors may get before they are refreshed automatically.
  static const autoUpdateInterval = Duration(days: 7);

  Future<void> _autoUpdateIfDue() async {
    if (!ref.mounted) return;
    final settings = ref.read(settingsControllerProvider);
    if (!settings.autoUpdate) return;
    final last = settings.lastEngineUpdate;
    final now = ref.read(clockProvider)();
    if (last != null && now.difference(last) < autoUpdateInterval) return;
    // Respect "Wi-Fi only": the update is a few megabytes.
    if (settings.wifiOnly &&
        !await ref.read(connectivityServiceProvider).isOnWifi()) {
      return;
    }
    if (!ref.mounted) return;
    await updateEngine(automatic: true);
  }

  /// Updates everything that can be updated without a new APK. Returns the
  /// message describing what happened.
  ///
  /// An [automatic] update is quiet: it leaves no message behind unless it
  /// actually installed something.
  Future<String> updateEngine({bool automatic = false}) async {
    final current = state.value;
    if (current == null) return tr('The engine is not ready yet.');
    if (current.isUpdating) return tr('An update is already running.');
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
      if (result?.updated ?? false) tr('yt-dlp ${result!.version}'),
      if (result?.galleryUpdated ?? false)
        tr('gallery-dl ${result!.galleryVersion}'),
      if (rulesUpdated) tr('page rules'),
    ];
    final String message;
    if (engineError != null) {
      message = tr('Update failed: $engineError');
    } else if (updated.isEmpty) {
      message = tr('Everything is already up to date.');
    } else {
      message = tr('Updated ${updated.join(', ')}.');
    }

    if (!ref.mounted) return message;
    if (engineError == null) {
      ref
          .read(settingsControllerProvider.notifier)
          .markEngineUpdated(ref.read(clockProvider)());
    }
    final quiet = automatic && (engineError != null || updated.isEmpty);
    state = AsyncData(
      EngineState(
        version: result?.version ?? current.version,
        galleryVersion: result?.galleryVersion ?? current.galleryVersion,
        lastUpdateMessage: quiet
            ? current.lastUpdateMessage
            : automatic
            ? tr('Updated automatically: ${updated.join(', ')}.')
            : message,
        lastUpdateFailed: !quiet && engineError != null,
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
