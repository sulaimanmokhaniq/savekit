/// Text made comparable for searching: lower case, Arabic written the same
/// way whichever form of a letter was used, and without diacritics, so
/// "الصلاة" finds "الصلاه" and "أحمد" finds "احمد".
String searchable(String text) {
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    // Diacritics (harakat), the dagger alif and the tatweel add nothing.
    if ((rune >= 0x064B && rune <= 0x065F) ||
        rune == 0x0670 ||
        rune == 0x0640) {
      continue;
    }
    buffer.writeCharCode(switch (rune) {
      0x0623 || 0x0625 || 0x0622 || 0x0671 => 0x0627, // أ إ آ ٱ -> ا
      0x0629 => 0x0647, // ة -> ه
      0x0649 => 0x064A, // ى -> ي
      0x0624 => 0x0648, // ؤ -> و
      0x0626 => 0x064A, // ئ -> ي
      _ => rune,
    });
  }
  return buffer.toString();
}

/// Whether every word of [query] appears somewhere in [fields].
bool matchesSearch(String query, Iterable<String?> fields) {
  final words = searchable(query)
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return true;
  final haystack = searchable(fields.whereType<String>().join('\n'));
  return words.every(haystack.contains);
}
