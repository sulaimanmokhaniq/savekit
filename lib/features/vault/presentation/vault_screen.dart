import 'feed_screen.dart';
import 'folder_widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/platform/media_platform.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../../core/widgets/media_thumbnail.dart';
import '../../../core/widgets/platform_badge.dart';
import '../../downloader/application/download_queue_controller.dart';
import '../../downloader/data/gallery_export_service.dart';
import '../../downloader/domain/download_task.dart';
import '../../tools/presentation/converter_screen.dart';
import '../../player/audio_player_screen.dart';
import '../../tools/presentation/editor_screen.dart';
import '../application/folders_controller.dart';
import '../application/vault_lock.dart';
import 'media_viewer_screen.dart';
import '../../../core/l10n/l10n.dart';

/// Media Vault: finished downloads. Searchable, sortable, filterable by
/// platform, as a grid or list, with multi-select and an optional lock.
class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key, this.folderId});

  /// Shows only this folder's items, with ways to add to it; null for the
  /// whole Vault.
  final String? folderId;

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  MediaPlatform? _filter;
  String _query = '';
  bool _searching = false;
  final _search = TextEditingController();
  final _selected = <String>{};
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Leaving the app locks the Vault again.
    _lifecycle = AppLifecycleListener(
      onHide: () => ref.read(vaultUnlockedProvider.notifier).lock(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final ok = await ref
        .read(vaultLockServiceProvider)
        .authenticate(tr('Unlock your Vault'));
    if (ok) ref.read(vaultUnlockedProvider.notifier).unlock();
  }

  Future<void> _share(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await SharePlus.instance.share(
        ShareParams(files: [for (final path in paths) XFile(path)]),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('This file could not be shared.'))),
      );
    }
  }

  /// Asks, then deletes [tasks]. Returns whether they were deleted.
  Future<bool> _delete(List<DownloadTask> tasks) async {
    if (tasks.isEmpty) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          tasks.length == 1
              ? tr('Delete this download?')
              : tr('Delete ${tasks.length} downloads?'),
        ),
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
    if (confirmed != true) return false;
    final everywhere = await ref
        .read(downloadQueueControllerProvider.notifier)
        .removeAll(tasks.map((task) => task.id));
    if (!everywhere && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'Removed from SaveKit, but a gallery copy could not be deleted. '
              'Delete it from your gallery app.',
            ),
          ),
        ),
      );
    }
    if (mounted) setState(() => _selected.removeAll(tasks.map((t) => t.id)));
    return true;
  }

  void _editVideo(DownloadTask task) {
    final video = task.filePaths.firstWhere(
      (path) => savedFileKindOf(path) == SavedFileKind.video,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorScreen(path: video, title: task.title),
      ),
    );
  }

  void _convert(DownloadTask task) {
    final video = task.filePaths.firstWhere(
      (path) => savedFileKindOf(path) == SavedFileKind.video,
    );
    enqueueConversion(ref, path: video, title: task.title, audioFormat: 'mp3');
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(tr('Converting to MP3. Follow it in the Queue.')),
        ),
      );
  }

  void _open(DownloadTask task) {
    // Audio plays in the audio player, which keeps going with the screen off.
    final path = task.filePath;
    if (path != null && savedFileKindOf(path) == SavedFileKind.audio) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AudioPlayerScreen(startPath: path),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaViewerScreen(
          task: task,
          onShare: (path) => _share([path]),
          onDelete: () => _delete([task]),
        ),
      ),
    );
  }

  void _openFolder(VaultFolder folder) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => VaultScreen(folderId: folder.id)),
    );
  }

  Future<void> _addToFolder(List<DownloadTask> tasks) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await addToFolder(context, ref, [
      for (final task in tasks) task.id,
    ]);
    if (name == null || !mounted) return;
    setState(_selected.clear);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(tr('Added ${tasks.length} to $name.'))),
      );
  }

  void _removeFromFolder(VaultFolder folder, List<DownloadTask> tasks) {
    ref.read(foldersProvider.notifier).remove(folder.id, [
      for (final task in tasks) task.id,
    ]);
    setState(_selected.clear);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            tr('Removed from ${folder.name}. They are still in the Vault.'),
          ),
        ),
      );
  }

  void _toggle(DownloadTask task) => setState(() {
    if (!_selected.remove(task.id)) _selected.add(task.id);
  });

  List<DownloadTask> _sorted(List<DownloadTask> tasks, VaultSort sort) {
    final sorted = [...tasks];
    DateTime date(DownloadTask task) => task.completedAt ?? task.createdAt;
    switch (sort) {
      case VaultSort.newest:
        sorted.sort((a, b) => date(b).compareTo(date(a)));
      case VaultSort.oldest:
        sorted.sort((a, b) => date(a).compareTo(date(b)));
      case VaultSort.largest:
        sorted.sort((a, b) => (b.fileSize ?? 0).compareTo(a.fileSize ?? 0));
      case VaultSort.smallest:
        sorted.sort((a, b) => (a.fileSize ?? 0).compareTo(b.fileSize ?? 0));
      case VaultSort.name:
        sorted.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final locked = settings.lockVault && !ref.watch(vaultUnlockedProvider);
    if (locked) return _LockedVault(onUnlock: _unlock);

    final folderId = widget.folderId;
    final folder = folderId == null
        ? null
        : ref
              .watch(foldersProvider)
              .where((folder) => folder.id == folderId)
              .firstOrNull;
    final all = folderId == null
        ? ref.watch(completedDownloadsProvider)
        : ref.watch(folderTasksProvider(folderId));
    final platforms = [
      for (final platform in MediaPlatform.values)
        if (all.any((task) => task.platform == platform)) platform,
    ];
    // A filter whose last item was deleted falls back to "All".
    final filter = platforms.contains(_filter) ? _filter : null;
    final query = _query.trim().toLowerCase();
    final tasks = _sorted([
      for (final task in all)
        if ((filter == null || task.platform == filter) &&
            (query.isEmpty ||
                task.title.toLowerCase().contains(query) ||
                (task.uploader?.toLowerCase().contains(query) ?? false)))
          task,
    ], settings.vaultSort);
    final selected = [
      for (final task in all)
        if (_selected.contains(task.id)) task,
    ];
    final selecting = selected.isNotEmpty;
    final grid = settings.vaultGrid;
    final settingsController = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        leading: selecting
            ? IconButton(
                onPressed: () => setState(_selected.clear),
                tooltip: tr('Cancel selection'),
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        title: selecting
            ? Text(
                tr('${selected.length} selected'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              )
            : _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: tr('Search your vault'),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              )
            : folder != null
            ? Row(
                children: [
                  Icon(Icons.folder_rounded, color: folder.color),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(folder.name, overflow: TextOverflow.ellipsis),
                  ),
                ],
              )
            : Text(tr('Vault')),
        actions: [
          if (selecting) ...[
            IconButton(
              onPressed: () => setState(
                () => _selected.addAll(tasks.map((task) => task.id)),
              ),
              tooltip: tr('Select all'),
              icon: const Icon(Icons.select_all_rounded),
            ),
            IconButton(
              onPressed: () =>
                  _share([for (final task in selected) ...task.filePaths]),
              tooltip: tr('Share selected'),
              icon: const Icon(Icons.share_outlined),
            ),
            if (folder == null)
              IconButton(
                onPressed: () => _addToFolder(selected),
                tooltip: tr('Add to folder'),
                icon: const Icon(Icons.create_new_folder_outlined),
              )
            else
              IconButton(
                onPressed: () => _removeFromFolder(folder, selected),
                tooltip: tr('Remove from folder'),
                icon: const Icon(Icons.folder_off_outlined),
              ),
            IconButton(
              onPressed: () => _delete(selected),
              tooltip: tr('Delete selected'),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ] else if (folder != null) ...[
            IconButton(
              onPressed: () => addFromPhone(context, ref, folderId: folder.id),
              tooltip: tr('Add from phone'),
              icon: const Icon(Icons.add_photo_alternate_outlined),
            ),
            if (all.isNotEmpty)
              IconButton(
                onPressed: () => settingsController.setVaultGrid(!grid),
                tooltip: grid ? tr('Show as list') : tr('Show as grid'),
                icon: Icon(
                  grid ? Icons.view_agenda_outlined : Icons.grid_view_rounded,
                ),
              ),
            IconButton(
              onPressed: () => showFolderOptions(context, ref, folder),
              tooltip: tr('Folder options'),
              icon: const Icon(Icons.more_vert_rounded),
            ),
          ] else if (all.isNotEmpty) ...[
            IconButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const FeedScreen()),
              ),
              tooltip: tr('Your feed'),
              icon: const Icon(Icons.swipe_up_rounded),
            ),
            IconButton(
              onPressed: () => setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _search.clear();
                  _query = '';
                }
              }),
              tooltip: _searching ? tr('Close search') : tr('Search'),
              icon: Icon(
                _searching ? Icons.search_off_rounded : Icons.search_rounded,
              ),
            ),
            PopupMenuButton<VaultSort>(
              tooltip: tr('Sort'),
              icon: const Icon(Icons.sort_rounded),
              initialValue: settings.vaultSort,
              onSelected: settingsController.setVaultSort,
              itemBuilder: (_) => [
                for (final sort in VaultSort.values)
                  PopupMenuItem(value: sort, child: Text(tr(sort.label))),
              ],
            ),
            IconButton(
              onPressed: () => settingsController.setVaultGrid(!grid),
              tooltip: grid ? tr('Show as list') : tr('Show as grid'),
              icon: Icon(
                grid ? Icons.view_agenda_outlined : Icons.grid_view_rounded,
              ),
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
      body: folderId != null && folder == null
          // The folder was deleted from its own menu.
          ? EmptyState(
              icon: Icons.folder_off_outlined,
              title: tr('This folder was deleted'),
              message: tr('Everything that was in it is still in the Vault.'),
            )
          : all.isEmpty && folder != null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                EmptyState(
                  icon: Icons.folder_open_rounded,
                  title: tr('This folder is empty'),
                  message: tr(
                    'Add photos and videos from your phone, or select items '
                    'in the Vault and choose Add to folder.',
                  ),
                ),
                FilledButton.icon(
                  onPressed: () =>
                      addFromPhone(context, ref, folderId: folder.id),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(tr('Add from phone')),
                ),
              ],
            )
          : all.isEmpty
          ? Column(
              children: [
                FolderRow(onOpen: _openFolder),
                Expanded(
                  child: EmptyState(
                    icon: Icons.video_library_outlined,
                    title: tr('Your vault is empty'),
                    message: tr(
                      'Finished downloads are kept here to play, share or '
                      'delete.',
                    ),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                if (folder == null && !_searching && !selecting)
                  FolderRow(onOpen: _openFolder),
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
                            label: Text(tr('All')),
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
                              label: Text(tr(platform.label)),
                              selected: filter == platform,
                              onSelected: (_) =>
                                  setState(() => _filter = platform),
                            ),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: tasks.isEmpty
                      ? EmptyState(
                          icon: Icons.search_off_rounded,
                          title: tr('Nothing matches'),
                          message: tr('Try another search or filter.'),
                        )
                      : grid
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
                          itemBuilder: (context, index) => _tile(
                            tasks[index],
                            grid: true,
                            selecting: selecting,
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          itemCount: tasks.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) => _tile(
                            tasks[index],
                            grid: false,
                            selecting: selecting,
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _tile(
    DownloadTask task, {
    required bool grid,
    required bool selecting,
  }) {
    final isSelected = _selected.contains(task.id);
    final canConvert = task.filePaths.any(
      (path) => savedFileKindOf(path) == SavedFileKind.video,
    );
    // While selecting, a tap toggles; otherwise it opens. A long press
    // starts selecting.
    void onTap() => selecting ? _toggle(task) : _open(task);
    final menu = selecting
        ? Icon(
            isSelected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: isSelected ? AppColors.accent : AppColors.textMuted,
          )
        : _Menu(
            onShare: () => _share(task.filePaths),
            onDelete: () => _delete([task]),
            onSelect: () => _toggle(task),
            onConvert: canConvert ? () => _convert(task) : null,
            onEdit: canConvert ? () => _editVideo(task) : null,
          );
    return grid
        ? _GridTile(
            key: ValueKey(task.id),
            task: task,
            selected: isSelected,
            onTap: onTap,
            onLongPress: () => _toggle(task),
            trailing: menu,
          )
        : _ListTile(
            key: ValueKey(task.id),
            task: task,
            selected: isSelected,
            onTap: onTap,
            onLongPress: () => _toggle(task),
            trailing: menu,
          );
  }
}

class _LockedVault extends StatelessWidget {
  const _LockedVault({required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Vault'))),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 44,
                color: AppColors.accent,
              ),
              const SizedBox(height: 16),
              Text(
                tr('The Vault is locked'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr('Confirm it’s you to see your downloads.'),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onUnlock,
                icon: const Icon(Icons.fingerprint_rounded, size: 20),
                label: Text(tr('Unlock')),
              ),
            ],
          ),
        ),
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
  tr(task.format.label),
  if (formatBytes(task.fileSize).isNotEmpty) formatBytes(task.fileSize),
].join(' · ');

class _Menu extends StatelessWidget {
  const _Menu({
    required this.onShare,
    required this.onDelete,
    required this.onSelect,
    this.onConvert,
    this.onEdit,
  });

  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback onSelect;

  /// Null when the download has no video to convert.
  final VoidCallback? onConvert;

  /// Null when the download has no video to edit.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    PopupMenuItem<String> item(
      String value,
      IconData icon,
      String label, {
      Color? color,
    }) => PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
    );

    return PopupMenuButton<String>(
      tooltip: tr('More'),
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_vert_rounded, color: AppColors.textMuted),
      onSelected: (value) => switch (value) {
        'share' => onShare(),
        'select' => onSelect(),
        'convert' => onConvert?.call(),
        'edit' => onEdit?.call(),
        _ => onDelete(),
      },
      itemBuilder: (_) => [
        item('share', Icons.share_outlined, tr('Share')),
        item('select', Icons.check_circle_outline_rounded, tr('Select')),
        if (onConvert != null)
          item('convert', Icons.graphic_eq_rounded, tr('Convert to audio')),
        if (onEdit != null) item('edit', Icons.movie_edit, tr('Edit video')),
        item(
          'delete',
          Icons.delete_outline_rounded,
          tr('Delete'),
          color: AppColors.danger,
        ),
      ],
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({
    super.key,
    required this.task,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.trailing,
  });

  final DownloadTask task;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// The ⋮ menu, or the selection mark while selecting.
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: selected ? AppColors.accent : AppColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
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
                      child: Icon(
                        _kindIcon(task),
                        size: 16,
                        color: Colors.white,
                      ),
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
                          style: TextStyle(
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
                    child: Center(child: trailing),
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
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.trailing,
  });

  final DownloadTask task;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// The ⋮ menu, or the selection mark while selecting.
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: selected ? AppColors.accent : AppColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
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
                            style: TextStyle(
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
              SizedBox(width: 44, height: 44, child: Center(child: trailing)),
            ],
          ),
        ),
      ),
    );
  }
}
