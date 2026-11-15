import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:savekit/app/app.dart';
import 'package:savekit/core/l10n/l10n.dart';
import 'package:savekit/core/platform/media_platform.dart';
import 'package:savekit/core/settings/app_settings.dart';
import 'package:savekit/core/theme/app_theme.dart';
import 'package:savekit/features/cookies/presentation/settings_screen.dart';
import 'package:savekit/features/downloader/domain/download_progress.dart';
import 'package:savekit/features/tools/application/storage_controller.dart';

import 'support/fakes.dart';

/// Set SAVEKIT_SCREENSHOTS=1 to also write PNGs of the Arabic screens to
/// test/screenshots/. They use DejaVu Sans, which has Arabic letters; the
/// phone uses its own Arabic font.
final bool screenshots = Platform.environment['SAVEKIT_SCREENSHOTS'] == '1';

Future<void> loadFonts() async {
  const dejavu = '/usr/share/fonts/truetype/dejavu';
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null || !File('$dejavu/DejaVuSans.ttf').existsSync()) return;
  Future<ByteData> bytes(String path) async =>
      ByteData.sublistView(await File(path).readAsBytes());

  final text = FontLoader('Roboto')
    ..addFont(bytes('$dejavu/DejaVuSans.ttf'))
    ..addFont(bytes('$dejavu/DejaVuSans-Bold.ttf'));
  await text.load();
  for (final family in [
    'MaterialIcons',
    'packages/material_ui/MaterialIcons',
  ]) {
    final icons = FontLoader(family)
      ..addFont(
        bytes(
          '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ),
      );
    await icons.load();
  }
}

void main() {
  setUpAll(() async {
    if (screenshots) await loadFonts();
  });

  late UiFakeNative native;

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 450));
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    AppSettings settings = const AppSettings(language: AppLanguage.arabic),
    Locale phone = const Locale('en'),
  }) async {
    native = UiFakeNative();
    tester.view.physicalSize = const Size(824, 1830);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.localeTestValue = phone;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    addTearDown(() {
      AppColors.current = AppPalette.fallback;
      L10n.locale = const Locale('en');
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: uiOverrides(
          native: native,
          settings: settings,
          storage: const StorageSnapshot(),
          tasks: [
            storedTask(
              'a',
              'Street food tour: 12 stalls in one night',
              MediaPlatform.youtube,
              videoFormat(1080),
              DownloadStatus.downloading,
            ),
            storedTask(
              'b',
              'Lo-fi study mix',
              MediaPlatform.youtube,
              mp3Format,
              DownloadStatus.completed,
              files: ['/none/b.mp3'],
              size: 9 * 1024 * 1024,
            ),
          ],
        ),
        child: const SaveKitApp(),
      ),
    );
    await settle(tester);
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    if (!screenshots) return;
    await expectLater(
      find.byType(SaveKitApp),
      matchesGoldenFile('screenshots/$name.png'),
    );
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await settle(tester);
  }

  testWidgets('Arabic: the app is translated and laid out right to left', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('ابحث عن الوسائط'), findsOneWidget);
    expect(find.text('Find media'), findsNothing);
    expect(
      Directionality.of(tester.element(find.text('ابحث عن الوسائط'))),
      TextDirection.rtl,
    );
    // Mirrored: the first tab is on the right.
    expect(
      tester.getCenter(find.text('الرئيسية')).dx,
      greaterThan(tester.getCenter(find.text('الإعدادات')).dx),
    );
    await shoot(tester, 'ar_1_home');

    native.events.add(
      const DownloadProgress(
        taskId: 'a',
        status: DownloadStatus.downloading,
        progressPercent: 62,
        speed: '4.8MiB/s',
        eta: 14,
      ),
    );
    await settle(tester);
    await openTab(tester, 'قائمة التنزيل');
    // Titles stay as they are; the app's own words are Arabic.
    expect(
      find.text('Street food tour: 12 stalls in one night'),
      findsOneWidget,
    );
    expect(find.text('بقي 14 ث'), findsOneWidget);
    expect(find.byTooltip('إيقاف مؤقت'), findsOneWidget);
    await shoot(tester, 'ar_2_queue');

    await openTab(tester, 'الخزنة');
    expect(find.text('MP3 · 9.0 MB'), findsOneWidget);
    await shoot(tester, 'ar_3_vault');

    await openTab(tester, 'الأدوات');
    expect(find.text('فيديو إلى صوت'), findsOneWidget);
    expect(find.text('حالات واتساب'), findsOneWidget);
    await shoot(tester, 'ar_4_tools');

    await openTab(tester, 'الإعدادات');
    expect(find.text('المظهر'), findsOneWidget);
    expect(find.text('اسأل في كل مرة'), findsOneWidget);
    await shoot(tester, 'ar_5_settings');
  });

  testWidgets('the language can be switched in Settings without restarting', (
    tester,
  ) async {
    await pumpApp(tester, settings: const AppSettings());
    await openTab(tester, 'Settings');
    expect(find.text('Phone language'), findsOneWidget);

    await tester.tap(find.text('Language'));
    await settle(tester);
    await tester.tap(find.text('العربية').last);
    await settle(tester);

    // Still on Settings, now in Arabic and mirrored.
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('اللغة'), findsOneWidget);
    expect(find.text('Language'), findsNothing);
    expect(
      Directionality.of(tester.element(find.text('اللغة'))),
      TextDirection.rtl,
    );

    await tester.tap(find.text('اللغة'));
    await settle(tester);
    await tester.tap(find.text('English').last);
    await settle(tester);
    expect(find.text('Language'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('Language'))),
      TextDirection.ltr,
    );
  });

  testWidgets('"Phone language" follows an Arabic phone', (tester) async {
    await pumpApp(
      tester,
      settings: const AppSettings(),
      phone: const Locale('ar', 'SA'),
    );
    expect(find.text('ابحث عن الوسائط'), findsOneWidget);
  });
}
