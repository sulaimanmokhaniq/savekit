import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/native/device_files_service.dart';
import '../../../core/platform/media_platform.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../downloader/application/download_queue_controller.dart';
import '../../extractor/domain/media_format.dart';
import '../../extractor/domain/media_info.dart';

/// The edits the editor offers.
enum VideoEdit {
  split(
    'split',
    'Split for WhatsApp Status',
    'Cut into numbered parts that each fit in a status.',
    Icons.view_week_outlined,
  ),
  vertical(
    'vertical',
    'Make vertical',
    'Crop the middle to 9:16 for stories and status.',
    Icons.crop_portrait_rounded,
  ),
  compress(
    'compress',
    'Make smaller',
    'Re-encode to about the size you choose.',
    Icons.compress_rounded,
  ),
  gif(
    'gif',
    'Make a GIF',
    'Turn a few seconds into an animated GIF.',
    Icons.gif_box_outlined,
  ),
  frame(
    'frame',
    'Save a photo',
    'Save the picture at any moment as a photo.',
    Icons.photo_camera_outlined,
  );

  const VideoEdit(this.id, this.title, this.description, this.icon);

  final String id;
  final String title;
  final String description;
  final IconData icon;
}

/// Queues [edit] of the video at [path]. It runs through the normal queue
/// and the results land in the Vault.
void enqueueEdit(
  WidgetRef ref, {
  required String path,
  required String title,
  required VideoEdit edit,
  required Map<String, String> options,
  required String label,
}) {
  ref
      .read(downloadQueueControllerProvider.notifier)
      .enqueue(
        MediaInfo(url: path, title: title, platform: MediaPlatform.device),
        MediaFormat(
          id: 'edit_${edit.id}',
          kind: edit == VideoEdit.frame || edit == VideoEdit.gif
              ? MediaFormatKind.gallery
              : MediaFormatKind.video,
          label: label,
          engine: DownloadEngineKind.edit,
          formatSelection: edit.id,
          options: options,
        ),
      );
}

/// Mini editor for a video already on the phone: split, crop, compress,
/// GIF or photo. Everything runs on the phone with FFmpeg.
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, this.path, this.title});

  /// A video to start with (from the Vault); null to choose one.
  final String? path;
  final String? title;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  String? _path;
  String? _title;
  VideoPlayerController? _player;
  bool _picking = false;

  VideoEdit _edit = VideoEdit.split;
  int _partSeconds = 60;
  int _targetMb = 16;
  double _at = 0;
  double _gifLength = 4;

  Duration get _duration => _player?.value.duration ?? Duration.zero;
  double get _seconds => _duration.inMilliseconds / 1000;

  @override
  void initState() {
    super.initState();
    final path = widget.path;
    if (path != null) {
      _open(path, widget.title ?? p.basenameWithoutExtension(path));
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _open(String path, String title) async {
    final old = _player;
    final player = VideoPlayerController.file(File(path));
    setState(() {
      _path = path;
      _title = title;
      _player = player;
      _at = 0;
    });
    await old?.dispose();
    try {
      await player.initialize();
    } catch (_) {
      // Shown as "length unknown"; most edits still work.
    }
    if (mounted) setState(() {});
  }

  Future<void> _pick() async {
    setState(() => _picking = true);
    try {
      final video = await ref.read(deviceFilesServiceProvider).pickVideo();
      if (video != null && mounted) {
        await _open(video.path, p.basenameWithoutExtension(video.name));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Couldn’t open that video: $error'))),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _seek(double seconds) async {
    setState(() => _at = seconds);
    await _player?.seekTo(Duration(milliseconds: (seconds * 1000).round()));
  }

  /// Parts a split of this video would make, when its length is known.
  int? get _partCount =>
      _seconds <= 0 ? null : (_seconds / (_partSeconds - 2)).ceil();

  void _start() {
    final path = _path;
    if (path == null) return;
    final (options, label) = switch (_edit) {
      VideoEdit.split => (
        {'seconds': '$_partSeconds'},
        tr('Split · ${_partSeconds}s parts'),
      ),
      VideoEdit.vertical => (<String, String>{}, tr('Vertical 9:16')),
      VideoEdit.compress => (
        {'targetMb': '$_targetMb', 'duration': _seconds.toStringAsFixed(2)},
        tr('About $_targetMb MB'),
      ),
      VideoEdit.gif => (
        {
          'start': _at.toStringAsFixed(2),
          'length': _gifLength.toStringAsFixed(1),
        },
        tr('GIF · ${_gifLength.round()}s'),
      ),
      VideoEdit.frame => (
        {'at': _at.toStringAsFixed(2)},
        tr('Photo at ${formatClock(_at.round())}'),
      ),
    };
    enqueueEdit(
      ref,
      path: path,
      title: _title ?? p.basenameWithoutExtension(path),
      edit: _edit,
      options: options,
      label: label,
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            tr('Working on it. Follow it in the Queue; it lands in the Vault.'),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final ready = player != null && player.value.isInitialized;
    final needsLength =
        _edit == VideoEdit.compress ||
        _edit == VideoEdit.gif ||
        _edit == VideoEdit.frame;
    final canStart = _path != null && (!needsLength || _seconds > 0);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Edit video'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton.icon(
            onPressed: canStart ? _start : null,
            icon: Icon(_edit.icon, size: 20),
            label: Text(tr(_edit.title)),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          // The video, or a button to choose one.
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: AspectRatio(
              aspectRatio: ready && player.value.aspectRatio > 0
                  ? player.value.aspectRatio.clamp(0.5, 2.0)
                  : 16 / 9,
              child: ColoredBox(
                color: AppColors.surface,
                child: ready
                    ? VideoPlayer(player)
                    : Center(
                        child: _path == null
                            ? OutlinedButton.icon(
                                onPressed: _picking ? null : _pick,
                                icon: const Icon(
                                  Icons.folder_open_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  _picking
                                      ? tr('Opening…')
                                      : tr('Choose a video'),
                                ),
                              )
                            : const CircularProgressIndicator(),
                      ),
              ),
            ),
          ),
          if (_path != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _title ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  _seconds > 0 ? formatClock(_seconds.round()) : '',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                TextButton(
                  onPressed: _picking ? null : _pick,
                  child: Text(tr('Change')),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          for (final edit in VideoEdit.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _EditCard(
                edit: edit,
                selected: edit == _edit,
                onTap: () => setState(() => _edit = edit),
              ),
            ),
          const SizedBox(height: 8),
          ..._settings(),
        ],
      ),
    );
  }

  /// The settings of the chosen edit.
  List<Widget> _settings() {
    Widget caption(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
    Widget note(String text) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
      ),
    );
    Widget timeSlider() => Slider(
      value: _at.clamp(0, _seconds > 0 ? _seconds : 1),
      max: _seconds > 0 ? _seconds : 1,
      onChanged: _seconds > 0 ? _seek : null,
    );

    switch (_edit) {
      case VideoEdit.split:
        final parts = _partCount;
        return [
          caption(tr('LENGTH OF EACH PART')),
          Wrap(
            spacing: 8,
            children: [
              for (final seconds in const [30, 60, 90])
                ChoiceChip(
                  label: Text(tr('$seconds seconds')),
                  selected: _partSeconds == seconds,
                  onSelected: (_) => setState(() => _partSeconds = seconds),
                ),
            ],
          ),
          note(
            parts == null
                ? tr('WhatsApp statuses can be up to 60 seconds long.')
                : tr(
                    'About $parts parts. WhatsApp statuses can be up to 60 '
                    'seconds long.',
                  ),
          ),
        ];
      case VideoEdit.vertical:
        return [
          note(
            tr(
              'Keeps the middle of the picture; the sides are cut off. '
              'This re-encodes the video, so it takes a while.',
            ),
          ),
        ];
      case VideoEdit.compress:
        return [
          caption(tr('TARGET SIZE')),
          Wrap(
            spacing: 8,
            children: [
              for (final mb in const [8, 16, 25, 50])
                ChoiceChip(
                  label: Text('$mb MB'),
                  selected: _targetMb == mb,
                  onSelected: (_) => setState(() => _targetMb = mb),
                ),
            ],
          ),
          note(
            tr(
              'Smaller sizes lower the picture quality. 16 MB fits WhatsApp '
              'and most messaging apps.',
            ),
          ),
        ];
      case VideoEdit.gif:
        return [
          caption(tr('START · ${formatClock(_at.round())}')),
          timeSlider(),
          caption(tr('LENGTH · ${_gifLength.round()} SECONDS')),
          Slider(
            value: _gifLength,
            min: 1,
            max: 10,
            divisions: 9,
            onChanged: (value) => setState(() => _gifLength = value),
          ),
        ];
      case VideoEdit.frame:
        return [
          caption(tr('MOMENT · ${formatClock(_at.round())}')),
          timeSlider(),
          note(
            tr('Move the slider until the picture above is the one you want.'),
          ),
        ];
    }
  }
}

class _EditCard extends StatelessWidget {
  const _EditCard({
    required this.edit,
    required this.selected,
    required this.onTap,
  });

  final VideoEdit edit;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: selected ? AppColors.accent : AppColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                edit.icon,
                color: selected ? AppColors.accent : AppColors.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(edit.title),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tr(edit.description),
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
