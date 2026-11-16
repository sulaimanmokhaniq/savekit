import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/formatters.dart';
import '../../core/widgets/media_thumbnail.dart';
import 'audio_player_controller.dart';
import 'player_handler.dart';

/// The audio player: every audio file in the Vault as a playlist, with the
/// file playing now on top. Playback continues with the screen off.
class AudioPlayerScreen extends ConsumerStatefulWidget {
  const AudioPlayerScreen({super.key, this.startPath});

  /// A file to start playing straight away (opened from the Vault).
  final String? startPath;

  @override
  ConsumerState<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends ConsumerState<AudioPlayerScreen> {
  static const _speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  static const _sleepChoices = [15, 30, 45, 60];

  @override
  void initState() {
    super.initState();
    final start = widget.startPath;
    if (start != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final tracks = ref.read(audioTracksProvider);
        final index = tracks.indexWhere((track) => track.path == start);
        if (index >= 0) {
          ref.read(audioPlayerProvider.notifier).play(tracks, index);
        }
      });
    }
  }

  Future<void> _chooseSleep(PlayerView view) async {
    final controller = ref.read(audioPlayerProvider.notifier);
    final minutes = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final minutes in _sleepChoices)
              ListTile(
                leading: const Icon(Icons.bedtime_outlined),
                title: Text(tr('Stop after $minutes minutes')),
                onTap: () => Navigator.of(context).pop(minutes),
              ),
            if (view.sleepAt != null)
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: Text(tr('Turn off the sleep timer')),
                onTap: () => Navigator.of(context).pop(0),
              ),
          ],
        ),
      ),
    );
    if (minutes == null) return;
    controller.setSleepTimer(minutes == 0 ? null : Duration(minutes: minutes));
  }

  @override
  Widget build(BuildContext context) {
    final tracks = ref.watch(audioTracksProvider);
    final view = ref.watch(audioPlayerProvider);
    final controller = ref.read(audioPlayerProvider.notifier);
    final current = view.current;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Audio player'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (current != null)
            IconButton(
              onPressed: controller.stop,
              tooltip: tr('Stop'),
              icon: const Icon(Icons.stop_circle_outlined),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: tracks.isEmpty
          ? EmptyState(
              icon: Icons.library_music_outlined,
              title: tr('No audio yet'),
              message: tr(
                'Download something as MP3 or M4A, or convert a video to '
                'audio, and it appears here.',
              ),
            )
          : Column(
              children: [
                if (current != null)
                  _NowPlaying(
                    view: view,
                    player: controller.player,
                    onToggle: controller.toggle,
                    onNext: controller.next,
                    onPrevious: controller.previous,
                    onSkip: controller.skip,
                    onSeek: controller.seek,
                    onSpeed: () {
                      final i = _speeds.indexOf(view.speed);
                      controller.setSpeed(_speeds[(i + 1) % _speeds.length]);
                    },
                    onSleep: () => _chooseSleep(view),
                  ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: tracks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final track = tracks[index];
                      final playing = current?.path == track.path;
                      return Material(
                        color: AppColors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          side: BorderSide(
                            color: playing
                                ? AppColors.accent
                                : AppColors.border,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          onTap: () => controller.play(tracks, index),
                          leading: Icon(
                            playing && view.playing
                                ? Icons.graphic_eq_rounded
                                : Icons.music_note_rounded,
                            color: playing
                                ? AppColors.accent
                                : AppColors.textMuted,
                          ),
                          title: Text(
                            track.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: track.artist == null
                              ? null
                              : Text(
                                  track.artist!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 12.5,
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({
    required this.view,
    required this.player,
    required this.onToggle,
    required this.onNext,
    required this.onPrevious,
    required this.onSkip,
    required this.onSeek,
    required this.onSpeed,
    required this.onSleep,
  });

  final PlayerView view;
  final AudioPlayer player;
  final VoidCallback onToggle;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final void Function(int seconds) onSkip;
  final void Function(Duration position) onSeek;
  final VoidCallback onSpeed;
  final VoidCallback onSleep;

  String _speedLabel(double speed) =>
      '${speed == speed.roundToDouble() ? speed.toInt() : speed}×';

  @override
  Widget build(BuildContext context) {
    final current = view.current!;
    final sleepAt = view.sleepAt;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(
            current.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (current.artist != null) ...[
            const SizedBox(height: 4),
            Text(
              current.artist!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
          const SizedBox(height: 8),
          StreamBuilder<Duration>(
            stream: player.positionStream,
            builder: (context, snapshot) {
              final position = snapshot.data ?? Duration.zero;
              final length = player.duration ?? Duration.zero;
              final max = length.inMilliseconds.toDouble();
              return Column(
                children: [
                  _SeekBar(position: position, max: max, onSeek: onSeek),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          formatClock(position.inSeconds),
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          formatClock(length.inSeconds),
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: onPrevious,
                tooltip: tr('Previous'),
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              IconButton(
                onPressed: () => onSkip(-PlayerHandler.backSeconds),
                tooltip: tr('Back 15 seconds'),
                icon: const Icon(Icons.replay_rounded),
              ),
              IconButton.filled(
                onPressed: onToggle,
                iconSize: 34,
                tooltip: view.playing ? tr('Pause') : tr('Play'),
                icon: Icon(
                  view.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
              IconButton(
                onPressed: () => onSkip(PlayerHandler.forwardSeconds),
                tooltip: tr('Forward 30 seconds'),
                icon: const Icon(Icons.forward_30_rounded),
              ),
              IconButton(
                onPressed: onNext,
                tooltip: tr('Next'),
                icon: const Icon(Icons.skip_next_rounded),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: onSpeed,
                icon: const Icon(Icons.speed_rounded, size: 18),
                label: Text(_speedLabel(view.speed)),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: onSleep,
                icon: const Icon(Icons.bedtime_outlined, size: 18),
                label: Text(
                  sleepAt == null
                      ? tr('Sleep timer')
                      : tr(
                          'Stops at ${sleepAt.hour.toString().padLeft(2, '0')}:'
                          '${sleepAt.minute.toString().padLeft(2, '0')}',
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The position slider. Dragging only moves the handle; the player jumps once,
/// when the finger lifts, instead of seeking on every movement.
class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.position,
    required this.max,
    required this.onSeek,
  });

  final Duration position;
  final double max;
  final void Function(Duration position) onSeek;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final max = widget.max;
    final value =
        _dragging ??
        (max <= 0
            ? 0.0
            : widget.position.inMilliseconds.clamp(0, max).toDouble());
    return Slider(
      value: value.clamp(0, max <= 0 ? 1 : max).toDouble(),
      max: max <= 0 ? 1 : max,
      onChanged: max <= 0 ? null : (ms) => setState(() => _dragging = ms),
      onChangeEnd: max <= 0
          ? null
          : (ms) {
              setState(() => _dragging = null);
              widget.onSeek(Duration(milliseconds: ms.round()));
            },
    );
  }
}
