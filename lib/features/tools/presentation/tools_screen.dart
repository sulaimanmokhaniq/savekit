import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../application/storage_controller.dart';
import 'converter_screen.dart';
import 'editor_screen.dart';
import 'stats_screen.dart';
import 'status_saver_screen.dart';
import 'storage_screen.dart';
import '../../../core/l10n/l10n.dart';

/// Tools: the converter, the WhatsApp status saver and the storage manager.
class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storage = ref.watch(storageSnapshotProvider).value;
    final used = storage == null || storage.totalBytes == 0
        ? tr('See what takes up space, sort by size, and delete.')
        : tr(
            '${formatBytes(storage.totalBytes)} used · ${storage.files.length} files',
          );

    return Scaffold(
      appBar: AppBar(title: Text(tr('Tools'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _ToolCard(
            icon: Icons.graphic_eq_rounded,
            title: tr('Video to audio'),
            subtitle: tr('Convert any video on this phone to MP3 or M4A.'),
            onTap: () => _open(context, const ConverterScreen()),
          ),
          const SizedBox(height: 10),
          _ToolCard(
            icon: Icons.movie_edit,
            title: tr('Edit video'),
            subtitle: tr(
              'Split for WhatsApp Status, make vertical, make smaller, '
              'make a GIF or save a photo.',
            ),
            onTap: () => _open(context, const EditorScreen()),
          ),
          const SizedBox(height: 10),
          _ToolCard(
            icon: Icons.chat_bubble_outline_rounded,
            title: tr('WhatsApp statuses'),
            subtitle: tr(
              'Save photos and videos from statuses you have viewed.',
            ),
            onTap: () => _open(context, const StatusSaverScreen()),
          ),
          const SizedBox(height: 10),
          _ToolCard(
            icon: Icons.pie_chart_outline_rounded,
            title: tr('Storage'),
            subtitle: used,
            onTap: () => _open(context, const StorageScreen()),
          ),
          const SizedBox(height: 10),
          _ToolCard(
            icon: Icons.insights_outlined,
            title: tr('Your stats'),
            subtitle: tr('How much you saved, from where, and when.'),
            onTap: () => _open(context, const StatsScreen()),
          ),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
