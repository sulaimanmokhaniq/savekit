import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../../../core/native/youtube_dl_native_service.dart';

/// Kind of a finished file, decided by its extension.
enum SavedFileKind { image, video, audio, other }

SavedFileKind savedFileKindOf(String path) {
  final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
  const images = {
    'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'heif', 'avif', 'bmp', //
  };
  const videos = {'mp4', 'mov', 'webm', 'mkv', 'm4v', '3gp', 'avi'};
  const audio = {'mp3', 'm4a', 'aac', 'opus', 'ogg', 'wav', 'flac'};
  if (images.contains(extension)) return SavedFileKind.image;
  if (videos.contains(extension)) return SavedFileKind.video;
  if (audio.contains(extension)) return SavedFileKind.audio;
  return SavedFileKind.other;
}

/// Copies finished downloads into the phone's shared storage so they show up
/// in the Gallery and music apps (Pictures/SaveKit, Movies/SaveKit,
/// Music/SaveKit, Download/SaveKit), and removes those copies again when the
/// download is deleted, so deleting in SaveKit frees the space everywhere.
class GalleryExportService {
  GalleryExportService(this._native);

  final YoutubeDlNativeService _native;

  /// Android 9 and below need the storage permission to write shared files;
  /// newer versions need none.
  Future<void> _ensureLegacyAccess() async {
    try {
      final status = await Permission.storage.status;
      if (!status.isGranted && !status.isPermanentlyDenied) {
        await Permission.storage.request();
      }
    } catch (_) {
      // Not applicable on this Android version.
    }
  }

  /// Exports [paths]. Returns, for each file that was exported, where its
  /// copy lives; keep this to delete the copy later.
  Future<Map<String, String>> export(List<String> paths) async {
    if (paths.isEmpty) return const {};
    await _ensureLegacyAccess();
    final exported = <String, String>{};
    for (final path in paths) {
      try {
        final location = await _native.exportToMediaStore(
          path,
          kind: savedFileKindOf(path).name,
        );
        if (location.isNotEmpty) exported[path] = location;
      } catch (_) {
        // This file stays in the Vault only.
      }
    }
    return exported;
  }

  /// Deletes exported copies. [locations] are values returned by [export];
  /// [legacyNames] are the file names of downloads exported before locations
  /// were recorded. Returns false when Android would not remove some copy
  /// (for example the user declined its confirmation).
  Future<bool> deleteExported({
    Iterable<String> locations = const [],
    Iterable<String> legacyNames = const [],
  }) async {
    if (locations.isEmpty && legacyNames.isEmpty) return true;
    try {
      return await _native.deleteFromMediaStore(
        locations: locations.toList(),
        names: legacyNames.toList(),
      );
    } catch (_) {
      return false;
    }
  }
}
