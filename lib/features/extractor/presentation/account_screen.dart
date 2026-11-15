import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/native/youtube_dl_native_service.dart';
import '../../../core/platform/media_platform.dart';
import '../../../core/providers.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/media_thumbnail.dart';
import '../../../core/widgets/platform_badge.dart';
import '../../downloader/application/download_queue_controller.dart';
import '../application/batch_controller.dart';
import '../domain/media_format.dart';
import '../domain/media_info.dart';
import '../../../core/l10n/l10n.dart';

enum _Filter { all, photos, videos }

/// An account's recent media as a grid: choose some, or all, and download
/// them. Opened when a profile or channel link is pasted or shared.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key, required this.url});

  /// The account's page, as pasted.
  final String url;

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  /// Posts listed per page. Listing is the slow part, and asking a platform
  /// for a whole account at once is what gets sessions rate-limited.
  static const pageSize = 100;

  /// Selections above this get a warning on platforms that need a login.
  static const largeSelection = 50;

  final _items = <AccountItem>[];
  final _selected = <String>{};
  _Filter _filter = _Filter.all;
  String? _title;
  String? _error;
  bool _loading = true;
  bool _hasMore = false;

  MediaPlatform get _platform => MediaPlatform.fromUrl(widget.url);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cookies = await ref.read(cookieExportServiceProvider).exportAll();
      final page = await ref
          .read(nativeServiceProvider)
          .getAccountMedia(
            accountMediaUrl(widget.url),
            cookiesFilePath: cookies,
            start: _items.length + 1,
            count: pageSize,
          );
      if (!mounted) return;
      setState(() {
        final known = {for (final item in _items) item.url};
        _items.addAll(page.items.where((item) => known.add(item.url)));
        _title ??= page.title;
        _hasMore = page.hasMore && page.items.isNotEmpty;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  List<AccountItem> get _visible => switch (_filter) {
    _Filter.all => _items,
    _Filter.photos => [
      for (final item in _items)
        if (!item.isVideo) item,
    ],
    _Filter.videos => [
      for (final item in _items)
        if (item.isVideo) item,
    ],
  };

  void _toggle(AccountItem item) => setState(() {
    if (!_selected.remove(item.url)) _selected.add(item.url);
  });

  Future<void> _download() async {
    final chosen = [
      for (final item in _items)
        if (_selected.contains(item.url)) item,
    ];
    if (chosen.isEmpty) return;

    // Platforms that need a login watch for bulk activity.
    if (chosen.length > largeSelection && _platform != MediaPlatform.youtube) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('Download ${chosen.length} items?')),
          content: Text(
            tr(
              'Downloading this many at once from ${_platform.label} can get '
              'your account temporarily limited. Smaller batches are safer.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr('Download anyway')),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    final name = _title ?? _platform.label;
    // Files with a direct address are fetched as one download.
    final direct = [
      for (final item in chosen)
        if (!item.needsExtractor) item,
    ];
    if (direct.isNotEmpty) {
      final videos = direct.where((item) => item.isVideo).length;
      ref
          .read(downloadQueueControllerProvider.notifier)
          .enqueue(
            MediaInfo(
              url: widget.url,
              title: direct.length == 1
                  ? (direct.single.title ?? name)
                  : tr('$name · ${direct.length} files'),
              platform: _platform,
              uploader: _title,
              thumbnail: direct
                  .map((item) => item.thumbnail)
                  .firstWhere((t) => t != null, orElse: () => null),
            ),
            MediaFormat(
              id: 'account',
              kind: MediaFormatKind.gallery,
              label: direct.length == 1
                  ? (videos == 1 ? tr('Video') : tr('Photo'))
                  : tr('${direct.length} files'),
              engine: DownloadEngineKind.direct,
              itemCount: direct.length,
              imageCount: direct.length - videos,
              videoCount: videos,
              directUrls: [for (final item in direct) item.url],
              referer: widget.url,
            ),
          );
    }

    // Videos given as post pages are looked up one by one, like a playlist.
    final pages = [
      for (final item in chosen)
        if (item.needsExtractor) item.url,
    ];
    if (pages.isNotEmpty) {
      final saved = ref.read(settingsControllerProvider).oneTap;
      ref
          .read(batchControllerProvider.notifier)
          .start(
            pages,
            saved == QualityPreference.ask ? QualityPreference.best : saved,
          );
    }

    if (!mounted) return;
    Navigator.of(context).pop(chosen.length);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final hasPhotos = _items.any((item) => !item.isVideo);
    final hasVideos = _items.any((item) => item.isVideo);
    final allVisibleSelected =
        visible.isNotEmpty &&
        visible.every((item) => _selected.contains(item.url));

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            PlatformBadge(_platform, size: 26),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                _selected.isEmpty
                    ? (_title ?? tr('Account'))
                    : tr('${_selected.length} selected'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (visible.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                final urls = visible.map((item) => item.url);
                allVisibleSelected
                    ? _selected.removeAll(urls)
                    : _selected.addAll(urls);
              }),
              child: Text(allVisibleSelected ? tr('Clear') : tr('Select all')),
            ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton.icon(
                  onPressed: _download,
                  icon: const Icon(Icons.download_rounded, size: 20),
                  label: Text(tr('Download ${_selected.length}')),
                ),
              ),
            ),
      body: _items.isEmpty
          ? _loading
                ? const _Loading()
                : EmptyState(
                    icon: _error == null
                        ? Icons.photo_library_outlined
                        : Icons.error_outline_rounded,
                    title: _error == null
                        ? tr('Nothing to show')
                        : tr('Couldn’t read this account'),
                    message:
                        _error ??
                        tr(
                          'No photos or videos were found. If the account is '
                          'private, log in under Settings → Platform '
                          'Accounts.',
                        ),
                  )
          : CustomScrollView(
              slivers: [
                if (hasPhotos && hasVideos)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (final (filter, label) in [
                            (_Filter.all, tr('All')),
                            (_Filter.photos, tr('Photos')),
                            (_Filter.videos, tr('Videos')),
                          ])
                            ChoiceChip(
                              label: Text(label),
                              selected: _filter == filter,
                              onSelected: (_) =>
                                  setState(() => _filter = filter),
                            ),
                        ],
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 140,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      return _ItemTile(
                        key: ValueKey(item.url),
                        item: item,
                        selected: _selected.contains(item.url),
                        onTap: () => _toggle(item),
                      );
                    },
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    child: _loading
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : _error != null
                        ? Text(
                            tr('Couldn’t load more: $_error'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.danger),
                          )
                        : _hasMore
                        ? OutlinedButton(
                            onPressed: _load,
                            child: Text(tr('Load more')),
                          )
                        : Text(
                            tr('${_items.length} items · that’s everything'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12.5,
                            ),
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(
              tr('Reading the account…'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              tr('Listing recent posts can take a minute.'),
              style: TextStyle(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AccountItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      label: item.title ?? (item.isVideo ? tr('Video') : tr('Photo')),
      child: Material(
        color: AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(
            color: selected ? AppColors.accent : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MediaThumbnail(
                url: item.thumbnail,
                radius: 0,
                fallbackIcon: item.isVideo
                    ? Icons.movie_outlined
                    : Icons.image_outlined,
              ),
              if (item.isVideo)
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.accent
                        : Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: selected
                      ? Icon(
                          Icons.check_rounded,
                          size: 15,
                          color: AppColors.onAccent,
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
