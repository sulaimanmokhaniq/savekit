import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/platform/media_platform.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../../core/widgets/media_thumbnail.dart';
import '../../../core/widgets/platform_badge.dart';
import '../../downloader/application/download_queue_controller.dart';
import '../../downloader/data/gallery_export_service.dart';
import '../../downloader/domain/download_task.dart';
import 'media_viewer_screen.dart';

/// Media Vault: finished downloads, filterable by platform, as a grid or list.
class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  MediaPlatform? _filter;
  bool _grid = true;

  Future<void> _share(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await SharePlus.instance.share(
        ShareParams(files: [for (final path in paths) XFile(path)]),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This file could not be shared.')),
      );
    }
  }

  /// Asks, then deletes. Returns whether the download was deleted.
  Future<bool> _delete(DownloadTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this download?'),
        content: Text(
          task.savedToGallery
              ? 'It is removed from SaveKit. The copy in your gallery stays.'
              : 'The file is removed from this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    await ref.read(downloadQueueControllerProvider.notifier).remove(task.id);
    return true;
  }

  void _open(DownloadTask task) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaViewerScreen(
          task: task,
          onShare: (path) => _share([path]),
          onDelete: () => _delete(task),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(completedDownloadsProvider);
    final platforms = [
      for (final platform in MediaPlatform.values)
        if (all.any((task) => task.platform == platform)) platform,
    ];
    // A filter whose last item was deleted falls back to "All".
    final filter = platforms.contains(_filter) ? _filter : null;
    final tasks = filter == null
        ? all
        : [
            for (final task in all)
              if (task.platform == filter) task,
          ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vault'),
        actions: [
          if (all.isNotEmpty)
            IconButton(
              onPressed: () => setState(() => _grid = !_grid),
              tooltip: _grid ? 'Show as list' : 'Show as grid',
              icon: Icon(
                _grid ? Icons.view_agenda_outlined : Icons.grid_view_rounded,
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: all.isEmpty
          ? const EmptyState(
              icon: Icons.video_library_outlined,
              title: 'Your vault is empty',
              message:
                  'Finished downloads are kept here to play, share or delete.',
            )
          : Column(
              children: [
                if (platforms.length > 1)
                  SizedBox(
                    height: 52,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: const Text('All'),
                            selected: filter == null,
                            onSelected: (_) => setState(() => _filter = null),
                          ),
                        ),
                        for (final platform in platforms)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              avatar: Icon(
                                platformStyle(platform).icon,
                                size: 16,
                                color: filter == platform
                                    ? AppColors.onAccent
                                    : platformStyle(platform).color,
                              ),
                              label: Text(platform.label),
                              selected: filter == platform,
                              onSelected: (_) =>
                                  setState(() => _filter = platform),
                            ),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _grid
                      ? GridView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 220,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 0.82,
                              ),
                          itemCount: tasks.length,
                          itemBuilder: (context, index) => _GridTile(
                            key: ValueKey(tasks[index].id),
                            task: tasks[index],
                            onOpen: () => _open(tasks[index]),
                            onShare: () => _share(tasks[index].filePaths),
                            onDelete: () => _delete(tasks[index]),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          itemCount: tasks.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) => _ListTile(
                            key: ValueKey(tasks[index].id),
                            task: tasks[index],
                            onOpen: () => _open(tasks[index]),
                            onShare: () => _share(tasks[index].filePaths),
                            onDelete: () => _delete(tasks[index]),
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

/// Icon for what the download is, used over or instead of a thumbnail.
IconData _kindIcon(DownloadTask task) {
  final path = task.filePath;
  if (path == null) return Icons.insert_drive_file_outlined;
  if (task.filePaths.length > 1) return Icons.photo_library_outlined;
  return switch (savedFileKindOf(path)) {
    SavedFileKind.image => Icons.image_outlined,
    SavedFileKind.video => Icons.play_arrow_rounded,
    SavedFileKind.audio => Icons.graphic_eq_rounded,
    SavedFileKind.other => Icons.insert_drive_file_outlined,
  };
}

/// A downloaded photo is its own best thumbnail.
String? _localThumbnail(DownloadTask task) {
  for (final path in task.filePaths) {
    if (savedFileKindOf(path) == SavedFileKind.image) return path;
  }
  return null;
}

String _subtitle(DownloadTask task) => [
  task.format.label,
  if (formatBytes(task.fileSize).isNotEmpty) formatBytes(task.fileSize),
].join(' · ');

class _Menu extends StatelessWidget {
  const _Menu({required this.onShare, required this.onDelete});

  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_vert_rounded, color: AppColors.textMuted),
      onSelected: (value) => value == 'share' ? onShare() : onDelete(),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'share',
          child: Row(
            children: [
              Icon(Icons.share_outlined, size: 20),
              SizedBox(width: 12),
              Text('Share'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.danger),
              SizedBox(width: 12),
              Text('Delete', style: TextStyle(color: AppColors.danger)),
            ],
          ),
        ),
      ],
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({
    super.key,
    required this.task,
    required this.onOpen,
    required this.onShare,
    required this.onDelete,
  });

  final DownloadTask task;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MediaThumbnail(
                    url: task.thumbnail,
                    filePath: _localThumbnail(task),
                    radius: 0,
                    fallbackIcon: _kindIcon(task),
                  ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: PlatformBadge(task.platform, size: 24),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(_kindIcon(task), size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _subtitle(task),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: _Menu(onShare: onShare, onDelete: onDelete),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListTile extends StatelessWidget {
  const _ListTile({
    super.key,
    required this.task,
    required this.onOpen,
    required this.onShare,
    required this.onDelete,
  });

  final DownloadTask task;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 2, 10),
          child: Row(
            children: [
              MediaThumbnail(
                url: task.thumbnail,
                filePath: _localThumbnail(task),
                width: 60,
                height: 60,
                fallbackIcon: _kindIcon(task),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        PlatformBadge(task.platform, size: 18),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _subtitle(task),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _Menu(onShare: onShare, onDelete: onDelete),
            ],
          ),
        ),
      ),
    );
  }
}
