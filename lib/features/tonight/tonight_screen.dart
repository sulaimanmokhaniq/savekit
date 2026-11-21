import 'night_alarm.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/errors/friendly_error.dart';
import '../../core/l10n/l10n.dart';
import '../../core/network/connectivity_service.dart';
import '../../core/platform/media_platform.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/media_thumbnail.dart';
import '../../core/widgets/platform_badge.dart';
import '../downloader/application/download_queue_controller.dart';
import '../downloader/domain/download_task.dart';
import 'tonight_controller.dart';

/// Tonight's list: links collected during the day, downloaded by themselves
/// at night, on Wi-Fi, from the time the user chose.
class TonightScreen extends ConsumerWidget {
  const TonightScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final links = ref.watch(tonightProvider);
    final tasks = ref.watch(tonightTasksProvider);
    final settings = ref.watch(settingsControllerProvider);
    final settingsController = ref.read(settingsControllerProvider.notifier);
    final tonight = ref.read(tonightProvider.notifier);
    final queue = ref.read(downloadQueueControllerProvider.notifier);
    final online = ref.watch(onlineProvider).value ?? true;
    final empty = links.isEmpty && tasks.isEmpty;
    final running = tasks.any((task) => task.status.isRunning);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Tonight'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      bottomNavigationBar: empty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: OutlinedButton.icon(
                  onPressed: tonight.downloadAllNow,
                  icon: const Icon(Icons.download_rounded, size: 20),
                  label: Text(tr('Download all now')),
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Text(
            tr(
              'Share links to SaveKit during the day. They download by '
              'themselves tonight, on Wi-Fi, from the time you choose.',
            ),
            style: TextStyle(color: AppColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 14),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: settings.shareToTonight,
                  onChanged: settingsController.setShareToTonight,
                  secondary: Icon(
                    Icons.ios_share_rounded,
                    color: AppColors.textMuted,
                  ),
                  title: Text(tr('Shared links come here')),
                  subtitle: Text(
                    tr(
                      'Sharing a link to SaveKit saves it for tonight, '
                      'without asking for a quality.',
                    ),
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const Divider(height: 1),
                PopupMenuButton<QualityPreference>(
                  tooltip: tr('Quality'),
                  initialValue: settings.tonightQuality,
                  onSelected: settingsController.setTonightQuality,
                  position: PopupMenuPosition.under,
                  itemBuilder: (_) => [
                    for (final quality in QualityPreference.automatic)
                      PopupMenuItem(
                        value: quality,
                        child: Text(tr(quality.label)),
                      ),
                  ],
                  child: ListTile(
                    leading: Icon(
                      Icons.high_quality_outlined,
                      color: AppColors.textMuted,
                    ),
                    title: Text(tr('Quality')),
                    subtitle: Text(
                      tr('For links saved from now on.'),
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tr(settings.tonightQuality.label),
                          style: TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Icon(
                          Icons.expand_more_rounded,
                          color: AppColors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    Icons.schedule_rounded,
                    color: AppColors.textMuted,
                  ),
                  title: Text(tr('Start at')),
                  subtitle: Text(
                    tr(
                      'On Wi-Fi, from this time until morning. The phone '
                      'does not need to be charging.',
                    ),
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                  trailing: Text(
                    formatNightStart(settings.nightStart),
                    style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(
                        hour: settings.nightStart ~/ 60,
                        minute: settings.nightStart % 60,
                      ),
                    );
                    if (picked != null) {
                      settingsController.setNightStart(
                        picked.hour * 60 + picked.minute,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          if (ref.watch(runsInBackgroundProvider).value == false) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.warning),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Let SaveKit run in the background'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr(
                      'When the phone is not charging, Android puts it into '
                      'deep sleep at night and can cut the internet. Allow '
                      'SaveKit to keep running so tonight’s downloads finish.',
                    ),
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () async {
                      await ref.read(backgroundPermissionProvider).request();
                      ref.invalidate(runsInBackgroundProvider);
                    },
                    child: Text(tr('Allow')),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (empty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: EmptyState(
                icon: Icons.bedtime_outlined,
                title: tr('Nothing for tonight yet'),
                message: tr(
                  'In any app, tap Share and choose SaveKit. Or open a link '
                  'here and choose Save for tonight.',
                ),
              ),
            )
          else ...[
            _Status(
              count: links.length + tasks.length,
              running: running,
              online: online,
            ),
            const SizedBox(height: 10),
            for (final task in tasks) ...[
              _TaskRow(task: task, onRemove: () => queue.cancel(task.id)),
              const SizedBox(height: 8),
            ],
            for (final link in links) ...[
              _LinkRow(
                link: link,
                online: online,
                onRemove: () => tonight.remove(link.url),
                onRetry: () => tonight.retry(link.url),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

/// When tonight's downloads will start.
class _Status extends ConsumerWidget {
  const _Status({
    required this.count,
    required this.running,
    required this.online,
  });

  final int count;
  final bool running;
  final bool online;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Icon(
          running ? Icons.downloading_rounded : Icons.bedtime_outlined,
          size: 18,
          color: AppColors.accent,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                running
                    ? tr('Downloading now')
                    : count == 1
                    ? tr('1 waiting')
                    : tr('$count waiting'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (!running)
                Text(
                  online
                      ? nightStartText(ref.watch(settingsControllerProvider))
                      : tr('Links are read once the phone is online'),
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.onRemove});

  final DownloadTask task;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final running = task.status.isRunning;
    return _Row(
      leading: MediaThumbnail(
        url: task.thumbnail,
        width: 52,
        height: 52,
        fallbackIcon: task.format.isAudio
            ? Icons.graphic_eq_rounded
            : Icons.movie_outlined,
      ),
      title: task.title,
      subtitle: Row(
        children: [
          PlatformBadge(task.platform, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              [
                tr(task.format.label),
                if (running) '${task.progressPercent.round()}%',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
            ),
          ),
        ],
      ),
      trailing: IconButton(
        onPressed: onRemove,
        tooltip: tr('Remove'),
        icon: const Icon(Icons.close_rounded),
        color: AppColors.textMuted,
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.link,
    required this.online,
    required this.onRemove,
    required this.onRetry,
  });

  final TonightLink link;
  final bool online;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final platform = MediaPlatform.fromUrl(link.url);
    final error = link.error;
    final String note;
    if (error != null) {
      note = tr(describeError(error).message);
    } else if (link.reading) {
      note = tr('Reading the link…');
    } else if (!online) {
      note = tr('Read once the phone is online');
    } else {
      note = tr('Waiting to be read');
    }
    return _Row(
      leading: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Icon(
          error == null ? Icons.link_rounded : Icons.error_outline_rounded,
          color: error == null ? AppColors.textMuted : AppColors.danger,
        ),
      ),
      title: link.url,
      titleIsLink: true,
      subtitle: Row(
        children: [
          if (platform != MediaPlatform.other) ...[
            PlatformBadge(platform, size: 18),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              note,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: error == null ? AppColors.textMuted : AppColors.danger,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error != null)
            IconButton(
              onPressed: onRetry,
              tooltip: tr('Retry'),
              icon: const Icon(Icons.refresh_rounded),
              color: AppColors.textMuted,
            ),
          IconButton(
            onPressed: onRemove,
            tooltip: tr('Remove'),
            icon: const Icon(Icons.close_rounded),
            color: AppColors.textMuted,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.titleIsLink = false,
  });

  final Widget leading;
  final String title;
  final Widget subtitle;
  final Widget trailing;

  /// Links read left to right in every language.
  final bool titleIsLink;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      title,
      maxLines: titleIsLink ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w700),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: leading,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (titleIsLink)
                  Directionality(textDirection: TextDirection.ltr, child: text)
                else
                  text,
                const SizedBox(height: 4),
                subtitle,
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
