import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../../core/widgets/media_thumbnail.dart';
import '../application/space_saver_controller.dart';

/// A small preview of a photo or video on the phone.
final _previewProvider = FutureProvider.autoDispose
    .family<Uint8List?, (String, int)>(
      (ref, key) =>
          ref.watch(spaceServiceProvider).preview(key.$1, size: key.$2),
    );

/// Space saver: finds copies, look-alike photos and large videos anywhere
/// on the phone, and frees the space once the user has looked and agreed.
class SpaceSaverScreen extends ConsumerStatefulWidget {
  const SpaceSaverScreen({super.key});

  @override
  ConsumerState<SpaceSaverScreen> createState() => _SpaceSaverScreenState();
}

class _SpaceSaverScreenState extends ConsumerState<SpaceSaverScreen> {
  /// Files ticked for deletion, by address, in each of the first two tabs.
  final _copies = <String>{};
  final _alike = <String>{};

  /// Videos ticked for re-encoding.
  final _videos = <String>{};
  CompressQuality _quality = CompressQuality.good;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Extra exact copies are safe to remove, so they start ticked.
    ref.listenManual(spaceSaverProvider, (previous, next) {
      if (previous?.phase != SpacePhase.done && next.phase == SpacePhase.done) {
        setState(() {
          _copies
            ..clear()
            ..addAll([
              for (final group in next.scan.duplicates)
                for (final item in group.skip(1)) item.uri,
            ]);
          _alike.clear();
          _videos.clear();
        });
      }
    });
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Ticks or unticks [item], always leaving one file of [group] unticked.
  void _toggle(Set<String> picked, List<PhoneMedia> group, PhoneMedia item) {
    setState(() {
      if (picked.remove(item.uri)) return;
      final others = group.where(
        (other) => other.uri != item.uri && !picked.contains(other.uri),
      );
      if (others.isEmpty) {
        _say(tr('Keep at least one of each group.'));
        return;
      }
      picked.add(item.uri);
    });
  }

  int _bytesOf(Set<String> picked, SpaceScan scan) => scan.items
      .where((item) => picked.contains(item.uri))
      .fold(0, (sum, item) => sum + item.size);

  Future<void> _delete(Set<String> picked, int bytes) async {
    final count = picked.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          count == 1 ? tr('Delete this file?') : tr('Delete $count files?'),
        ),
        content: Text(
          count == 1
              ? tr(
                  'This removes it from the phone and the gallery for good, '
                  'freeing ${formatBytes(bytes)}. Android may ask you to '
                  'confirm.',
                )
              : tr(
                  'This removes them from the phone and the gallery for '
                  'good, freeing ${formatBytes(bytes)}. Android may ask you '
                  'to confirm.',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final uris = {...picked};
    final deleted = await ref.read(spaceSaverProvider.notifier).delete(uris);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (deleted) {
        _copies.removeAll(uris);
        _alike.removeAll(uris);
        _videos.removeAll(uris);
      }
    });
    _say(
      deleted ? tr('Freed ${formatBytes(bytes)}.') : tr('Nothing was deleted.'),
    );
  }

  void _compress(List<PhoneMedia> videos) {
    final queued = ref
        .read(spaceSaverProvider.notifier)
        .compress(videos, _quality);
    setState(_videos.clear);
    _say(
      queued == 0
          ? tr('Nothing to make smaller.')
          : tr(
              'Making $queued smaller. Follow it in the Queue, then come '
              'back here to delete the originals.',
            ),
    );
  }

  void _preview(PhoneMedia item) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Consumer(
                builder: (context, ref, _) {
                  final bytes = ref
                      .watch(_previewProvider((item.uri, 1080)))
                      .value;
                  return bytes == null
                      ? const SizedBox(
                          height: 240,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : Image.memory(bytes, fit: BoxFit.contain);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '${item.name} · ${formatBytes(item.size)}'
                '${item.width > 0 ? ' · ${item.width}×${item.height}' : ''}',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(spaceSaverProvider);
    final controller = ref.read(spaceSaverProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Space saver'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (state.phase == SpacePhase.done)
            IconButton(
              onPressed: controller.start,
              tooltip: tr('Scan again'),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: switch (state.phase) {
        SpacePhase.intro => _Intro(onStart: controller.start),
        SpacePhase.denied => _Intro(
          onStart: controller.start,
          note: tr(
            'SaveKit needs access to your photos and videos to look for '
            'space. Allow it, or turn it on in the phone’s Settings.',
          ),
        ),
        SpacePhase.failed => _Intro(
          onStart: controller.start,
          note: tr('The scan could not finish: ${state.error ?? ''}'),
        ),
        SpacePhase.scanning => _Scanning(
          progress: state.progress,
          onCancel: controller.cancel,
        ),
        SpacePhase.done => _results(state.scan),
      },
    );
  }

  Widget _results(SpaceScan scan) {
    final compressing = ref.watch(compressingUrisProvider);
    final ready = ref.watch(readyOriginalsProvider);
    final readyUris = {for (final entry in ready) entry.original.uri};

    // Videos worth re-encoding at the chosen quality, biggest saving first.
    final plans =
        <(PhoneMedia, CompressPlan)>[
          for (final item in scan.items)
            if (item.isVideo && !readyUris.contains(item.uri))
              if (compressPlanFor(item, _quality) case final plan?)
                (item, plan),
        ]..sort(
          (a, b) => (b.$1.size - b.$2.targetBytes).compareTo(
            a.$1.size - a.$2.targetBytes,
          ),
        );
    final videoSaving = plans.fold(
      0,
      (sum, entry) => sum + entry.$1.size - entry.$2.targetBytes,
    );
    final pickedPlans = [
      for (final entry in plans)
        if (_videos.contains(entry.$1.uri)) entry,
    ];
    final pickedSaving = pickedPlans.fold(
      0,
      (sum, entry) => sum + entry.$1.size - entry.$2.targetBytes,
    );
    final total = scan.duplicateBytes + scan.similarBytes + videoSaving;

    return DefaultTabController(
      length: 3,
      child: Builder(
        builder: (context) {
          final tabs = DefaultTabController.of(context);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: _Headline(bytes: total, files: scan.items.length),
              ),
              TabBar(
                tabs: [
                  Tab(text: tr('Copies (${scan.duplicates.length})')),
                  Tab(text: tr('Look-alikes (${scan.similar.length})')),
                  Tab(text: tr('Videos (${plans.length})')),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _GroupList(
                      groups: scan.duplicates,
                      picked: _copies,
                      keepLabel: tr('Keep'),
                      emptyTitle: tr('No copies found'),
                      emptyMessage: tr(
                        'No photo or video is on this phone twice.',
                      ),
                      onToggle: (group, item) => _toggle(_copies, group, item),
                      onPreview: _preview,
                    ),
                    _GroupList(
                      groups: scan.similar,
                      picked: _alike,
                      keepLabel: tr('Best'),
                      emptyTitle: tr('No look-alikes found'),
                      emptyMessage: tr(
                        'No photos that look nearly the same were found.',
                      ),
                      hint: tr(
                        'Photos taken close together that look nearly the '
                        'same. Tap the ones to delete; hold one to see it '
                        'larger.',
                      ),
                      onToggle: (group, item) => _toggle(_alike, group, item),
                      onPreview: _preview,
                    ),
                    _VideoList(
                      plans: plans,
                      picked: _videos,
                      compressing: compressing,
                      ready: ready,
                      quality: _quality,
                      onQuality: (quality) => setState(() {
                        _quality = quality;
                        _videos.clear();
                      }),
                      onToggle: (video) => setState(() {
                        if (!_videos.remove(video.uri)) _videos.add(video.uri);
                      }),
                      onPreview: _preview,
                      onDeleteOriginals: _busy
                          ? null
                          : () => _delete(
                              readyUris,
                              ready.fold(
                                0,
                                (sum, entry) => sum + entry.original.size,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              AnimatedBuilder(
                animation: tabs,
                builder: (context, _) {
                  final (label, action) = switch (tabs.index) {
                    0 => (
                      _copies.isEmpty
                          ? tr('Tap the files to delete')
                          : tr(
                              'Delete ${_copies.length} · '
                              '${formatBytes(_bytesOf(_copies, scan))}',
                            ),
                      _copies.isEmpty
                          ? null
                          : () => _delete(_copies, _bytesOf(_copies, scan)),
                    ),
                    1 => (
                      _alike.isEmpty
                          ? tr('Tap the files to delete')
                          : tr(
                              'Delete ${_alike.length} · '
                              '${formatBytes(_bytesOf(_alike, scan))}',
                            ),
                      _alike.isEmpty
                          ? null
                          : () => _delete(_alike, _bytesOf(_alike, scan)),
                    ),
                    _ => (
                      pickedPlans.isEmpty
                          ? tr('Tick the videos to make smaller')
                          : tr(
                              'Make ${pickedPlans.length} smaller · saves about '
                              '${formatBytes(pickedSaving)}',
                            ),
                      pickedPlans.isEmpty
                          ? null
                          : () => _compress([
                              for (final entry in pickedPlans) entry.$1,
                            ]),
                    ),
                  };
                  return SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busy ? null : action,
                          child: Text(label),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.onStart, this.note});

  final VoidCallback onStart;

  /// Why the last attempt did not work, when there was one.
  final String? note;

  @override
  Widget build(BuildContext context) {
    Widget point(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.accent, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(
          tr('Find space on this phone'),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          tr(
            'SaveKit looks through all your photos and videos, not only the '
            'ones it saved, and shows what can go.',
          ),
          style: TextStyle(color: AppColors.textMuted, height: 1.4),
        ),
        const SizedBox(height: 22),
        point(
          Icons.content_copy_rounded,
          tr('Copies: the same photo or video stored more than once.'),
        ),
        point(
          Icons.burst_mode_outlined,
          tr('Look-alikes: photos that are nearly the same shot.'),
        ),
        point(
          Icons.compress_rounded,
          tr('Large videos: made smaller, with the saving shown first.'),
        ),
        point(
          Icons.lock_outline_rounded,
          tr(
            'Everything happens on the phone, and nothing is deleted until '
            'you have looked and agreed.',
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 4),
          Text(note!, style: TextStyle(color: AppColors.warning, height: 1.4)),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.search_rounded, size: 20),
          label: Text(tr('Scan my phone')),
        ),
      ],
    );
  }
}

class _Scanning extends StatelessWidget {
  const _Scanning({required this.progress, required this.onCancel});

  final ScanProgress progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final label = switch (progress.stage) {
      'duplicates' => tr('Looking for copies…'),
      'similar' => tr('Comparing photos…'),
      _ => tr('Listing photos and videos…'),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.fraction,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 10),
            if (progress.total > 0)
              Text(
                tr('${progress.done} of ${progress.total}'),
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            const SizedBox(height: 6),
            Text(
              tr('A large gallery can take a few minutes.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 18),
            TextButton(onPressed: onCancel, child: Text(tr('Stop'))),
          ],
        ),
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.bytes, required this.files});

  final int bytes;
  final int files;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bytes <= 0
                ? tr('Nothing to free')
                : tr('Up to ${formatBytes(bytes)} can be freed'),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            tr('$files photos and videos checked'),
            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/// Groups of copies or look-alikes; each file can be ticked for deletion.
class _GroupList extends StatelessWidget {
  const _GroupList({
    required this.groups,
    required this.picked,
    required this.keepLabel,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.onToggle,
    required this.onPreview,
    this.hint,
  });

  final List<List<PhoneMedia>> groups;
  final Set<String> picked;

  /// Shown on the first file of a group while it is not ticked.
  final String keepLabel;
  final String emptyTitle;
  final String emptyMessage;
  final String? hint;
  final void Function(List<PhoneMedia> group, PhoneMedia item) onToggle;
  final void Function(PhoneMedia item) onPreview;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return EmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: emptyTitle,
        message: emptyMessage,
      );
    }
    final lead = hint == null ? 0 : 1;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      itemCount: groups.length + lead,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index < lead) {
          return Text(
            hint!,
            style: TextStyle(color: AppColors.textMuted, height: 1.4),
          );
        }
        final group = groups[index - lead];
        final extra = group.skip(1).fold(0, (sum, item) => sum + item.size);
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('${group.length} files · ${formatBytes(extra)} extra'),
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 104,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: group.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, position) {
                    final item = group[position];
                    final ticked = picked.contains(item.uri);
                    return _Tile(
                      key: ValueKey(item.uri),
                      item: item,
                      ticked: ticked,
                      badge: position == 0 && !ticked ? keepLabel : null,
                      onTap: () => onToggle(group, item),
                      onLongPress: () => onPreview(item),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.item,
    required this.ticked,
    required this.onTap,
    required this.onLongPress,
    this.badge,
  });

  final PhoneMedia item;
  final bool ticked;
  final String? badge;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: ticked,
      label: item.name,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Container(
          width: 104,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(
              color: ticked ? AppColors.danger : AppColors.border,
              width: ticked ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Preview(uri: item.uri, isVideo: item.isVideo),
              if (ticked) ColoredBox(color: AppColors.danger.withAlpha(70)),
              Positioned(
                top: 4,
                right: 4,
                child: Icon(
                  ticked
                      ? Icons.delete_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: ticked ? AppColors.danger : Colors.white,
                  shadows: const [Shadow(blurRadius: 4)],
                ),
              ),
              if (badge != null)
                Positioned(
                  top: 4,
                  left: 4,
                  child: _Chip(text: badge!, color: AppColors.success),
                ),
              Positioned(
                left: 4,
                bottom: 4,
                child: _Chip(text: formatBytes(item.size)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color ?? Colors.black.withAlpha(160),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Preview extends ConsumerWidget {
  const _Preview({required this.uri, required this.isVideo});

  final String uri;
  final bool isVideo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(_previewProvider((uri, 256))).value;
    if (bytes == null) {
      return ColoredBox(
        color: AppColors.surfaceHigh,
        child: Icon(
          isVideo ? Icons.movie_outlined : Icons.image_outlined,
          color: AppColors.textMuted,
        ),
      );
    }
    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => ColoredBox(color: AppColors.surfaceHigh),
    );
  }
}

class _VideoList extends StatelessWidget {
  const _VideoList({
    required this.plans,
    required this.picked,
    required this.compressing,
    required this.ready,
    required this.quality,
    required this.onQuality,
    required this.onToggle,
    required this.onPreview,
    required this.onDeleteOriginals,
  });

  final List<(PhoneMedia, CompressPlan)> plans;
  final Set<String> picked;

  /// Videos whose smaller copy is being made right now.
  final Set<String> compressing;
  final List<ReadyOriginal> ready;
  final CompressQuality quality;
  final void Function(CompressQuality quality) onQuality;
  final void Function(PhoneMedia video) onToggle;
  final void Function(PhoneMedia video) onPreview;
  final VoidCallback? onDeleteOriginals;

  @override
  Widget build(BuildContext context) {
    final readySaving = ready.fold(0, (sum, entry) => sum + entry.savedBytes);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      children: [
        if (ready.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.success),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ready.length == 1
                      ? tr('1 smaller copy is ready')
                      : tr('${ready.length} smaller copies are ready'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(
                    'The copies are in your gallery, in the SaveKit album. '
                    'Check one, then delete the originals to free '
                    '${formatBytes(readySaving)}.',
                  ),
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: onDeleteOriginals,
                  child: Text(tr('Delete the originals')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        SegmentedButton<CompressQuality>(
          segments: [
            ButtonSegment(
              value: CompressQuality.good,
              label: Text(tr('Good quality')),
            ),
            ButtonSegment(
              value: CompressQuality.small,
              label: Text(tr('Smallest')),
            ),
          ],
          selected: {quality},
          showSelectedIcon: false,
          onSelectionChanged: (choice) => onQuality(choice.first),
        ),
        const SizedBox(height: 8),
        Text(
          quality == CompressQuality.good
              ? tr(
                  'Full HD at most. Hard to tell from the original on a '
                  'phone. Originals stay until you delete them.',
                )
              : tr(
                  'HD at most. Much smaller and a little softer. Originals '
                  'stay until you delete them.',
                ),
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        if (plans.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: EmptyState(
              icon: Icons.check_circle_outline_rounded,
              title: tr('No large videos'),
              message: tr('No video would get much smaller.'),
            ),
          ),
        for (final (video, plan) in plans) ...[
          _VideoRow(
            video: video,
            plan: plan,
            ticked: picked.contains(video.uri),
            working: compressing.contains(video.uri),
            onTap: () => onToggle(video),
            onLongPress: () => onPreview(video),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _VideoRow extends StatelessWidget {
  const _VideoRow({
    required this.video,
    required this.plan,
    required this.ticked,
    required this.working,
    required this.onTap,
    required this.onLongPress,
  });

  final PhoneMedia video;
  final CompressPlan plan;
  final bool ticked;
  final bool working;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: ticked ? AppColors.accent : AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: working ? null : onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
          child: Row(
            children: [
              Checkbox(
                value: ticked,
                onChanged: working ? null : (_) => onTap(),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: _Preview(uri: video.uri, isVideo: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      working
                          ? tr('Making a smaller copy…')
                          : tr(
                              '${formatClock(video.duration.inSeconds)} · '
                              '${formatBytes(video.size)} now · about '
                              '${formatBytes(plan.targetBytes)} after',
                            ),
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
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
