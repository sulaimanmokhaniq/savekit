import 'dart:ui';

/// One selectable colour theme. Every colour is a flat, solid fill.
class AppPalette {
  const AppPalette({
    required this.id,
    required this.name,
    required this.description,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.accent,
    required this.onAccent,
    required this.text,
    required this.textMuted,
    this.success = const Color(0xFF5FD39A),
    this.danger = const Color(0xFFFF6B6B),
    this.warning = const Color(0xFFFFC46B),
  });

  /// Stored in settings.
  final String id;
  final String name;
  final String description;

  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color border;
  final Color accent;

  /// Text and icons drawn on top of [accent].
  final Color onAccent;
  final Color text;
  final Color textMuted;
  final Color success;
  final Color danger;
  final Color warning;

  static const ember = AppPalette(
    id: 'ember',
    name: 'Ember',
    description: 'Warm black, ember orange',
    background: Color(0xFF100D0B),
    surface: Color(0xFF1A1512),
    surfaceHigh: Color(0xFF241D19),
    border: Color(0xFF30261F),
    accent: Color(0xFFFF6A2B),
    onAccent: Color(0xFF1A0D05),
    text: Color(0xFFF6EFE9),
    textMuted: Color(0xFFA39589),
  );

  static const vault = AppPalette(
    id: 'vault',
    name: 'Vault',
    description: 'Deep green-black, mint',
    background: Color(0xFF090F0D),
    surface: Color(0xFF111916),
    surfaceHigh: Color(0xFF18231F),
    border: Color(0xFF213029),
    accent: Color(0xFF22C98A),
    onAccent: Color(0xFF04160F),
    text: Color(0xFFE9F3EF),
    textMuted: Color(0xFF84978E),
  );

  static const pulse = AppPalette(
    id: 'pulse',
    name: 'Pulse',
    description: 'Ink violet, electric lilac',
    background: Color(0xFF0D0B14),
    surface: Color(0xFF16131F),
    surfaceHigh: Color(0xFF1F1B2C),
    border: Color(0xFF2A2540),
    accent: Color(0xFF8E6CFF),
    onAccent: Color(0xFF0E0820),
    text: Color(0xFFEFEBF8),
    textMuted: Color(0xFF938CAA),
  );

  static const tide = AppPalette(
    id: 'tide',
    name: 'Tide',
    description: 'Midnight navy, aqua',
    background: Color(0xFF070D14),
    surface: Color(0xFF0F1822),
    surfaceHigh: Color(0xFF16222F),
    border: Color(0xFF1F2F40),
    accent: Color(0xFF12B5E5),
    onAccent: Color(0xFF03131B),
    text: Color(0xFFE8F1F8),
    textMuted: Color(0xFF8094A6),
  );

  static const classic = AppPalette(
    id: 'classic',
    name: 'Classic',
    description: 'Blue-grey, soft blue',
    background: Color(0xFF0D0F14),
    surface: Color(0xFF161922),
    surfaceHigh: Color(0xFF1D212C),
    border: Color(0xFF262B38),
    accent: Color(0xFF7C9CFF),
    onAccent: Color(0xFF0B1020),
    text: Color(0xFFE9ECF3),
    textMuted: Color(0xFF8B93A7),
  );

  /// In the order the theme picker shows them.
  static const all = [ember, vault, pulse, tide, classic];

  static const fallback = ember;

  static AppPalette byId(String? id) =>
      all.firstWhere((palette) => palette.id == id, orElse: () => fallback);
}
