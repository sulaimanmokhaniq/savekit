import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/l10n/l10n.dart';
import '../core/l10n/material_localizations_ar.dart';
import '../core/settings/app_settings.dart';
import '../core/theme/app_theme.dart';
import 'home_shell.dart';

class SaveKitApp extends ConsumerStatefulWidget {
  const SaveKitApp({super.key});

  @override
  ConsumerState<SaveKitApp> createState() => _SaveKitAppState();
}

class _SaveKitAppState extends ConsumerState<SaveKitApp>
    with WidgetsBindingObserver {
  late AppPalette _palette;
  late Locale _locale;

  Locale _resolveLocale(AppLanguage language) =>
      language.resolve(WidgetsBinding.instance.platformDispatcher.locale);

  @override
  void initState() {
    super.initState();
    _palette = AppPalette.byId(ref.read(settingsControllerProvider).themeId);
    AppColors.current = _palette;
    _locale = _resolveLocale(ref.read(settingsControllerProvider).language);
    L10n.locale = _locale;
    WidgetsBinding.instance.addObserver(this);

    // Bring the home-screen icon in line with the saved theme. Android does
    // nothing when it already matches.
    final settings = ref.read(settingsControllerProvider);
    ref.read(launcherIconProvider)(
      settings.matchIcon ? settings.themeId : AppSettings.defaultThemeId,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The phone's language changed, or was only now reported by Android.
  @override
  void didChangeLocales(List<Locale>? locales) {
    _applyLanguage(ref.read(settingsControllerProvider).language);
  }

  /// Screens read their colours from [AppColors] while building, so a new
  /// theme asks every widget to build again. Nothing is recreated: scroll
  /// positions, the open tab and typed text all stay as they are.
  void _applyTheme(String themeId) {
    final palette = AppPalette.byId(themeId);
    if (palette.id == _palette.id) return;
    AppColors.current = palette;
    setState(() => _palette = palette);
    _rebuildEverything();
  }

  /// Text is translated while building too, so a new language rebuilds every
  /// widget the same way; the layout direction follows the locale.
  void _applyLanguage(AppLanguage language) {
    final locale = _resolveLocale(language);
    if (locale == _locale) return;
    L10n.locale = locale;
    setState(() => _locale = locale);
    _rebuildEverything();
  }

  void _rebuildEverything() {
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
    ref.listen(
      settingsControllerProvider.select((settings) => settings.language),
      (_, language) => _applyLanguage(language),
    );

    return MaterialApp(
      title: 'SaveKit',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(_palette),
      locale: _locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        AppMaterialLocalizationsDelegate(),
        AppCupertinoLocalizationsDelegate(),
        GlobalWidgetsLocalizations.delegate,
      ],
      // Colours switch at once rather than fading through mixed states.
      themeAnimationDuration: Duration.zero,
      home: const HomeShell(),
    );
  }
}
