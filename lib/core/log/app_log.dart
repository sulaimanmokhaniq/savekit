import 'dart:io';

/// A short record of what went wrong recently, for the "Send a report"
/// button. It is kept in a file in the app's private storage so it survives
/// a crash, and is never sent anywhere unless the user shares the report.
/// Cookies and passwords never pass through here; links and extractor
/// messages do.
abstract final class AppLog {
  static const _capacity = 200;
  static final _lines = <String>[];
  static File? _file;

  /// Loads what earlier runs recorded and keeps recording to [file].
  static void attach(File file) {
    _file = file;
    try {
      if (file.existsSync()) {
        final saved = file.readAsStringSync().split('\n\u0000\n');
        _lines.insertAll(0, [
          for (final line in saved)
            if (line.trim().isNotEmpty) line,
        ]);
        while (_lines.length > _capacity) {
          _lines.removeAt(0);
        }
      }
    } catch (_) {
      // A damaged log starts afresh.
    }
  }

  static void _save() {
    final file = _file;
    if (file == null) return;
    try {
      file.writeAsStringSync(_lines.join('\n\u0000\n'));
    } catch (_) {
      // Logging must never break the app.
    }
  }

  /// Records [event], with optional [detail] such as an extractor message.
  static void add(String event, [String? detail]) {
    final time = DateTime.now().toIso8601String().substring(0, 19);
    _lines.add(
      detail == null || detail.isEmpty
          ? '$time  $event'
          : '$time  $event\n    ${detail.trim().replaceAll('\n', '\n    ')}',
    );
    if (_lines.length > _capacity) _lines.removeAt(0);
    _save();
  }

  /// The recorded lines, oldest first.
  static List<String> get lines => List.unmodifiable(_lines);

  static void clear() {
    _lines.clear();
    _save();
  }
}
