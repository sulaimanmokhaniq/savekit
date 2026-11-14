import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:savekit/core/native/youtube_dl_native_service.dart';
import 'package:savekit/core/platform/media_platform.dart';
import 'package:savekit/core/providers.dart';
import 'package:savekit/core/storage/app_paths.dart';
import 'package:savekit/features/cookies/data/cookie_export_service.dart';
import 'package:savekit/features/downloader/application/download_queue_controller.dart';
import 'package:savekit/features/downloader/data/direct_download_service.dart';
import 'package:savekit/features/downloader/data/download_repository.dart';
import 'package:savekit/features/downloader/data/gallery_export_service.dart';
import 'package:savekit/features/downloader/domain/download_progress.dart';
import 'package:savekit/features/downloader/domain/download_task.dart';
import 'package:savekit/features/extractor/domain/media_format.dart';
import 'package:savekit/features/extractor/domain/media_info.dart';

class FakeNative implements YoutubeDlNativeService {
  final events = StreamController<DownloadProgress>.broadcast();
  final started = <String>[];
  final canceled = <String>[];
  final finishedNotifications = <String, bool>{};
  final serviceCounts = <int>[];
  final startArguments = <String, Map<String, Object?>>{};

  /// Error to throw from the next startDownload.
  EngineException? startError;

  /// Whether cancelDownload reports that a process was stopped.
  bool cancelStopsProcess = true;

  @override
  Stream<DownloadProgress> get progressStream => events.stream;

  @override
  Future<void> startDownload({
    required String taskId,
    required String url,
    required MediaFormat format,
    required String outputDir,
    String? cookiesFilePath,
  }) async {
    final error = startError;
    if (error != null) {
      startError = null;
      throw error;
    }
    started.add(taskId);
    startArguments[taskId] = {
      'url': url,
      'outputDir': outputDir,
      'cookies': cookiesFilePath,
      'format': format.id,
    };
  }

  @override
  Future<bool> cancelDownload(String taskId) async {
    canceled.add(taskId);
    return cancelStopsProcess;
  }

  @override
  Future<void> updateDownloadService({
    required int activeCount,
    String title = 'Downloading',
    String text = '',
    int progress = -1,
  }) async => serviceCounts.add(activeCount);

  @override
  Future<void> notifyDownloadFinished({
    required String taskId,
    required String title,
    required bool success,
  }) async => finishedNotifications[taskId] = success;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDirect implements DirectDownloadService {
  final events = StreamController<DownloadProgress>.broadcast();
  final started = <String, List<String>>{};
  final canceled = <String>[];

  @override
  Stream<DownloadProgress> get progressStream => events.stream;

  @override
  void start({
    required String taskId,
    required List<String> urls,
    required String outputDir,
    String? referer,
    String namePrefix = 'savekit',
  }) => started[taskId] = urls;

  @override
  bool cancel(String taskId) {
    canceled.add(taskId);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeGallery implements GalleryExportService {
  final exported = <List<String>>[];
  bool result = true;

  @override
  Future<bool> export(List<String> paths) async {
    exported.add(paths);
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCookies implements CookieExportService {
  @override
  Future<String?> exportAll() async => '/data/cookies.txt';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const video = MediaFormat(
  id: 'video_1080',
  kind: MediaFormatKind.video,
  label: '1080p',
  formatSelection: 'bv*+ba/b',
);

MediaInfo info(String name, {MediaFormat? gallery}) => MediaInfo(
  url: 'https://example.com/$name',
  title: name,
  platform: MediaPlatform.youtube,
  videoOptions: const [video],
  galleryOption: gallery,
);

/// Lets queued microtasks and timers of the controller run.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late FakeNative native;
  late FakeDirect direct;
  late FakeGallery gallery;
  late InMemoryDownloadRepository repository;
  late Directory directory;
  late ProviderContainer container;
  var notificationRequests = 0;

  ProviderContainer createContainer() {
    final created = ProviderContainer(
      overrides: [
        nativeServiceProvider.overrideWithValue(native),
        directDownloadServiceProvider.overrideWithValue(direct),
        galleryExportServiceProvider.overrideWithValue(gallery),
        cookieExportServiceProvider.overrideWithValue(FakeCookies()),
        downloadRepositoryProvider.overrideWithValue(repository),
        appPathsProvider.overrideWithValue(
          AppPaths(externalDirectory: () async => directory),
        ),
        notificationPermissionProvider.overrideWithValue(
          () async => notificationRequests++,
        ),
      ],
    );
    addTearDown(created.dispose);
    return created;
  }

  DownloadQueueController controller() =>
      container.read(downloadQueueControllerProvider.notifier);
  List<DownloadTask> tasks() => container.read(downloadQueueControllerProvider);
  DownloadTask task(String id) => tasks().firstWhere((t) => t.id == id);

  setUp(() async {
    native = FakeNative();
    direct = FakeDirect();
    gallery = FakeGallery();
    repository = InMemoryDownloadRepository();
    directory = await Directory.systemTemp.createTemp('savekit_queue');
    notificationRequests = 0;
    container = createContainer();
    // Keep the provider alive for the whole test.
    container.listen(downloadQueueControllerProvider, (_, _) {});
  });

  tearDown(() => directory.delete(recursive: true));

  test('starts a download with the cookies and download folder', () async {
    final id = controller().enqueue(info('a'), video);
    expect(task(id).status, DownloadStatus.queued);
    await settle();

    expect(native.started, [id]);
    expect(task(id).status, DownloadStatus.starting);
    expect(native.startArguments[id], {
      'url': 'https://example.com/a',
      'outputDir': '${directory.path}/downloads',
      'cookies': '/data/cookies.txt',
      'format': 'video_1080',
    });
    expect(notificationRequests, 1);
    expect(native.serviceCounts.last, 1);
    expect(repository.loadAll().single.status, DownloadStatus.starting);
  });

  test('follows progress to completion, exports and notifies', () async {
    final id = controller().enqueue(info('a'), video);
    await settle();

    native.events.add(
      DownloadProgress(
        taskId: id,
        status: DownloadStatus.downloading,
        progressPercent: 40,
        speed: '2.0MiB/s',
        eta: 9,
      ),
    );
    await settle();
    expect(task(id).progressPercent, 40);
    expect(task(id).speed, '2.0MiB/s');

    native.events.add(
      DownloadProgress(
        taskId: id,
        status: DownloadStatus.completed,
        filePaths: const ['/d/a.mp4'],
        fileSize: 123,
      ),
    );
    await settle();

    final done = task(id);
    expect(done.status, DownloadStatus.completed);
    expect(done.filePath, '/d/a.mp4');
    expect(done.savedToGallery, isTrue);
    expect(gallery.exported, [
      ['/d/a.mp4'],
    ]);
    expect(native.finishedNotifications, {id: true});
    expect(native.serviceCounts.last, 0);
    expect(repository.loadAll().single.savedToGallery, isTrue);
    expect(container.read(completedDownloadsProvider).single.id, id);
    expect(container.read(activeDownloadsProvider), isEmpty);
    expect(container.read(activeDownloadCountProvider), 0);
  });

  test('runs at most three at once and starts the next when one ends', () async {
    final ids = [
      for (var i = 0; i < 5; i++) controller().enqueue(info('v$i'), video),
    ];
    await settle();
    expect(native.started, ids.take(3));
    expect(task(ids[3]).status, DownloadStatus.queued);
    expect(notificationRequests, 1);

    native.events.add(
      DownloadProgress(taskId: ids[0], status: DownloadStatus.failed, error: 'boom'),
    );
    await settle();

    expect(task(ids[0]).status, DownloadStatus.failed);
    expect(task(ids[0]).error, 'boom');
    expect(native.finishedNotifications, {ids[0]: false});
    expect(native.started, ids.take(4));
    expect(gallery.exported, isEmpty);
  });

  test('a failed start fails the task', () async {
    native.startError = const EngineException('DOWNLOAD_FAILED', 'No space left');
    final id = controller().enqueue(info('a'), video);
    await settle();
    expect(task(id).status, DownloadStatus.failed);
    expect(task(id).error, 'No space left');
  });

  test('cancels a queued task without touching the engine', () async {
    final ids = [
      for (var i = 0; i < 4; i++) controller().enqueue(info('v$i'), video),
    ];
    await settle();
    await controller().cancel(ids[3]);
    expect(task(ids[3]).status, DownloadStatus.canceled);
    expect(native.canceled, isEmpty);
  });

  test('cancels a running task through the engine', () async {
    final id = controller().enqueue(info('a'), video);
    await settle();

    await controller().cancel(id);
    expect(native.canceled, [id]);
    // Still active until the engine confirms.
    expect(task(id).isActive, isTrue);

    native.events.add(DownloadProgress(taskId: id, status: DownloadStatus.canceled));
    await settle();
    expect(task(id).status, DownloadStatus.canceled);
    expect(native.finishedNotifications, isEmpty);
  });

  test('cancel finishes the task itself when no process was running', () async {
    native.cancelStopsProcess = false;
    final id = controller().enqueue(info('a'), video);
    await settle();
    await controller().cancel(id);
    expect(task(id).status, DownloadStatus.canceled);
  });

  test('retry queues a failed task again and clears its error', () async {
    final id = controller().enqueue(info('a'), video);
    await settle();
    native.events.add(
      DownloadProgress(taskId: id, status: DownloadStatus.failed, error: 'boom'),
    );
    await settle();

    controller().retry(id);
    expect(task(id).error, isNull);
    await settle();
    expect(native.started, [id, id]);
    expect(task(id).status, DownloadStatus.starting);
  });

  test('sends WebView-found photos to the direct downloader', () async {
    const photos = MediaFormat(
      id: 'gallery',
      kind: MediaFormatKind.gallery,
      label: 'Photos (2)',
      engine: DownloadEngineKind.direct,
      directUrls: ['https://cdn/a.jpg', 'https://cdn/b.jpg'],
    );
    final id = controller().enqueue(info('post', gallery: photos), photos);
    await settle();

    expect(native.started, isEmpty);
    expect(direct.started[id], ['https://cdn/a.jpg', 'https://cdn/b.jpg']);

    direct.events.add(
      DownloadProgress(
        taskId: id,
        status: DownloadStatus.completed,
        filePaths: const ['/d/1.jpg', '/d/2.jpg'],
      ),
    );
    await settle();
    expect(task(id).status, DownloadStatus.completed);
    expect(task(id).filePaths, hasLength(2));

    await controller().cancel(id);
    expect(direct.canceled, isEmpty);
  });

  test('remove deletes the task and its files', () async {
    final file = File('${directory.path}/a.mp4')..writeAsStringSync('x');
    final id = controller().enqueue(info('a'), video);
    await settle();
    native.events.add(
      DownloadProgress(
        taskId: id,
        status: DownloadStatus.completed,
        filePaths: [file.path],
      ),
    );
    await settle();

    await controller().remove(id);
    expect(tasks(), isEmpty);
    expect(repository.loadAll(), isEmpty);
    expect(file.existsSync(), isFalse);
  });

  test('clearFailed keeps active and completed tasks', () async {
    final a = controller().enqueue(info('a'), video);
    final b = controller().enqueue(info('b'), video);
    await settle();
    native.events.add(
      DownloadProgress(taskId: a, status: DownloadStatus.failed, error: 'x'),
    );
    await settle();

    await controller().clearFailed();
    expect(tasks().map((t) => t.id), [b]);
    expect(repository.loadAll().map((t) => t.id), [b]);
  });

  test('restores history and resumes interrupted downloads on launch', () async {
    final created = DateTime(2026, 1, 1);
    DownloadTask stored(String id, DownloadStatus status, int minutes) =>
        DownloadTask.create(
          id: id,
          info: info(id),
          format: video,
          now: created.add(Duration(minutes: minutes)),
        ).copyWith(status: status, progressPercent: 30);

    repository = InMemoryDownloadRepository([
      stored('done', DownloadStatus.completed, 0),
      stored('interrupted', DownloadStatus.downloading, 1),
      stored('failed', DownloadStatus.failed, 2),
    ]);
    container = createContainer();
    container.listen(downloadQueueControllerProvider, (_, _) {});

    // Newest first.
    expect(tasks().map((t) => t.id), ['failed', 'interrupted', 'done']);
    await settle();

    expect(native.started, ['interrupted']);
    expect(task('done').status, DownloadStatus.completed);
    expect(task('failed').status, DownloadStatus.failed);
  });

  test('a download still running from before keeps reporting', () async {
    repository = InMemoryDownloadRepository([
      DownloadTask.create(
        id: 'alive',
        info: info('alive'),
        format: video,
      ).copyWith(status: DownloadStatus.downloading),
    ]);
    native.startError = const EngineException(
      'DOWNLOAD_FAILED',
      'Task alive is already running.',
    );
    container = createContainer();
    container.listen(downloadQueueControllerProvider, (_, _) {});
    await settle();

    expect(task('alive').status, DownloadStatus.starting);
    native.events.add(
      const DownloadProgress(
        taskId: 'alive',
        status: DownloadStatus.downloading,
        progressPercent: 80,
      ),
    );
    await settle();
    expect(task('alive').progressPercent, 80);
  });
}
