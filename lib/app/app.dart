import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/settings/app_settings.dart';
import '../core/theme/app_theme.dart';
import 'home_shell.dart';

class SaveKitApp extends ConsumerWidget {
  const SaveKitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeId = ref.watch(
      settingsControllerProvider.select((settings) => settings.themeId),
    );
    final palette = AppPalette.byId(themeId);
    AppColors.current = palette;

    return MaterialApp(
      title: 'SaveKit',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(palette),
      // Screens read their colours while building, so a new theme rebuilds
      // them all. The selected tab lives in a provider and survives this.
      home: KeyedSubtree(key: ValueKey(palette.id), child: const HomeShell()),
    );
  }
}
