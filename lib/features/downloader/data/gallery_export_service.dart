import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;

import '../../../core/native/youtube_dl_native_service.dart';

/// Kind of a finished file, decided by its extension.
enum SavedFileKind { image, video, audio, other }

SavedFileKind savedFileKindOf(String path) {
  final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
  const images = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'heif', 'avif', 'bmp'};
  const videos = {'mp4', 'mov', 'webm', 'mkv', 'm4v', '3gp', 'avi'};
  const audio = {'mp3', 'm4a', 'aac', 'opus', 'ogg', 'wav', 'flac'};
  if (images.contains(extension)) return SavedFileKind.image;
  if (videos.contains(extension)) return SavedFileKind.video;
  if (audio.contains(extension)) return SavedFileKind.audio;
  return SavedFileKind.other;
}

/// Copies finished downloads into the phone's shared storage so they show up
/// in the Gallery and music apps: photos and videos into a "SaveKit" album,
/// audio into Music/SaveKit, anything else into Download/SaveKit.
class GalleryExportService {
  GalleryExportService(this._native);

  static const album = 'SaveKit';

  final YoutubeDlNativeService _native;

  /// Asks for storage access where the Android version needs it (9 and below).
  Future<bool> ensureAccess() async {
    try {
      if (await Gal.hasPermission(toAlbum: true)) return true;
      return await Gal.requestPermission(toAlbum: true);
    } catch (_) {
      return false;
    }
  }

  /// Exports [paths]. Returns true only when every file was exported.
  Future<bool> export(List<String> paths) async {
    if (paths.isEmpty) return false;
    if (!await ensureAccess()) return false;
    var allSaved = true;
    for (final path in paths) {
      try {
        switch (savedFileKindOf(path)) {
          case SavedFileKind.image:
            await Gal.putImage(path, album: album);
          case SavedFileKind.video:
            await Gal.putVideo(path, album: album);
          case SavedFileKind.audio:
            await _native.exportToMediaStore(path, audio: true);
          case SavedFileKind.other:
            await _native.exportToMediaStore(path, audio: false);
        }
      } catch (_) {
        allSaved = false;
      }
    }
    return allSaved;
  }
}
