import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../features/cookies/presentation/settings_screen.dart';
import '../features/downloader/application/download_queue_controller.dart';
import '../features/downloader/presentation/queue_screen.dart';
import '../features/extractor/application/incoming_link_controller.dart';
import '../features/extractor/presentation/format_picker_sheet.dart';
import '../features/extractor/presentation/home_screen.dart';
import '../features/vault/presentation/vault_screen.dart';

/// The four tabs, and the one place that opens the format picker: for links
/// typed on Home, and for links shared to the app from elsewhere.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _home = 0, _queue = 1, _settings = 3;

  int _tab = _home;
  bool _pickerOpen = false;

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
                onPressed: () => setState(() => _tab = _queue),
              ),
            ),
          );
      case FormatPickerResult.openAccounts:
        setState(() => _tab = _settings);
      case null:
        break;
    }
  }

  void _handleShared(String url) {
    ref.read(incomingLinkControllerProvider.notifier).consumeShared();
    // A share can arrive while another route is on top; bring Home forward.
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => _tab = _home);
    _openPicker(url);
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

    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(onFetch: _openPicker),
          const QueueScreen(),
          const VaultScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF262B38))),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (index) => setState(() => _tab = index),
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
