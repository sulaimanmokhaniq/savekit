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
  if (seconds < 60) return '${seconds}s left';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  if (m < 60) return '${m}m ${s.toString().padLeft(2, '0')}s left';
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m left';
}
