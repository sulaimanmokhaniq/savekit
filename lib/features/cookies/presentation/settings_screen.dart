import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/engine/engine_controller.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/platform_badge.dart';
import '../../../core/widgets/savekit_logo.dart';
import '../../vault/application/vault_lock.dart';
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

  /// Turning the lock on or off itself needs a successful unlock, so the
  /// setting cannot be changed by someone who merely holds the phone.
  Future<void> _setVaultLock(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final lock = ref.read(vaultLockServiceProvider);
    if (!await lock.isAvailable()) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Set up a screen lock or fingerprint on this phone first.',
          ),
        ),
      );
      return;
    }
    final confirmed = await lock.authenticate(
      enabled
          ? 'Confirm to lock the Vault'
          : 'Confirm to remove the Vault lock',
    );
    if (!confirmed) return;
    ref.read(settingsControllerProvider.notifier).setLockVault(enabled);
    // Enabling it should not immediately lock the user out of this session.
    if (enabled) ref.read(vaultUnlockedProvider.notifier).unlock();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsControllerProvider);
    final engine = ref.watch(engineControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final settingsController = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const _SectionTitle('THEME'),
          _ThemePicker(
            selectedId: settings.themeId,
            onSelect: settingsController.setTheme,
          ),
          const SizedBox(height: 10),
          Card(
            child: SwitchListTile(
              value: settings.matchIcon,
              onChanged: settingsController.setMatchIcon,
              secondary: Icon(Icons.apps_rounded, color: AppColors.textMuted),
              title: const Text('Match the app icon'),
              subtitle: Text(
                'The icon on your home screen takes the theme’s colour. '
                'It can take a few seconds to change.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
              ),
            ),
          ),
          const SizedBox(height: 22),
          const _SectionTitle('DOWNLOADS'),
          Card(
            child: Column(
              children: [
                _ChoiceRow<QualityPreference>(
                  icon: Icons.bolt_rounded,
                  title: 'One-tap download',
                  subtitle:
                      'Quality used when you share a link to SaveKit, '
                      'skipping the picker.',
                  value: settings.oneTap,
                  values: QualityPreference.values,
                  labelOf: (value) => value.label,
                  onChanged: settingsController.setOneTap,
                ),
                const Divider(),
                SwitchListTile(
                  value: settings.wifiOnly,
                  onChanged: settingsController.setWifiOnly,
                  secondary: Icon(
                    Icons.wifi_rounded,
                    color: AppColors.textMuted,
                  ),
                  title: const Text('Wi-Fi only'),
                  subtitle: Text(
                    'Downloads wait until the phone is on Wi-Fi.',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const Divider(),
                _ChoiceRow<int>(
                  icon: Icons.layers_outlined,
                  title: 'Downloads at once',
                  subtitle: 'More is faster on a good connection.',
                  value: settings.maxConcurrent,
                  values: const [1, 2, 3, 4, 5],
                  labelOf: (value) => '$value',
                  onChanged: settingsController.setMaxConcurrent,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const _SectionTitle('PRIVACY'),
          Card(
            child: SwitchListTile(
              value: settings.lockVault,
              onChanged: (value) => _setVaultLock(context, ref, value),
              secondary: Icon(
                Icons.fingerprint_rounded,
                color: AppColors.textMuted,
              ),
              title: const Text('Lock the Vault'),
              subtitle: Text(
                'Ask for fingerprint, face or screen lock to open it.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
              ),
            ),
          ),
          const SizedBox(height: 22),
          const _SectionTitle('PLATFORM ACCOUNTS'),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
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
                onLogout: () => ref
                    .read(accountsControllerProvider.notifier)
                    .logout(account),
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
          const SizedBox(height: 10),
          Card(
            child: SwitchListTile(
              value: settings.autoUpdate,
              onChanged: settingsController.setAutoUpdate,
              secondary: Icon(
                Icons.autorenew_rounded,
                color: AppColors.textMuted,
              ),
              title: const Text('Update automatically'),
              subtitle: Text(
                settings.lastEngineUpdate == null
                    ? 'Checks once a week when you open the app.'
                    : 'Checks once a week. Last checked '
                          '${_daysAgo(settings.lastEngineUpdate!)}.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const _SectionTitle('STORAGE'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Photos and videos also appear in your gallery under “SaveKit”, '
                'and audio in Music/SaveKit. Deleting a download in SaveKit '
                'deletes it from the gallery too, so the space is really freed.',
                style: TextStyle(color: AppColors.textMuted, height: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
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
        style: TextStyle(
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
                          style: TextStyle(
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
                style: TextStyle(color: AppColors.danger, height: 1.4),
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
              Text(
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
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
              ),
            ],
          ),
        ),
        Text(
          version.isEmpty ? 'unavailable' : version,
          style: TextStyle(
            color: AppColors.textMuted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

String _daysAgo(DateTime when) {
  final days = DateTime.now().difference(when).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  return '$days days ago';
}

/// The selectable colour themes, each previewed with its own colours.
class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.selectedId, required this.onSelect});

  final String selectedId;
  final void Function(String id) onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: AppPalette.all.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final palette = AppPalette.all[index];
          final selected = palette.id == selectedId;
          return Semantics(
            button: true,
            selected: selected,
            label: '${palette.name} theme',
            child: InkWell(
              onTap: () => onSelect(palette.id),
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Container(
                width: 104,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.background,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: selected ? palette.accent : palette.border,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SaveKitLogo(size: 26, palette: palette),
                        const Spacer(),
                        if (selected)
                          Icon(
                            Icons.check_circle_rounded,
                            size: 20,
                            color: palette.accent,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // A miniature card and progress bar in the theme's colours.
                    Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: palette.border),
                      ),
                      alignment: Alignment.center,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: 0.62,
                          minHeight: 5,
                          color: palette.accent,
                          backgroundColor: palette.surfaceHigh,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      palette.name,
                      style: TextStyle(
                        color: palette.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A settings row whose value is picked from a short list in a menu.
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final T value;
  final List<T> values;
  final String Function(T value) labelOf;
  final void Function(T value) onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: title,
      initialValue: value,
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      itemBuilder: (_) => [
        for (final option in values)
          PopupMenuItem(value: option, child: Text(labelOf(option))),
      ],
      child: ListTile(
        leading: Icon(icon, color: AppColors.textMuted),
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              labelOf(value),
              style: TextStyle(
                color: AppColors.accent,
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
