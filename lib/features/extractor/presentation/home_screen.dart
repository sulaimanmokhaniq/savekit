import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/engine/engine_controller.dart';
import '../../../core/platform/media_platform.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/platform_badge.dart';
import '../../../core/widgets/savekit_logo.dart';
import '../application/batch_controller.dart';
import '../application/incoming_link_controller.dart';
import '../../../core/errors/friendly_error.dart';
import '../../../core/l10n/l10n.dart';

/// Home / Smart Paste: paste or type a link, or take the one found on the
/// clipboard, and open the format picker for it.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.onFetch});

  /// Handles what was typed or pasted: one link opens the format picker,
  /// several links or a playlist open the batch sheet.
  final void Function(String text) onFetch;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (!mounted) return;
    final urls = extractAllUrls(text);
    if (urls.isEmpty) {
      _showMessage(tr('There is no link on the clipboard.'));
      return;
    }
    _controller.text = urls.join('\n');
    _submit();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _showMessage(tr('Paste a link first.'));
      return;
    }
    _focus.unfocus();
    final links = ref.read(incomingLinkControllerProvider.notifier);
    extractAllUrls(text).forEach(links.markHandled);
    widget.onFetch(text);
  }

  void _useClipboardLink(String url) {
    ref.read(incomingLinkControllerProvider.notifier).dismissClipboard();
    _controller.text = url;
    widget.onFetch(url);
  }

  Future<void> _updateEngine() async {
    final message = await ref
        .read(engineControllerProvider.notifier)
        .updateEngine();
    if (mounted) _showMessage(message);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final engine = ref.watch(engineControllerProvider);
    final clipboardLink = ref.watch(
      incomingLinkControllerProvider.select((links) => links.clipboard),
    );
    final updating = engine.value?.isUpdating ?? false;
    final batch = ref.watch(batchControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const SaveKitLogo(size: 30),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                tr('SaveKit'),
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton.icon(
              onPressed: engine.hasValue && !updating ? _updateEngine : null,
              icon: updating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.system_update_alt_rounded, size: 18),
              label: Text(updating ? tr('Updating…') : tr('Update Engine')),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Text(
            tr('Save video, audio and photos'),
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              'Paste one link or several, or share one to SaveKit from any '
              'app. Everything runs on this phone.',
            ),
            style: TextStyle(color: AppColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _controller,
            focusNode: _focus,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            // Links read left to right in every language.
            textDirection: TextDirection.ltr,
            // Grows to show several pasted links.
            minLines: 1,
            maxLines: 4,
            autocorrect: false,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'https://…',
              hintTextDirection: TextDirection.ltr,
              prefixIcon: Icon(Icons.link_rounded, color: AppColors.textMuted),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: TextButton.icon(
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: Text(tr('Paste')),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.search_rounded, size: 20),
            label: Text(tr('Find media')),
          ),
          if (clipboardLink != null) ...[
            const SizedBox(height: 14),
            _ClipboardBanner(
              url: clipboardLink,
              onUse: () => _useClipboardLink(clipboardLink),
              onDismiss: ref
                  .read(incomingLinkControllerProvider.notifier)
                  .dismissClipboard,
            ),
          ],
          if (!batch.isEmpty) ...[
            const SizedBox(height: 14),
            _BatchBanner(
              batch: batch,
              onCancel: ref.read(batchControllerProvider.notifier).cancel,
              onDismiss: ref.read(batchControllerProvider.notifier).dismiss,
              onOpenFailure: (url) {
                ref.read(batchControllerProvider.notifier).removeFailure(url);
                widget.onFetch(url);
              },
            ),
          ],
          const SizedBox(height: 14),
          _EngineStatus(
            engine: engine,
            onRetry: () => ref.invalidate(engineControllerProvider),
          ),
          const SizedBox(height: 28),
          Text(
            tr('WORKS WITH'),
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final platform in MediaPlatform.featured)
                PlatformPill(platform),
              const _MorePill(),
            ],
          ),
        ],
      ),
    );
  }
}

class _MorePill extends StatelessWidget {
  const _MorePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        tr('+ 1,000 more sites'),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

class _ClipboardBanner extends StatelessWidget {
  const _ClipboardBanner({
    required this.url,
    required this.onUse,
    required this.onDismiss,
  });

  final String url;
  final VoidCallback onUse;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: AppColors.accent.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onUse,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              PlatformBadge(MediaPlatform.fromUrl(url), size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('Link copied — tap to fetch'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                tooltip: tr('Dismiss'),
                icon: const Icon(Icons.close_rounded, size: 20),
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EngineStatus extends StatelessWidget {
  const _EngineStatus({required this.engine, required this.onRetry});

  final AsyncValue<EngineState> engine;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: AppColors.textMuted, fontSize: 12.5);
    return engine.when(
      loading: () => Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.8),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr(
                'Preparing the download engine (first launch takes a moment)…',
              ),
              style: style,
            ),
          ),
        ],
      ),
      error: (error, _) => Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr('Engine failed to start: $error'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(tr('Retry'))),
        ],
      ),
      data: (state) => Row(
        children: [
          Icon(Icons.check_circle_rounded, size: 15, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr('Engine ready · yt-dlp ${state.version}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

/// Progress and outcome of a batch, playlist or one-tap download.
class _BatchBanner extends StatelessWidget {
  const _BatchBanner({
    required this.batch,
    required this.onCancel,
    required this.onDismiss,
    required this.onOpenFailure,
  });

  final BatchState batch;
  final VoidCallback onCancel;
  final VoidCallback onDismiss;
  final void Function(String url) onOpenFailure;

  @override
  Widget build(BuildContext context) {
    final failures = batch.failures;
    final String title;
    if (batch.running) {
      title = batch.total == 1
          ? tr('Reading link…')
          : tr('Reading link ${batch.done + 1} of ${batch.total}…');
    } else if (failures.isEmpty) {
      title = batch.queued == 1
          ? tr('Added to the queue')
          : tr('${batch.queued} downloads added to the queue');
    } else {
      title = batch.queued == 0
          ? tr(
              'Couldn’t read ${failures.length == 1 ? 'this link' : 'these links'}',
            )
          : tr('${batch.queued} added · ${failures.length} couldn’t be read');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (batch.running)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    failures.isEmpty
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    size: 18,
                    color: failures.isEmpty
                        ? AppColors.success
                        : AppColors.danger,
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (batch.running)
                  TextButton(onPressed: onCancel, child: Text(tr('Stop')))
                else
                  IconButton(
                    onPressed: onDismiss,
                    tooltip: tr('Dismiss'),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AppColors.textMuted,
                  ),
              ],
            ),
            if (batch.running && batch.total > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 6, 10, 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    value: batch.done / batch.total,
                  ),
                ),
              ),
            for (final failure in failures.take(3))
              InkWell(
                onTap: () => onOpenFailure(failure.url),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 6, 10, 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              failure.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                            Text(
                              tr(describeError(failure.message).message),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        tr('Open'),
                        style: TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (failures.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  tr('and ${failures.length - 3} more'),
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
