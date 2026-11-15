import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../../core/widgets/media_thumbnail.dart';
import '../../../core/widgets/platform_badge.dart';
import '../../downloader/application/download_queue_controller.dart';
import '../application/extraction_controller.dart';
import '../domain/media_format.dart';
import '../domain/media_info.dart';

/// What happened in the picker.
enum FormatPickerResult { queued, openAccounts }

/// Looks up [url] and shows the format picker for it. Resolves to
/// [FormatPickerResult.queued] when a download was added,
/// [FormatPickerResult.openAccounts] when the user chose to sign in, and null
/// when the sheet was dismissed.
Future<FormatPickerResult?> showFormatPicker(
  BuildContext context,
  WidgetRef ref,
  String url,
) async {
  final controller = ref.read(extractionControllerProvider.notifier);
  // Not awaited: the sheet shows the lookup's progress.
  controller.fetch(url);
  final result = await showModalBottomSheet<FormatPickerResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const FormatPickerSheet(),
  );
  controller.clear();
  return result;
}

class FormatPickerSheet extends ConsumerWidget {
  const FormatPickerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(extractionControllerProvider);
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: switch (state) {
          ExtractionIdle() => const SizedBox(height: 120),
          ExtractionLoading(:final url) => _Loading(url: url),
          ExtractionFailed() => _Failed(state: state),
          ExtractionLoaded(:final info) => _Picker(info: info),
        },
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          const SizedBox(height: 18),
          const Text(
            'Reading link…',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _Failed extends ConsumerWidget {
  const _Failed({required this.state});

  final ExtractionFailed state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 32),
          const SizedBox(height: 12),
          const Text(
            'Couldn’t read this link',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            state.message,
            textAlign: TextAlign.center,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 20),
          if (state.loginRequired) ...[
            FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(FormatPickerResult.openAccounts),
              icon: const Icon(Icons.login_rounded, size: 20),
              label: const Text('Log in to this platform'),
            ),
            const SizedBox(height: 10),
          ],
          OutlinedButton(
            onPressed: () => ref
                .read(extractionControllerProvider.notifier)
                .fetch(state.url),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

enum _Tab { video, photos, audio }

class _Picker extends ConsumerStatefulWidget {
  const _Picker({required this.info});

  final MediaInfo info;

  @override
  ConsumerState<_Picker> createState() => _PickerState();
}

class _PickerState extends ConsumerState<_Picker> {
  late _Tab _tab;
  late MediaFormat _selected;

  MediaInfo get info => widget.info;

  List<MediaFormat> _optionsOf(_Tab tab) => switch (tab) {
    _Tab.video => [?info.noWatermarkOption, ...info.videoOptions],
    _Tab.photos => [?info.galleryOption],
    _Tab.audio => info.audioOptions,
  };

  List<_Tab> get _tabs => [
    for (final tab in _Tab.values)
      if (_optionsOf(tab).isNotEmpty) tab,
  ];

  @override
  void initState() {
    super.initState();
    _selected = info.defaultOption!;
    _tab = _tabs.firstWhere((tab) => _optionsOf(tab).contains(_selected));
  }

  void _selectTab(_Tab tab) => setState(() {
    _tab = tab;
    _selected = _optionsOf(tab).first;
  });

  void _download() {
    ref.read(downloadQueueControllerProvider.notifier).enqueue(info, _selected);
    Navigator.of(context).pop(FormatPickerResult.queued);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    final options = _optionsOf(_tab);
    final size = formatBytes(_selected.fileSize);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(info: info),
        const SizedBox(height: 18),
        if (tabs.length > 1) ...[
          SegmentedButton<_Tab>(
            showSelectedIcon: false,
            segments: [
              for (final tab in tabs)
                ButtonSegment(
                  value: tab,
                  label: Text(switch (tab) {
                    _Tab.video => 'Video',
                    _Tab.photos => 'Photos',
                    _Tab.audio => 'Audio',
                  }),
                  icon: Icon(switch (tab) {
                    _Tab.video => Icons.videocam_outlined,
                    _Tab.photos => Icons.photo_library_outlined,
                    _Tab.audio => Icons.graphic_eq_rounded,
                  }, size: 18),
                ),
            ],
            selected: {_tab},
            onSelectionChanged: (selection) => _selectTab(selection.first),
          ),
          const SizedBox(height: 16),
        ],
        if (_tab == _Tab.photos && info.galleryItems.isNotEmpty) ...[
          _GalleryStrip(items: info.galleryItems),
          const SizedBox(height: 14),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              ChoiceChip(
                label: Text(option.label),
                selected: option.id == _selected.id,
                onSelected: (_) => setState(() => _selected = option),
              ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _download,
          icon: const Icon(Icons.download_rounded, size: 20),
          label: Text(size.isEmpty ? 'Download' : 'Download · about $size'),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.info});

  final MediaInfo info;

  @override
  Widget build(BuildContext context) {
    final duration = formatDuration(info.duration);
    final details = [
      info.platform.label,
      if (info.uploader != null) info.uploader!,
    ].join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            MediaThumbnail(
              url: info.thumbnail,
              width: 112,
              height: 84,
              fallbackIcon: info.hasVideo
                  ? Icons.movie_outlined
                  : Icons.image_outlined,
            ),
            if (duration.isNotEmpty)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    duration,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                info.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  PlatformBadge(info.platform, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GalleryStrip extends StatelessWidget {
  const _GalleryStrip({required this.items});

  final List<GalleryItem> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          return Stack(
            alignment: Alignment.center,
            children: [
              MediaThumbnail(
                url: item.thumbnail,
                width: 76,
                height: 76,
                fallbackIcon: item.isVideo
                    ? Icons.movie_outlined
                    : Icons.image_outlined,
              ),
              if (item.isVideo && item.thumbnail != null)
                const Icon(Icons.play_circle_fill_rounded, color: Colors.white),
            ],
          );
        },
      ),
    );
  }
}
