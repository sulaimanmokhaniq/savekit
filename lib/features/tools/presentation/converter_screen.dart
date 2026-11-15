import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../../core/native/device_files_service.dart';
import '../../../core/platform/media_platform.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../downloader/application/download_queue_controller.dart';
import '../../extractor/domain/media_format.dart';
import '../../extractor/domain/media_info.dart';
import '../../../core/l10n/l10n.dart';

/// Queues a conversion of the video at [path] into [audioFormat] ("mp3" or
/// "m4a"). It runs through the normal queue and lands in the Vault.
void enqueueConversion(
  WidgetRef ref, {
  required String path,
  required String title,
  required String audioFormat,
}) {
  final format = MediaFormat(
    id: 'convert_$audioFormat',
    kind: MediaFormatKind.audio,
    label: audioFormat.toUpperCase(),
    engine: DownloadEngineKind.convert,
    formatSelection: 'convert',
    extractAudio: true,
    audioFormat: audioFormat,
    ext: audioFormat,
  );
  ref
      .read(downloadQueueControllerProvider.notifier)
      .enqueue(
        MediaInfo(url: path, title: title, platform: MediaPlatform.device),
        format,
      );
}

/// Converter: pick any video on the phone and turn it into MP3 or M4A, on
/// the device.
class ConverterScreen extends ConsumerStatefulWidget {
  const ConverterScreen({super.key});

  @override
  ConsumerState<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends ConsumerState<ConverterScreen> {
  PickedVideo? _video;
  String _format = 'mp3';
  bool _picking = false;

  Future<void> _pick() async {
    setState(() => _picking = true);
    try {
      final video = await ref.read(deviceFilesServiceProvider).pickVideo();
      if (!mounted) return;
      if (video != null) setState(() => _video = video);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Couldn’t open that video: $error'))),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _convert() {
    final video = _video;
    if (video == null) return;
    enqueueConversion(
      ref,
      path: video.path,
      title: p.basenameWithoutExtension(video.name),
      audioFormat: _format,
    );
    setState(() => _video = null);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            tr('Converting. Follow it in the Queue; it lands in the Vault.'),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Video to audio'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            tr(
              'Turn any video on this phone into an audio file. The conversion '
              'runs on the phone; nothing is uploaded.',
            ),
            style: TextStyle(color: AppColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: video == null
                  ? Column(
                      children: [
                        Icon(
                          Icons.video_file_outlined,
                          size: 40,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          tr('No video chosen'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: _picking ? null : _pick,
                          icon: _picking
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.folder_open_rounded, size: 18),
                          label: Text(
                            _picking ? tr('Opening…') : tr('Choose a video'),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHigh,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.movie_outlined,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                video.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formatBytes(video.size),
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _picking ? null : _pick,
                          child: Text(tr('Change')),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            tr('CONVERT TO'),
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
            children: [
              for (final (id, label) in [
                ('mp3', tr('MP3 · plays everywhere')),
                ('m4a', tr('M4A · smaller file')),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _format == id,
                  onSelected: (_) => setState(() => _format = id),
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: video == null ? null : _convert,
            icon: const Icon(Icons.graphic_eq_rounded, size: 20),
            label: Text(tr('Convert to audio')),
          ),
          const SizedBox(height: 12),
          Text(
            tr(
              'Tip: videos already in your Vault can be converted from the '
              'three-dot menu on each item.',
            ),
            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
