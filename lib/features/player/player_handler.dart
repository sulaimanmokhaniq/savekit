import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/savekit_logo.dart';

/// Connects the audio player to Android's media notification, lock screen and
/// headset buttons: what they show (title, cover, progress) and what their
/// buttons do.
class PlayerHandler extends BaseAudioHandler {
  static const backSeconds = 15;
  static const forwardSeconds = 30;

  static const _backAction = 'back';
  static const _forwardAction = 'forward';

  AudioPlayer? _player;

  /// Called just before the notification's buttons leave the current file,
  /// so its place can be saved.
  void Function()? onLeaveTrack;

  /// Called when playback is ended from outside the app.
  void Function()? onStopped;

  /// Created on first use, so starting the app does not set up audio.
  AudioPlayer get player => _player ??= _createPlayer();

  AudioPlayer _createPlayer() {
    final created = AudioPlayer();
    created.playbackEventStream.listen(
      (_) => _broadcast(),
      onError: (Object _) => _broadcast(),
    );
    created.playerStateStream.listen((state) {
      _broadcast();
      // At the end of the list: stop on the last file instead of sitting
      // in a finished state that shows as still playing.
      if (state.processingState == ProcessingState.completed && state.playing) {
        created.pause().then((_) => created.seek(Duration.zero));
      }
    });
    created.speedStream.listen((_) => _broadcast());
    created.currentIndexStream.distinct().listen((_) => _showCurrent());
    created.durationStream.distinct().listen((_) => _showCurrent());
    return created;
  }

  /// Loads [items] (one per entry of [sources]) and starts at [initialIndex].
  Future<void> load(
    List<MediaItem> items,
    List<AudioSource> sources, {
    required int initialIndex,
    required Duration initialPosition,
  }) async {
    final cover = await _coverFile();
    queue.add([
      for (final item in items)
        cover == null ? item : item.copyWith(artUri: cover),
    ]);
    _thumbnails
      ..clear()
      ..addAll({
        for (final item in items)
          if (item.artUri != null) item.id: item.artUri!,
      });
    mediaItem.add(queue.value[initialIndex]);
    unawaited(_loadThumbnail(queue.value[initialIndex].id));
    await player.setAudioSources(
      sources,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
    );
  }

  /// Each file's own picture (a web address), by item id.
  final _thumbnails = <String, Uri>{};

  /// Shows the file playing now: its title, length and picture.
  void _showCurrent() {
    final index = _player?.currentIndex;
    final items = queue.value;
    if (index == null || index < 0 || index >= items.length) return;
    final shown = mediaItem.value;
    var item = items[index].copyWith(duration: _player?.duration);
    // Keep a picture that was already loaded for this file.
    if (shown != null && shown.id == item.id) {
      item = item.copyWith(artUri: shown.artUri);
    }
    mediaItem.add(item);
    if (shown?.id != item.id) unawaited(_loadThumbnail(item.id));
  }

  /// Swaps the SaveKit cover for the file's own picture once it has been
  /// fetched. The cover stays when there is none or it cannot be loaded.
  Future<void> _loadThumbnail(String id) async {
    final address = _thumbnails[id];
    if (address == null || !address.scheme.startsWith('http')) return;
    try {
      final file = await AudioService.cacheManager
          .getSingleFile(address.toString())
          .timeout(const Duration(seconds: 8));
      final shown = mediaItem.value;
      if (shown == null || shown.id != id) return;
      mediaItem.add(shown.copyWith(artUri: file.uri));
    } catch (_) {
      // Offline or gone: the SaveKit cover is already showing.
    }
  }

  void _broadcast() {
    final player = _player;
    if (player == null) return;
    final playing = player.playing;
    final many = queue.value.length > 1;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          if (many) MediaControl.skipToPrevious,
          MediaControl.rewind,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.fastForward,
          if (many) MediaControl.skipToNext,
          // Newer Android versions only show extra buttons given this way.
          MediaControl.custom(
            androidIcon: 'drawable/audio_service_fast_rewind',
            label: 'Back $backSeconds seconds',
            name: _backAction,
          ),
          MediaControl.custom(
            androidIcon: 'drawable/audio_service_fast_forward',
            label: 'Forward $forwardSeconds seconds',
            name: _forwardAction,
          ),
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        // Small notification: previous, play/pause, next when there is a
        // list; back, play/pause, forward for a single file.
        androidCompactActionIndices: many ? const [0, 2, 4] : const [0, 1, 2],
        processingState: switch (player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: player.currentIndex,
      ),
    );
  }

  /// Jumps [seconds] forwards or, when negative, backwards.
  Future<void> skipBy(int seconds) {
    final target = player.position + Duration(seconds: seconds);
    final length = player.duration;
    return player.seek(
      target < Duration.zero
          ? Duration.zero
          : (length != null && target > length ? length : target),
    );
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> rewind() => skipBy(-backSeconds);

  @override
  Future<void> fastForward() => skipBy(forwardSeconds);

  @override
  Future<void> skipToNext() {
    onLeaveTrack?.call();
    return player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() {
    onLeaveTrack?.call();
    return player.seekToPrevious();
  }

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) {
    return switch (name) {
      _backAction => rewind(),
      _forwardAction => fastForward(),
      _ => super.customAction(name, extras),
    };
  }

  /// Ends playback and removes the notification.
  @override
  Future<void> stop() async {
    onLeaveTrack?.call();
    await _player?.stop();
    onStopped?.call();
    await super.stop();
  }

  /// The picture shown until (or instead of) a file's own: the SaveKit logo
  /// in the current theme's colours. Null when it cannot be made.
  Future<Uri?> _coverFile() async {
    try {
      final palette = AppColors.current;
      final folder = await getApplicationSupportDirectory();
      final file = File('${folder.path}/player-cover-${palette.id}.png');
      if (!file.existsSync()) {
        await file.writeAsBytes(await _drawCover(palette), flush: true);
      }
      return file.uri;
    } catch (_) {
      return null;
    }
  }

  static Future<List<int>> _drawCover(AppPalette palette) async {
    const side = 512.0;
    const logo = 224.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..drawRect(
        const ui.Rect.fromLTWH(0, 0, side, side),
        ui.Paint()..color = palette.surface,
      )
      ..translate((side - logo) / 2, (side - logo) / 2);
    paintSaveKitLogo(canvas, const ui.Size.square(logo), palette);
    final image = await recorder.endRecording().toImage(
      side.toInt(),
      side.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }
}

PlayerHandler? _handler;

/// The app's one player. Works without [initBackgroundAudio] too, but then
/// only while the app is open.
PlayerHandler get playerHandler => _handler ??= PlayerHandler();

/// Sets up background playback; call once before the app starts.
Future<void> initBackgroundAudio() async {
  _handler = await AudioService.init(
    builder: PlayerHandler.new,
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.savekit.app.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationIcon: 'drawable/ic_stat_savekit',
      notificationColor: AppColors.current.accent,
      // While playing the notification stays put; once paused it can be
      // swiped away like any other player's.
      androidNotificationOngoing: true,
    ),
  );
}
