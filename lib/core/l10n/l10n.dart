import 'dart:ui';

import 'strings_ar.dart';

/// The language the app's own text is shown in.
enum AppLanguage {
  /// Follow the phone: Arabic when the phone is set to Arabic, else English.
  system('system', 'Phone language'),
  english('en', 'English'),
  arabic('ar', 'العربية');

  const AppLanguage(this.id, this.label);

  final String id;

  /// Shown as is in every language, so each can be recognised.
  final String label;

  static AppLanguage fromId(String? id) =>
      values.firstWhere((value) => value.id == id, orElse: () => system);

  /// The locale this choice means on a phone set to [phone].
  Locale resolve(Locale phone) => switch (this) {
    AppLanguage.english => const Locale('en'),
    AppLanguage.arabic => const Locale('ar'),
    AppLanguage.system =>
      phone.languageCode == 'ar' ? const Locale('ar') : const Locale('en'),
  };
}

/// The app's text is written in English in the code and translated on the
/// way to the screen by [tr]. `SaveKitApp` sets the language.
abstract final class L10n {
  static Locale _locale = const Locale('en');
  static final _cache = <String, String>{};
  static List<(RegExp, String)>? _templates;

  static Locale get locale => _locale;
  static bool get isArabic => _locale.languageCode == 'ar';

  static set locale(Locale value) {
    _locale = value;
    _cache.clear();
  }

  /// Arabic text with placeholders, matched against text whose values have
  /// already been filled in ("3 selected" matches "{} selected").
  static List<(RegExp, String)> get _arabicTemplates {
    final cached = _templates;
    if (cached != null) return cached;
    final entries = [
      for (final entry in arabicStrings.entries)
        if (entry.key.contains('{}')) entry,
    ];
    // The template with the most fixed text wins, so "Save · {}" is tried
    // before "Save {}".
    int fixed(String key) => key.replaceAll('{}', '').length;
    entries.sort((a, b) => fixed(b.key).compareTo(fixed(a.key)));
    return _templates = [
      for (final entry in entries)
        (
          RegExp(
            '^${entry.key.split('{}').map(RegExp.escape).join('(.+?)')}\$',
            dotAll: true,
          ),
          entry.value,
        ),
    ];
  }

  static String _translate(String text, int depth) {
    final exact = arabicStrings[text];
    if (exact != null) return exact;
    if (depth > 3) return text;

    for (final (pattern, arabic) in _arabicTemplates) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;
      // The filled-in values may be translatable themselves ("this link").
      var index = 0;
      return arabic.replaceAllMapped('{}', (_) {
        index++;
        return _translate(match.group(index) ?? '', depth + 1);
      });
    }

    // "1080p · 148 MB", "TikTok · Photos (4)": translate each part.
    if (text.contains(' · ')) {
      return text
          .split(' · ')
          .map((part) => _translate(part, depth + 1))
          .join(' · ');
    }
    return text;
  }
}

/// [text] in the app's language. English text is returned as is; so is
/// anything without a translation, such as titles and extractor messages.
String tr(String text) {
  if (!L10n.isArabic || text.isEmpty) return text;
  final cached = L10n._cache[text];
  if (cached != null) return cached;
  final translated = L10n._translate(text, 0);
  if (L10n._cache.length > 2000) L10n._cache.clear();
  return L10n._cache[text] = translated;
}
