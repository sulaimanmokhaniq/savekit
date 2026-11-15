import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../../core/widgets/media_thumbnail.dart';
import '../../downloader/application/download_queue_controller.dart';
import '../../downloader/data/gallery_export_service.dart';
import '../application/storage_controller.dart';
import '../../../core/l10n/l10n.dart';

/// Storage manager: how much space SaveKit uses, every file with its size,
/// sortable, with single and multi-select delete.
class StorageScreen extends ConsumerStatefulWidget {
  const StorageScreen({super.key});

  @override
  ConsumerState<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends ConsumerState<StorageScreen> {
  VaultSort _sort = VaultSort.largest;
  final _selected = <String>{};

  List<StoredFile> _sorted(List<StoredFile> files) {
    final sorted = [...files];
    switch (_sort) {
      case VaultSort.largest:
        sorted.sort((a, b) => b.size.compareTo(a.size));
      case VaultSort.smallest:
        sorted.sort((a, b) => a.size.compareTo(b.size));
      case VaultSort.newest:
        sorted.sort((a, b) => b.modified.compareTo(a.modified));
      case VaultSort.oldest:
        sorted.sort((a, b) => a.modified.compareTo(b.modified));
      case VaultSort.name:
        sorted.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    }
    return sorted;
  }

  Future<void> _delete(Set<String> paths, int bytes) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          paths.length == 1
              ? tr('Delete this file?')
              : tr('Delete ${paths.length} files?'),
        ),
        content: Text(
          tr(
            'This deletes ${paths.length == 1 ? 'it' : 'them'} everywhere on '
            'this phone: from SaveKit and from your gallery. It frees at least '
            '${formatBytes(bytes)} and cannot be undone.',
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
    if (confirmed != true) return;
    final everywhere = await ref
        .read(downloadQueueControllerProvider.notifier)
        .deleteFiles(paths);
    if (!mounted) return;
    setState(() => _selected.removeAll(paths));
    if (!everywhere) {
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
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(storageSnapshotProvider);
    final data = snapshot.value ?? const StorageSnapshot();
    final files = _sorted(data.files);
    // Selections of files that no longer exist are dropped.
    final selected = _selected.intersection({for (final f in files) f.path});
    final selectedBytes = files
        .where((file) => selected.contains(file.path))
        .fold(0, (sum, file) => sum + file.size);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          selected.isEmpty ? tr('Storage') : tr('${selected.length} selected'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (selected.isNotEmpty)
            TextButton(
              onPressed: () => setState(_selected.clear),
              child: Text(tr('Clear')),
            )
          else if (files.isNotEmpty)
            TextButton(
              onPressed: () =>
                  setState(() => _selected.addAll(files.map((f) => f.path))),
              child: Text(tr('Select all')),
            ),
          PopupMenuButton<VaultSort>(
            tooltip: tr('Sort'),
            icon: const Icon(Icons.sort_rounded),
            initialValue: _sort,
            onSelected: (sort) => setState(() => _sort = sort),
            itemBuilder: (_) => [
              for (final sort in VaultSort.values)
                PopupMenuItem(value: sort, child: Text(tr(sort.label))),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton.icon(
                  onPressed: () => _delete(selected, selectedBytes),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  label: Text(
                    tr(
                      'Delete ${selected.length} · ${formatBytes(selectedBytes)}',
                    ),
                  ),
                ),
              ),
            ),
      body: snapshot.isLoading && !snapshot.hasValue
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                _Summary(data: data),
                if (data.leftoverBytes > 0) ...[
                  const SizedBox(height: 10),
                  Card(
                    child: ListTile(
                      leading: Icon(
                        Icons.cleaning_services_outlined,
                        color: AppColors.warning,
                      ),
                      title: Text(tr('Leftover partial files')),
                      subtitle: Text(
                        tr(
                          '${formatBytes(data.leftoverBytes)} from downloads '
                          'that were canceled or removed.',
                        ),
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                      trailing: TextButton(
                        onPressed: () => cleanLeftovers(ref, data),
                        child: Text(tr('Clean up')),
                      ),
                    ),
                  ),
                ],
                if (data.missingTaskIds.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Card(
                    child: ListTile(
                      leading: Icon(
                        Icons.link_off_rounded,
                        color: AppColors.textMuted,
                      ),
                      title: Text(
                        data.missingTaskIds.length == 1
                            ? tr('1 download has no file')
                            : tr(
                                '${data.missingTaskIds.length} downloads have no files',
                              ),
                      ),
                      subtitle: Text(
                        tr(
                          'They were deleted outside SaveKit, for example from '
                          'the gallery.',
                        ),
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                      trailing: TextButton(
                        onPressed: () => ref
                            .read(downloadQueueControllerProvider.notifier)
                            .removeAll(data.missingTaskIds),
                        child: Text(tr('Remove')),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                if (files.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: EmptyState(
                      icon: Icons.folder_open_rounded,
                      title: tr('Nothing stored yet'),
                      message: tr(
                        'Files you download are listed here with their sizes.',
                      ),
                    ),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      tr(
                        '${files.length} FILES · ${tr(_sort.label).toUpperCase()}',
                      ),
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  for (final file in files)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _FileRow(
                        key: ValueKey(file.path),
                        file: file,
                        selected: selected.contains(file.path),
                        onToggle: () => setState(() {
                          if (!_selected.remove(file.path)) {
                            _selected.add(file.path);
                          }
                        }),
                        onDelete: () => _delete({file.path}, file.size),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

/// Colour and label of each kind of file in the usage bar.
({Color color, String label, IconData icon}) _kindStyle(SavedFileKind kind) =>
    switch (kind) {
      SavedFileKind.video => (
        color: AppColors.accent,
        label: tr('Videos'),
        icon: Icons.movie_outlined,
      ),
      SavedFileKind.audio => (
        color: AppColors.success,
        label: tr('Audio'),
        icon: Icons.graphic_eq_rounded,
      ),
      SavedFileKind.image => (
        color: AppColors.warning,
        label: tr('Photos'),
        icon: Icons.image_outlined,
      ),
      SavedFileKind.other => (
        color: AppColors.textMuted,
        label: tr('Other'),
        icon: Icons.insert_drive_file_outlined,
      ),
    };

class _Summary extends StatelessWidget {
  const _Summary({required this.data});

  final StorageSnapshot data;

  @override
  Widget build(BuildContext context) {
    final total = data.totalBytes;
    final kinds = [
      for (final kind in SavedFileKind.values)
        if (data.countOf(kind) > 0) kind,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('USED BY SAVEKIT'),
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              total == 0 ? '0 MB' : formatBytes(total),
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 14),
            // One solid segment per kind of file, sized by its share.
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                height: 10,
                child: total == 0
                    ? ColoredBox(color: AppColors.surfaceHigh)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final kind in kinds)
                            Expanded(
                              flex: (data.bytesOf(kind) * 1000 ~/ total).clamp(
                                1,
                                1000,
                              ),
                              child: ColoredBox(color: _kindStyle(kind).color),
                            ),
                          if (data.leftoverBytes > 0)
                            Expanded(
                              flex: (data.leftoverBytes * 1000 ~/ total).clamp(
                                1,
                                1000,
                              ),
                              child: ColoredBox(color: AppColors.border),
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 14),
            for (final kind in kinds)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _kindStyle(kind).color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${_kindStyle(kind).label} · ${data.countOf(kind)}',
                      ),
                    ),
                    Text(
                      formatBytes(data.bytesOf(kind)),
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
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

class _FileRow extends StatelessWidget {
  const _FileRow({
    super.key,
    required this.file,
    required this.selected,
    required this.onToggle,
    required this.onDelete,
  });

  final StoredFile file;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final style = _kindStyle(file.kind);
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: selected ? AppColors.accent : AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Row(
            children: [
              Checkbox(value: selected, onChanged: (_) => onToggle()),
              MediaThumbnail(
                filePath: file.kind == SavedFileKind.image ? file.path : null,
                width: 44,
                height: 44,
                fallbackIcon: style.icon,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatBytes(file.size),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                tooltip: tr('Delete'),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
