import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/l10n/l10n.dart';
import '../core/l10n/material_localizations_ar.dart';
import '../core/settings/app_settings.dart';
import '../core/theme/app_theme.dart';
import '../features/onboarding/welcome_screen.dart';
import '../features/disguise/calculator_screen.dart';
import 'home_shell.dart';
import 'opening_splash.dart';

class SaveKitApp extends ConsumerStatefulWidget {
  const SaveKitApp({super.key});

  @override
  ConsumerState<SaveKitApp> createState() => _SaveKitAppState();
}

class _SaveKitAppState extends ConsumerState<SaveKitApp>
    with WidgetsBindingObserver {
  late AppPalette _palette;
  late Locale _locale;

  /// Whether the opening logo animation is still showing.
  bool _opening = true;

  late final AppLifecycleListener _lifecycle;
  DateTime? _hiddenAt;

  /// Disguised, the app goes back to the calculator after a minute away. A
  /// shorter absence, such as picking a file, keeps it open.
  void _relockIfAway() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    if (hiddenAt == null || !ref.read(settingsControllerProvider).disguised) {
      return;
    }
    if (DateTime.now().difference(hiddenAt) > const Duration(minutes: 1)) {
      ref.read(disguiseUnlockedProvider.notifier).lock();
    }
  }

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

    // Bring the home-screen icon in line with the saved choice. Android does
    // nothing when it already matches.
    final settings = ref.read(settingsControllerProvider);
    ref.read(launcherIconProvider)(settings.launcherIconId);
    // And the next launch's splash with the theme.
    ref.read(splashThemeProvider)(settings.splashId);
    if (settings.disguised) {
      ref.read(taskLabelProvider)('Calculator');
      // A calculator opens without SaveKit's logo.
      _opening = false;
    }
    _lifecycle = AppLifecycleListener(
      onHide: () => _hiddenAt = DateTime.now(),
      onShow: _relockIfAway,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lifecycle.dispose();
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
    final onboarded = ref.watch(
      settingsControllerProvider.select((settings) => settings.onboarded),
    );
    final locked =
        ref.watch(
          settingsControllerProvider.select((settings) => settings.disguised),
        ) &&
        !ref.watch(disguiseUnlockedProvider);

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
      home: locked
          ? const CalculatorScreen()
          : onboarded
          ? const HomeShell()
          : const WelcomeScreen(),
      builder: (context, child) => Stack(
        children: [
          ?child,
          if (_opening)
            Positioned.fill(
              child: OpeningSplash(
                palette: _palette,
                onDone: () => setState(() => _opening = false),
              ),
            ),
        ],
      ),
    );
  }
}
