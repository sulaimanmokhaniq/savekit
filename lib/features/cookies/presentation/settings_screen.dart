import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/engine/engine_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/platform_badge.dart';
import '../application/accounts_controller.dart';
import '../domain/platform_account.dart';
import 'login_webview_screen.dart';

/// Settings & Platform Logins: account cards and the extractor versions.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _login(
    BuildContext context,
    WidgetRef ref,
    PlatformAccount account,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final signedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LoginWebViewScreen(account: account)),
    );
    await ref.read(accountsControllerProvider.notifier).refresh();
    if (signedIn == true) {
      messenger.showSnackBar(
        SnackBar(content: Text('Signed in to ${account.label}.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsControllerProvider);
    final engine = ref.watch(engineControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const _SectionTitle('PLATFORM ACCOUNTS'),
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Log in to save stories, private or age-restricted posts. '
              'Your session stays on this phone.',
              style: TextStyle(color: AppColors.textMuted, height: 1.4),
            ),
          ),
          for (final account in PlatformAccount.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AccountCard(
                account: account,
                signedIn: accounts.value?[account],
                onLogin: () => _login(context, ref, account),
                onLogout: () =>
                    ref.read(accountsControllerProvider.notifier).logout(account),
              ),
            ),
          const SizedBox(height: 18),
          const _SectionTitle('EXTRACTORS'),
          _EngineCard(
            engine: engine,
            onUpdate: () async {
              final messenger = ScaffoldMessenger.of(context);
              final message = await ref
                  .read(engineControllerProvider.notifier)
                  .updateEngine();
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(message)));
            },
            onRetry: () => ref.invalidate(engineControllerProvider),
          ),
          const SizedBox(height: 18),
          const _SectionTitle('STORAGE'),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Photos and videos are copied to the “SaveKit” album in your '
                'gallery, audio to Music/SaveKit. The Vault keeps its own copy '
                'for playback.',
                style: TextStyle(color: AppColors.textMuted, height: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Only download media you have the right to save.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.signedIn,
    required this.onLogin,
    required this.onLogout,
  });

  final PlatformAccount account;

  /// Null while the status is being read.
  final bool? signedIn;
  final VoidCallback onLogin;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final status = signedIn;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            PlatformBadge(account.platform, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: status == true
                              ? AppColors.success
                              : AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          status == null
                              ? 'Checking…'
                              : status
                              ? 'Signed in'
                              : 'Not signed in',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (status == true)
              OutlinedButton(onPressed: onLogout, child: const Text('Log out'))
            else
              FilledButton(
                onPressed: status == null ? null : onLogin,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                child: const Text('Log in'),
              ),
          ],
        ),
      ),
    );
  }
}

class _EngineCard extends StatelessWidget {
  const _EngineCard({
    required this.engine,
    required this.onUpdate,
    required this.onRetry,
  });

  final AsyncValue<EngineState> engine;
  final VoidCallback onUpdate;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: engine.when(
          loading: () => const Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Preparing the engine…'),
            ],
          ),
          error: (error, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'The engine failed to start: $error',
                style: const TextStyle(color: AppColors.danger, height: 1.4),
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
          data: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _VersionRow(
                name: 'yt-dlp',
                detail: 'Video and audio',
                version: state.version,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(),
              ),
              _VersionRow(
                name: 'gallery-dl',
                detail: 'Photos and carousels',
                version: state.galleryVersion,
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: state.isUpdating ? null : onUpdate,
                icon: state.isUpdating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update_alt_rounded, size: 20),
                label: Text(
                  state.isUpdating ? 'Updating…' : 'Update extractors',
                ),
              ),
              if (state.lastUpdateMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  state.lastUpdateMessage!,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: state.lastUpdateFailed
                        ? AppColors.danger
                        : AppColors.textMuted,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                'Update when a site stops working; platforms change often.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.name,
    required this.detail,
    required this.version,
  });

  final String name;
  final String detail;
  final String version;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
        Text(
          version.isEmpty ? 'unavailable' : version,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
