/// A short in-memory record of what went wrong recently, for the "Send a
/// report" button. Nothing is written to disk or sent anywhere unless the
/// user shares the report themselves. Cookies and passwords never pass
/// through here; links and extractor messages do.
abstract final class AppLog {
  static const _capacity = 200;
  static final _lines = <String>[];

  /// Records [event], with optional [detail] such as an extractor message.
  static void add(String event, [String? detail]) {
    final time = DateTime.now().toIso8601String().substring(0, 19);
    _lines.add(
      detail == null || detail.isEmpty
          ? '$time  $event'
          : '$time  $event\n    ${detail.trim().replaceAll('\n', '\n    ')}',
    );
    if (_lines.length > _capacity) _lines.removeAt(0);
  }

  /// The recorded lines, oldest first.
  static List<String> get lines => List.unmodifiable(_lines);

  static void clear() => _lines.clear();
}
