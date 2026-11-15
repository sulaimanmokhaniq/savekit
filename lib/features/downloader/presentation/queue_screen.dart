import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../../core/widgets/media_thumbnail.dart';
import '../../../core/widgets/platform_badge.dart';
import '../application/download_queue_controller.dart';
import '../domain/download_progress.dart';
import '../domain/download_task.dart';

/// Queue & Active Downloads: live progress, with cancel and retry.
class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(activeDownloadsProvider);
    final hasFailed = tasks.any((task) => task.canRetry);
    final hasActive = tasks.any((task) => task.isActive);
    final hasPaused = tasks.any((task) => task.canResume);
    final waitingForWifi = ref.watch(waitingForWifiProvider);
    final controller = ref.read(downloadQueueControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Queue'),
        actions: [
          if (hasActive || hasPaused || hasFailed)
            PopupMenuButton<String>(
              tooltip: 'Queue actions',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (value) => switch (value) {
                'pause' => controller.pauseAll(),
                'resume' => controller.resumeAll(),
                _ => controller.clearFailed(),
              },
              itemBuilder: (_) => [
                if (hasActive)
                  const PopupMenuItem(value: 'pause', child: Text('Pause all')),
                if (hasPaused)
                  const PopupMenuItem(
                    value: 'resume',
                    child: Text('Resume all'),
                  ),
                if (hasFailed)
                  const PopupMenuItem(
                    value: 'clear',
                    child: Text('Clear failed'),
                  ),
              ],
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: tasks.isEmpty
          ? const EmptyState(
              icon: Icons.downloading_rounded,
              title: 'Nothing downloading',
              message:
                  'Downloads you start show up here with live progress. '
                  'Finished ones move to the Vault.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                if (waitingForWifi)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: AppColors.warning),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.wifi_off_rounded,
                            color: AppColors.warning,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Waiting for Wi-Fi. Downloads start when the '
                              'phone is back on Wi-Fi.',
                              style: TextStyle(fontSize: 13, height: 1.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                for (final task in tasks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _TaskCard(key: ValueKey(task.id), task: task),
                  ),
              ],
            ),
    );
  }
}

class _TaskCard extends ConsumerWidget {
  const _TaskCard({super.key, required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(downloadQueueControllerProvider.notifier);
    final failed = task.status == DownloadStatus.failed;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MediaThumbnail(
                  url: task.thumbnail,
                  width: 64,
                  height: 64,
                  fallbackIcon: task.format.isAudio
                      ? Icons.graphic_eq_rounded
                      : task.format.isGallery
                      ? Icons.photo_library_outlined
                      : Icons.movie_outlined,
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
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          PlatformBadge(task.platform, size: 18),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '${task.platform.label} · ${task.format.label}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (task.isActive || task.canResume) ...[
                  IconButton(
                    onPressed: () => task.canResume
                        ? controller.resume(task.id)
                        : controller.pause(task.id),
                    tooltip: task.canResume ? 'Resume' : 'Pause',
                    icon: Icon(
                      task.canResume
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                    ),
                    color: task.canResume
                        ? AppColors.accent
                        : AppColors.textMuted,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed: () => controller.cancel(task.id),
                    tooltip: 'Cancel',
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.textMuted,
                    visualDensity: VisualDensity.compact,
                  ),
                ] else
                  IconButton(
                    onPressed: () => controller.remove(task.id),
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline_rounded),
                    color: AppColors.textMuted,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (task.isActive || task.canResume) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  // Starting has no number yet: show movement, not an empty
                  // bar. A task still waiting its turn stays empty.
                  value: task.status == DownloadStatus.starting
                      ? null
                      : (task.progressPercent / 100).clamp(0.0, 1.0),
                ),
              ),
              const SizedBox(height: 8),
              _ProgressLine(task: task),
            ] else ...[
              Row(
                children: [
                  Icon(
                    failed ? Icons.error_outline_rounded : Icons.block_rounded,
                    size: 16,
                    color: failed ? AppColors.danger : AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      failed ? (task.error ?? 'Download failed') : 'Canceled',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: failed ? AppColors.danger : AppColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => controller.retry(task.id),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final String left;
    final String right;
    switch (task.status) {
      case DownloadStatus.queued:
        left = 'Waiting…';
        right = '';
      case DownloadStatus.paused:
        left = 'Paused';
        right = '${task.progressPercent.round()}%';
      case DownloadStatus.starting:
        left = 'Starting…';
        right = '';
      case DownloadStatus.processing:
        left = 'Finishing…';
        right = '${task.progressPercent.round()}%';
      default:
        left = [
          '${task.progressPercent.round()}%',
          if (task.speed.isNotEmpty) task.speed,
        ].join(' · ');
        right = formatEta(task.eta);
    }
    final style = TextStyle(
      color: AppColors.textMuted,
      fontSize: 12.5,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        Expanded(child: Text(left, style: style)),
        Text(right, style: style),
      ],
    );
  }
}
