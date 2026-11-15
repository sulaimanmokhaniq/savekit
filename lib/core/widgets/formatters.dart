import '../l10n/l10n.dart';

/// "1.4 GB", "820 KB"; empty when the size is unknown.
String formatBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// "3:07" or "1:02:45"; empty when the length is unknown.
String formatDuration(int? seconds) {
  if (seconds == null || seconds <= 0) return '';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// "12s left", "4m 05s left"; empty when unknown.
String formatEta(int seconds) {
  if (seconds < 0) return '';
  if (seconds < 60) return tr('${seconds}s left');
  final m = seconds ~/ 60;
  final s = seconds % 60;
  if (m < 60) return tr('${m}m ${s.toString().padLeft(2, '0')}s left');
  return tr('${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m left');
}

const _languageNames = {
  'ar': 'Arabic',
  'en': 'English',
  'fr': 'French',
  'es': 'Spanish',
  'de': 'German',
  'it': 'Italian',
  'pt': 'Portuguese',
  'ru': 'Russian',
  'tr': 'Turkish',
  'fa': 'Persian',
  'ur': 'Urdu',
  'hi': 'Hindi',
  'id': 'Indonesian',
  'ja': 'Japanese',
  'ko': 'Korean',
  'zh': 'Chinese',
};

/// "Arabic" for "ar", "English (US)" for "en-US"; the code itself when the
/// language is not one of the common ones.
String languageName(String code) {
  final parts = code.split(RegExp('[-_]'));
  final name = _languageNames[parts.first.toLowerCase()];
  if (name == null) return code;
  final shown = tr(name);
  return parts.length > 1 ? '$shown (${parts.sublist(1).join('-')})' : shown;
}

/// "0:10" – always minutes and seconds, including for zero.
String formatClock(int seconds) {
  final formatted = formatDuration(seconds);
  return formatted.isEmpty ? '0:00' : formatted;
}
