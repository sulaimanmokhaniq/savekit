import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/settings/app_settings.dart';
import '../core/theme/app_theme.dart';
import 'home_shell.dart';

class SaveKitApp extends ConsumerStatefulWidget {
  const SaveKitApp({super.key});

  @override
  ConsumerState<SaveKitApp> createState() => _SaveKitAppState();
}

class _SaveKitAppState extends ConsumerState<SaveKitApp> {
  late AppPalette _palette;

  @override
  void initState() {
    super.initState();
    _palette = AppPalette.byId(ref.read(settingsControllerProvider).themeId);
    AppColors.current = _palette;

    // Bring the home-screen icon in line with the saved theme. Android does
    // nothing when it already matches.
    final settings = ref.read(settingsControllerProvider);
    ref.read(launcherIconProvider)(
      settings.matchIcon ? settings.themeId : AppSettings.defaultThemeId,
    );
  }

  /// Screens read their colours from [AppColors] while building, so a new
  /// theme asks every widget to build again. Nothing is recreated: scroll
  /// positions, the open tab and typed text all stay as they are.
  void _applyTheme(String themeId) {
    final palette = AppPalette.byId(themeId);
    if (palette.id == _palette.id) return;
    AppColors.current = palette;
    setState(() => _palette = palette);
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    context.visitChildElements(rebuild);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      settingsControllerProvider.select((settings) => settings.themeId),
      (_, themeId) => _applyTheme(themeId),
    );

    return MaterialApp(
      title: 'SaveKit',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(_palette),
      // Colours switch at once rather than fading through mixed states.
      themeAnimationDuration: Duration.zero,
      home: const HomeShell(),
    );
  }
}
