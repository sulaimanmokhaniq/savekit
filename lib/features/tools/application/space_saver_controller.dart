import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../../../core/native/youtube_dl_native_service.dart';
import '../../../core/platform/media_platform.dart';
import '../../../core/providers.dart';
import '../../downloader/application/download_queue_controller.dart';
import '../../downloader/domain/download_progress.dart';
import '../../extractor/domain/media_format.dart';
import '../../extractor/domain/media_info.dart';

/// One photo or video on the phone (not only SaveKit's own).
class PhoneMedia {
  const PhoneMedia({
    required this.uri,
    required this.name,
    required this.size,
    required this.date,
    this.path,
    this.width = 0,
    this.height = 0,
    this.duration = Duration.zero,
    this.isVideo = false,
  });

  /// Android's address of the file; what deleting and previews use.
  final String uri;

  /// Where the file can be read directly, when Android says.
  final String? path;
  final String name;
  final int size;
  final DateTime date;
  final int width;
  final int height;
  final Duration duration;
  final bool isVideo;

  /// The picture's shorter side, in pixels; 0 when unknown.
  int get shortSide => width < height ? width : height;

  factory PhoneMedia.fromMap(Map<Object?, Object?> map) => PhoneMedia(
    uri: map['uri'] as String? ?? '',
    path: map['path'] as String?,
    name: map['name'] as String? ?? '',
    size: (map['size'] as num?)?.toInt() ?? 0,
    date: DateTime.fromMillisecondsSinceEpoch(
      (map['date'] as num?)?.toInt() ?? 0,
    ),
    width: (map['width'] as num?)?.toInt() ?? 0,
    height: (map['height'] as num?)?.toInt() ?? 0,
    duration: Duration(milliseconds: (map['durationMs'] as num?)?.toInt() ?? 0),
    isVideo: map['isVideo'] as bool? ?? false,
  );
}

/// What a scan of the phone found.
class SpaceScan {
  const SpaceScan({
    this.items = const [],
    this.duplicates = const [],
    this.similar = const [],
  });

  /// Every photo and video.
  final List<PhoneMedia> items;

  /// Groups of identical files; the first of each is the one to keep.
  final List<List<PhoneMedia>> duplicates;

  /// Groups of photos that look alike; the first of each is the best one.
  final List<List<PhoneMedia>> similar;

  /// Space taken by the extra copies.
  int get duplicateBytes => _extraBytes(duplicates);

  /// Space taken by all but the best of each look-alike group.
  int get similarBytes => _extraBytes(similar);

  static int _extraBytes(List<List<PhoneMedia>> groups) => groups.fold(
    0,
    (sum, group) => sum + group.skip(1).fold(0, (s, item) => s + item.size),
  );

  /// The scan without the files at [uris], after they were deleted.
  SpaceScan without(Set<String> uris) {
    List<List<PhoneMedia>> prune(List<List<PhoneMedia>> groups) => [
      for (final group in groups)
        if (group.where((item) => !uris.contains(item.uri)).length > 1)
          [
            for (final item in group)
              if (!uris.contains(item.uri)) item,
          ],
    ];
    return SpaceScan(
      items: [
        for (final item in items)
          if (!uris.contains(item.uri)) item,
      ],
      duplicates: prune(duplicates),
      similar: prune(similar),
    );
  }
}

/// How hard to squeeze a video.
enum CompressQuality {
  /// Full HD at most; hard to tell from the original on a phone.
  good('good', 1080),

  /// HD at most; clearly smaller files, a little softer.
  small('small', 720);

  const CompressQuality(this.id, this.maxShortSide);

  final String id;
  final int maxShortSide;
}

/// What re-encoding one video would do.
class CompressPlan {
  const CompressPlan({required this.targetBytes, this.shortSide});

  /// About how large the new file will be.
  final int targetBytes;

  /// The new shorter side when the picture is made smaller; null to keep it.
  final int? shortSide;
}

/// Videos smaller than this are not worth re-encoding.
const _minCompressBytes = 20 * 1024 * 1024;

/// A plan is only offered when it frees at least this share of the file.
const _minSaving = 0.3;

const _audioKbps = 96;

/// Video bitrate, in kbps, for a picture whose shorter side is [shortSide].
int _videoKbps(int shortSide, CompressQuality quality) {
  final good = quality == CompressQuality.good;
  if (shortSide > 720) return good ? 5000 : 3200;
  if (shortSide > 480) return good ? 3000 : 2200;
  return good ? 1500 : 1100;
}

/// The plan for [video] at [quality], or null when it would save too little.
CompressPlan? compressPlanFor(PhoneMedia video, CompressQuality quality) {
  final seconds = video.duration.inMilliseconds / 1000;
  if (!video.isVideo || seconds < 1 || video.size < _minCompressBytes) {
    return null;
  }
  // An unknown size is treated as Full HD.
  final current = video.shortSide > 0 ? video.shortSide : 1080;
  final shrink = current > quality.maxShortSide;
  final outputSide = shrink ? quality.maxShortSide : current;
  final target =
      ((_videoKbps(outputSide, quality) + _audioKbps) * 1000 / 8 * seconds)
          .round();
  if (target > video.size * (1 - _minSaving)) return null;
  return CompressPlan(
    targetBytes: target,
    shortSide: shrink ? outputSide : null,
  );
}

/// How far a running scan has got.
class ScanProgress {
  const ScanProgress({this.stage = 'listing', this.done = 0, this.total = 0});

  /// `listing`, `duplicates` or `similar`.
  final String stage;
  final int done;
  final int total;

  double? get fraction => total <= 0 ? null : (done / total).clamp(0, 1);
}

/// The phone's photos and videos, through Android.
class SpaceService {
  SpaceService({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel(YoutubeDlNativeService.engineChannel);

  final MethodChannel _channel;

  /// Asks for access to photos and videos. True when the scan can read them.
  Future<bool> requestAccess() async {
    try {
      final answers = await [
        Permission.photos,
        Permission.videos,
        Permission.storage,
      ].request();
      bool ok(Permission permission) {
        final status = answers[permission];
        return status == PermissionStatus.granted ||
            status == PermissionStatus.limited;
      }

      // Android 13+ has the first two; older versions the third.
      return (ok(Permission.photos) && ok(Permission.videos)) ||
          ok(Permission.storage);
    } catch (_) {
      return false;
    }
  }

  Future<SpaceScan> scan() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('scanSpace');
    final items = [
      for (final item in (result?['items'] as List?) ?? const [])
        PhoneMedia.fromMap(item as Map),
    ];
    final byUri = {for (final item in items) item.uri: item};
    List<List<PhoneMedia>> groups(Object? raw) => [
      for (final group in (raw as List?) ?? const [])
        [
          for (final uri in group as List)
            if (byUri[uri] != null) byUri[uri]!,
        ],
    ].where((group) => group.length > 1).toList();
    return SpaceScan(
      items: items,
      duplicates: groups(result?['duplicates']),
      similar: groups(result?['similar']),
    );
  }

  Future<ScanProgress> progress() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'spaceScanProgress',
    );
    return ScanProgress(
      stage: result?['stage'] as String? ?? 'listing',
      done: (result?['done'] as num?)?.toInt() ?? 0,
      total: (result?['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> cancel() => _channel.invokeMethod<void>('cancelSpaceScan');

  /// JPEG preview of a photo or video, or null when none can be made.
  Future<Uint8List?> preview(String uri, {int size = 256}) async {
    try {
      return await _channel.invokeMethod<Uint8List>('mediaPreview', {
        'uri': uri,
        'size': size,
      });
    } catch (_) {
      return null;
    }
  }
}

final spaceServiceProvider = Provider<SpaceService>((ref) => SpaceService());

enum SpacePhase { intro, scanning, done, denied, failed }

class SpaceState {
  const SpaceState({
    this.phase = SpacePhase.intro,
    this.progress = const ScanProgress(),
    this.scan = const SpaceScan(),
    this.error,
  });

  final SpacePhase phase;
  final ScanProgress progress;
  final SpaceScan scan;
  final String? error;
}

/// A video that has been re-encoded and whose original can now go.
class ReadyOriginal {
  const ReadyOriginal({required this.original, required this.newBytes});

  final PhoneMedia original;

  /// Size of the smaller copy that replaces it.
  final int newBytes;

  int get savedBytes => original.size - newBytes;
}

/// Finds space to free on the phone and frees it: deleting copies and
/// look-alikes, and re-encoding large videos.
class SpaceSaverController extends Notifier<SpaceState> {
  Timer? _poll;

  @override
  SpaceState build() {
    ref.onDispose(() => _poll?.cancel());
    return const SpaceState();
  }

  SpaceService get _service => ref.read(spaceServiceProvider);

  /// Asks for access if needed, then scans the phone.
  Future<void> start() async {
    if (state.phase == SpacePhase.scanning) return;
    if (!await _service.requestAccess()) {
      if (ref.mounted) state = const SpaceState(phase: SpacePhase.denied);
      return;
    }
    if (!ref.mounted) return;
    state = const SpaceState(phase: SpacePhase.scanning);
    _poll = Timer.periodic(const Duration(milliseconds: 400), (_) async {
      try {
        final progress = await _service.progress();
        if (ref.mounted && state.phase == SpacePhase.scanning) {
          state = SpaceState(phase: SpacePhase.scanning, progress: progress);
        }
      } catch (_) {
        // The bar simply stays where it was.
      }
    });
    try {
      final scan = await _service.scan();
      if (ref.mounted) state = SpaceState(phase: SpacePhase.done, scan: scan);
    } on PlatformException catch (error) {
      if (!ref.mounted) return;
      state = error.code == 'SCAN_DENIED'
          ? const SpaceState(phase: SpacePhase.denied)
          : SpaceState(phase: SpacePhase.failed, error: error.message);
    } catch (error) {
      if (ref.mounted) {
        state = SpaceState(phase: SpacePhase.failed, error: '$error');
      }
    } finally {
      _poll?.cancel();
    }
  }

  /// Stops a running scan; what it found so far is shown.
  Future<void> cancel() async {
    try {
      await _service.cancel();
    } catch (_) {
      // Nothing to stop.
    }
  }

  /// Deletes the files at [uris] from the phone for good. Android may ask
  /// the user to confirm. Returns whether they are gone.
  Future<bool> delete(Set<String> uris) async {
    if (uris.isEmpty) return true;
    final bool deleted;
    try {
      deleted = await ref
          .read(nativeServiceProvider)
          .deleteFromMediaStore(locations: uris.toList(), names: const []);
    } catch (_) {
      return false;
    }
    if (deleted && ref.mounted) {
      state = SpaceState(phase: state.phase, scan: state.scan.without(uris));
    }
    return deleted;
  }

  /// Queues re-encoding of [videos]. The originals stay until the user
  /// deletes them from [readyOriginals], once the smaller copies exist.
  int compress(List<PhoneMedia> videos, CompressQuality quality) {
    final queue = ref.read(downloadQueueControllerProvider.notifier);
    final alreadyQueued = {
      for (final task in ref.read(downloadQueueControllerProvider))
        if (task.status != DownloadStatus.failed &&
            task.status != DownloadStatus.canceled)
          ?task.format.options[replacesOption],
    };
    var queued = 0;
    for (final video in videos) {
      final path = video.path;
      final plan = compressPlanFor(video, quality);
      if (path == null || plan == null || alreadyQueued.contains(video.uri)) {
        continue;
      }
      queue.enqueue(
        MediaInfo(
          url: path,
          title: p.basenameWithoutExtension(video.name),
          platform: MediaPlatform.device,
        ),
        MediaFormat(
          id: 'edit_compress',
          kind: MediaFormatKind.video,
          label: 'Smaller copy',
          engine: DownloadEngineKind.edit,
          formatSelection: 'compress',
          options: {
            'targetMb': (plan.targetBytes / (1024 * 1024)).toStringAsFixed(1),
            'duration': (video.duration.inMilliseconds / 1000).toStringAsFixed(
              2,
            ),
            if (plan.shortSide != null) 'shortSide': '${plan.shortSide}',
            replacesOption: video.uri,
          },
        ),
      );
      queued++;
    }
    return queued;
  }

  /// The option that marks a queued edit as the smaller copy of a phone
  /// video; its value is that video's address.
  static const replacesOption = 'replaces';
}

final spaceSaverProvider = NotifierProvider<SpaceSaverController, SpaceState>(
  SpaceSaverController.new,
);

/// Addresses of phone videos whose smaller copy is still being made.
final compressingUrisProvider = Provider<Set<String>>((ref) {
  return {
    for (final task in ref.watch(downloadQueueControllerProvider))
      if (task.status != DownloadStatus.completed &&
          task.status != DownloadStatus.failed &&
          task.status != DownloadStatus.canceled)
        ?task.format.options[SpaceSaverController.replacesOption],
  };
});

/// Originals that can be deleted now: their smaller copy is finished, is on
/// the phone, and really is smaller.
final readyOriginalsProvider = Provider<List<ReadyOriginal>>((ref) {
  final scan = ref.watch(spaceSaverProvider).scan;
  if (scan.items.isEmpty) return const [];
  final byUri = {for (final item in scan.items) item.uri: item};
  final ready = <ReadyOriginal>[];
  final seen = <String>{};
  for (final task in ref.watch(downloadQueueControllerProvider)) {
    if (task.status != DownloadStatus.completed) continue;
    final uri = task.format.options[SpaceSaverController.replacesOption];
    final original = uri == null ? null : byUri[uri];
    if (original == null || task.filePaths.isEmpty || !seen.add(original.uri)) {
      continue;
    }
    var newBytes = 0;
    try {
      newBytes = File(task.filePaths.first).lengthSync();
    } catch (_) {
      // The copy is gone; the original must stay.
    }
    if (newBytes > 0 && newBytes < original.size) {
      ready.add(ReadyOriginal(original: original, newBytes: newBytes));
    }
  }
  return ready;
});
