import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../downloader/application/download_queue_controller.dart';
import '../downloader/data/gallery_export_service.dart';
import '../downloader/domain/download_task.dart';

/// One playable audio file from the Vault.
class Track {
  const Track({required this.path, required this.title, this.artist});

  final String path;
  final String title;
  final String? artist;
}

/// Every audio file in the Vault, newest first.
final audioTracksProvider = Provider<List<Track>>((ref) {
  final tasks = ref.watch(completedDownloadsProvider);
  return [
    for (final DownloadTask task in tasks)
      for (final path in task.filePaths)
        if (savedFileKindOf(path) == SavedFileKind.audio)
          Track(path: path, title: task.title, artist: task.uploader),
  ];
});

/// Where each file was left off, so long lectures resume where you stopped.
abstract interface class PositionStore {
  Duration? get(String path);
  Future<void> put(String path, Duration position);
}

class HivePositionStore implements PositionStore {
  HivePositionStore(this._box);

  static const boxName = 'playback';
  final Box<int> _box;

  /// Call after `Hive.initFlutter()`.
  static Future<HivePositionStore> open() async =>
      HivePositionStore(await Hive.openBox<int>(boxName));

  @override
  Duration? get(String path) {
    final millis = _box.get(path);
    return millis == null ? null : Duration(milliseconds: millis);
  }

  @override
  Future<void> put(String path, Duration position) =>
      _box.put(path, position.inMilliseconds);
}

class MemoryPositionStore implements PositionStore {
  final _positions = <String, Duration>{};

  @override
  Duration? get(String path) => _positions[path];

  @override
  Future<void> put(String path, Duration position) async =>
      _positions[path] = position;
}

/// Overridden in `main()` with the opened Hive store.
final positionStoreProvider = Provider<PositionStore>(
  (ref) => MemoryPositionStore(),
);

/// What the player is doing, for the screen.
class PlayerView {
  const PlayerView({
    this.tracks = const [],
    this.index,
    this.playing = false,
    this.speed = 1,
    this.sleepAt,
  });

  /// The playlist being played.
  final List<Track> tracks;
  final int? index;
  final bool playing;
  final double speed;

  /// When the sleep timer stops playback; null when none is set.
  final DateTime? sleepAt;

  Track? get current =>
      index == null || index! >= tracks.length ? null : tracks[index!];
}

/// The audio player. Playback continues with the screen off and shows the
/// usual media controls on the lock screen and in the notification.
class AudioPlayerController extends Notifier<PlayerView> {
  AudioPlayer? _player;
  Timer? _saveTimer;
  Timer? _sleepTimer;
  final _subscriptions = <StreamSubscription<Object?>>[];

  /// Positions this close to either end start the file from the beginning.
  static const _resumeMargin = Duration(seconds: 10);

  AudioPlayer get player => _player ??= _createPlayer();

  AudioPlayer _createPlayer() {
    final created = AudioPlayer();
    _subscriptions
      ..add(
        created.playerStateStream.listen((state) {
          _update(playing: state.playing);
          if (!state.playing) _savePosition();
        }),
      )
      ..add(
        created.currentIndexStream.listen((index) {
          _savePosition();
          _update(index: index);
          _resumeCurrent();
        }),
      )
      ..add(created.speedStream.listen((speed) => _update(speed: speed)));
    // Remember the place every few seconds while playing.
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (created.playing) _savePosition();
    });
    return created;
  }

  @override
  PlayerView build() {
    ref.onDispose(() {
      _savePosition();
      _saveTimer?.cancel();
      _sleepTimer?.cancel();
      for (final subscription in _subscriptions) {
        subscription.cancel();
      }
      _player?.dispose();
    });
    return const PlayerView();
  }

  void _update({int? index, bool? playing, double? speed}) {
    if (!ref.mounted) return;
    state = PlayerView(
      tracks: state.tracks,
      index: index ?? state.index,
      playing: playing ?? state.playing,
      speed: speed ?? state.speed,
      sleepAt: state.sleepAt,
    );
  }

  /// Plays [tracks] from [startAt], resuming that file where it was left.
  Future<void> play(List<Track> tracks, int startAt) async {
    final existing = tracks.where((t) => File(t.path).existsSync()).toList();
    if (existing.isEmpty) return;
    final wanted = tracks[startAt.clamp(0, tracks.length - 1)];
    final index = existing.indexWhere((t) => t.path == wanted.path);

    state = PlayerView(
      tracks: existing,
      index: index < 0 ? 0 : index,
      speed: state.speed,
      sleepAt: state.sleepAt,
    );
    await player.setAudioSources(
      [
        for (final track in existing)
          AudioSource.file(
            track.path,
            tag: MediaItem(
              id: track.path,
              title: track.title,
              artist: track.artist,
              album: 'SaveKit',
            ),
          ),
      ],
      initialIndex: index < 0 ? 0 : index,
      initialPosition: _resumePoint(existing[index < 0 ? 0 : index].path),
    );
    await player.play();
  }

  /// Where to start [path]: its saved place, unless that is at either end.
  Duration _resumePoint(String path) {
    final saved = ref.read(positionStoreProvider).get(path);
    if (saved == null || saved < _resumeMargin) return Duration.zero;
    return saved;
  }

  /// Moving to the next file: start it where it was left off too.
  void _resumeCurrent() {
    final current = state.current;
    final player = _player;
    if (current == null || player == null) return;
    final point = _resumePoint(current.path);
    final length = player.duration;
    if (point > Duration.zero &&
        (length == null || point < length - _resumeMargin)) {
      player.seek(point);
    }
  }

  void _savePosition() {
    final player = _player;
    final current = state.current;
    if (player == null || current == null) return;
    final position = player.position;
    final length = player.duration;
    // Finished files start from the beginning next time.
    final finished = length != null && position >= length - _resumeMargin;
    ref
        .read(positionStoreProvider)
        .put(current.path, finished ? Duration.zero : position);
  }

  Future<void> toggle() => player.playing ? player.pause() : player.play();
  Future<void> next() => player.seekToNext();
  Future<void> previous() => player.seekToPrevious();
  Future<void> seek(Duration position) => player.seek(position);

  /// Jumps [seconds] forwards or, when negative, backwards.
  Future<void> skip(int seconds) {
    final target = player.position + Duration(seconds: seconds);
    final length = player.duration;
    return player.seek(
      target < Duration.zero
          ? Duration.zero
          : (length != null && target > length ? length : target),
    );
  }

  Future<void> setSpeed(double speed) => player.setSpeed(speed);

  /// Stops playback after [after]; null cancels the timer.
  void setSleepTimer(Duration? after) {
    _sleepTimer?.cancel();
    _sleepTimer = after == null
        ? null
        : Timer(after, () {
            _player?.pause();
            if (ref.mounted) {
              state = PlayerView(
                tracks: state.tracks,
                index: state.index,
                playing: false,
                speed: state.speed,
              );
            }
          });
    state = PlayerView(
      tracks: state.tracks,
      index: state.index,
      playing: state.playing,
      speed: state.speed,
      sleepAt: after == null ? null : DateTime.now().add(after),
    );
  }
}

final audioPlayerProvider = NotifierProvider<AudioPlayerController, PlayerView>(
  AudioPlayerController.new,
);

/// Sets up background playback; call once before the app starts.
Future<void> initBackgroundAudio() => JustAudioBackground.init(
  androidNotificationChannelId: 'com.savekit.app.audio',
  androidNotificationChannelName: 'Audio playback',
  androidNotificationOngoing: true,
  androidNotificationIcon: 'drawable/ic_stat_savekit',
);
