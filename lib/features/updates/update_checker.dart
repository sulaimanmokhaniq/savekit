import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device/device_service.dart';

/// A newer SaveKit published on the project's Releases page.
class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.apkUrl,
    required this.pageUrl,
  });

  final String version;

  /// Direct download of the APK matching this phone's processor.
  final String apkUrl;

  /// The release page, as a fallback.
  final String pageUrl;
}

/// Fetches the latest release description; a seam for tests.
typedef ReleaseFetcher = Future<Map<String, dynamic>?> Function();

final releaseFetcherProvider = Provider<ReleaseFetcher>(
  (ref) => () async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(
        Uri.parse(
          'https://api.github.com/repos/sulaimanmokhaniq/savekit/releases/latest',
        ),
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      return Map<String, dynamic>.from(
        jsonDecode(await utf8.decodeStream(response)) as Map,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  },
);

/// Compares "1.0.15" style versions; a missing part counts as zero.
int compareVersions(String a, String b) {
  List<int> parts(String v) => [
    for (final part in v.replaceFirst(RegExp('^v'), '').split('.'))
      int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
  ];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final left = i < x.length ? x[i] : 0;
    final right = i < y.length ? y[i] : 0;
    if (left != right) return left.compareTo(right);
  }
  return 0;
}

/// The newer release, or null when this is the latest, the check failed, or
/// the installed version is unknown (a development build).
final appUpdateProvider = FutureProvider<AppUpdate?>((ref) async {
  final info = await ref.watch(appInfoProvider.future);
  if (info.version.isEmpty) return null;
  final release = await ref.watch(releaseFetcherProvider)();
  if (release == null) return null;

  final tag = release['tag_name'] as String? ?? '';
  if (tag.isEmpty || compareVersions(tag, info.version) <= 0) return null;

  final assets = (release['assets'] as List? ?? const []).whereType<Map>();
  final wanted = switch (info.abi) {
    'armeabi-v7a' => 'SaveKit-arm32.apk',
    'x86_64' => 'SaveKit-x86_64.apk',
    _ => 'SaveKit-arm64.apk',
  };
  String? apk;
  for (final asset in assets) {
    if (asset['name'] == wanted) apk = asset['browser_download_url'] as String?;
  }
  final page = release['html_url'] as String? ?? '';
  return AppUpdate(
    version: tag.replaceFirst('v', ''),
    apkUrl: apk ?? page,
    pageUrl: page,
  );
});
