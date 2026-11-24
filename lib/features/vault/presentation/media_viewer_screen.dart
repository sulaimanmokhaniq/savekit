import 'dart:io';
import 'dart:typed_data';

import 'post_details_sheet.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../moments/mark_moment.dart';

import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

import '../../../core/native/device_files_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../downloader/data/gallery_export_service.dart';
import '../../downloader/domain/download_task.dart';
import '../../../core/l10n/l10n.dart';

/// Full-screen playback of a finished download: photos zoom, video and audio
/// play. Multi-file posts page sideways.
class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({
    super.key,
    required this.task,
    required this.onShare,
    required this.onDelete,
    this.initialPath,
    this.startAt,
  });

  final DownloadTask task;

  /// The file to show first (from a moment); the first file when null.
  final String? initialPath;

  /// Where to start playing [initialPath].
  final Duration? startAt;

  /// Shares the file currently shown.
  final void Function(String path) onShare;

  /// Deletes the whole download; the viewer closes itself afterwards.
  final Future<bool> Function() onDelete;

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late int _index = widget.initialPath == null
      ? 0
      : widget.task.filePaths.indexOf(widget.initialPath!).clamp(0, 1 << 30);

  /// A post with several files opens as a grid; tapping one shows it full
  /// screen, and swiping moves between them.
  late bool _grid =
      widget.task.filePaths.length > 1 && widget.initialPath == null;
  late PageController? _pages = widget.initialPath == null
      ? null
      : PageController(initialPage: _index);

  List<String> get _files => widget.task.filePaths;

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  void _openAt(int index) {
    _pages?.dispose();
    setState(() {
      _index = index;
      _pages = PageController(initialPage: index);
      _grid = false;
    });
  }

  void _showGrid() => setState(() => _grid = true);

  @override
  Widget build(BuildContext context) {
    final files = _files;
    final many = files.length > 1;
    return PopScope(
      // Back from a single file returns to the grid first.
      canPop: !many || _grid,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showGrid();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(
            _grid
                ? widget.task.title
                : many
                ? tr('${_index + 1} of ${files.length}')
                : widget.task.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          actions: [
            if (many && !_grid)
              IconButton(
                onPressed: _showGrid,
                tooltip: tr('Show all'),
                icon: const Icon(Icons.grid_view_rounded),
              ),
            IconButton(
              onPressed: () => showPostDetails(context, widget.task),
              tooltip: tr('Post details'),
              icon: const Icon(Icons.info_outline_rounded),
            ),
            if (!_grid)
              IconButton(
                onPressed: files.isEmpty
                    ? null
                    : () => widget.onShare(files[_index]),
                tooltip: tr('Share'),
                icon: const Icon(Icons.share_outlined),
              ),
            IconButton(
              onPressed: () async {
                final navigator = Navigator.of(context);
                if (await widget.onDelete()) navigator.pop();
              },
              tooltip: tr('Delete'),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        body: files.isEmpty
            ? const _Missing()
            : _grid
            ? _Grid(files: files, onOpen: _openAt)
            : PageView.builder(
                controller: _pages,
                itemCount: files.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) => MediaFileView(
                  key: ValueKey(files[index]),
                  path: files[index],
                  title: widget.task.title,
                  startAt: files[index] == widget.initialPath
                      ? widget.startAt
                      : null,
                ),
              ),
      ),
    );
  }
}

/// Every file of a post side by side; tap one to see it full screen.
class _Grid extends StatelessWidget {
  const _Grid({required this.files, required this.onOpen});

  final List<String> files;
  final void Function(int index) onOpen;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final path = files[index];
        final kind = savedFileKindOf(path);
        final Widget picture = kind == SavedFileKind.image
            ? Image.file(
                File(path),
                fit: BoxFit.cover,
                cacheWidth: 400,
                errorBuilder: (_, _, _) => const _GridIcon(Icons.broken_image),
              )
            : kind == SavedFileKind.video
            ? _VideoTile(path: path)
            : _GridIcon(
                kind == SavedFileKind.audio
                    ? Icons.graphic_eq_rounded
                    : Icons.insert_drive_file_outlined,
              );
        return Semantics(
          button: true,
          label: tr('Item ${index + 1}'),
          child: GestureDetector(
            onTap: () => onOpen(index),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: picture,
            ),
          ),
        );
      },
    );
  }
}

/// A frame from the video, with a play mark over it.
class _VideoTile extends StatefulWidget {
  const _VideoTile({required this.path});

  final String path;

  @override
  State<_VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<_VideoTile> {
  late final Future<Uint8List?> _frame = DeviceFilesService().statusThumbnail(
    Uri.file(widget.path).toString(),
    size: 400,
    isVideo: true,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _frame,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (bytes == null)
              const ColoredBox(color: Color(0xFF1C1C1C))
            else
              Image.memory(bytes, fit: BoxFit.cover),
            const Center(
              child: Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white,
                size: 34,
                shadows: [Shadow(blurRadius: 6)],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GridIcon extends StatelessWidget {
  const _GridIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF1C1C1C),
      child: Center(child: Icon(icon, color: Colors.white70, size: 36)),
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
          tr('This file is no longer on the phone.'),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted),
        ),
      ),
    );
  }
}

/// Shows one local file: photos zoom, video and audio play.
class MediaFileView extends StatelessWidget {
  const MediaFileView({
    super.key,
    required this.path,
    required this.title,
    this.startAt,
  });

  final String path;
  final String title;

  /// Where to start playing; from the beginning when null.
  final Duration? startAt;

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
        startAt: startAt,
      ),
      SavedFileKind.audio => _Player(
        path: path,
        audioOnly: true,
        title: title,
        startAt: startAt,
      ),
      SavedFileKind.other => Center(
        child: Text(
          tr('This file type can’t be previewed. Use Share to open it.'),
          style: TextStyle(color: AppColors.textMuted),
        ),
      ),
    };
  }
}

class _Player extends ConsumerStatefulWidget {
  const _Player({
    required this.path,
    required this.audioOnly,
    required this.title,
    this.startAt,
  });

  final String path;
  final bool audioOnly;
  final String title;
  final Duration? startAt;

  @override
  ConsumerState<_Player> createState() => _PlayerState();
}

class _PlayerState extends ConsumerState<_Player> {
  late final VideoPlayerController _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path))
      ..addListener(_onTick);
    _controller
        .initialize()
        .then((_) async {
          if (!mounted) return;
          final start = widget.startAt;
          if (start != null) await _controller.seekTo(start);
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
            tr(
              'This file can’t be played here. Use Share to open it in another app.',
            ),
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
                  onPressed: () => markMoment(
                    context,
                    ref,
                    path: widget.path,
                    position: _controller.value.position,
                  ),
                  tooltip: tr('Mark this moment'),
                  icon: const Icon(Icons.bookmark_add_outlined),
                ),
                IconButton(
                  onPressed: _toggle,
                  iconSize: 32,
                  tooltip: value.isPlaying ? tr('Pause') : tr('Play'),
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
