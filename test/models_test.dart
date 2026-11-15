import 'package:flutter_test/flutter_test.dart';
import 'package:savekit/core/platform/media_platform.dart';
import 'package:savekit/features/downloader/domain/download_progress.dart';
import 'package:savekit/features/downloader/domain/download_task.dart';
import 'package:savekit/features/extractor/domain/media_format.dart';
import 'package:savekit/features/extractor/domain/media_info.dart';

/// Shaped like the map the Kotlin engine sends, including the loosely typed
/// nested maps a platform channel produces.
Map<String, dynamic> engineInfo() => {
  'id': 'abc',
  'url': 'https://www.tiktok.com/@u/video/1',
  'webpageUrl': 'https://www.tiktok.com/@u/video/1',
  'title': 'A clip',
  'uploader': 'someone',
  'thumbnail': 'https://img/1.jpg',
  'duration': 42,
  'platform': 'tiktok',
  'entryCount': 0,
  'videoOptions': <Object?>[
    <Object?, Object?>{
      'id': 'video_1080',
      'kind': 'video',
      'label': '1080p',
      'formatSelection': 'bv*+ba/b',
      'formatSort': 'res:1080,vcodec:h264,acodec:aac',
      'extractAudio': false,
      'audioFormat': null,
      'ext': 'mp4',
      'height': 1080,
      'fileSize': 1234567,
    },
  ],
  'noWatermarkOption': <Object?, Object?>{
    'id': 'no_watermark',
    'kind': 'noWatermark',
    'label': 'Best No-Watermark',
    'formatSelection': 'b',
    'formatSort': '',
    'extractAudio': false,
  },
  'audioOptions': <Object?>[
    <Object?, Object?>{
      'id': 'audio_mp3',
      'kind': 'audio',
      'label': 'MP3',
      'formatSelection': 'ba/b',
      'extractAudio': true,
      'audioFormat': 'mp3',
      'ext': 'mp3',
    },
  ],
  'galleryOption': <Object?, Object?>{
    'id': 'gallery',
    'kind': 'gallery',
    'label': 'Photos (2)',
    'engine': 'gallerydl',
    'formatSelection': 'gallery',
    'itemCount': 2,
    'imageCount': 2,
    'videoCount': 0,
  },
  'galleryItems': <Object?>[
    <Object?, Object?>{
      'url': 'https://img/a.jpg',
      'extension': 'jpg',
      'width': 1080,
      'height': 1350,
      'isVideo': false,
      'thumbnail': 'https://img/a.jpg',
    },
    <Object?, Object?>{
      'url': 'https://img/b.jpg',
      'extension': 'jpg',
      'isVideo': false,
    },
  ],
};

void main() {
  group('MediaInfo.fromMap', () {
    final info = MediaInfo.fromMap(engineInfo());

    test('reads metadata', () {
      expect(info.title, 'A clip');
      expect(info.platform, MediaPlatform.tiktok);
      expect(info.duration, 42);
      expect(info.uploader, 'someone');
    });

    test('reads every option group', () {
      expect(info.videoOptions.single.label, '1080p');
      expect(info.videoOptions.single.height, 1080);
      expect(info.videoOptions.single.engine, DownloadEngineKind.ytdlp);
      expect(info.noWatermarkOption!.kind, MediaFormatKind.noWatermark);
      expect(info.audioOptions.single.extractAudio, isTrue);
      expect(info.galleryOption!.engine, DownloadEngineKind.gallerydl);
      expect(info.galleryOption!.itemCount, 2);
      expect(info.galleryItems, hasLength(2));
      expect(info.galleryItems.first.width, 1080);
    });

    test('prefers the watermark-free stream by default', () {
      expect(info.defaultOption!.id, 'no_watermark');
      expect(info.allOptions.map((o) => o.id), [
        'no_watermark',
        'video_1080',
        'gallery',
        'audio_mp3',
      ]);
    });

    test('tolerates a sparse map', () {
      final sparse = MediaInfo.fromMap({
        'url': 'https://e.com',
        'galleryOption': null,
      });
      expect(sparse.title, 'Untitled');
      expect(sparse.platform, MediaPlatform.other);
      expect(sparse.allOptions, isEmpty);
      expect(sparse.defaultOption, isNull);
    });
  });

  group('DownloadProgress.fromMap', () {
    test('reads a completed event', () {
      final progress = DownloadProgress.fromMap(<Object?, Object?>{
        'taskId': 't1',
        'status': 'completed',
        'progressPercent': 100.0,
        'speed': '',
        'eta': 0,
        'filePath': '/d/a.mp4',
        'filePaths': <Object?>['/d/a.mp4'],
        'fileSize': 10,
      });
      expect(progress.status, DownloadStatus.completed);
      expect(progress.status.isTerminal, isTrue);
      expect(progress.filePaths, ['/d/a.mp4']);
      expect(progress.fileSize, 10);
    });

    test('accepts an integer percentage', () {
      final progress = DownloadProgress.fromMap(<Object?, Object?>{
        'taskId': 't1',
        'status': 'downloading',
        'progressPercent': 40,
        'speed': '1.0MiB/s',
        'eta': 12,
      });
      expect(progress.progressPercent, 40.0);
      expect(progress.status.isRunning, isTrue);
    });
  });

  group('DownloadTask', () {
    final info = MediaInfo.fromMap(engineInfo());
    final created = DateTime(2026, 1, 2, 3, 4, 5);
    DownloadTask newTask() => DownloadTask.create(
      id: 't1',
      info: info,
      format: info.galleryOption!,
      now: created,
    );

    test('starts queued with the media metadata', () {
      final task = newTask();
      expect(task.status, DownloadStatus.queued);
      expect(task.title, 'A clip');
      expect(task.isActive, isTrue);
      expect(task.filePath, isNull);
    });

    test('applies progress, completion and failure', () {
      final running = newTask().applyProgress(
        const DownloadProgress(
          taskId: 't1',
          status: DownloadStatus.downloading,
          progressPercent: 50,
          speed: '1/2 files',
        ),
      );
      expect(running.progressPercent, 50);
      expect(running.speed, '1/2 files');

      final done = running.applyProgress(
        const DownloadProgress(
          taskId: 't1',
          status: DownloadStatus.completed,
          filePaths: ['/d/a.jpg', '/d/b.jpg'],
          fileSize: 99,
        ),
        now: DateTime(2026, 1, 2, 4),
      );
      expect(done.status, DownloadStatus.completed);
      expect(done.progressPercent, 100);
      expect(done.filePath, '/d/a.jpg');
      expect(done.fileSize, 99);
      expect(done.completedAt, DateTime(2026, 1, 2, 4));
      expect(done.isActive, isFalse);

      final failed = running.applyProgress(
        const DownloadProgress(
          taskId: 't1',
          status: DownloadStatus.failed,
          error: 'Login required',
        ),
      );
      expect(failed.error, 'Login required');
      expect(failed.canRetry, isTrue);

      // Retrying clears the previous error.
      final retried = failed.applyProgress(
        const DownloadProgress(taskId: 't1', status: DownloadStatus.starting),
      );
      expect(retried.error, isNull);
    });

    test('keeps the trim and subtitle choices through persistence', () {
      final format = info.videoOptions.single.withExtras(
        clipStart: 10,
        clipEnd: 35,
        subtitleLanguage: 'ar',
        autoSubtitles: true,
        label: '1080p · 0:10–0:35',
      );
      final restored = DownloadTask.fromMap(
        Map<Object?, Object?>.from(
          DownloadTask.create(
            id: 't',
            info: info,
            format: format,
            now: created,
          ).toMap(),
        ),
      ).format;
      expect(restored.isClipped, isTrue);
      expect(restored.clipStart, 10);
      expect(restored.clipEnd, 35);
      expect(restored.subtitleLanguage, 'ar');
      expect(restored.autoSubtitles, isTrue);
      // A clip is smaller than the whole, so the old estimate is dropped.
      expect(restored.fileSize, isNull);
      expect(
        restored.formatSelection,
        info.videoOptions.single.formatSelection,
      );
    });

    test('survives a persistence round trip', () {
      final task = newTask()
          .applyProgress(
            const DownloadProgress(
              taskId: 't1',
              status: DownloadStatus.completed,
              filePaths: ['/d/a.jpg'],
              fileSize: 5,
            ),
            now: DateTime(2026, 1, 2, 4),
          )
          .copyWith(savedToGallery: true);
      final restored = DownloadTask.fromMap(
        Map<Object?, Object?>.from(task.toMap()),
      );
      expect(restored.toMap(), task.toMap());
      expect(restored.format.engine, DownloadEngineKind.gallerydl);
      expect(restored.createdAt, created);
      expect(restored.savedToGallery, isTrue);
    });
  });
}
