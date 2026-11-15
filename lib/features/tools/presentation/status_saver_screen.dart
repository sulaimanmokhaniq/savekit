import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/native/device_files_service.dart';
import '../../../core/platform/media_platform.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../../core/widgets/media_thumbnail.dart';
import '../../downloader/application/download_queue_controller.dart';
import '../../extractor/domain/media_format.dart';

/// Whether access to WhatsApp's status folder has been granted.
final statusAccessProvider = FutureProvider<bool>(
  (ref) => ref.watch(deviceFilesServiceProvider).statusFolderGranted(),
);

/// The viewed statuses currently on the phone.
final statusListProvider = FutureProvider<List<WhatsAppStatus>>((ref) async {
  final granted = await ref.watch(statusAccessProvider.future);
  if (!granted) return const [];
  return ref.watch(deviceFilesServiceProvider).listStatuses();
});

/// WhatsApp Status saver. WhatsApp downloads a status to the phone when you
/// view it; after the user grants access to that folder once, this screen
/// lists those files and copies the chosen ones into the Vault and gallery.
class StatusSaverScreen extends ConsumerStatefulWidget {
  const StatusSaverScreen({super.key});

  @override
  ConsumerState<StatusSaverScreen> createState() => _StatusSaverScreenState();
}

class _StatusSaverScreenState extends ConsumerState<StatusSaverScreen> {
  final _selected = <String>{};
  bool _saving = false;

  Future<void> _grant({required bool business}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final granted = await ref
          .read(deviceFilesServiceProvider)
          .grantStatusFolder(business: business);
      if (!granted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Access was not given. Open the “.Statuses” folder and tap '
              '“Use this folder”.',
            ),
          ),
        );
      }
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
    ref.invalidate(statusAccessProvider);
  }

  Future<void> _save(List<WhatsAppStatus> statuses) async {
    final chosen = [
      for (final status in statuses)
        if (_selected.contains(status.uri)) status,
    ];
    if (chosen.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final directory = await ref.read(appPathsProvider).downloadDirectory();
      final paths = await ref.read(deviceFilesServiceProvider).importStatuses([
        for (final status in chosen) status.uri,
      ], directory);
      if (paths.isEmpty) throw Exception('The statuses could not be copied.');

      final videos = chosen.where((status) => status.isVideo).length;
      final photos = chosen.length - videos;
      await ref
          .read(downloadQueueControllerProvider.notifier)
          .addCompleted(
            title: paths.length == 1
                ? 'WhatsApp status'
                : 'WhatsApp statuses (${paths.length})',
            platform: MediaPlatform.whatsapp,
            format: MediaFormat(
              id: 'whatsapp_status',
              kind: videos > 0 && photos == 0
                  ? MediaFormatKind.video
                  : MediaFormatKind.gallery,
              label: paths.length == 1
                  ? (videos == 1 ? 'Video' : 'Photo')
                  : '${paths.length} files',
              itemCount: paths.length,
              imageCount: photos,
              videoCount: videos,
            ),
            filePaths: paths,
          );
      if (!mounted) return;
      setState(_selected.clear);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            paths.length == 1
                ? 'Saved to the Vault and your gallery.'
                : '${paths.length} statuses saved to the Vault and your gallery.',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Couldn’t save: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(statusAccessProvider);
    final statuses = ref.watch(statusListProvider);
    final items = statuses.value ?? const <WhatsAppStatus>[];
    final granted = access.value ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selected.isEmpty
              ? 'WhatsApp statuses'
              : '${_selected.length} selected',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (granted) ...[
            IconButton(
              onPressed: () => ref.invalidate(statusListProvider),
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (_) async {
                await ref.read(deviceFilesServiceProvider).forgetStatusFolder();
                ref.invalidate(statusAccessProvider);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'forget', child: Text('Remove access')),
              ],
            ),
          ],
        ],
      ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _save(items),
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded, size: 20),
                  label: Text(_saving ? 'Saving…' : 'Save ${_selected.length}'),
                ),
              ),
            ),
      body: switch ((access.isLoading && !access.hasValue, granted)) {
        (true, _) => const Center(child: CircularProgressIndicator()),
        (_, false) => _Setup(onGrant: _grant),
        _ when statuses.isLoading && !statuses.hasValue => const Center(
          child: CircularProgressIndicator(),
        ),
        _ when statuses.hasError => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Couldn’t read the statuses',
          message: '${statuses.error}',
        ),
        _ when items.isEmpty => const EmptyState(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'No statuses yet',
          message:
              'Open WhatsApp and view a status first. WhatsApp keeps viewed '
              'statuses for about a day, then they appear here.',
        ),
        _ => GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 160,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.72,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final status = items[index];
            return _StatusTile(
              key: ValueKey(status.uri),
              status: status,
              selected: _selected.contains(status.uri),
              onToggle: () => setState(() {
                if (!_selected.remove(status.uri)) _selected.add(status.uri);
              }),
            );
          },
        ),
      },
    );
  }
}

class _Setup extends StatelessWidget {
  const _Setup({required this.onGrant});

  final void Function({required bool business}) onGrant;

  @override
  Widget build(BuildContext context) {
    Widget step(String number, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              number,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(height: 1.35))),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          'Save photos and videos from statuses you have viewed in WhatsApp. '
          'Android needs your permission to read WhatsApp’s status folder, once.',
          style: TextStyle(color: AppColors.textMuted, height: 1.4),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: Column(
              children: [
                step('1', 'Tap “Give access” below. A folder screen opens.'),
                step('2', 'It should already show the “.Statuses” folder.'),
                step('3', 'Tap “Use this folder”, then “Allow”.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => onGrant(business: false),
          icon: const Icon(Icons.folder_open_rounded, size: 20),
          label: const Text('Give access'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => onGrant(business: true),
          child: const Text('I use WhatsApp Business'),
        ),
        const SizedBox(height: 16),
        Text(
          'Only save statuses you have permission to keep.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }
}

class _StatusTile extends ConsumerStatefulWidget {
  const _StatusTile({
    super.key,
    required this.status,
    required this.selected,
    required this.onToggle,
  });

  final WhatsAppStatus status;
  final bool selected;
  final VoidCallback onToggle;

  @override
  ConsumerState<_StatusTile> createState() => _StatusTileState();
}

class _StatusTileState extends ConsumerState<_StatusTile> {
  late final Future<Uint8List?> _thumbnail = ref
      .read(deviceFilesServiceProvider)
      .statusThumbnail(widget.status.uri);

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    return Material(
      color: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: widget.selected ? AppColors.accent : AppColors.border,
          width: widget.selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onToggle,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: _thumbnail,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes == null) {
                  return Icon(
                    status.isVideo
                        ? Icons.movie_outlined
                        : Icons.image_outlined,
                    color: AppColors.textMuted,
                  );
                }
                return Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                );
              },
            ),
            if (status.isVideo)
              const Center(
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  formatBytes(status.size),
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              ),
            ),
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: widget.selected
                      ? AppColors.accent
                      : Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: widget.selected
                    ? Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: AppColors.onAccent,
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
