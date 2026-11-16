import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../device/device_service.dart';
import '../settings/app_settings.dart';
import 'app_log.dart';

/// The text of a problem report: versions, the phone, the settings that
/// change behaviour, and the recent events. No cookies, passwords or files.
String buildReport({
  required AppInfo app,
  required String engineVersion,
  required String galleryVersion,
  required AppSettings settings,
  required List<String> events,
  DateTime? now,
}) {
  final buffer = StringBuffer()
    ..writeln('SaveKit problem report')
    ..writeln('Created: ${(now ?? DateTime.now()).toIso8601String()}')
    ..writeln()
    ..writeln('App: ${app.version.isEmpty ? 'unknown' : app.version}')
    ..writeln('Android: ${app.android} (API ${app.sdk}) · ${app.abi}')
    ..writeln('Phone: ${app.device}')
    ..writeln('yt-dlp: $engineVersion')
    ..writeln('gallery-dl: $galleryVersion')
    ..writeln()
    ..writeln('Settings:')
    ..writeln('  save to: ${settings.saveLocation.id}')
    ..writeln('  wifi only: ${settings.wifiOnly}')
    ..writeln('  at once: ${settings.maxConcurrent}')
    ..writeln('  one-tap: ${settings.oneTap.id}')
    ..writeln('  auto update: ${settings.autoUpdate}')
    ..writeln('  language: ${settings.language.id}')
    ..writeln()
    ..writeln('Recent events (${events.length}):');
  if (events.isEmpty) {
    buffer.writeln('  none');
  } else {
    for (final event in events) {
      buffer.writeln(event);
    }
  }
  return buffer.toString();
}

/// Writes the report to a temporary file and opens the share sheet, so the
/// user decides where it goes (WhatsApp, email…).
Future<void> shareReport(String report) async {
  final directory = await getTemporaryDirectory();
  final file = File(p.join(directory.path, 'savekit-report.txt'));
  await file.writeAsString(report, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'text/plain')],
      subject: 'SaveKit problem report',
      text: AppLog.lines.isEmpty ? null : 'SaveKit problem report',
    ),
  );
}
