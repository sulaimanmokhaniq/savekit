import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/platform/media_platform.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../../core/widgets/media_thumbnail.dart';
import '../../../core/widgets/platform_badge.dart';
import '../../downloader/application/download_queue_controller.dart';
import '../../downloader/domain/download_progress.dart';
import '../../downloader/domain/download_task.dart';
import '../../extractor/domain/media_format.dart';

/// Totals over every finished download still in the Vault.
class DownloadStats {
  DownloadStats(List<DownloadTask> tasks, {DateTime? now})
    : this._([
        for (final task in tasks)
          if (task.status == DownloadStatus.completed) task,
      ], now ?? DateTime.now());

  DownloadStats._(this.tasks, DateTime now)
    : count = tasks.length,
      bytes = tasks.fold(0, (sum, task) => sum + (task.fileSize ?? 0)),
      byPlatform = _group(tasks, (task) => task.platform),
      byKind = _group(tasks, (task) => _kindOf(task.format.kind)),
      byMonth = _months(tasks, now);

  final List<DownloadTask> tasks;
  final int count;
  final int bytes;

  /// (count, bytes) per platform, largest first.
  final List<(MediaPlatform, int, int)> byPlatform;
  final List<(String, int, int)> byKind;

  /// (month start, count) for the last six months, oldest first.
  final List<(DateTime, int)> byMonth;

  static String _kindOf(MediaFormatKind kind) => switch (kind) {
    MediaFormatKind.audio => 'Audio',
    MediaFormatKind.gallery => 'Photos',
    _ => 'Videos',
  };

  static List<(K, int, int)> _group<K>(
    List<DownloadTask> tasks,
    K Function(DownloadTask) keyOf,
  ) {
    final counts = <K, int>{};
    final sizes = <K, int>{};
    for (final task in tasks) {
      final key = keyOf(task);
      counts[key] = (counts[key] ?? 0) + 1;
      sizes[key] = (sizes[key] ?? 0) + (task.fileSize ?? 0);
    }
    final rows = [
      for (final key in counts.keys) (key, counts[key]!, sizes[key]!),
    ];
    rows.sort((a, b) => b.$2.compareTo(a.$2));
    return rows;
  }

  static List<(DateTime, int)> _months(List<DownloadTask> tasks, DateTime now) {
    final months = [
      for (var back = 5; back >= 0; back--)
        DateTime(now.year, now.month - back),
    ];
    return [
      for (final month in months)
        (
          month,
          tasks.where((task) {
            final when = task.completedAt ?? task.createdAt;
            return when.year == month.year && when.month == month.month;
          }).length,
        ),
    ];
  }
}

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Your stats": how much you saved, from where, and when.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = DownloadStats(ref.watch(downloadQueueControllerProvider));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Your stats'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      body: stats.count == 0
          ? EmptyState(
              icon: Icons.insights_outlined,
              title: tr('Nothing yet'),
              message: tr('Your stats appear here once you have downloads.'),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Number(
                        value: '${stats.count}',
                        label: tr('Downloads'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Number(
                        value: formatBytes(stats.bytes).isEmpty
                            ? '0 MB'
                            : formatBytes(stats.bytes),
                        label: tr('Saved'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _Title(tr('LAST SIX MONTHS')),
                _MonthBars(months: stats.byMonth),
                const SizedBox(height: 22),
                _Title(tr('BY PLATFORM')),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        for (final (platform, count, bytes) in stats.byPlatform)
                          _Bar(
                            leading: PlatformBadge(platform, size: 24),
                            label: tr(platform.label),
                            count: count,
                            max: stats.byPlatform.first.$2,
                            detail: formatBytes(bytes),
                            color: platformStyle(platform).color,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _Title(tr('BY TYPE')),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        for (final (kind, count, bytes) in stats.byKind)
                          _Bar(
                            leading: Icon(
                              switch (kind) {
                                'Audio' => Icons.graphic_eq_rounded,
                                'Photos' => Icons.image_outlined,
                                _ => Icons.movie_outlined,
                              },
                              size: 22,
                              color: AppColors.textMuted,
                            ),
                            label: tr(kind),
                            count: count,
                            max: stats.byKind.first.$2,
                            detail: formatBytes(bytes),
                            color: AppColors.accent,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: TextStyle(
        color: AppColors.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    ),
  );
}

class _Number extends StatelessWidget {
  const _Number({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.accent,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: AppColors.textMuted)),
        ],
      ),
    ),
  );
}

/// One solid bar with its count, scaled against [max].
class _Bar extends StatelessWidget {
  const _Bar({
    required this.leading,
    required this.label,
    required this.count,
    required this.max,
    required this.detail,
    required this.color,
  });

  final Widget leading;
  final String label;
  final int count;
  final int max;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        leading,
        const SizedBox(width: 10),
        SizedBox(
          width: 86,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: max == 0 ? 0 : count / max,
              minHeight: 10,
              color: color,
              backgroundColor: AppColors.surfaceHigh,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 74,
          child: Text(
            detail.isEmpty ? '$count' : '$count · $detail',
            textAlign: TextAlign.end,
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

/// A column per month, in the accent colour.
class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.months});

  final List<(DateTime, int)> months;

  @override
  Widget build(BuildContext context) {
    final highest = months.fold(
      0,
      (top, month) => month.$2 > top ? month.$2 : top,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
        child: SizedBox(
          height: 150,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (month, count) in months)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '$count',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 22,
                        height: highest == 0 ? 2 : 2 + 92 * count / highest,
                        decoration: BoxDecoration(
                          color: count == 0
                              ? AppColors.surfaceHigh
                              : AppColors.accent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tr(_monthNames[month.month - 1]),
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
