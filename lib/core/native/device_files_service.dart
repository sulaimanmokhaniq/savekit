import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'youtube_dl_native_service.dart';

/// A video chosen from the phone, staged for conversion.
class PickedVideo {
  const PickedVideo({
    required this.path,
    required this.name,
    required this.size,
  });

  final String path;
  final String name;
  final int size;
}

/// A status WhatsApp has downloaded for viewing.
class WhatsAppStatus {
  const WhatsAppStatus({
    required this.uri,
    required this.name,
    required this.size,
    required this.modified,
    required this.isVideo,
  });

  /// Android document address; opaque to Dart.
  final String uri;
  final String name;
  final int size;
  final DateTime modified;
  final bool isVideo;

  factory WhatsAppStatus.fromMap(Map<Object?, Object?> map) => WhatsAppStatus(
    uri: map['uri'] as String? ?? '',
    name: map['name'] as String? ?? '',
    size: (map['size'] as num?)?.toInt() ?? 0,
    modified: DateTime.fromMillisecondsSinceEpoch(
      (map['modified'] as num?)?.toInt() ?? 0,
    ),
    isVideo: map['isVideo'] as bool? ?? false,
  );
}

/// Files outside the app, reached through Android's own pickers: a video for
/// the converter, and WhatsApp's status folder.
class DeviceFilesService {
  DeviceFilesService({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel(YoutubeDlNativeService.engineChannel);

  final MethodChannel _channel;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (error) {
      throw EngineException.from(error);
    } on MissingPluginException {
      throw const EngineException(
        'ENGINE_UNAVAILABLE',
        'This is only available on Android.',
      );
    }
  }

  /// Opens the system picker for a video. Null when the user backs out.
  Future<PickedVideo?> pickVideo() => _guard(() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('pickVideo');
    if (result == null) return null;
    return PickedVideo(
      path: result['path'] as String,
      name: result['name'] as String? ?? 'video',
      size: (result['size'] as num?)?.toInt() ?? 0,
    );
  });

  /// Whether access to a WhatsApp status folder has been granted.
  Future<bool> statusFolderGranted() => _guard(
    () async =>
        await _channel.invokeMethod<bool>('statusFolderGranted') ?? false,
  );

  /// Opens Android's folder picker at WhatsApp's status folder; the user taps
  /// "Use this folder". Returns false if they back out or pick another folder.
  Future<bool> grantStatusFolder({bool business = false}) => _guard(
    () async =>
        await _channel.invokeMethod<bool>('grantStatusFolder', {
          'business': business,
        }) ??
        false,
  );

  Future<void> forgetStatusFolder() =>
      _guard(() => _channel.invokeMethod<void>('forgetStatusFolder'));

  /// The viewed statuses still on the phone, newest first.
  Future<List<WhatsAppStatus>> listStatuses() => _guard(() async {
    final result = await _channel.invokeListMethod<Map>('listStatuses');
    return [
      for (final item in result ?? const <Map>[]) WhatsAppStatus.fromMap(item),
    ];
  });

  /// JPEG preview of a status, or null when none can be made.
  Future<Uint8List?> statusThumbnail(String uri, {int size = 320}) async {
    try {
      return await _channel.invokeMethod<Uint8List>('statusThumbnail', {
        'uri': uri,
        'size': size,
      });
    } catch (_) {
      return null;
    }
  }

  /// Copies statuses into [outputDir] and returns the new files' paths.
  Future<List<String>> importStatuses(List<String> uris, String outputDir) =>
      _guard(() async {
        final result = await _channel.invokeListMethod<String>(
          'importStatuses',
          {'uris': uris, 'outputDir': outputDir},
        );
        return result ?? const <String>[];
      });
}

final deviceFilesServiceProvider = Provider<DeviceFilesService>(
  (ref) => DeviceFilesService(),
);
