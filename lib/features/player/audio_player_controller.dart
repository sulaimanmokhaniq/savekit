import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';

import '../downloader/application/download_queue_controller.dart';
import '../downloader/data/gallery_export_service.dart';
import '../downloader/domain/download_task.dart';
import 'player_handler.dart';

/// One playable audio file from the Vault.
class Track {
  const Track({
    required this.path,
    required this.title,
    this.artist,
    this.thumbnail,
  });

  final String path;
  final String title;
  final String? artist;

  /// The web address of the file's picture, when it has one.
  final String? thumbnail;
}

/// Every audio file in the Vault, newest first.
final audioTracksProvider = Provider<List<Track>>((ref) {
  final tasks = ref.watch(completedDownloadsProvider);
  return [
    for (final DownloadTask task in tasks)
      for (final path in task.filePaths)
        if (savedFileKindOf(path) == SavedFileKind.audio)
          Track(
            path: path,
            title: task.title,
            artist: task.uploader,
            thumbnail: task.thumbnail,
          ),
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
  PlayerHandler? _handler;
  Timer? _saveTimer;
  Timer? _sleepTimer;

  /// The file the player is on, as last handled. just_audio reports the
  /// current index again on every playback event (each seek included), so
  /// only a real change of file may act on it: seeking on every report
  /// seeks forever and freezes the app.
  int? _handledIndex;
  final _subscriptions = <StreamSubscription<Object?>>[];

  /// Positions this close to either end start the file from the beginning.
  static const _resumeMargin = Duration(seconds: 10);

  /// The player, or null before anything has been played.
  AudioPlayer? get _player => _handler?.player;

  AudioPlayer get player => _attach().player;

  /// Starts following the app's player on first use.
  PlayerHandler _attach() {
    final attached = _handler;
    if (attached != null) return attached;
    final handler = playerHandler
      ..onLeaveTrack = _savePosition
      ..onStopped = _clear;
    _handler = handler;
    final player = handler.player;
    _subscriptions
      ..add(
        player.playerStateStream.listen((state) {
          _update(playing: state.playing);
          if (!state.playing) _savePosition();
        }),
      )
      ..add(
        player.currentIndexStream.listen((index) {
          if (index == null || index == _handledIndex) return;
          _handledIndex = index;
          _update(index: index);
          _resumeCurrent();
        }),
      )
      ..add(player.speedStream.listen((speed) => _update(speed: speed)));
    // Remember the place every few seconds while playing.
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (player.playing) _savePosition();
    });
    return handler;
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
      _handler
        ?..onLeaveTrack = null
        ..onStopped = null;
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
  Future<void> play(
    List<Track> tracks,
    int startAt, {
    Duration? position,
  }) async {
    final existing = tracks.where((t) => File(t.path).existsSync()).toList();
    if (existing.isEmpty) return;
    final wanted = tracks[startAt.clamp(0, tracks.length - 1)];
    final index = existing.indexWhere((t) => t.path == wanted.path);

    // Keep the place in whatever was playing before.
    _savePosition();
    // The first file starts at its saved place through initialPosition.
    _handledIndex = index < 0 ? 0 : index;
    state = PlayerView(
      tracks: existing,
      index: index < 0 ? 0 : index,
      speed: state.speed,
      sleepAt: state.sleepAt,
    );
    final start = index < 0 ? 0 : index;
    await _attach().load(
      [
        for (final track in existing)
          MediaItem(
            id: track.path,
            title: track.title,
            artist: track.artist,
            album: 'SaveKit',
            artUri: track.thumbnail == null
                ? null
                : Uri.tryParse(track.thumbnail!),
          ),
      ],
      [for (final track in existing) AudioSource.file(track.path)],
      initialIndex: start,
      initialPosition: position ?? _resumePoint(existing[start].path),
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

  /// Ends playback and removes the media notification; the place in the
  /// file is kept for next time.
  Future<void> stop() async {
    // Saves the place and clears the screen through the handler's callbacks,
    // the same way as when playback is ended from outside the app.
    await _handler?.stop();
  }

  void _clear() {
    _sleepTimer?.cancel();
    _handledIndex = null;
    if (!ref.mounted) return;
    state = PlayerView(speed: state.speed);
  }

  Future<void> next() {
    _savePosition();
    return player.seekToNext();
  }

  Future<void> previous() {
    _savePosition();
    return player.seekToPrevious();
  }

  Future<void> seek(Duration position) => player.seek(position);

  /// Jumps [seconds] forwards or, when negative, backwards.
  Future<void> skip(int seconds) => _attach().skipBy(seconds);

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
