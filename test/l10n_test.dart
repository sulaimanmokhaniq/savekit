import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:savekit/core/l10n/l10n.dart';
import 'package:savekit/core/l10n/strings_ar.dart';

void main() {
  tearDown(() => L10n.locale = const Locale('en'));

  test('English text is returned untouched', () {
    expect(tr('Queue'), 'Queue');
    expect(tr('3 selected'), '3 selected');
  });

  group('Arabic', () {
    setUp(() => L10n.locale = const Locale('ar'));

    test('translates fixed text', () {
      expect(tr('Queue'), 'قائمة التنزيل');
      expect(tr('Delete this download?'), 'حذف هذا التنزيل؟');
    });

    test('translates text with values filled in', () {
      expect(tr('3 selected'), 'تم تحديد 3');
      expect(tr('Reading link 2 of 5…'), 'جارٍ قراءة الرابط 2 من 5…');
      expect(tr('Trim · 0:10 to 0:35'), 'قص · من 0:10 إلى 0:35');
    });

    test('translates the values themselves when they are app text', () {
      expect(tr('Couldn’t read this link'), 'تعذّرت قراءة هذا الرابط');
      expect(tr('Arabic (automatic)'), 'العربية (تلقائية)');
    });

    test('prefers the more specific of two matching templates', () {
      expect(tr('Save · 1.4 MB'), 'حفظ · 1.4 MB');
      expect(tr('Save 2'), 'حفظ 2');
      expect(tr('Download all (3)'), 'تنزيل الكل (3)');
      expect(tr('Download 4'), 'تنزيل 4');
    });

    test('translates each part of a dotted line', () {
      expect(tr('This phone · MP3'), 'هذا الهاتف · MP3');
      expect(tr('Photos (4) · 3.0 MB'), 'الصور (4) · 3.0 MB');
    });

    test('leaves titles and unknown text alone', () {
      expect(tr('Golden hour timelapse'), 'Golden hour timelapse');
      expect(tr('ERROR: Video unavailable'), 'ERROR: Video unavailable');
      expect(tr(''), '');
    });

    test('every translation keeps its placeholders', () {
      for (final entry in arabicStrings.entries) {
        expect(
          '{}'.allMatches(entry.value).length,
          '{}'.allMatches(entry.key).length,
          reason: entry.key,
        );
        expect(entry.value.trim(), isNotEmpty, reason: entry.key);
      }
    });
  });

  test('the phone language decides when set to follow it', () {
    expect(
      AppLanguage.system.resolve(const Locale('ar', 'SA')).languageCode,
      'ar',
    );
    expect(AppLanguage.system.resolve(const Locale('fr')).languageCode, 'en');
    expect(AppLanguage.english.resolve(const Locale('ar')).languageCode, 'en');
    expect(AppLanguage.arabic.resolve(const Locale('en')).languageCode, 'ar');
    expect(AppLanguage.fromId('ar'), AppLanguage.arabic);
    expect(AppLanguage.fromId(null), AppLanguage.system);
  });
}
