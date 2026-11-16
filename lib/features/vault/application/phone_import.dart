import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/native/youtube_dl_native_service.dart';
import '../../../core/platform/media_platform.dart';
import '../../../core/providers.dart';
import '../../downloader/application/download_queue_controller.dart';
import '../../extractor/domain/media_format.dart';
import 'folders_controller.dart';

/// A photo or video picked from the phone, before it is added.
class PickedMedia {
  const PickedMedia({
    required this.uri,
    required this.name,
    required this.size,
    this.isVideo = false,
    this.mediaUri,
    this.folder,
  });

  /// Where to read it from.
  final String uri;
  final String name;
  final int size;
  final bool isVideo;

  /// Its entry in the phone's media library, needed to delete it after a
  /// move. Null for files from elsewhere (cloud drives, other apps).
  final String? mediaUri;

  /// Where it is on the phone, such as "DCIM/Camera/"; null when unknown.
  final String? folder;

  bool get canMove => mediaUri != null;

  /// "DCIM/Camera/IMG_001.jpg", or the name alone when the folder is unknown.
  String get location {
    final where = folder;
    if (where == null || where.isEmpty) return name;
    return where.endsWith('/') ? '$where$name' : '$where/$name';
  }

  factory PickedMedia.fromMap(Map<Object?, Object?> map) => PickedMedia(
    uri: map['uri'] as String? ?? '',
    name: map['name'] as String? ?? 'file',
    size: (map['size'] as num?)?.toInt() ?? 0,
    isVideo: map['isVideo'] as bool? ?? false,
    mediaUri: map['mediaUri'] as String?,
    folder: map['folder'] as String?,
  );
}

/// The phone's photos and videos, through Android's file picker.
class PhoneMediaService {
  PhoneMediaService({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel(YoutubeDlNativeService.engineChannel);

  final MethodChannel _channel;

  /// Opens the picker; empty when the user backs out.
  Future<List<PickedMedia>> pick() async {
    final result = await _channel.invokeListMethod<Map>('pickPhoneMedia');
    return [
      for (final item in result ?? const <Map>[]) PickedMedia.fromMap(item),
    ];
  }

  /// Copies [items] into [outputDir]. Returns the new path of each, by its
  /// [PickedMedia.uri]; ones that could not be copied are missing.
  Future<Map<String, String>> copy(
    List<PickedMedia> items,
    String outputDir,
  ) async {
    final result = await _channel.invokeListMethod<Map>('importPhoneMedia', {
      'uris': [for (final item in items) item.uri],
      'outputDir': outputDir,
    });
    return {
      for (final entry in result ?? const <Map>[])
        if (entry['path'] != null)
          entry['uri'] as String: entry['path'] as String,
    };
  }
}

final phoneMediaServiceProvider = Provider<PhoneMediaService>(
  (ref) => PhoneMediaService(),
);

/// What adding files from the phone did.
class ImportOutcome {
  const ImportOutcome({
    required this.added,
    required this.failed,
    this.originalsRemoved = false,
  });

  /// Files now in the Vault.
  final int added;

  /// Files that could not be copied.
  final int failed;

  /// For a move: whether the originals are gone from the phone. False when
  /// Android was not allowed to delete them, so both copies exist.
  final bool originalsRemoved;
}

/// Adds files from the phone to the Vault.
class PhoneImporter {
  PhoneImporter(this.ref);

  final Ref ref;

  /// Adds [items] to the Vault, and to folder [folderId] when given. With
  /// [move], the originals are then deleted (Android asks the user first),
  /// so SaveKit keeps the only copy.
  Future<ImportOutcome> add(
    List<PickedMedia> items, {
    String? folderId,
    bool move = false,
  }) async {
    final directory = await ref.read(appPathsProvider).downloadDirectory();
    final copies = await ref
        .read(phoneMediaServiceProvider)
        .copy(items, directory);

    final queue = ref.read(downloadQueueControllerProvider.notifier);
    final added = <String>[];
    final copied = <PickedMedia>[];
    for (final item in items) {
      final path = copies[item.uri];
      if (path == null) continue;
      final id = await queue.addCompleted(
        title: p.basenameWithoutExtension(item.name),
        platform: MediaPlatform.device,
        format: MediaFormat(
          id: 'phone',
          kind: item.isVideo ? MediaFormatKind.video : MediaFormatKind.gallery,
          label: 'From your phone',
          itemCount: 1,
          imageCount: item.isVideo ? 0 : 1,
          videoCount: item.isVideo ? 1 : 0,
        ),
        filePaths: [path],
        // It came from the gallery; putting it back would only duplicate it.
        toGallery: false,
      );
      if (id == null) continue;
      added.add(id);
      copied.add(item);
    }
    if (folderId != null && added.isNotEmpty) {
      // At the top of the folder, in the order they were picked.
      ref.read(foldersProvider.notifier).add(folderId, added);
    }

    var removed = false;
    if (move && copied.isNotEmpty) {
      try {
        removed = await ref
            .read(nativeServiceProvider)
            .deleteFromMediaStore(
              locations: [
                for (final item in copied)
                  if (item.mediaUri != null) item.mediaUri!,
              ],
              names: const [],
            );
      } catch (_) {
        removed = false;
      }
    }
    return ImportOutcome(
      added: added.length,
      failed: items.length - added.length,
      originalsRemoved: removed,
    );
  }
}

final phoneImporterProvider = Provider<PhoneImporter>(PhoneImporter.new);

/// Where SaveKit keeps its files, as a person would write it:
/// "Android/data/com.savekit.app/files/downloads".
String readableLocation(String path) {
  const roots = ['/storage/emulated/0/', '/sdcard/'];
  for (final root in roots) {
    if (path.startsWith(root)) return path.substring(root.length);
  }
  return path;
}
