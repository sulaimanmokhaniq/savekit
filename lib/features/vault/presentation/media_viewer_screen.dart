import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../downloader/data/gallery_export_service.dart';
import '../../downloader/domain/download_task.dart';

/// Full-screen playback of a finished download: photos zoom, video and audio
/// play. Multi-file posts page sideways.
class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({
    super.key,
    required this.task,
    required this.onShare,
    required this.onDelete,
  });

  final DownloadTask task;

  /// Shares the file currently shown.
  final void Function(String path) onShare;

  /// Deletes the whole download; the viewer closes itself afterwards.
  final Future<bool> Function() onDelete;

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  int _index = 0;

  List<String> get _files => widget.task.filePaths;

  @override
  Widget build(BuildContext context) {
    final files = _files;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          files.length > 1
              ? '${_index + 1} of ${files.length}'
              : widget.task.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            onPressed: files.isEmpty
                ? null
                : () => widget.onShare(files[_index]),
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              if (await widget.onDelete()) navigator.pop();
            },
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: files.isEmpty
          ? const _Missing()
          : PageView.builder(
              itemCount: files.length,
              onPageChanged: (index) => setState(() => _index = index),
              itemBuilder: (context, index) => _FileView(
                key: ValueKey(files[index]),
                path: files[index],
                title: widget.task.title,
              ),
            ),
    );
  }
}

class _Missing extends StatelessWidget {
  const _Missing();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'This file is no longer on the phone.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted),
        ),
      ),
    );
  }
}

class _FileView extends StatelessWidget {
  const _FileView({super.key, required this.path, required this.title});

  final String path;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (!File(path).existsSync()) return const _Missing();
    return switch (savedFileKindOf(path)) {
      SavedFileKind.image => InteractiveViewer(
        maxScale: 5,
        child: Center(
          child: Image.file(
            File(path),
            errorBuilder: (_, _, _) => const _Missing(),
          ),
        ),
      ),
      SavedFileKind.video => _Player(
        path: path,
        audioOnly: false,
        title: title,
      ),
      SavedFileKind.audio => _Player(path: path, audioOnly: true, title: title),
      SavedFileKind.other => Center(
        child: Text(
          'This file type can’t be previewed. Use Share to open it.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      ),
    };
  }
}

class _Player extends StatefulWidget {
  const _Player({
    required this.path,
    required this.audioOnly,
    required this.title,
  });

  final String path;
  final bool audioOnly;
  final String title;

  @override
  State<_Player> createState() => _PlayerState();
}

class _PlayerState extends State<_Player> {
  late final VideoPlayerController _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path))
      ..addListener(_onTick);
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() {});
          _controller.play();
        })
        .catchError((Object error) {
          if (mounted) setState(() => _error = error);
        });
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  void _toggle() {
    final value = _controller.value;
    if (value.isPlaying) {
      _controller.pause();
    } else {
      if (value.position >= value.duration) _controller.seekTo(Duration.zero);
      _controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'This file can’t be played here. Use Share to open it in another app.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
      );
    }
    final value = _controller.value;
    if (!value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final total = value.duration.inMilliseconds.toDouble();
    final position = value.position.inMilliseconds
        .clamp(0, value.duration.inMilliseconds)
        .toDouble();

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _toggle,
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: widget.audioOnly
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Icon(
                            Icons.graphic_eq_rounded,
                            size: 52,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            widget.title,
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    )
                  : AspectRatio(
                      aspectRatio: value.aspectRatio == 0
                          ? 16 / 9
                          : value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: _toggle,
                  iconSize: 32,
                  tooltip: value.isPlaying ? 'Pause' : 'Play',
                  icon: Icon(
                    value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                Text(
                  formatDuration(value.position.inSeconds).isEmpty
                      ? '0:00'
                      : formatDuration(value.position.inSeconds),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: total <= 0 ? 0 : position,
                    max: total <= 0 ? 1 : total,
                    onChanged: total <= 0
                        ? null
                        : (ms) => _controller.seekTo(
                            Duration(milliseconds: ms.round()),
                          ),
                  ),
                ),
                Text(
                  formatDuration(value.duration.inSeconds),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
