import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:savekit/core/native/device_files_service.dart';
import 'package:savekit/core/native/youtube_dl_native_service.dart';
import 'package:savekit/core/network/connectivity_service.dart';
import 'package:savekit/core/platform/media_platform.dart';
import 'package:savekit/core/providers.dart';
import 'package:savekit/core/settings/app_settings.dart';
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
import 'package:savekit/features/tools/application/storage_controller.dart';
import 'package:savekit/features/vault/application/vault_lock.dart';

/// Stand-ins for everything that needs Android, for widget tests.

class UiFakeNative implements YoutubeDlNativeService {
  final events = StreamController<DownloadProgress>.broadcast();
  final started = <String>[];
  final canceled = <String>[];

  /// Whether cancelDownload reports that a process was stopped.
  bool cancelStops = false;

  @override
  Stream<DownloadProgress> get progressStream => events.stream;

  @override
  Future<EngineStatus> initEngine() async =>
      const EngineStatus(version: '2026.11.10', galleryVersion: '1.32.20');

  /// Times updateEngine was called.
  int updates = 0;

  @override
  Future<EngineUpdateResult> updateEngine() async {
    updates++;
    return _updateResult;
  }

  static const _updateResult = EngineUpdateResult(
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

  /// Pages asked for from an account, as (url, start).
  final accountRequests = <(String, int)>[];

  @override
  Future<AccountPage> getAccountMedia(
    String url, {
    String? cookiesFilePath,
    int start = 1,
    int count = 100,
  }) async {
    accountRequests.add((url, start));
    // Two pages: photos and direct videos first, then videos that still
    // need looking up.
    return AccountPage(
      title: 'harbour.studio',
      platform: 'x',
      hasMore: start == 1,
      items: [
        for (var i = start; i < start + 6; i++)
          AccountItem(
            url: start == 1
                ? 'https://cdn.example/$i.${i.isEven ? 'mp4' : 'jpg'}'
                : 'https://x.com/harbour/status/$i',
            title: 'Post $i',
            isVideo: start != 1 || i.isEven,
            needsExtractor: start != 1,
          ),
      ],
    );
  }

  @override
  Future<PlaylistInfo> getPlaylistInfo(
    String url, {
    String? cookiesFilePath,
  }) async => PlaylistInfo(
    url: url,
    title: 'Road trip mixes',
    uploader: 'harbour.studio',
    entries: [
      for (var i = 1; i <= 4; i++)
        PlaylistEntry(url: 'https://youtu.be/mix$i', title: 'Mix volume $i'),
    ],
  );

  @override
  Future<bool> cancelDownload(String taskId) async {
    canceled.add(taskId);
    return cancelStops;
  }

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

/// A connection the test controls.
class FakeConnectivity implements ConnectivityService {
  FakeConnectivity({this.onWifi = true});

  bool onWifi;
  final _changes = StreamController<bool>.broadcast();

  void setWifi(bool value) {
    onWifi = value;
    _changes.add(value);
  }

  @override
  Future<bool> isOnWifi() async => onWifi;

  @override
  Stream<bool> get wifiChanges => _changes.stream;
}

class UiFakeVaultLock implements VaultLockService {
  UiFakeVaultLock({this.accept = true});

  /// Whether the "fingerprint" is accepted.
  bool accept;
  final prompts = <String>[];

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> authenticate(String reason) async {
    prompts.add(reason);
    return accept;
  }
}

class UiFakeDeviceFiles implements DeviceFilesService {
  bool granted = true;
  final imported = <List<String>>[];

  @override
  Future<bool> statusFolderGranted() async => granted;

  @override
  Future<bool> grantStatusFolder({bool business = false}) async =>
      granted = true;

  @override
  Future<List<WhatsAppStatus>> listStatuses() async => [
    for (var i = 0; i < 6; i++)
      WhatsAppStatus(
        uri: 'content://statuses/$i',
        name: 'status_$i.${i.isEven ? 'jpg' : 'mp4'}',
        size: (i + 1) * 700 * 1024,
        modified: DateTime(2026, 11, 14, 12 - i),
        isVideo: i.isOdd,
      ),
  ];

  @override
  Future<String> previewStatus(String uri) async => '/none/preview.jpg';

  @override
  Future<Uint8List?> statusThumbnail(String uri, {int size = 320}) async =>
      null;

  @override
  Future<List<String>> importStatuses(
    List<String> uris,
    String outputDir,
  ) async {
    imported.add(uris);
    return [for (final uri in uris) '$outputDir/${uri.split('/').last}.jpg'];
  }

  @override
  Future<PickedVideo?> pickVideo() async => const PickedVideo(
    path: '/cache/converter/Holiday clip.mp4',
    name: 'Holiday clip.mp4',
    size: 48 * 1024 * 1024,
  );

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
  /// Direct downloads started, as task id -> addresses.
  final started = <String, List<String>>{};

  @override
  void start({
    required String taskId,
    required List<String> urls,
    required String outputDir,
    String? referer,
    String namePrefix = 'savekit',
  }) => started[taskId] = urls;

  @override
  Stream<DownloadProgress> get progressStream => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UiFakeGallery implements GalleryExportService {
  /// Gallery copies deleted, as (locations, legacy names).
  final deleted = <(List<String>, List<String>)>[];

  /// What deleteExported answers; false simulates Android keeping a copy.
  bool deleteSucceeds = true;

  /// When set, exporting really copies each file into this folder, the way
  /// Android copies it into the gallery, and reports the copy's path.
  Directory? galleryFolder;

  /// Files handed over for export.
  final exportedPaths = <String>[];

  @override
  Future<Map<String, ExportedCopy>> export(List<String> paths) async {
    exportedPaths.addAll(paths);
    final folder = galleryFolder;
    return {
      for (final path in paths)
        path: ExportedCopy(
          location: 'content://media/${path.split('/').last}',
          path: folder == null
              ? null
              : (File(path).copySync('${folder.path}/${path.split('/').last}'))
                    .path,
        ),
    };
  }

  @override
  Future<bool> deleteExported({
    Iterable<String> locations = const [],
    Iterable<String> legacyNames = const [],
  }) async {
    deleted.add((locations.toList(), legacyNames.toList()));
    return deleteSucceeds;
  }

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
  Future<void> logout(PlatformAccount account) async =>
      signedIn.remove(account);

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
  final created = DateTime(
    2026,
    11,
    14,
    12,
  ).subtract(Duration(minutes: minutesAgo));
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
  AppSettings settings = const AppSettings(),
  FakeConnectivity? connectivity,
  DownloadRepository? repository,
  AppPaths? paths,
  MediaExtractor? extractor,
  UiFakeVaultLock? vaultLock,
  UiFakeDeviceFiles? deviceFiles,
  StorageSnapshot? storage,
  UiFakeGallery? gallery,
  List<String>? iconChanges,
  UiFakeDirect? direct,

  /// Tests of the app's screens start with automatic updates off, so the
  /// engine versions they show are the ones the fake starts with.
  bool allowAutoUpdate = false,
}) => [
  launcherIconProvider.overrideWithValue(
    (themeId) async => iconChanges?.add(themeId),
  ),
  vaultLockServiceProvider.overrideWithValue(vaultLock ?? UiFakeVaultLock()),
  deviceFilesServiceProvider.overrideWithValue(
    deviceFiles ?? UiFakeDeviceFiles(),
  ),
  // Widget tests cannot do real file I/O, so the measured storage is given.
  if (storage != null)
    storageSnapshotProvider.overrideWith((ref) async => storage),
  settingsRepositoryProvider.overrideWithValue(
    InMemorySettingsRepository(
      allowAutoUpdate ? settings : settings.copyWith(autoUpdate: false),
    ),
  ),
  connectivityServiceProvider.overrideWithValue(
    connectivity ?? FakeConnectivity(),
  ),
  nativeServiceProvider.overrideWithValue(native),
  directDownloadServiceProvider.overrideWithValue(direct ?? UiFakeDirect()),
  galleryExportServiceProvider.overrideWithValue(gallery ?? UiFakeGallery()),
  cookieExportServiceProvider.overrideWithValue(UiFakeCookies({...signedIn})),
  mediaExtractorProvider.overrideWithValue(
    extractor ?? UiFakeExtractor(extraction ?? sampleInfo()),
  ),
  downloadRepositoryProvider.overrideWithValue(
    repository ?? InMemoryDownloadRepository(tasks),
  ),
  appPathsProvider.overrideWithValue(paths ?? UiFakePaths()),
  webExtractionRulesStoreProvider.overrideWithValue(UiFakeRulesStore()),
  notificationPermissionProvider.overrideWithValue(() async {}),
  shareSourceProvider.overrideWithValue(shareSource ?? UiFakeShareSource()),
  clipboardReaderProvider.overrideWithValue(() async => clipboard),
];
