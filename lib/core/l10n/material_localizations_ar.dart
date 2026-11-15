import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoLocalizations, DefaultCupertinoLocalizations;
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// The few built-in Material labels the app shows (button and menu tooltips),
/// in Arabic. Everything else falls back to the English defaults.
class ArabicMaterialLocalizations extends DefaultMaterialLocalizations {
  const ArabicMaterialLocalizations();

  @override
  String get backButtonTooltip => 'رجوع';

  @override
  String get closeButtonTooltip => 'إغلاق';

  @override
  String get closeButtonLabel => 'إغلاق';

  @override
  String get cancelButtonLabel => 'إلغاء';

  @override
  String get okButtonLabel => 'موافق';

  @override
  String get deleteButtonTooltip => 'حذف';

  @override
  String get moreButtonTooltip => 'المزيد';

  @override
  String get showMenuTooltip => 'عرض القائمة';

  @override
  String get searchFieldLabel => 'بحث';

  @override
  String get modalBarrierDismissLabel => 'إغلاق';

  @override
  String get copyButtonLabel => 'نسخ';

  @override
  String get cutButtonLabel => 'قص';

  @override
  String get pasteButtonLabel => 'لصق';

  @override
  String get selectAllButtonLabel => 'تحديد الكل';
}

/// Provides Material labels for both of the app's languages.
class AppMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const AppMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'ar';

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      SynchronousFuture<MaterialLocalizations>(
        locale.languageCode == 'ar'
            ? const ArabicMaterialLocalizations()
            : const DefaultMaterialLocalizations(),
      );

  @override
  bool shouldReload(AppMaterialLocalizationsDelegate old) => false;
}

/// The framework asks for iOS-style labels for every supported language even
/// though this Android app shows none of them; the English defaults do.
class AppCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const AppCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' || locale.languageCode == 'ar';

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      SynchronousFuture<CupertinoLocalizations>(
        const DefaultCupertinoLocalizations(),
      );

  @override
  bool shouldReload(AppCupertinoLocalizationsDelegate old) => false;
}
