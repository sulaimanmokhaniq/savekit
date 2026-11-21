import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:savekit/app/app.dart';
import 'package:savekit/core/settings/app_settings.dart';
import 'package:savekit/core/theme/app_theme.dart';
import 'package:savekit/features/downloader/application/download_queue_controller.dart';
import 'package:savekit/features/downloader/domain/download_progress.dart';
import 'package:savekit/features/extractor/data/media_extractor.dart';
import 'package:savekit/features/tonight/tonight_controller.dart';
import 'package:savekit/features/tools/application/storage_controller.dart';

import 'app_test.dart' show loadFonts;
import 'support/fakes.dart';

final bool screenshots = Platform.environment['SAVEKIT_SCREENSHOTS'] == '1';

const link = 'https://www.tiktok.com/@studio/video/1';

void main() {
  setUpAll(loadFonts);

  late UiFakeNative native;
  late UiFakeShareSource share;
  late FakeConnectivity connectivity;
  late UiFakeExtractor extractor;

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 450));
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    if (!screenshots) return;
    await expectLater(
      find.byType(SaveKitApp),
      matchesGoldenFile('screenshots/$name.png'),
    );
  }

  Future<ProviderContainer> open(
    WidgetTester tester, {
    AppSettings settings = const AppSettings(
      shareToTonight: true,
      tonightQuality: QualityPreference.mp3,
    ),
    bool online = true,
  }) async {
    native = UiFakeNative();
    share = UiFakeShareSource();
    connectivity = FakeConnectivity(online: online);
    extractor = UiFakeExtractor(sampleInfo());
    tester.view.physicalSize = const Size(824, 1830);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(() => AppColors.current = AppPalette.fallback);
    await tester.pumpWidget(
      ProviderScope(
        overrides: uiOverrides(
          native: native,
          shareSource: share,
          connectivity: connectivity,
          extractor: extractor,
          settings: settings,
          storage: const StorageSnapshot(),
        ),
        child: const SaveKitApp(),
      ),
    );
    await settle(tester);
    return ProviderScope.containerOf(
      tester.element(find.byType(NavigationBar)),
    );
  }

  testWidgets('a shared link is saved for tonight and queued for the night', (
    tester,
  ) async {
    final container = await open(tester);
    expect(find.text('Tonight'), findsOneWidget);

    share.stream.add('Look at this $link');
    await settle(tester);
    expect(find.text('Saved for tonight.'), findsOneWidget);
    // No picker, and nothing downloads yet.
    expect(find.text('Download'), findsNothing);
    expect(native.started, isEmpty);

    // Read straight away, and waiting in the queue for the night at the
    // chosen quality.
    final task = container.read(downloadQueueControllerProvider).single;
    expect(task.tonight, isTrue);
    expect(task.status, DownloadStatus.queued);
    expect(task.format.audioFormat, 'mp3');
    expect(container.read(tonightProvider), isEmpty);
    expect(find.text('Tonight · 1 link'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));

    await tester.tap(find.text('Tonight · 1 link'));
    await settle(tester);
    expect(find.text(sampleInfo().title), findsOneWidget);
    expect(find.text('1 waiting'), findsOneWidget);
    await shoot(tester, '40_tonight');

    // Or everything now.
    await tester.tap(find.text('Download all now'));
    await settle(tester);
    expect(native.started, hasLength(1));
  });

  testWidgets('without internet the link waits here, then is read', (
    tester,
  ) async {
    final container = await open(tester, online: false);
    share.stream.add(link);
    await settle(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(container.read(tonightProvider).single.url, link);
    expect(container.read(downloadQueueControllerProvider), isEmpty);

    await tester.tap(find.text('Tonight · 1 link'));
    await settle(tester);
    expect(find.text(link), findsOneWidget);
    expect(find.text('Read once the phone is online'), findsOneWidget);

    connectivity.setOnline(true);
    await settle(tester);
    expect(container.read(tonightProvider), isEmpty);
    expect(
      container.read(downloadQueueControllerProvider).single.tonight,
      true,
    );
  });

  testWidgets('a link that cannot be read stays, with the reason', (
    tester,
  ) async {
    final container = await open(tester);
    extractor.result = const MediaExtractionException(
      'ERROR: Unsupported URL: https://example.com/a',
    );
    share.stream.add('https://example.com/a');
    await settle(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(container.read(tonightProvider).single.error, isNotNull);

    await tester.tap(find.text('Tonight · 1 link'));
    await settle(tester);
    expect(find.text('SaveKit cannot read this kind of link.'), findsOneWidget);

    // Removing it empties the list.
    await tester.tap(find.byTooltip('Remove'));
    await settle(tester);
    expect(find.text('Nothing for tonight yet'), findsOneWidget);
  });

  testWidgets('sharing asks as before when the setting is off', (tester) async {
    final container = await open(tester, settings: const AppSettings());
    share.stream.add(link);
    await settle(tester);
    expect(find.text('Saved for tonight.'), findsNothing);
    expect(container.read(tonightProvider), isEmpty);
  });

  test('the settings keep tonight\'s choices, never "ask"', () {
    final saved = const AppSettings(
      shareToTonight: true,
      tonightQuality: QualityPreference.p720,
    ).toMap();
    final read = AppSettings.fromMap(saved);
    expect(read.shareToTonight, isTrue);
    expect(read.tonightQuality, QualityPreference.p720);
    expect(
      AppSettings.fromMap({...saved, 'tonightQuality': 'ask'}).tonightQuality,
      QualityPreference.best,
    );
  });
}
