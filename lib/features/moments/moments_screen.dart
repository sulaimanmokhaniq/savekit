import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/l10n/l10n.dart';
import '../../core/platform/media_platform.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/formatters.dart';
import '../../core/widgets/media_thumbnail.dart';
import '../downloader/application/download_queue_controller.dart';
import '../downloader/data/gallery_export_service.dart';
import '../downloader/domain/download_task.dart';
import '../extractor/domain/media_format.dart';
import '../extractor/domain/media_info.dart';
import '../player/audio_player_screen.dart';
import '../vault/presentation/media_viewer_screen.dart';
import 'moments_controller.dart';

/// Every moment marked in saved videos and audio, grouped by file: tap one
/// to play from there, edit its note, or save it as a short clip.
class MomentsScreen extends ConsumerWidget {
  const MomentsScreen({super.key});

  void _open(BuildContext context, Moment moment, DownloadTask task) {
    final audio = savedFileKindOf(moment.path) == SavedFileKind.audio;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => audio
            ? AudioPlayerScreen(
                startPath: moment.path,
                startAt: moment.position,
              )
            : MediaViewerScreen(
                task: task,
                initialPath: moment.path,
                startAt: moment.position,
                onShare: (path) =>
                    SharePlus.instance.share(ShareParams(files: [XFile(path)])),
                onDelete: () async => false,
              ),
      ),
    );
  }

  Future<void> _editNote(
    BuildContext context,
    WidgetRef ref,
    Moment moment,
  ) async {
    final note = TextEditingController(text: moment.note);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Note')),
        content: TextField(
          controller: note,
          autofocus: true,
          maxLength: 120,
          onSubmitted: (_) => Navigator.of(context).pop(true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Save')),
          ),
        ],
      ),
    );
    if (saved == true) {
      ref.read(momentsProvider.notifier).editNote(moment.id, note.text);
    }
    note.dispose();
  }

  Future<void> _makeClip(
    BuildContext context,
    WidgetRef ref,
    Moment moment,
    DownloadTask task,
  ) async {
    final seconds = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                tr('Clip length, from this moment'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final length in const [15, 30, 60])
              ListTile(
                leading: const Icon(Icons.content_cut_rounded),
                title: Text(tr('$length seconds')),
                onTap: () => Navigator.of(context).pop(length),
              ),
          ],
        ),
      ),
    );
    if (seconds == null || !context.mounted) return;
    final audio = savedFileKindOf(moment.path) == SavedFileKind.audio;
    final start = moment.position.inMilliseconds / 1000;
    ref
        .read(downloadQueueControllerProvider.notifier)
        .enqueue(
          MediaInfo(
            url: moment.path,
            title: moment.note.isEmpty
                ? '${task.title} · ${formatClock(moment.position.inSeconds)}'
                : moment.note,
            platform: MediaPlatform.device,
          ),
          MediaFormat(
            id: 'edit_clip',
            kind: audio ? MediaFormatKind.audio : MediaFormatKind.video,
            label: 'Clip · $seconds s',
            engine: DownloadEngineKind.edit,
            formatSelection: 'clip',
            options: {'start': start.toStringAsFixed(2), 'length': '$seconds'},
          ),
        );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            tr('Making the clip. It lands in the Vault, ready to share.'),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moments = ref.watch(vaultMomentsProvider);
    // Grouped by file, in the order the newest moment of each was marked.
    final groups = <String, List<(Moment, DownloadTask)>>{};
    for (final entry in moments) {
      groups.putIfAbsent(entry.$1.path, () => []).add(entry);
    }
    for (final group in groups.values) {
      group.sort((a, b) => a.$1.position.compareTo(b.$1.position));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Moments'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      body: groups.isEmpty
          ? EmptyState(
              icon: Icons.bookmark_border_rounded,
              title: tr('No moments yet'),
              message: tr(
                'While a video or audio plays, tap the bookmark button to '
                'mark the moment, with a note if you like.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                for (final group in groups.values) ...[
                  _FileHeader(task: group.first.$2, path: group.first.$1.path),
                  const SizedBox(height: 6),
                  for (final (moment, task) in group)
                    _MomentRow(
                      moment: moment,
                      onOpen: () => _open(context, moment, task),
                      onEdit: () => _editNote(context, ref, moment),
                      onClip: () => _makeClip(context, ref, moment, task),
                      onDelete: () =>
                          ref.read(momentsProvider.notifier).remove(moment.id),
                    ),
                  const SizedBox(height: 18),
                ],
              ],
            ),
    );
  }
}

class _FileHeader extends StatelessWidget {
  const _FileHeader({required this.task, required this.path});

  final DownloadTask task;
  final String path;

  @override
  Widget build(BuildContext context) {
    final audio = savedFileKindOf(path) == SavedFileKind.audio;
    return Row(
      children: [
        MediaThumbnail(
          url: task.thumbnail,
          width: 40,
          height: 40,
          fallbackIcon: audio ? Icons.graphic_eq_rounded : Icons.movie_outlined,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            task.filePaths.length > 1
                ? '${task.title} · ${p.basename(path)}'
                : task.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _MomentRow extends StatelessWidget {
  const _MomentRow({
    required this.moment,
    required this.onOpen,
    required this.onEdit,
    required this.onClip,
    required this.onDelete,
  });

  final Moment moment;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onClip;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    formatClock(moment.position.inSeconds),
                    style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    moment.note.isEmpty ? tr('No note') : moment.note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: moment.note.isEmpty
                          ? AppColors.textMuted
                          : AppColors.text,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: tr('More'),
                  onSelected: (value) => switch (value) {
                    'edit' => onEdit(),
                    'clip' => onClip(),
                    _ => onDelete(),
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'edit', child: Text(tr('Edit note'))),
                    PopupMenuItem(
                      value: 'clip',
                      child: Text(tr('Save as a clip')),
                    ),
                    PopupMenuItem(value: 'delete', child: Text(tr('Delete'))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
