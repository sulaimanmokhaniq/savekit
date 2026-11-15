import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/platform/media_platform.dart';
import '../core/settings/app_settings.dart';
import '../core/theme/app_theme.dart';
import '../features/cookies/presentation/settings_screen.dart';
import '../features/downloader/application/download_queue_controller.dart';
import '../features/downloader/presentation/queue_screen.dart';
import '../features/extractor/application/batch_controller.dart';
import '../features/extractor/application/incoming_link_controller.dart';
import '../features/extractor/presentation/account_screen.dart';
import '../features/extractor/presentation/batch_sheet.dart';
import '../features/extractor/presentation/format_picker_sheet.dart';
import '../features/extractor/presentation/home_screen.dart';
import '../features/tools/presentation/tools_screen.dart';
import '../features/vault/presentation/vault_screen.dart';

/// The four tabs, and the one place that opens the format picker: for links
/// typed on Home, and for links shared to the app from elsewhere.
/// The selected tab. Kept outside the widget so it survives a theme change,
/// which rebuilds the whole shell.
class ShellTabController extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

final shellTabProvider = NotifierProvider<ShellTabController, int>(
  ShellTabController.new,
);

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _home = 0, _queue = 1, _settings = 4;

  bool _pickerOpen = false;

  void _select(int index) => ref.read(shellTabProvider.notifier).select(index);

  Future<void> _openPicker(String url) async {
    if (_pickerOpen) return;
    _pickerOpen = true;
    final result = await showFormatPicker(context, ref, url);
    _pickerOpen = false;
    if (!mounted) return;

    switch (result) {
      case FormatPickerResult.queued:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: const Text('Added to the queue.'),
              action: SnackBarAction(
                label: 'View',
                onPressed: () => _select(_queue),
              ),
            ),
          );
      case FormatPickerResult.openAccounts:
        _select(_settings);
      case null:
        break;
    }
  }

  /// Routes typed or pasted text: several links or a playlist go to the
  /// batch sheet, a single link to the format picker.
  Future<void> _handleInput(String text) async {
    final urls = extractAllUrls(text);
    if (urls.length > 1) {
      await _openBatch(urls: urls);
    } else if (urls.length == 1 && isPlaylistUrl(urls.single)) {
      await _openBatch(playlistUrl: urls.single);
    } else if (urls.length == 1 && isAccountUrl(urls.single)) {
      await _openAccount(urls.single);
    } else {
      await _openPicker(urls.isEmpty ? text.trim() : urls.single);
    }
  }

  Future<void> _openBatch({
    List<String> urls = const [],
    String? playlistUrl,
  }) async {
    if (_pickerOpen) return;
    _pickerOpen = true;
    await showBatchSheet(context, urls: urls, playlistUrl: playlistUrl);
    _pickerOpen = false;
  }

  /// Shows an account's media to choose from.
  Future<void> _openAccount(String url) async {
    if (_pickerOpen) return;
    _pickerOpen = true;
    final count = await Navigator.of(context)
        .push<int>(MaterialPageRoute(builder: (_) => AccountScreen(url: url)));
    _pickerOpen = false;
    if (count == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            count == 1 ? 'Added to the queue.' : '$count items on their way.',
          ),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => _select(_queue),
          ),
        ),
      );
  }

  void _handleShared(String url) {
    ref.read(incomingLinkControllerProvider.notifier).consumeShared();
    // A share can arrive while another route is on top; bring Home forward.
    Navigator.of(context).popUntil((route) => route.isFirst);
    _select(_home);

    if (isPlaylistUrl(url)) {
      _openBatch(playlistUrl: url);
      return;
    }
    if (isAccountUrl(url)) {
      _openAccount(url);
      return;
    }
    // One-tap download: queue at the saved quality without asking. The Home
    // banner shows the outcome, and offers the picker if the link fails.
    final oneTap = ref.read(settingsControllerProvider).oneTap;
    if (oneTap == QualityPreference.ask) {
      _openPicker(url);
    } else {
      ref.read(batchControllerProvider.notifier).start([url], oneTap);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A link shared from another app opens the picker straight away.
    ref.listen(incomingLinkControllerProvider.select((links) => links.shared), (
      _,
      shared,
    ) {
      if (shared != null) _handleShared(shared);
    });

    final activeCount = ref.watch(activeDownloadCountProvider);
    final tab = ref.watch(shellTabProvider);

    return Scaffold(
      body: IndexedStack(
        index: tab,
        children: [
          HomeScreen(onFetch: _handleInput),
          const QueueScreen(),
          const VaultScreen(),
          const ToolsScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: _select,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: activeCount > 0,
                label: Text('$activeCount'),
                child: const Icon(Icons.downloading_rounded),
              ),
              label: 'Queue',
            ),
            const NavigationDestination(
              icon: Icon(Icons.video_library_outlined),
              selectedIcon: Icon(Icons.video_library_rounded),
              label: 'Vault',
            ),
            const NavigationDestination(
              icon: Icon(Icons.handyman_outlined),
              selectedIcon: Icon(Icons.handyman_rounded),
              label: 'Tools',
            ),
            const NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
