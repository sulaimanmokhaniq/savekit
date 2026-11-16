import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:savekit/app/app.dart';
import 'package:savekit/core/platform/media_platform.dart';
import 'package:savekit/core/settings/app_settings.dart';
import 'package:savekit/core/theme/app_theme.dart';
import 'package:savekit/features/downloader/domain/download_progress.dart';
import 'package:savekit/features/downloader/domain/download_task.dart';
import 'package:savekit/features/tools/application/storage_controller.dart';
import 'package:savekit/features/transfer/transfer_controller.dart';
import 'package:savekit/features/vault/presentation/feed_screen.dart';

import 'support/fakes.dart';

void main() {
  late Directory folder;
  final screenOn = <bool>[];

  setUp(() {
    folder = Directory.systemTemp.createTempSync('savekit-feed');
    screenOn.clear();
  });
  tearDown(() => folder.deleteSync(recursive: true));

  String file(String name) {
    final path = '${folder.path}/$name';
    File(path).writeAsBytesSync([0]);
    return path;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 450));
  }

  Future<ProviderContainer> open(
    WidgetTester tester,
    List<DownloadTask> tasks, {
    AppSettings settings = const AppSettings(),
  }) async {
    tester.view.physicalSize = const Size(824, 1830);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(() => AppColors.current = AppPalette.fallback);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...uiOverrides(
            native: UiFakeNative(),
            tasks: tasks,
            settings: settings,
            storage: const StorageSnapshot(),
          ),
          keepScreenOnProvider.overrideWithValue(
            (on) async => screenOn.add(on),
          ),
        ],
        child: const SaveKitApp(),
      ),
    );
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Vault'),
      ),
    );
    await settle(tester);
    return ProviderScope.containerOf(
      tester.element(find.byType(NavigationBar)),
    );
  }

  testWidgets('photos and videos, newest first, one per screen', (
    tester,
  ) async {
    final tasks = [
      storedTask(
        'new',
        'Harbour at dawn',
        MediaPlatform.instagram,
        photosFormat,
        DownloadStatus.completed,
        files: [file('a.jpg'), file('b.jpg')],
      ),
      storedTask(
        'old',
        'Old photo',
        MediaPlatform.x,
        photosFormat,
        DownloadStatus.completed,
        minutesAgo: 60,
        files: [file('c.png')],
      ),
      // Audio and missing files are left out.
      storedTask(
        'song',
        'A song',
        MediaPlatform.youtube,
        mp3Format,
        DownloadStatus.completed,
        files: [file('d.mp3')],
      ),
      storedTask(
        'gone',
        'Deleted elsewhere',
        MediaPlatform.youtube,
        photosFormat,
        DownloadStatus.completed,
        files: ['${folder.path}/missing.jpg'],
      ),
    ];
    final container = await open(tester, tasks);
    final items = container.read(feedItemsProvider);
    expect(
      [for (final item in items) item.title],
      ['Harbour at dawn', 'Harbour at dawn', 'Old photo'],
    );
    expect(items.first.source, 'Instagram');

    await tester.tap(find.byTooltip('Your feed'));
    await settle(tester);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text('Harbour at dawn'), findsOneWidget);
    expect(screenOn, [true]);

    // Swipe up for the next.
    await tester.fling(find.byType(PageView), const Offset(0, -600), 2000);
    await settle(tester);
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(0, -600), 2000);
    await settle(tester);
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('Old photo'), findsOneWidget);
    expect(find.text('X'), findsOneWidget);

    // Deleting asks first, then removes it from the feed.
    await tester.tap(find.byTooltip('Delete'));
    await settle(tester);
    expect(find.text('Delete this file?'), findsOneWidget);
    await tester.tap(find.text('Delete').last);
    await settle(tester);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(container.read(feedItemsProvider), hasLength(2));

    await tester.pageBack();
    await settle(tester);
    expect(screenOn, [true, false]);
  });

  testWidgets('an empty feed explains itself', (tester) async {
    await open(tester, [
      storedTask(
        'song',
        'A song',
        MediaPlatform.youtube,
        mp3Format,
        DownloadStatus.completed,
        files: [file('d.mp3')],
      ),
    ]);
    await tester.tap(find.byTooltip('Your feed'));
    await settle(tester);
    expect(find.text('Nothing to watch yet'), findsOneWidget);
  });

  testWidgets('the Vault lock covers the feed', (tester) async {
    await open(tester, [
      storedTask(
        'new',
        'Harbour at dawn',
        MediaPlatform.instagram,
        photosFormat,
        DownloadStatus.completed,
        files: [file('a.jpg')],
      ),
    ], settings: const AppSettings(lockVault: true));
    // The Vault itself is locked, so the feed opens from Tools.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Tools'),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Your feed'));
    await settle(tester);
    expect(find.text('The Vault is locked'), findsOneWidget);
    expect(find.text('Harbour at dawn'), findsNothing);

    await tester.tap(find.text('Unlock'));
    await settle(tester);
    expect(find.text('Harbour at dawn'), findsOneWidget);
  });
}
