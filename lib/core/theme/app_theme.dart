import 'package:material_ui/material_ui.dart';

import 'app_palette.dart';

export 'app_palette.dart';

/// The colours of the theme currently in use. Widgets read these while
/// building; `SaveKitApp` rebuilds the whole tree when the theme changes.
abstract final class AppColors {
  /// Set by `SaveKitApp` from the user's saved choice.
  static AppPalette current = AppPalette.fallback;

  static Color get background => current.background;
  static Color get surface => current.surface;
  static Color get surfaceHigh => current.surfaceHigh;
  static Color get border => current.border;
  static Color get accent => current.accent;
  static Color get onAccent => current.onAccent;
  static Color get text => current.text;
  static Color get textMuted => current.textMuted;
  static Color get success => current.success;
  static Color get danger => current.danger;
  static Color get warning => current.warning;
}

abstract final class AppRadius {
  /// Cards, sheets and inputs: a rounded square, not a pill.
  static const card = 14.0;
  static const control = 10.0;
}

ThemeData buildAppTheme(AppPalette palette) {
  final scheme = ColorScheme.dark(
    primary: palette.accent,
    onPrimary: palette.onAccent,
    secondary: palette.accent,
    onSecondary: palette.onAccent,
    surface: palette.surface,
    onSurface: palette.text,
    onSurfaceVariant: palette.textMuted,
    surfaceContainerHighest: palette.surfaceHigh,
    outline: palette.border,
    outlineVariant: palette.border,
    error: palette.danger,
    onError: palette.onAccent,
  );

  final cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.card),
    side: BorderSide(color: palette.border),
  );
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.control),
  );
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.card),
    borderSide: BorderSide(color: palette.border),
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.background,
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: palette.text,
      displayColor: palette.text,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      // Derived from the theme's own style so the platform font is kept.
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: palette.text,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: cardShape,
    ),
    dividerTheme: DividerThemeData(color: palette.border, space: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.background,
      surfaceTintColor: Colors.transparent,
      indicatorColor: palette.surfaceHigh,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? palette.text
              : palette.textMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? palette.accent
              : palette.textMuted,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surface,
      hintStyle: TextStyle(color: palette.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: palette.accent, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 50),
        shape: controlShape,
        textStyle: base.textTheme.labelLarge?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        foregroundColor: palette.text,
        side: BorderSide(color: palette.border),
        shape: controlShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: controlShape),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: palette.surface,
      selectedColor: palette.accent,
      checkmarkColor: palette.onAccent,
      showCheckmark: false,
      side: BorderSide(color: palette.border),
      shape: controlShape,
      labelStyle: base.textTheme.labelLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: palette.text,
      ),
      secondaryLabelStyle: base.textTheme.labelLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: palette.onAccent,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: palette.border,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: cardShape,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: palette.surfaceHigh,
      contentTextStyle: TextStyle(color: palette.text),
      actionTextColor: palette.accent,
      shape: cardShape,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: palette.accent,
      linearTrackColor: palette.surfaceHigh,
      circularTrackColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: palette.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      shape: cardShape,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(controlShape),
        side: WidgetStatePropertyAll(BorderSide(color: palette.border)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.surfaceHigh
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.text
              : palette.textMuted,
        ),
      ),
    ),
  );
}
