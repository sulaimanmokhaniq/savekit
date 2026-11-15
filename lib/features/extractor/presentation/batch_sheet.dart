import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/native/youtube_dl_native_service.dart';
import '../../../core/providers.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../application/batch_controller.dart';
import '../../../core/l10n/l10n.dart';

/// Asks for one quality and queues several links at once: either [urls]
/// pasted together, or every video of the playlist at [playlistUrl].
/// Resolves to true when a batch was started.
Future<bool> showBatchSheet(
  BuildContext context, {
  List<String> urls = const [],
  String? playlistUrl,
}) async {
  final started = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _BatchSheet(urls: urls, playlistUrl: playlistUrl),
  );
  return started ?? false;
}

class _BatchSheet extends ConsumerStatefulWidget {
  const _BatchSheet({required this.urls, required this.playlistUrl});

  final List<String> urls;
  final String? playlistUrl;

  @override
  ConsumerState<_BatchSheet> createState() => _BatchSheetState();
}

class _BatchSheetState extends ConsumerState<_BatchSheet> {
  late QualityPreference _quality;
  Future<PlaylistInfo>? _playlist;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(settingsControllerProvider).oneTap;
    _quality = saved == QualityPreference.ask ? QualityPreference.best : saved;
    final playlistUrl = widget.playlistUrl;
    if (playlistUrl != null) _playlist = _loadPlaylist(playlistUrl);
  }

  Future<PlaylistInfo> _loadPlaylist(String url) async {
    final cookies = await ref.read(cookieExportServiceProvider).exportAll();
    return ref
        .read(nativeServiceProvider)
        .getPlaylistInfo(url, cookiesFilePath: cookies);
  }

  void _start(List<String> urls) {
    // Not awaited: the batch reports its progress on the Home screen.
    ref.read(batchControllerProvider.notifier).start(urls, _quality);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final playlist = _playlist;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: playlist == null
          ? _body(
              title: tr('${widget.urls.length} links'),
              subtitle: tr('Each one is looked up and added to the queue.'),
              urls: widget.urls,
            )
          : FutureBuilder<PlaylistInfo>(
              future: playlist,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _Message(
                    icon: Icons.error_outline_rounded,
                    color: AppColors.danger,
                    title: tr('Couldn’t read this playlist'),
                    message: snapshot.error.toString(),
                  );
                }
                final info = snapshot.data;
                if (info == null) {
                  return _Message(
                    icon: null,
                    color: AppColors.accent,
                    title: tr('Reading playlist…'),
                    message: widget.playlistUrl ?? '',
                  );
                }
                if (info.entries.isEmpty) {
                  return _Message(
                    icon: Icons.playlist_remove_rounded,
                    color: AppColors.textMuted,
                    title: tr('This playlist is empty'),
                    message: info.title,
                  );
                }
                return _body(
                  title: info.title,
                  subtitle: [
                    tr('${info.entries.length} videos'),
                    if (info.uploader != null) info.uploader!,
                  ].join(' · '),
                  urls: [for (final entry in info.entries) entry.url],
                  preview: [for (final entry in info.entries) entry.title],
                );
              },
            ),
    );
  }

  Widget _body({
    required String title,
    required String subtitle,
    required List<String> urls,
    List<String>? preview,
  }) {
    final lines = preview ?? urls;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.playlist_play_rounded, color: AppColors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 132),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: AppColors.border),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: lines.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '${index + 1}.  ${lines[index]}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          tr('DOWNLOAD AS'),
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final quality in QualityPreference.automatic)
              ChoiceChip(
                label: Text(tr(quality.label)),
                selected: quality == _quality,
                onSelected: (_) => setState(() => _quality = quality),
              ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => _start(urls),
          icon: const Icon(Icons.download_rounded, size: 20),
          label: Text(tr('Download all (${urls.length})')),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  /// Null shows a spinner instead.
  final IconData? icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon == null)
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            )
          else
            Icon(icon, color: color, size: 32),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
