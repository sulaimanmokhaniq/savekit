import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:savekit/core/engine/engine_controller.dart';
import 'package:savekit/core/platform/media_platform.dart';
import 'package:savekit/core/providers.dart';
import 'package:savekit/core/settings/app_settings.dart';
import 'package:savekit/core/storage/app_paths.dart';
import 'package:savekit/core/theme/app_palette.dart';
import 'package:savekit/features/downloader/application/download_queue_controller.dart';
import 'package:savekit/features/downloader/data/download_repository.dart';
import 'package:savekit/features/downloader/domain/download_progress.dart';
import 'package:savekit/features/downloader/domain/download_task.dart';
import 'package:savekit/features/extractor/application/batch_controller.dart';
import 'package:savekit/features/extractor/data/media_extractor.dart';
import 'package:savekit/features/extractor/domain/media_format.dart';
import 'package:savekit/features/extractor/domain/media_info.dart';
import 'package:savekit/features/extractor/domain/quality_selection.dart';
import 'package:savekit/features/tools/application/storage_controller.dart';

import 'support/fakes.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

/// Answers each link from a table; unknown links fail.
class TableExtractor implements MediaExtractor {
  final results = <String, Object>{};
  final fetched = <String>[];
  Completer<void>? gate;

  @override
  Future<MediaInfo> fetch(String url) async {
    fetched.add(url);
    await gate?.future;
    final result = results[url];
    if (result is MediaInfo) return result;
    throw result ?? const MediaExtractionException('Unsupported link');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaInfo video(String url, {List<int> heights = const [2160, 1080, 720]}) =>
    MediaInfo(
      url: url,
      title: url,
      platform: MediaPlatform.youtube,
      videoOptions: [for (final h in heights) videoFormat(h)],
      audioOptions: const [mp3Format, m4aFormat],
    );

void main() {
  group('link parsing', () {
    test('finds every distinct link in pasted text', () {
      expect(
        extractAllUrls(
          'https://youtu.be/a\nand https://youtu.be/b, https://youtu.be/a',
        ),
        ['https://youtu.be/a', 'https://youtu.be/b'],
      );
      expect(extractAllUrls('nothing'), isEmpty);
    });

    test('recognises account pages but not single posts', () {
      const accounts = [
        'https://www.youtube.com/@harbour',
        'https://www.youtube.com/@harbour/videos',
        'https://www.youtube.com/channel/UC123',
        'https://x.com/harbour',
        'https://twitter.com/harbour/media',
        'https://www.instagram.com/harbour/',
        'https://www.tiktok.com/@harbour',
        'https://www.snapchat.com/add/harbour',
      ];
      const posts = [
        'https://www.youtube.com/watch?v=abc',
        'https://youtu.be/abc',
        'https://x.com/harbour/status/1',
        'https://x.com/home',
        'https://www.instagram.com/p/abc/',
        'https://www.instagram.com/reel/abc/',
        'https://www.tiktok.com/@harbour/video/1',
        'https://www.snapchat.com/spotlight/abc',
        'https://example.com/harbour',
      ];
      for (final url in accounts) {
        expect(isAccountUrl(url), isTrue, reason: url);
      }
      for (final url in posts) {
        expect(isAccountUrl(url), isFalse, reason: url);
      }
      expect(
        accountMediaUrl('https://x.com/harbour'),
        'https://x.com/harbour/media',
      );
      expect(
        accountMediaUrl('https://www.instagram.com/harbour/'),
        'https://www.instagram.com/harbour/',
      );
    });

    test('recognises playlist pages but not a video inside a playlist', () {
      expect(
        isPlaylistUrl('https://www.youtube.com/playlist?list=PL123'),
        isTrue,
      );
      expect(
        isPlaylistUrl('https://www.youtube.com/watch?v=a&list=PL123'),
        isFalse,
      );
      expect(isPlaylistUrl('https://www.youtube.com/playlist'), isFalse);
      expect(isPlaylistUrl('https://example.com/playlist?list=1'), isFalse);
    });
  });

  group('pickPreferredFormat', () {
    final info = video('u');

    test('takes the best quality within the limit', () {
      expect(pickPreferredFormat(info, QualityPreference.best)!.height, 2160);
      expect(pickPreferredFormat(info, QualityPreference.p1080)!.height, 1080);
      expect(pickPreferredFormat(info, QualityPreference.p480)!.height, 720);
      expect(
        pickPreferredFormat(
          video('u', heights: [720, 360]),
          QualityPreference.p480,
        )!.height,
        360,
      );
    });

    test('picks the requested audio format', () {
      expect(
        pickPreferredFormat(info, QualityPreference.mp3)!.audioFormat,
        'mp3',
      );
      expect(
        pickPreferredFormat(info, QualityPreference.m4a)!.audioFormat,
        'm4a',
      );
    });

    test('prefers the clean stream and falls back to photos', () {
      expect(
        pickPreferredFormat(sampleInfo(), QualityPreference.p720)!.id,
        'no_watermark',
      );
      const photos = MediaInfo(
        url: 'u',
        title: 't',
        platform: MediaPlatform.instagram,
        galleryOption: photosFormat,
      );
      expect(
        pickPreferredFormat(photos, QualityPreference.p1080),
        same(photosFormat),
      );
      expect(pickPreferredFormat(photos, QualityPreference.mp3), isNull);
    });

    test('"ask" never picks', () {
      expect(pickPreferredFormat(info, QualityPreference.ask), isNull);
    });
  });

  group('settings', () {
    test('survive a round trip and clamp bad values', () {
      const settings = AppSettings(
        themeId: 'tide',
        oneTap: QualityPreference.p720,
        wifiOnly: true,
        maxConcurrent: 5,
        lockVault: true,
        vaultSort: VaultSort.largest,
        vaultGrid: false,
      );
      final restored = AppSettings.fromMap(settings.toMap());
      expect(restored.toMap(), settings.toMap());
      expect(AppSettings.fromMap(const {'maxConcurrent': 99}).maxConcurrent, 5);
      expect(AppSettings.fromMap(const {}).themeId, 'ember');
    });

    test('the controller saves every change', () {
      final repository = InMemorySettingsRepository();
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      container.read(settingsControllerProvider.notifier)
        ..setTheme('pulse')
        ..setWifiOnly(true)
        ..setMaxConcurrent(1);
      expect(repository.load().themeId, 'pulse');
      expect(repository.load().wifiOnly, isTrue);
      expect(repository.load().maxConcurrent, 1);
    });

    test('the icon colour follows the theme only when set to match', () {
      const matching = AppSettings(themeId: 'tide');
      expect(matching.launcherIconId, 'tide');
      expect(matching.copyWith(iconId: 'gold').launcherIconId, 'gold');
      // Settings saved by the version that had a "match" switch.
      expect(AppSettings.fromMap(const {'matchIcon': false}).iconId, 'ember');
      expect(
        AppSettings.fromMap(const {'matchIcon': true}).iconId,
        AppSettings.iconMatchesTheme,
      );
      expect(AppPalette.all.map((p) => p.id), containsAll(['rose', 'gold']));
    });

    test('every theme has a unique id and an unknown id falls back', () {
      final ids = AppPalette.all.map((p) => p.id).toSet();
      expect(ids, hasLength(AppPalette.all.length));
      expect(AppPalette.byId('nope'), AppPalette.fallback);
      expect(AppPalette.byId('tide').name, 'Tide');
    });
  });

  group('automatic engine updates', () {
    final now = DateTime(2026, 11, 15, 9);

    Future<(UiFakeNative, ProviderContainer)> start(
      AppSettings settings,
    ) async {
      final native = UiFakeNative();
      final container = ProviderContainer(
        overrides: [
          ...uiOverrides(
            native: native,
            settings: settings,
            allowAutoUpdate: true,
          ),
          clockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);
      container.listen(engineControllerProvider, (_, _) {});
      await container.read(engineControllerProvider.future);
      await settle();
      return (native, container);
    }

    test('run when the extractors were never updated', () async {
      final (native, container) = await start(const AppSettings());
      expect(native.updates, 1);
      expect(container.read(settingsControllerProvider).lastEngineUpdate, now);
      // It installed something, so it says so.
      expect(
        container.read(engineControllerProvider).value!.lastUpdateMessage,
        'Updated automatically: yt-dlp 2026.11.14.',
      );
    });

    test('run again after a week, but not before', () async {
      final (fresh, _) = await start(
        AppSettings(lastEngineUpdate: now.subtract(const Duration(days: 6))),
      );
      expect(fresh.updates, 0);

      final (stale, _) = await start(
        AppSettings(lastEngineUpdate: now.subtract(const Duration(days: 8))),
      );
      expect(stale.updates, 1);
    });

    test('can be turned off', () async {
      final (native, _) = await start(const AppSettings(autoUpdate: false));
      expect(native.updates, 0);
    });
  });

  group('queue controls', () {
    late UiFakeNative native;
    late FakeConnectivity connectivity;
    late InMemoryDownloadRepository repository;
    late ProviderContainer container;
    late Directory directory;
    late UiFakeGallery gallery;

    ProviderContainer create(
      AppSettings settings, {
      TableExtractor? extractor,
    }) {
      final created = ProviderContainer(
        overrides: uiOverrides(
          native: native,
          settings: settings,
          connectivity: connectivity,
          extractor: extractor,
          repository: repository,
          gallery: gallery,
          paths: AppPaths(externalDirectory: () async => directory),
        ),
      );
      addTearDown(created.dispose);
      created.listen(downloadQueueControllerProvider, (_, _) {});
      return created;
    }

    DownloadQueueController queue() =>
        container.read(downloadQueueControllerProvider.notifier);
    DownloadTask task(String id) => container
        .read(downloadQueueControllerProvider)
        .firstWhere((t) => t.id == id);

    setUp(() async {
      native = UiFakeNative()..cancelStops = true;
      connectivity = FakeConnectivity();
      gallery = UiFakeGallery();
      repository = InMemoryDownloadRepository();
      directory = await Directory.systemTemp.createTemp('savekit_controls');
    });
    tearDown(() => directory.delete(recursive: true));

    test('respects the "downloads at once" setting', () async {
      container = create(const AppSettings(maxConcurrent: 1));
      await settle();
      final a = queue().enqueue(video('a'), videoFormat(720));
      final b = queue().enqueue(video('b'), videoFormat(720));
      await settle();
      expect(native.started, [a]);

      container.read(settingsControllerProvider.notifier).setMaxConcurrent(2);
      await settle();
      expect(native.started, [a, b]);
    });

    test('pause keeps the task for later and resume restarts it', () async {
      container = create(const AppSettings());
      await settle();
      final id = queue().enqueue(video('a'), videoFormat(720));
      await settle();
      native.events.add(
        DownloadProgress(
          taskId: id,
          status: DownloadStatus.downloading,
          progressPercent: 40,
        ),
      );
      await settle();

      await queue().pause(id);
      expect(task(id).status, DownloadStatus.paused);
      expect(task(id).progressPercent, 40);
      expect(native.canceled, [id]);
      expect(container.read(activeDownloadCountProvider), 0);

      // Not restarted until the stopped process has reported in.
      queue().resume(id);
      await settle();
      expect(native.started, [id]);
      native.events.add(
        DownloadProgress(taskId: id, status: DownloadStatus.canceled),
      );
      await settle();
      expect(native.started, [id, id]);
      expect(task(id).status, DownloadStatus.starting);
    });

    test('a paused task ignores late progress and can be canceled', () async {
      container = create(const AppSettings());
      await settle();
      final id = queue().enqueue(video('a'), videoFormat(720));
      await settle();
      await queue().pause(id);
      native.events
        ..add(
          DownloadProgress(
            taskId: id,
            status: DownloadStatus.downloading,
            progressPercent: 90,
          ),
        )
        ..add(DownloadProgress(taskId: id, status: DownloadStatus.canceled));
      await settle();
      expect(task(id).status, DownloadStatus.paused);

      await queue().cancel(id);
      expect(task(id).status, DownloadStatus.canceled);
    });

    test(
      'Wi-Fi only holds downloads on mobile data and releases them on Wi-Fi',
      () async {
        connectivity.onWifi = false;
        container = create(const AppSettings(wifiOnly: true));
        await settle();
        final id = queue().enqueue(video('a'), videoFormat(720));
        await settle();
        expect(native.started, isEmpty);
        expect(container.read(waitingForWifiProvider), isTrue);

        connectivity.setWifi(true);
        await settle();
        expect(native.started, [id]);
        expect(container.read(waitingForWifiProvider), isFalse);

        // Losing Wi-Fi mid-download sends it back to waiting.
        connectivity.setWifi(false);
        await settle();
        expect(native.canceled, [id]);
        expect(task(id).status, DownloadStatus.queued);
      },
    );

    test('conversions run without Wi-Fi', () async {
      connectivity.onWifi = false;
      container = create(const AppSettings(wifiOnly: true));
      await settle();
      const convert = MediaFormat(
        id: 'convert_mp3',
        kind: MediaFormatKind.audio,
        label: 'MP3',
        engine: DownloadEngineKind.convert,
        audioFormat: 'mp3',
      );
      final id = queue().enqueue(
        const MediaInfo(
          url: '/sdcard/clip.mp4',
          title: 'clip',
          platform: MediaPlatform.device,
        ),
        convert,
      );
      await settle();
      expect(native.started, [id]);
    });

    test(
      'deleteFiles trims a download and drops it when nothing is left',
      () async {
        final one = File('${directory.path}/1.jpg')..writeAsStringSync('aaaa');
        final two = File('${directory.path}/2.jpg')..writeAsStringSync('bb');
        container = create(const AppSettings());
        await settle();
        await queue().addCompleted(
          title: 'Statuses',
          platform: MediaPlatform.whatsapp,
          format: photosFormat,
          filePaths: [one.path, two.path],
        );
        final id = container.read(downloadQueueControllerProvider).single.id;
        expect(task(id).fileSize, 6);
        expect(task(id).status, DownloadStatus.completed);

        var storage = await container.read(storageSnapshotProvider.future);
        expect(storage.files.map((f) => f.size), unorderedEquals([4, 2]));
        expect(storage.totalBytes, 6);

        expect(await queue().deleteFiles({one.path}), isTrue);
        expect(one.existsSync(), isFalse);
        // Only that file's gallery copy is removed.
        expect(gallery.deleted.single.$1, ['content://media/1.jpg']);
        expect(task(id).exported.keys, [two.path]);
        expect(task(id).filePaths, [two.path]);
        expect(task(id).fileSize, 2);

        await queue().deleteFiles({two.path});
        expect(container.read(downloadQueueControllerProvider), isEmpty);
        expect(repository.loadAll(), isEmpty);
        storage = await container.read(storageSnapshotProvider.future);
        expect(storage.totalBytes, 0);
      },
    );

    test(
      'gallery mode keeps one copy: the gallery file replaces ours',
      () async {
        final galleryFolder = Directory('${directory.path}/Pictures')
          ..createSync();
        gallery.galleryFolder = galleryFolder;
        container = create(const AppSettings());
        await settle();
        final id = queue().enqueue(video('a'), videoFormat(720));
        await settle();
        final ours = File('${directory.path}/clip.mp4')
          ..writeAsStringSync('video');
        native.events.add(
          DownloadProgress(
            taskId: id,
            status: DownloadStatus.completed,
            filePaths: [ours.path],
            fileSize: 5,
          ),
        );
        await settle();

        // Our copy is gone; the task now points at the gallery file.
        final galleryPath = '${galleryFolder.path}/clip.mp4';
        expect(ours.existsSync(), isFalse);
        expect(File(galleryPath).readAsStringSync(), 'video');
        expect(task(id).filePaths, [galleryPath]);
        expect(task(id).exported, {galleryPath: 'content://media/clip.mp4'});

        // Deleting the download deletes that one remaining copy.
        await queue().removeAll([id]);
        expect(gallery.deleted.single.$1, ['content://media/clip.mp4']);
      },
    );

    test('our copy is kept when the gallery copy cannot be read', () async {
      // The fake reports no file path, as Android sometimes does.
      container = create(const AppSettings());
      await settle();
      final id = queue().enqueue(video('a'), videoFormat(720));
      await settle();
      final ours = File('${directory.path}/clip.mp4')
        ..writeAsStringSync('video');
      native.events.add(
        DownloadProgress(
          taskId: id,
          status: DownloadStatus.completed,
          filePaths: [ours.path],
        ),
      );
      await settle();
      expect(ours.existsSync(), isTrue);
      expect(task(id).filePaths, [ours.path]);
      expect(task(id).savedToGallery, isTrue);
    });

    test('private mode keeps downloads out of the gallery', () async {
      container = create(const AppSettings(saveLocation: SaveLocation.private));
      await settle();
      final id = queue().enqueue(video('a'), videoFormat(720));
      await settle();
      final ours = File('${directory.path}/clip.mp4')
        ..writeAsStringSync('video');
      native.events.add(
        DownloadProgress(
          taskId: id,
          status: DownloadStatus.completed,
          filePaths: [ours.path],
        ),
      );
      await settle();
      expect(gallery.exportedPaths, isEmpty);
      expect(ours.existsSync(), isTrue);
      expect(task(id).savedToGallery, isFalse);

      await queue().removeAll([id]);
      expect(ours.existsSync(), isFalse);
      // Nothing to remove from the gallery.
      expect(gallery.deleted.single.$1, isEmpty);
      expect(gallery.deleted.single.$2, isEmpty);
    });

    test(
      'downloads exported by older versions are found by file name',
      () async {
        final file = File('${directory.path}/old.mp4')..writeAsStringSync('x');
        repository = InMemoryDownloadRepository([
          storedTask(
            'old',
            'Old video',
            MediaPlatform.youtube,
            videoFormat(720),
            DownloadStatus.completed,
            files: [file.path],
          ),
        ]);
        container = create(const AppSettings());
        await settle();

        await queue().removeAll(['old']);
        expect(file.existsSync(), isFalse);
        expect(gallery.deleted.single.$1, isEmpty);
        expect(gallery.deleted.single.$2, ['old.mp4']);
      },
    );

    test('reports when Android keeps a gallery copy', () async {
      final file = File('${directory.path}/a.jpg')..writeAsStringSync('x');
      container = create(const AppSettings());
      await settle();
      await queue().addCompleted(
        title: 'Photo',
        platform: MediaPlatform.whatsapp,
        format: photosFormat,
        filePaths: [file.path],
      );
      gallery.deleteSucceeds = false;
      final id = container.read(downloadQueueControllerProvider).single.id;
      expect(await queue().removeAll([id]), isFalse);
      // SaveKit's own copy is still gone.
      expect(file.existsSync(), isFalse);
    });

    test('storage reports abandoned partial files as leftovers', () async {
      container = create(const AppSettings());
      await settle();
      Directory('${directory.path}/downloads').createSync();
      File('${directory.path}/downloads/video.mp4.part')
          .writeAsStringSync('12345');
      final storage = await container.read(storageSnapshotProvider.future);
      expect(storage.leftoverBytes, 5);
      expect(storage.files, isEmpty);
    });

    test(
      'a batch queues each link at the chosen quality and keeps failures',
      () async {
        final extractor = TableExtractor()
          ..results['https://a'] = video('https://a')
          ..results['https://b'] = const MediaExtractionException(
            'Private video',
          )
          ..results['https://c'] = video('https://c');
        container = create(const AppSettings(), extractor: extractor);
        await settle();

        await container.read(batchControllerProvider.notifier).start([
          'https://a',
          'https://b',
          'https://c',
        ], QualityPreference.p1080);
        await settle();

        final batch = container.read(batchControllerProvider);
        expect(batch.running, isFalse);
        expect(batch.total, 3);
        expect(batch.queued, 2);
        expect(batch.failures.single.url, 'https://b');
        expect(batch.failures.single.message, 'Private video');
        final tasks = container.read(downloadQueueControllerProvider);
        expect(tasks.map((t) => t.format.height), [1080, 1080]);

        container.read(batchControllerProvider.notifier)
          ..removeFailure('https://b')
          ..dismiss();
        expect(container.read(batchControllerProvider).isEmpty, isTrue);
      },
    );

    test('a batch can be stopped part-way', () async {
      final extractor = TableExtractor()
        ..results['https://a'] = video('https://a')
        ..results['https://b'] = video('https://b')
        ..gate = Completer<void>();
      container = create(const AppSettings(), extractor: extractor);
      await settle();

      final run = container.read(batchControllerProvider.notifier).start([
        'https://a',
        'https://b',
      ], QualityPreference.best);
      await settle();
      container.read(batchControllerProvider.notifier).cancel();
      extractor.gate!.complete();
      await run;
      await settle();

      expect(extractor.fetched, ['https://a']);
      expect(container.read(batchControllerProvider).running, isFalse);
      expect(container.read(downloadQueueControllerProvider), isEmpty);
    });
  });
}
