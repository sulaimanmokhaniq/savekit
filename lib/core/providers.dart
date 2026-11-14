import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../features/cookies/data/cookie_export_service.dart';
import '../features/downloader/data/direct_download_service.dart';
import '../features/downloader/data/download_repository.dart';
import '../features/downloader/data/gallery_export_service.dart';
import '../features/extractor/data/media_extractor.dart';
import '../features/extractor/data/web_extraction_rules.dart';
import '../features/extractor/data/web_page_extractor.dart';
import 'native/youtube_dl_native_service.dart';
import 'storage/app_paths.dart';

/// The app's services, wired together. Controllers read these; tests override
/// them with fakes.

final nativeServiceProvider = Provider<YoutubeDlNativeService>(
  (ref) => YoutubeDlNativeService(),
);

final cookieExportServiceProvider = Provider<CookieExportService>(
  (ref) => CookieExportService(),
);

final webExtractionRulesStoreProvider = Provider<WebExtractionRulesStore>(
  (ref) => WebExtractionRulesStore(),
);

final webPageExtractorProvider = Provider<WebPageExtractor>(
  (ref) => WebPageExtractor(rules: ref.watch(webExtractionRulesStoreProvider)),
);

final mediaExtractorProvider = Provider<MediaExtractor>(
  (ref) => MediaExtractor(
    native: ref.watch(nativeServiceProvider),
    cookies: ref.watch(cookieExportServiceProvider),
    webPage: ref.watch(webPageExtractorProvider),
  ),
);

final directDownloadServiceProvider = Provider<DirectDownloadService>((ref) {
  final service = DirectDownloadService();
  ref.onDispose(service.dispose);
  return service;
});

final galleryExportServiceProvider = Provider<GalleryExportService>(
  (ref) => GalleryExportService(ref.watch(nativeServiceProvider)),
);

final appPathsProvider = Provider<AppPaths>((ref) => AppPaths());

/// Overridden in `main()` with the opened Hive repository.
final downloadRepositoryProvider = Provider<DownloadRepository>(
  (ref) => InMemoryDownloadRepository(),
);

/// Asks for the notification permission (Android 13+) the first time a
/// download starts, so progress and "finished" notifications can be shown.
/// Downloads proceed whatever the answer.
typedef NotificationPermissionRequester = Future<void> Function();

final notificationPermissionProvider = Provider<NotificationPermissionRequester>(
  (ref) => () async {
    try {
      if (await Permission.notification.isGranted) return;
      await Permission.notification.request();
    } catch (_) {
      // Not available on this platform or already settled.
    }
  },
);
