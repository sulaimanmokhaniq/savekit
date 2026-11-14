import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:savekit/core/native/youtube_dl_native_service.dart';
import 'package:savekit/core/platform/media_platform.dart';
import 'package:savekit/core/providers.dart';
import 'package:savekit/core/storage/app_paths.dart';
import 'package:savekit/features/cookies/data/cookie_export_service.dart';
import 'package:savekit/features/cookies/domain/platform_account.dart';
import 'package:savekit/features/downloader/data/direct_download_service.dart';
import 'package:savekit/features/downloader/data/download_repository.dart';
import 'package:savekit/features/downloader/data/gallery_export_service.dart';
import 'package:savekit/features/downloader/domain/download_progress.dart';
import 'package:savekit/features/downloader/domain/download_task.dart';
import 'package:savekit/features/extractor/application/incoming_link_controller.dart';
import 'package:savekit/features/extractor/data/media_extractor.dart';
import 'package:savekit/features/extractor/data/web_extraction_rules.dart';
import 'package:savekit/features/extractor/domain/media_format.dart';
import 'package:savekit/features/extractor/domain/media_info.dart';

/// Stand-ins for everything that needs Android, for widget tests.

class UiFakeNative implements YoutubeDlNativeService {
  final events = StreamController<DownloadProgress>.broadcast();
  final started = <String>[];

  @override
  Stream<DownloadProgress> get progressStream => events.stream;

  @override
  Future<EngineStatus> initEngine() async =>
      const EngineStatus(version: '2026.11.10', galleryVersion: '1.32.20');

  @override
  Future<EngineUpdateResult> updateEngine() async => const EngineUpdateResult(
    updated: true,
    version: '2026.11.14',
    galleryUpdated: false,
    galleryVersion: '1.32.20',
  );

  @override
  Future<void> startDownload({
    required String taskId,
    required String url,
    required MediaFormat format,
    required String outputDir,
    String? cookiesFilePath,
  }) async => started.add(taskId);

  @override
  Future<bool> cancelDownload(String taskId) async => false;

  @override
  Future<void> updateDownloadService({
    required int activeCount,
    String title = 'Downloading',
    String text = '',
    int progress = -1,
  }) async {}

  @override
  Future<void> notifyDownloadFinished({
    required String taskId,
    required String title,
    required bool success,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UiFakePaths implements AppPaths {
  @override
  Future<String> downloadDirectory() async => '/savekit/downloads';
}

class UiFakeRulesStore implements WebExtractionRulesStore {
  @override
  Future<bool> updateFromRemote() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UiFakeDirect implements DirectDownloadService {
  @override
  Stream<DownloadProgress> get progressStream => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UiFakeGallery implements GalleryExportService {
  @override
  Future<bool> export(List<String> paths) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UiFakeCookies implements CookieExportService {
  UiFakeCookies(this.signedIn);

  final Set<PlatformAccount> signedIn;

  @override
  Future<String?> exportAll() async => null;

  @override
  Future<Map<PlatformAccount, bool>> loginStatuses() async => {
    for (final account in PlatformAccount.values)
      account: signedIn.contains(account),
  };

  @override
  Future<void> logout(PlatformAccount account) async => signedIn.remove(account);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UiFakeExtractor implements MediaExtractor {
  UiFakeExtractor(this.result);

  /// Returned for every link; a [MediaExtractionException] is thrown instead.
  Object result;

  @override
  Future<MediaInfo> fetch(String url) async {
    final value = result;
    if (value is MediaInfo) return value;
    throw value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UiFakeShareSource implements ShareSource {
  final stream = StreamController<String>.broadcast();

  @override
  Future<String?> initialText() async => null;

  @override
  Stream<String> textStream() => stream.stream;

  @override
  Future<void> reset() async {}
}

MediaFormat videoFormat(int height, {int? size}) => MediaFormat(
  id: 'video_$height',
  kind: MediaFormatKind.video,
  label: height >= 2160 ? '4K' : '${height}p',
  formatSelection: 'bv*+ba/b',
  formatSort: 'res:$height',
  height: height,
  fileSize: size,
  ext: 'mp4',
);

const mp3Format = MediaFormat(
  id: 'audio_mp3',
  kind: MediaFormatKind.audio,
  label: 'MP3',
  extractAudio: true,
  audioFormat: 'mp3',
  ext: 'mp3',
);

const m4aFormat = MediaFormat(
  id: 'audio_m4a',
  kind: MediaFormatKind.audio,
  label: 'M4A',
  extractAudio: true,
  audioFormat: 'm4a',
  ext: 'm4a',
);

const photosFormat = MediaFormat(
  id: 'gallery',
  kind: MediaFormatKind.gallery,
  label: 'Photos (4)',
  engine: DownloadEngineKind.gallerydl,
  itemCount: 4,
  imageCount: 4,
);

/// A clip with every kind of option, as the picker would get for a TikTok.
MediaInfo sampleInfo() => MediaInfo(
  url: 'https://www.tiktok.com/@studio/video/1',
  title: 'Golden hour timelapse over the old harbour',
  platform: MediaPlatform.tiktok,
  uploader: 'harbour.studio',
  duration: 187,
  videoOptions: [
    videoFormat(2160, size: 412 * 1024 * 1024),
    videoFormat(1080, size: 148 * 1024 * 1024),
    videoFormat(720, size: 61 * 1024 * 1024),
    videoFormat(480, size: 27 * 1024 * 1024),
  ],
  noWatermarkOption: const MediaFormat(
    id: 'no_watermark',
    kind: MediaFormatKind.noWatermark,
    label: 'Best No-Watermark',
    formatSelection: 'b',
    ext: 'mp4',
  ),
  audioOptions: const [mp3Format, m4aFormat],
  galleryOption: photosFormat,
  galleryItems: const [
    GalleryItem(url: 'https://img.example/1.jpg', extension: 'jpg'),
    GalleryItem(url: 'https://img.example/2.jpg', extension: 'jpg'),
    GalleryItem(url: 'https://img.example/3.jpg', extension: 'jpg'),
    GalleryItem(url: 'https://img.example/4.jpg', extension: 'jpg'),
  ],
);

DownloadTask storedTask(
  String id,
  String title,
  MediaPlatform platform,
  MediaFormat format,
  DownloadStatus status, {
  int minutesAgo = 0,
  List<String> files = const [],
  int? size,
  String? error,
}) {
  final created = DateTime(2026, 11, 14, 12).subtract(Duration(minutes: minutesAgo));
  return DownloadTask(
    id: id,
    url: 'https://example.com/$id',
    title: title,
    platform: platform,
    format: format,
    createdAt: created,
    status: status,
    filePaths: files,
    fileSize: size,
    error: error,
    completedAt: status == DownloadStatus.completed ? created : null,
    savedToGallery: status == DownloadStatus.completed,
  );
}

/// Provider overrides that make the whole app run without Android.
List<Override> uiOverrides({
  required UiFakeNative native,
  Object? extraction,
  List<DownloadTask> tasks = const [],
  Set<PlatformAccount> signedIn = const {},
  String? clipboard,
  UiFakeShareSource? shareSource,
}) => [
  nativeServiceProvider.overrideWithValue(native),
  directDownloadServiceProvider.overrideWithValue(UiFakeDirect()),
  galleryExportServiceProvider.overrideWithValue(UiFakeGallery()),
  cookieExportServiceProvider.overrideWithValue(UiFakeCookies({...signedIn})),
  mediaExtractorProvider.overrideWithValue(
    UiFakeExtractor(extraction ?? sampleInfo()),
  ),
  downloadRepositoryProvider.overrideWithValue(
    InMemoryDownloadRepository(tasks),
  ),
  appPathsProvider.overrideWithValue(UiFakePaths()),
  webExtractionRulesStoreProvider.overrideWithValue(UiFakeRulesStore()),
  notificationPermissionProvider.overrideWithValue(() async {}),
  shareSourceProvider.overrideWithValue(shareSource ?? UiFakeShareSource()),
  clipboardReaderProvider.overrideWithValue(() async => clipboard),
];
