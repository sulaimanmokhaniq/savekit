import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/device/device_service.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/platform_badge.dart';
import '../../downloader/domain/download_task.dart';

/// What is known about the post a download came from: its text, author and
/// date, with a way back to the original.
Future<void> showPostDetails(BuildContext context, DownloadTask task) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PostDetails(task: task),
    );

String _date(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

class _PostDetails extends ConsumerWidget {
  const _PostDetails({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caption = task.caption?.trim();
    final link = task.url;
    final canOpen = link.startsWith('https://');
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text(
            task.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              PlatformBadge(task.platform, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [
                    task.uploader ?? tr(task.platform.label),
                    if (task.postedAt != null)
                      tr('Posted ${_date(task.postedAt!)}'),
                    if (task.completedAt != null)
                      tr('Saved ${_date(task.completedAt!)}'),
                  ].join(' · '),
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (caption == null || caption.isEmpty)
            Text(
              tr('This post had no text, or the site did not share it.'),
              style: TextStyle(color: AppColors.textMuted),
            )
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                caption,
                style: const TextStyle(height: 1.5),
              ),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (caption != null && caption.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: caption));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(tr('Text copied'))));
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text(tr('Copy text')),
                ),
              if (canOpen)
                FilledButton.icon(
                  onPressed: () =>
                      ref.read(deviceServiceProvider).openUrl(link),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(tr('Open the original post')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
