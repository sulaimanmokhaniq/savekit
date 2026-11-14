import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/engine/engine_controller.dart';
import '../../../core/platform/media_platform.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/platform_badge.dart';
import '../application/incoming_link_controller.dart';

/// Home / Smart Paste: paste or type a link, or take the one found on the
/// clipboard, and open the format picker for it.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.onFetch});

  /// Opens the format picker for a link.
  final void Function(String url) onFetch;

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
    final url = extractFirstUrl(text);
    if (url == null) {
      _showMessage('There is no link on the clipboard.');
      return;
    }
    _controller.text = url;
    _submit();
  }

  void _submit() {
    final url = extractFirstUrl(_controller.text) ?? _controller.text.trim();
    if (url.isEmpty) {
      _showMessage('Paste a link first.');
      return;
    }
    _focus.unfocus();
    ref.read(incomingLinkControllerProvider.notifier).markHandled(url);
    widget.onFetch(url);
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('SaveKit'),
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
              label: Text(updating ? 'Updating…' : 'Update Engine'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          const Text(
            'Save video, audio and photos',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Paste a link, or share one to SaveKit from any app. '
            'Everything runs on this phone.',
            style: TextStyle(color: AppColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _controller,
            focusNode: _focus,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'https://…',
              prefixIcon: const Icon(
                Icons.link_rounded,
                color: AppColors.textMuted,
              ),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: TextButton.icon(
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: const Text('Paste'),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.search_rounded, size: 20),
            label: const Text('Find media'),
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
          const SizedBox(height: 14),
          _EngineStatus(
            engine: engine,
            onRetry: () => ref.invalidate(engineControllerProvider),
          ),
          const SizedBox(height: 28),
          const Text(
            'WORKS WITH',
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
      child: const Text(
        '+ 1,000 more sites',
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
                    const Text(
                      'Link copied — tap to fetch',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                tooltip: 'Dismiss',
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
    const style = TextStyle(color: AppColors.textMuted, fontSize: 12.5);
    return engine.when(
      loading: () => const Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.8),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Preparing the download engine (first launch takes a moment)…',
              style: style,
            ),
          ),
        ],
      ),
      error: (error, _) => Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Engine failed to start: $error',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
      data: (state) => Row(
        children: [
          const Icon(Icons.check_circle_rounded, size: 15, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Engine ready · yt-dlp ${state.version}',
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
