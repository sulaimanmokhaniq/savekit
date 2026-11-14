import 'package:flutter/services.dart';

import '../../features/downloader/domain/download_progress.dart';
import '../../features/extractor/domain/media_format.dart';
import '../../features/extractor/domain/media_info.dart';

/// A failure reported by the native engine, with yt-dlp's or gallery-dl's own
/// message when there is one.
class EngineException implements Exception {
  const EngineException(this.code, this.message);

  factory EngineException.from(PlatformException error) =>
      EngineException(error.code, error.message ?? error.code);

  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Versions of the extractors unpacked on the device.
class EngineStatus {
  const EngineStatus({required this.version, required this.galleryVersion});

  /// yt-dlp version.
  final String version;

  /// gallery-dl version; empty if it could not be started.
  final String galleryVersion;
}

/// Outcome of an over-the-air extractor update.
class EngineUpdateResult {
  const EngineUpdateResult({
    required this.updated,
    required this.version,
    required this.galleryUpdated,
    required this.galleryVersion,
    this.galleryError,
  });

  /// Whether a newer yt-dlp was installed.
  final bool updated;
  final String version;
  final bool galleryUpdated;
  final String galleryVersion;

  /// Set when yt-dlp updated but gallery-dl could not.
  final String? galleryError;

  bool get anythingUpdated => updated || galleryUpdated;
}

/// Dart side of the Kotlin bridge: every on-device extraction and download
/// goes through here.
class YoutubeDlNativeService {
  YoutubeDlNativeService({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methods = methodChannel ?? const MethodChannel(engineChannel),
       _events = eventChannel ?? const EventChannel(progressChannel);

  static const engineChannel = 'com.app.downloader/engine';
  static const progressChannel = 'com.app.downloader/progress';

  final MethodChannel _methods;
  final EventChannel _events;
  Stream<DownloadProgress>? _progress;

  /// Progress of every running native download. The native side replays the
  /// latest event of each unfinished task to a new listener, so nothing is
  /// lost while Flutter was not listening.
  Stream<DownloadProgress> get progressStream {
    return _progress ??= _events
        .receiveBroadcastStream()
        .where((event) => event is Map)
        .map((event) => DownloadProgress.fromMap(event as Map))
        .asBroadcastStream();
  }

  /// Unpacks Python, yt-dlp, FFmpeg, aria2c and gallery-dl. Slow on the very
  /// first launch (several seconds), near-instant afterwards.
  Future<EngineStatus> initEngine() async {
    final result = await _invokeMap('initEngine');
    return EngineStatus(
      version: result['version'] as String? ?? '',
      galleryVersion: result['galleryVersion'] as String? ?? '',
    );
  }

  Future<String> getEngineVersion() => _guard(
    () async => await _methods.invokeMethod<String>('getEngineVersion') ?? '',
  );

  /// Downloads the newest yt-dlp (nightly) and gallery-dl.
  Future<EngineUpdateResult> updateEngine() async {
    final result = await _invokeMap('updateEngine');
    return EngineUpdateResult(
      updated: result['updated'] as bool? ?? false,
      version: result['version'] as String? ?? '',
      galleryUpdated: result['galleryUpdated'] as bool? ?? false,
      galleryVersion: result['galleryVersion'] as String? ?? '',
      galleryError: result['galleryError'] as String?,
    );
  }

  /// Reads a link's metadata and download options.
  Future<MediaInfo> getMediaInfo(String url, {String? cookiesFilePath}) async {
    final result = await _invokeMap('getMediaInfo', {
      'url': url,
      'cookiesFilePath': cookiesFilePath,
    });
    return MediaInfo.fromMap(result);
  }

  /// Starts a native download. Returns once the task is accepted; progress and
  /// the final result arrive on [progressStream] under [taskId].
  Future<void> startDownload({
    required String taskId,
    required String url,
    required MediaFormat format,
    required String outputDir,
    String? cookiesFilePath,
  }) {
    assert(
      format.engine != DownloadEngineKind.direct,
      'Direct downloads are handled by DirectDownloadService.',
    );
    return _guard(
      () => _methods.invokeMethod<void>('startDownload', {
        'taskId': taskId,
        'url': url,
        'formatSelection': format.formatSelection.isEmpty
            ? 'best'
            : format.formatSelection,
        'formatSort': format.formatSort,
        'outputDir': outputDir,
        'cookiesFilePath': cookiesFilePath,
        'extractAudio': format.extractAudio,
        'audioFormat': format.audioFormat,
        'engine': format.engine.id,
        'itemCount': format.itemCount,
      }),
    );
  }

  /// Stops a running native download. Returns false when it was not running.
  Future<bool> cancelDownload(String taskId) => _guard(
    () async =>
        await _methods.invokeMethod<bool>('cancelDownload', {
          'taskId': taskId,
        }) ??
        false,
  );

  Future<Map<String, dynamic>> _invokeMap(
    String method, [
    Map<String, Object?>? arguments,
  ]) {
    return _guard(() async {
      final result = await _methods.invokeMapMethod<String, dynamic>(
        method,
        arguments,
      );
      return result ?? const <String, dynamic>{};
    });
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (error) {
      throw EngineException.from(error);
    } on MissingPluginException {
      throw const EngineException(
        'ENGINE_UNAVAILABLE',
        'The download engine is only available on Android.',
      );
    }
  }
}
