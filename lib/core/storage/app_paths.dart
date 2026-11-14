import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where SaveKit keeps its own copies of downloaded files. The vault plays,
/// shares and deletes these; the gallery gets a separate exported copy.
class AppPaths {
  AppPaths({Future<Directory?> Function()? externalDirectory})
    : _externalDirectory = externalDirectory ?? getExternalStorageDirectory;

  final Future<Directory?> Function() _externalDirectory;
  String? _downloads;

  /// `Android/data/com.savekit.app/files/downloads`, created on first use.
  /// Falls back to internal storage when no external storage is mounted.
  Future<String> downloadDirectory() async {
    final cached = _downloads;
    if (cached != null) return cached;
    Directory? base;
    try {
      base = await _externalDirectory();
    } catch (_) {
      base = null;
    }
    base ??= await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(base.path, 'downloads'));
    await directory.create(recursive: true);
    return _downloads = directory.path;
  }
}
