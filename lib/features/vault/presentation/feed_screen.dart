import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/media_thumbnail.dart';
import '../../downloader/application/download_queue_controller.dart';
import '../../downloader/data/gallery_export_service.dart';
import '../../transfer/transfer_controller.dart' show keepScreenOnProvider;
import '../application/vault_lock.dart';

/// One video or photo in the feed.
class FeedItem {
  const FeedItem({
    required this.path,
    required this.title,
    required this.source,
    required this.isVideo,
  });

  final String path;
  final String title;

  /// Who posted it and where, such as "harbour.studio · TikTok".
  final String source;
  final bool isVideo;
}

/// Every saved video and photo still on the phone, newest first.
final feedItemsProvider = Provider<List<FeedItem>>((ref) {
  return [
    for (final task in ref.watch(completedDownloadsProvider))
      for (final path in task.filePaths)
        if (savedFileKindOf(path) case final kind
            when (kind == SavedFileKind.video || kind == SavedFileKind.image) &&
                File(path).existsSync())
          FeedItem(
            path: path,
            title: task.title,
            source: [
              if (task.uploader?.isNotEmpty ?? false) task.uploader!,
              task.platform.label,
            ].join(' · '),
            isVideo: kind == SavedFileKind.video,
          ),
  ];
});

/// Your feed: the saved videos and photos, one per screen, swiped upwards.
/// Works with no connection, and shows only what the user chose to keep.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _pages = PageController();

  /// The paths in the order shown; fixed while the screen is open so the
  /// feed does not jump when a download finishes.
  late List<String> _order;
  int _index = 0;
  bool _muted = false;
  bool _shuffled = false;
  late final Future<void> Function(bool on) _keepScreenOn;

  @override
  void initState() {
    super.initState();
    _order = [for (final item in ref.read(feedItemsProvider)) item.path];
    _keepScreenOn = ref.read(keepScreenOnProvider);
    _keepScreenOn(true);
  }

  @override
  void dispose() {
    _keepScreenOn(false);
    _pages.dispose();
    super.dispose();
  }

  void _toggleShuffle() {
    final newest = [for (final item in ref.read(feedItemsProvider)) item.path];
    setState(() {
      _shuffled = !_shuffled;
      _order = _shuffled ? (newest..shuffle(Random())) : newest;
      _index = 0;
    });
    if (_pages.hasClients) _pages.jumpToPage(0);
  }

  Future<void> _share(FeedItem item) async {
    try {
      await SharePlus.instance.share(ShareParams(files: [XFile(item.path)]));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('This file could not be shared.'))),
      );
    }
  }

  Future<void> _delete(FeedItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete this file?')),
        content: Text(
          tr(
            'This deletes it everywhere on this phone: from SaveKit and from '
            'your gallery. It cannot be undone.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(downloadQueueControllerProvider.notifier).deleteFiles({
      item.path,
    });
    if (!mounted) return;
    setState(() {
      _order.remove(item.path);
      if (_index >= _order.length) _index = max(0, _order.length - 1);
    });
  }

  Future<void> _unlock() async {
    final ok = await ref
        .read(vaultLockServiceProvider)
        .authenticate(tr('Unlock your Vault'));
    if (ok) ref.read(vaultUnlockedProvider.notifier).unlock();
  }

  @override
  Widget build(BuildContext context) {
    final byPath = {
      for (final item in ref.watch(feedItemsProvider)) item.path: item,
    };
    // Files deleted elsewhere drop out; new ones wait for the next visit.
    final items = [for (final path in _order) ?byPath[path]];
    final locked =
        ref.watch(settingsControllerProvider).lockVault &&
        !ref.watch(vaultUnlockedProvider);
    final index = items.isEmpty ? 0 : _index.clamp(0, items.length - 1);

    return Theme(
      // Always dark: this screen is for watching.
      data: buildAppTheme(AppColors.current)
          .copyWith(scaffoldBackgroundColor: Colors.black),
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          title: Text(
            items.isEmpty || locked
                ? tr('Your feed')
                : '${index + 1} / ${items.length}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              shadows: [Shadow(blurRadius: 6)],
            ),
          ),
          actions: [
            if (items.length > 1 && !locked)
              IconButton(
                onPressed: _toggleShuffle,
                tooltip: _shuffled ? tr('Newest first') : tr('Shuffle'),
                icon: Icon(
                  Icons.shuffle_rounded,
                  color: _shuffled ? AppColors.accent : Colors.white,
                  shadows: const [Shadow(blurRadius: 6)],
                ),
              ),
          ],
        ),
        body: locked
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  EmptyState(
                    icon: Icons.lock_outline_rounded,
                    title: tr('The Vault is locked'),
                    message: tr('Unlock it to watch your feed.'),
                  ),
                  FilledButton(onPressed: _unlock, child: Text(tr('Unlock'))),
                ],
              )
            : items.isEmpty
            ? EmptyState(
                icon: Icons.swipe_up_rounded,
                title: tr('Nothing to watch yet'),
                message: tr(
                  'Videos and photos you save appear here, one per screen. '
                  'Swipe up for the next.',
                ),
              )
            : PageView.builder(
                controller: _pages,
                scrollDirection: Axis.vertical,
                itemCount: items.length,
                onPageChanged: (page) => setState(() => _index = page),
                itemBuilder: (context, page) {
                  final item = items[page];
                  return _FeedPage(
                    key: ValueKey(item.path),
                    item: item,
                    active: page == index,
                    muted: _muted,
                    onMute: () => setState(() => _muted = !_muted),
                    onShare: () => _share(item),
                    onDelete: () => _delete(item),
                  );
                },
              ),
      ),
    );
  }
}

class _FeedPage extends StatefulWidget {
  const _FeedPage({
    super.key,
    required this.item,
    required this.active,
    required this.muted,
    required this.onMute,
    required this.onShare,
    required this.onDelete,
  });

  final FeedItem item;

  /// Whether this is the page on screen; only that one plays.
  final bool active;
  final bool muted;
  final VoidCallback onMute;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  State<_FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<_FeedPage> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(_FeedPage old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) {
      widget.active ? _start() : _stop();
    }
    if (widget.muted != old.muted) {
      _controller?.setVolume(widget.muted ? 0 : 1);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Loads and plays the video. Only the page on screen holds a player, so
  /// a long feed never keeps more than one video open.
  void _start() {
    if (!widget.item.isVideo || _controller != null) return;
    final controller = VideoPlayerController.file(File(widget.item.path));
    _controller = controller;
    _failed = false;
    controller
        .initialize()
        .then((_) async {
          if (!mounted || _controller != controller) return;
          await controller.setLooping(true);
          await controller.setVolume(widget.muted ? 0 : 1);
          await controller.play();
          if (mounted) setState(() {});
        })
        .catchError((Object _) {
          if (mounted && _controller == controller) {
            setState(() => _failed = true);
          }
        });
  }

  void _stop() {
    final controller = _controller;
    _controller = null;
    controller?.dispose();
    if (mounted) setState(() {});
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      controller.value.isPlaying ? controller.pause() : controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;

    final Widget picture;
    if (!item.isVideo) {
      picture = InteractiveViewer(
        maxScale: 4,
        child: Center(
          child: Image.file(
            File(item.path),
            errorBuilder: (_, _, _) => const _Unplayable(),
          ),
        ),
      );
    } else if (_failed) {
      picture = const _Unplayable();
    } else if (!ready) {
      picture = const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    } else {
      picture = Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      );
    }

    const shadow = [Shadow(blurRadius: 8)];
    Widget action(IconData icon, String label, VoidCallback onPressed) =>
        IconButton(
          onPressed: onPressed,
          tooltip: label,
          iconSize: 28,
          icon: Icon(icon, color: Colors.white, shadows: shadow),
        );

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: item.isVideo ? _togglePlay : null,
          behavior: HitTestBehavior.opaque,
          child: picture,
        ),
        if (ready && !controller.value.isPlaying)
          const IgnorePointer(
            child: Center(
              child: Icon(
                Icons.play_arrow_rounded,
                size: 84,
                color: Colors.white70,
                shadows: shadow,
              ),
            ),
          ),
        PositionedDirectional(
          end: 6,
          bottom: 96,
          child: Column(
            children: [
              if (item.isVideo)
                action(
                  widget.muted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  widget.muted ? tr('Sound on') : tr('Sound off'),
                  widget.onMute,
                ),
              action(Icons.share_outlined, tr('Share'), widget.onShare),
              action(
                Icons.delete_outline_rounded,
                tr('Delete'),
                widget.onDelete,
              ),
            ],
          ),
        ),
        PositionedDirectional(
          start: 16,
          end: 64,
          bottom: 28,
          child: IgnorePointer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    shadows: shadow,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                    shadows: shadow,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (ready)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              padding: const EdgeInsets.only(top: 14),
              colors: VideoProgressColors(
                playedColor: AppColors.accent,
                bufferedColor: Colors.white24,
                backgroundColor: Colors.white12,
              ),
            ),
          ),
      ],
    );
  }
}

class _Unplayable extends StatelessWidget {
  const _Unplayable();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          tr(
            'This file can’t be played here. Use Share to open it in another app.',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      ),
    );
  }
}
