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
import '../../../core/errors/friendly_error.dart';
import '../../../core/l10n/l10n.dart';

/// What happened in the picker.
enum FormatPickerResult { queued, openAccounts, openVault }

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
          Text(
            tr('Reading link…'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
    final error = describeError(state.message);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 32),
          const SizedBox(height: 12),
          Text(
            tr('Couldn’t read this link'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            tr(error.message),
            textAlign: TextAlign.center,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textMuted, height: 1.4),
          ),
          if (error.isRewritten) ...[
            const SizedBox(height: 8),
            // The extractor's own words, for anyone reporting the problem.
            Text(
              error.raw,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textMuted.withValues(alpha: 0.7),
                fontSize: 11.5,
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (state.loginRequired || error.loginRequired) ...[
            FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(FormatPickerResult.openAccounts),
              icon: const Icon(Icons.login_rounded, size: 20),
              label: Text(tr('Log in to this platform')),
            ),
            const SizedBox(height: 10),
          ],
          OutlinedButton(
            onPressed: () => ref
                .read(extractionControllerProvider.notifier)
                .fetch(state.url),
            child: Text(tr('Try again')),
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

  /// Section to keep, in seconds; null downloads the whole thing.
  RangeValues? _clip;

  /// Subtitles to embed, as (language, machine-made); null for none.
  (String, bool)? _subtitles;

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

  /// Trimming and subtitles are yt-dlp features for something with a length.
  bool get _canTrim =>
      _tab != _Tab.photos &&
      _selected.engine == DownloadEngineKind.ytdlp &&
      (info.duration ?? 0) >= 4;

  bool get _canAddSubtitles => _tab == _Tab.video && info.hasSubtitles;

  /// With [tonight], the download waits until the phone is charging on Wi-Fi.
  Future<void> _download({bool tonight = false}) async {
    final clip = _canTrim ? _clip : null;
    final subtitles = _canAddSubtitles ? _subtitles : null;
    var format = _selected;
    if (clip != null || subtitles != null) {
      final start = clip?.start.round();
      final end = clip?.end.round();
      format = _selected.withExtras(
        clipStart: start,
        clipEnd: end,
        subtitleLanguage: subtitles?.$1,
        autoSubtitles: subtitles?.$2 ?? false,
        label: clip == null
            ? _selected.label
            : '${_selected.label} · ${formatClock(start!)}–${formatClock(end!)}',
      );
    }
    final queue = ref.read(downloadQueueControllerProvider.notifier);
    final existing = queue.findDuplicate(info, format);
    if (existing != null) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('You already have this')),
          content: Text(
            tr('It is already in your Vault as ${tr(existing.format.label)}.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('again'),
              child: Text(tr('Download again')),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('open'),
              child: Text(tr('Open the Vault')),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (choice == 'open') {
        Navigator.of(context).pop(FormatPickerResult.openVault);
        return;
      }
      if (choice != 'again') return;
    }
    queue.enqueue(info, format, tonight: tonight);
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
                    _Tab.video => tr('Video'),
                    _Tab.photos => tr('Photos'),
                    _Tab.audio => tr('Audio'),
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
                label: _OptionLabel(
                  option: option,
                  selected: option.id == _selected.id,
                ),
                selected: option.id == _selected.id,
                onSelected: (_) => setState(() => _selected = option),
              ),
          ],
        ),
        if (_canTrim) ...[
          const SizedBox(height: 10),
          _TrimControl(
            duration: info.duration!,
            clip: _clip,
            onChanged: (clip) => setState(() => _clip = clip),
          ),
        ],
        if (_canAddSubtitles) ...[
          const SizedBox(height: 4),
          _SubtitleControl(
            info: info,
            selected: _subtitles,
            onChanged: (value) => setState(() => _subtitles = value),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _download,
          icon: const Icon(Icons.download_rounded, size: 20),
          label: Text(
            _canTrim && _clip != null
                ? tr(
                    'Download clip · '
                    '${formatClock((_clip!.end - _clip!.start).round())}',
                  )
                : size.isEmpty
                ? tr('Download')
                : tr('Download · about $size'),
          ),
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () => _download(tonight: true),
          icon: const Icon(Icons.bedtime_outlined, size: 18),
          label: Text(tr('Download tonight · when charging on Wi-Fi')),
        ),
      ],
    );
  }
}

/// A quality chip's text: the quality, with its approximate size beneath
/// when the site reports enough to know it.
class _OptionLabel extends StatelessWidget {
  const _OptionLabel({required this.option, required this.selected});

  final MediaFormat option;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final size = formatBytes(option.fileSize);
    if (size.isEmpty) return Text(tr(option.label));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(tr(option.label)),
        const SizedBox(height: 2),
        Text(
          size,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: selected ? AppColors.onAccent : AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

/// "Trim" switch with a range slider to keep only part of the video.
class _TrimControl extends StatelessWidget {
  const _TrimControl({
    required this.duration,
    required this.clip,
    required this.onChanged,
  });

  /// Full length in seconds.
  final int duration;
  final RangeValues? clip;
  final void Function(RangeValues? clip) onChanged;

  @override
  Widget build(BuildContext context) {
    final range = clip;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.content_cut_rounded,
              size: 18,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                range == null
                    ? tr('Trim')
                    : tr(
                        'Trim · ${formatClock(range.start.round())} to '
                        '${formatClock(range.end.round())}',
                      ),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Switch(
              value: range != null,
              onChanged: (on) =>
                  onChanged(on ? RangeValues(0, duration.toDouble()) : null),
            ),
          ],
        ),
        if (range != null) ...[
          RangeSlider(
            values: range,
            max: duration.toDouble(),
            divisions: duration,
            labels: RangeLabels(
              formatClock(range.start.round()),
              formatClock(range.end.round()),
            ),
            // Keep at least a second between the two handles.
            onChanged: (values) {
              if (values.end - values.start >= 1) onChanged(values);
            },
          ),
          Text(
            tr(
              'Cuts at the nearest clean frame, so the clip can start or end '
              'a few seconds off.',
            ),
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

/// Chooses subtitles to embed in the video, or none.
class _SubtitleControl extends StatelessWidget {
  const _SubtitleControl({
    required this.info,
    required this.selected,
    required this.onChanged,
  });

  final MediaInfo info;
  final (String, bool)? selected;
  final void Function((String, bool)? value) onChanged;

  @override
  Widget build(BuildContext context) {
    final choice = selected;
    final label = choice == null
        ? tr('None')
        : choice.$2
        ? tr('${languageName(choice.$1)} (automatic)')
        : languageName(choice.$1);

    // A menu reports nothing when a null item is picked, so "None" is an
    // empty language.
    return PopupMenuButton<(String, bool)>(
      tooltip: tr('Subtitles'),
      position: PopupMenuPosition.under,
      onSelected: (value) => onChanged(value.$1.isEmpty ? null : value),
      itemBuilder: (_) => [
        PopupMenuItem(value: ('', false), child: Text(tr('None'))),
        for (final language in info.subtitleLanguages)
          PopupMenuItem(
            value: (language, false),
            child: Text(languageName(language)),
          ),
        for (final language in info.autoCaptionLanguages)
          if (!info.subtitleLanguages.contains(language))
            PopupMenuItem(
              value: (language, true),
              child: Text(tr('${languageName(language)} (automatic)')),
            ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.subtitles_outlined,
              size: 18,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr('Subtitles'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: choice == null ? AppColors.textMuted : AppColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
            Icon(Icons.expand_more_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
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
