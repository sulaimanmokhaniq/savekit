import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:savekit/app/app.dart';
import 'package:savekit/core/platform/media_platform.dart';
import 'package:savekit/core/settings/app_settings.dart';
import 'package:savekit/core/theme/app_theme.dart';
import 'package:savekit/features/cookies/domain/platform_account.dart';
import 'package:savekit/features/cookies/presentation/settings_screen.dart';
import 'package:savekit/features/downloader/data/gallery_export_service.dart';
import 'package:savekit/features/downloader/domain/download_progress.dart';
import 'package:savekit/features/downloader/domain/download_task.dart';
import 'package:savekit/features/extractor/data/media_extractor.dart';
import 'package:savekit/features/tools/application/storage_controller.dart';

import 'support/fakes.dart';

/// Set SAVEKIT_SCREENSHOTS=1 to also write a PNG of each screen to
/// test/screenshots/ (rendered with the real fonts, for reviewing the design).
final bool screenshots = Platform.environment['SAVEKIT_SCREENSHOTS'] == '1';

Future<void> loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final fonts = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!fonts.existsSync()) return;
  Future<ByteData> bytes(String name) async =>
      ByteData.sublistView(await File('${fonts.path}/$name').readAsBytes());

  final roboto = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold', 'Black']) {
    roboto.addFont(bytes('Roboto-$weight.ttf'));
  }
  await roboto.load();
  for (final family in [
    'MaterialIcons',
    'packages/material_ui/MaterialIcons',
  ]) {
    final icons = FontLoader(family)
      ..addFont(bytes('MaterialIcons-Regular.otf'));
    await icons.load();
  }
}

List<DownloadTask> vaultTasks() => [
  storedTask(
    'v1',
    'Golden hour timelapse',
    MediaPlatform.tiktok,
    videoFormat(1080),
    DownloadStatus.completed,
    files: ['/none/a.mp4'],
    size: 148 * 1024 * 1024,
  ),
  storedTask(
    'v2',
    'Lo-fi study mix',
    MediaPlatform.youtube,
    mp3Format,
    DownloadStatus.completed,
    minutesAgo: 5,
    files: ['/none/b.mp3'],
    size: 9 * 1024 * 1024,
  ),
  storedTask(
    'v3',
    'Product launch photos',
    MediaPlatform.linkedin,
    photosFormat,
    DownloadStatus.completed,
    minutesAgo: 9,
    files: ['/none/1.jpg', '/none/2.jpg'],
    size: 3 * 1024 * 1024,
  ),
  storedTask(
    'v4',
    'Harbour at dusk',
    MediaPlatform.instagram,
    videoFormat(720),
    DownloadStatus.completed,
    minutesAgo: 20,
    files: ['/none/c.mp4'],
    size: 40 * 1024 * 1024,
  ),
];

StorageSnapshot sampleStorage() => StorageSnapshot(
  files: [
    StoredFile(
      path: '/none/a.mp4',
      size: 148 * 1024 * 1024,
      modified: DateTime(2026, 11, 14),
      kind: SavedFileKind.video,
      title: 'Golden hour timelapse',
    ),
    StoredFile(
      path: '/none/c.mp4',
      size: 40 * 1024 * 1024,
      modified: DateTime(2026, 11, 13),
      kind: SavedFileKind.video,
      title: 'Harbour at dusk',
    ),
    StoredFile(
      path: '/none/b.mp3',
      size: 9 * 1024 * 1024,
      modified: DateTime(2026, 11, 12),
      kind: SavedFileKind.audio,
      title: 'Lo-fi study mix',
    ),
    StoredFile(
      path: '/none/1.jpg',
      size: 2 * 1024 * 1024,
      modified: DateTime(2026, 11, 11),
      kind: SavedFileKind.image,
      title: 'Product launch photos',
    ),
    StoredFile(
      path: '/none/2.jpg',
      size: 1024 * 1024,
      modified: DateTime(2026, 11, 11),
      kind: SavedFileKind.image,
      title: 'Product launch photos',
    ),
  ],
  leftovers: const ['/none/x.part'],
  leftoverBytes: 12 * 1024 * 1024,
);

void main() {
  setUpAll(() async {
    if (screenshots) await loadFonts();
  });

  late UiFakeNative native;
  late UiFakeVaultLock vaultLock;
  late UiFakeDeviceFiles deviceFiles;
  late List<String> iconChanges;

  /// Starts pending animations and async work, then runs them to the end.
  /// (pumpAndSettle cannot be used: progress spinners never settle.)
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 450));
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    Object? extraction,
    List<DownloadTask> tasks = const [],
    Set<PlatformAccount> signedIn = const {},
    String? clipboard,
    UiFakeShareSource? shareSource,
    AppSettings settings = const AppSettings(),
    StorageSnapshot? storage,
  }) async {
    native = UiFakeNative();
    vaultLock = UiFakeVaultLock();
    deviceFiles = UiFakeDeviceFiles();
    iconChanges = [];
    tester.view.physicalSize = const Size(824, 1830);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(() => AppColors.current = AppPalette.fallback);
    await tester.pumpWidget(
      ProviderScope(
        overrides: uiOverrides(
          native: native,
          extraction: extraction,
          tasks: tasks,
          signedIn: signedIn,
          clipboard: clipboard,
          shareSource: shareSource,
          settings: settings,
          vaultLock: vaultLock,
          deviceFiles: deviceFiles,
          iconChanges: iconChanges,
          storage: storage ?? const StorageSnapshot(),
        ),
        child: const SaveKitApp(),
      ),
    );
    // Engine start-up, queue restore and the clipboard check.
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

  /// The Settings tab's own vertical list (the theme row scrolls sideways).
  Finder settingsList() => find
      .descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(Scrollable),
      )
      .first;

  ScrollPosition themeRow(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(Scrollable),
            )
            .at(1),
      )
      .position;

  Future<void> scrollSettingsTo(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(target, 250, scrollable: settingsList());
    await settle(tester);
  }

  testWidgets('home shows the engine, platforms and a copied link', (
    tester,
  ) async {
    await pumpApp(tester, clipboard: 'https://www.instagram.com/reel/Cabc123/');

    expect(find.text('SaveKit'), findsOneWidget);
    expect(
      find.textContaining('Engine ready · yt-dlp 2026.11.10'),
      findsOneWidget,
    );
    for (final platform in MediaPlatform.featured) {
      expect(find.text(platform.label), findsWidgets);
    }
    expect(find.text('Link copied — tap to fetch'), findsOneWidget);
    await shoot(tester, '01_home');

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.text('Link copied — tap to fetch'), findsNothing);
  });

  testWidgets('pasting a link opens the picker and queues the download', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.enterText(
      find.byType(TextField),
      'https://www.tiktok.com/@studio/video/1',
    );
    await tester.tap(find.text('Find media'));
    await settle(tester);

    expect(
      find.text('Golden hour timelapse over the old harbour'),
      findsOneWidget,
    );
    expect(find.text('Best No-Watermark'), findsOneWidget);
    expect(find.text('4K'), findsOneWidget);
    expect(find.text('3:07'), findsOneWidget);
    await shoot(tester, '02_format_picker');

    await tester.tap(find.text('1080p'));
    await tester.pump();
    expect(find.text('Download · about 148 MB'), findsOneWidget);

    await tester.tap(find.text('Audio'));
    await settle(tester);
    expect(find.text('MP3'), findsOneWidget);
    expect(find.text('4K'), findsNothing);

    await tester.tap(find.text('Photos'));
    await settle(tester);
    expect(find.text('Photos (4)'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.download_rounded));
    await settle(tester);
    expect(find.text('Added to the queue.'), findsOneWidget);
    expect(native.started, hasLength(1));

    await openTab(tester, 'Queue');
    expect(find.text('TikTok · Photos (4)'), findsOneWidget);
    // Let the snackbar's timer finish.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('several pasted links open the batch sheet', (tester) async {
    await pumpApp(tester);
    await tester.enterText(
      find.byType(TextField),
      'https://youtu.be/a\nhttps://youtu.be/b\nhttps://youtu.be/c',
    );
    await tester.tap(find.text('Find media'));
    await settle(tester);

    expect(find.text('3 links'), findsOneWidget);
    expect(find.text('Download all (3)'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '720p'));
    await tester.pump();
    await shoot(tester, '03_batch');

    await tester.tap(find.text('Download all (3)'));
    await settle(tester);
    expect(find.text('3 downloads added to the queue'), findsOneWidget);
    expect(native.started, hasLength(3));
    await shoot(tester, '04_batch_done');
  });

  testWidgets('a playlist link lists its videos before downloading', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.enterText(
      find.byType(TextField),
      'https://www.youtube.com/playlist?list=PL123',
    );
    await tester.tap(find.text('Find media'));
    await settle(tester);

    expect(find.text('Road trip mixes'), findsOneWidget);
    expect(find.text('Download all (4)'), findsOneWidget);
    await tester.tap(find.text('Download all (4)'));
    await settle(tester);
    expect(find.text('4 downloads added to the queue'), findsOneWidget);
  });

  testWidgets('a failed lookup offers to log in', (tester) async {
    await pumpApp(
      tester,
      extraction: const MediaExtractionException(
        'This story is only visible to logged-in users.',
        loginRequired: true,
      ),
    );
    await tester.enterText(
      find.byType(TextField),
      'https://www.instagram.com/stories/a/1/',
    );
    await tester.tap(find.text('Find media'));
    await settle(tester);

    expect(find.text('Couldn’t read this link'), findsOneWidget);
    expect(
      find.text('This story is only visible to logged-in users.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Log in to this platform'));
    await settle(tester);
    // The picker sends the user to Settings, where the accounts are.
    expect(find.text('THEME'), findsOneWidget);
  });

  testWidgets('a shared link opens the picker when one-tap is off', (
    tester,
  ) async {
    final share = UiFakeShareSource();
    await pumpApp(tester, shareSource: share);
    await openTab(tester, 'Vault');

    share.stream.add('Watch this https://www.tiktok.com/@studio/video/1');
    await settle(tester);

    expect(
      find.text('Golden hour timelapse over the old harbour'),
      findsOneWidget,
    );
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('a shared link downloads straight away with one-tap on', (
    tester,
  ) async {
    final share = UiFakeShareSource();
    await pumpApp(
      tester,
      shareSource: share,
      settings: const AppSettings(oneTap: QualityPreference.p720),
    );
    share.stream.add('https://www.tiktok.com/@studio/video/1');
    await settle(tester);

    // No picker: it went to the queue, and Home says so.
    expect(find.text('Download'), findsNothing);
    expect(find.text('Added to the queue'), findsOneWidget);
    expect(native.started, hasLength(1));
  });

  testWidgets('queue shows progress, pause, failures and retry', (
    tester,
  ) async {
    await pumpApp(
      tester,
      tasks: [
        storedTask(
          'a',
          'Street food tour: 12 stalls in one night',
          MediaPlatform.youtube,
          videoFormat(1080),
          DownloadStatus.downloading,
          minutesAgo: 1,
        ),
        storedTask(
          'b',
          'Launch keynote highlights',
          MediaPlatform.linkedin,
          mp3Format,
          DownloadStatus.paused,
          minutesAgo: 2,
        ),
        storedTask(
          'c',
          'Weekend in the mountains',
          MediaPlatform.instagram,
          photosFormat,
          DownloadStatus.failed,
          minutesAgo: 3,
          error: 'This post is private. Log in to Instagram to save it.',
        ),
      ],
    );
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
    await openTab(tester, 'Queue');

    expect(find.text('62% · 4.8MiB/s'), findsOneWidget);
    expect(find.text('14s left'), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget);
    expect(
      find.text('This post is private. Log in to Instagram to save it.'),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('1')),
      findsOneWidget,
    );
    await shoot(tester, '05_queue');

    await tester.tap(find.byTooltip('Resume'));
    await settle(tester);
    expect(native.started, contains('b'));
    expect(find.text('Paused'), findsNothing);

    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(native.started, contains('c'));

    await tester.tap(find.byTooltip('Queue actions'));
    await settle(tester);
    expect(find.text('Pause all'), findsOneWidget);
    await tester.tap(find.text('Pause all'));
    await settle(tester);
    expect(find.text('Paused'), findsNWidgets(3));
  });

  testWidgets('queue says when it is waiting for Wi-Fi', (tester) async {
    native = UiFakeNative();
    final connectivity = FakeConnectivity(onWifi: false);
    tester.view.physicalSize = const Size(824, 1830);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: uiOverrides(
          native: native,
          connectivity: connectivity,
          settings: const AppSettings(wifiOnly: true),
          storage: const StorageSnapshot(),
          tasks: [
            storedTask(
              'a',
              'Big video',
              MediaPlatform.youtube,
              videoFormat(1080),
              DownloadStatus.queued,
            ),
          ],
        ),
        child: const SaveKitApp(),
      ),
    );
    await settle(tester);
    await openTab(tester, 'Queue');
    expect(find.textContaining('Waiting for Wi-Fi'), findsOneWidget);
    expect(native.started, isEmpty);

    connectivity.setWifi(true);
    await settle(tester);
    expect(find.textContaining('Waiting for Wi-Fi'), findsNothing);
    expect(native.started, ['a']);
  });

  testWidgets('vault searches, sorts, filters and deletes', (tester) async {
    await pumpApp(tester, tasks: vaultTasks());
    await openTab(tester, 'Vault');

    expect(find.text('Golden hour timelapse'), findsOneWidget);
    expect(find.text('1080p · 148 MB'), findsOneWidget);
    await shoot(tester, '06_vault_grid');

    await tester.tap(find.byTooltip('Show as list'));
    await settle(tester);

    // Largest first puts the 148 MB video on top and the 3 MB photos last.
    await tester.tap(find.byTooltip('Sort'));
    await settle(tester);
    await tester.tap(find.text('Largest first').last);
    await settle(tester);
    expect(
      tester.getTopLeft(find.text('Golden hour timelapse')).dy,
      lessThan(tester.getTopLeft(find.text('Product launch photos')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Harbour at dusk')).dy,
      lessThan(tester.getTopLeft(find.text('Lo-fi study mix')).dy),
    );
    await shoot(tester, '07_vault_list');

    await tester.tap(find.byTooltip('Search'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, 'lo-fi');
    await settle(tester);
    expect(find.text('Lo-fi study mix'), findsOneWidget);
    expect(find.text('Golden hour timelapse'), findsNothing);
    await tester.tap(find.byTooltip('Close search'));
    await settle(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'YouTube'));
    await settle(tester);
    expect(find.text('Golden hour timelapse'), findsNothing);

    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(find.text('Delete this download?'), findsOneWidget);
    // The user is told the gallery copy goes too.
    expect(find.textContaining('everywhere on this phone'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await settle(tester);

    // The filter's last item is gone, so the vault falls back to everything.
    expect(find.text('Lo-fi study mix'), findsNothing);
    expect(find.text('Golden hour timelapse'), findsOneWidget);
  });

  testWidgets('vault selects several items and converts a video', (
    tester,
  ) async {
    await pumpApp(tester, tasks: vaultTasks());
    await openTab(tester, 'Vault');

    await tester.longPress(find.text('Golden hour timelapse'));
    await settle(tester);
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.text('Harbour at dusk'));
    await settle(tester);
    expect(find.text('2 selected'), findsOneWidget);
    await shoot(tester, '08_vault_selecting');

    await tester.tap(find.byTooltip('Delete selected'));
    await settle(tester);
    expect(find.text('Delete 2 downloads?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await settle(tester);
    expect(find.text('Golden hour timelapse'), findsNothing);
    expect(find.text('Harbour at dusk'), findsNothing);
    expect(find.text('Lo-fi study mix'), findsOneWidget);
  });

  testWidgets('vault menu converts a video to audio', (tester) async {
    await pumpApp(tester, tasks: vaultTasks().take(1).toList());
    await openTab(tester, 'Vault');
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Convert to audio'));
    await settle(tester);
    expect(native.started, hasLength(1));
    await openTab(tester, 'Queue');
    expect(find.text('This phone · MP3'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a locked vault opens only after confirming', (tester) async {
    await pumpApp(
      tester,
      tasks: vaultTasks(),
      settings: const AppSettings(lockVault: true),
    );
    await openTab(tester, 'Vault');
    expect(find.text('The Vault is locked'), findsOneWidget);
    expect(find.text('Golden hour timelapse'), findsNothing);
    await shoot(tester, '09_vault_locked');

    vaultLock.accept = false;
    await tester.tap(find.text('Unlock'));
    await settle(tester);
    expect(find.text('The Vault is locked'), findsOneWidget);

    vaultLock.accept = true;
    await tester.tap(find.text('Unlock'));
    await settle(tester);
    expect(find.text('Golden hour timelapse'), findsOneWidget);
  });

  testWidgets('tools: storage lists files by size and deletes a selection', (
    tester,
  ) async {
    await pumpApp(tester, tasks: vaultTasks(), storage: sampleStorage());
    await openTab(tester, 'Tools');
    expect(find.text('Video to audio'), findsOneWidget);
    expect(find.text('WhatsApp statuses'), findsOneWidget);
    expect(find.textContaining('212 MB used · 5 files'), findsOneWidget);
    await shoot(tester, '10_tools');

    await tester.tap(find.text('Storage'));
    await settle(tester);
    expect(find.text('212 MB'), findsOneWidget);
    expect(find.text('Videos · 2'), findsOneWidget);
    expect(find.text('Leftover partial files'), findsOneWidget);
    expect(find.text('5 FILES · LARGEST FIRST'), findsOneWidget);
    await shoot(tester, '11_storage');

    await tester.tap(find.text('Lo-fi study mix'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Delete 1 · 9.0 MB'), findsOneWidget);
    await tester.tap(find.text('Delete 1 · 9.0 MB'));
    await settle(tester);
    expect(find.text('Delete this file?'), findsOneWidget);
    expect(find.textContaining('everywhere on this phone'), findsOneWidget);
  });

  testWidgets('tools: converter queues a picked video', (tester) async {
    await pumpApp(tester);
    await openTab(tester, 'Tools');
    await tester.tap(find.text('Video to audio'));
    await settle(tester);

    await tester.tap(find.text('Choose a video'));
    await settle(tester);
    expect(find.text('Holiday clip.mp4'), findsOneWidget);
    expect(find.text('48.0 MB'), findsOneWidget);
    await tester.tap(find.text('M4A · smaller file'));
    await tester.pump();
    await shoot(tester, '12_converter');

    await tester.tap(find.text('Convert to audio'));
    await settle(tester);
    expect(native.started, hasLength(1));
    expect(find.text('No video chosen'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('tools: WhatsApp statuses are listed and saved', (tester) async {
    await pumpApp(tester);
    await openTab(tester, 'Tools');
    await tester.tap(find.text('WhatsApp statuses'));
    await settle(tester);

    // Photos and videos are on separate tabs.
    expect(find.text('Photos (3)'), findsOneWidget);
    expect(find.text('Videos (3)'), findsOneWidget);
    expect(find.text('700 KB'), findsOneWidget);
    expect(find.text('1.4 MB'), findsNothing);

    // A long press starts selecting; further taps add to the selection.
    await tester.longPress(find.text('700 KB'));
    await settle(tester);
    await tester.tap(find.text('2.1 MB'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    await shoot(tester, '13_whatsapp_statuses');

    await tester.tap(find.text('Save 2'));
    await settle(tester);
    expect(deviceFiles.imported.single, hasLength(2));
    expect(find.textContaining('2 statuses saved'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('tools: a WhatsApp status can be previewed before saving', (
    tester,
  ) async {
    await pumpApp(tester);
    await openTab(tester, 'Tools');
    await tester.tap(find.text('WhatsApp statuses'));
    await settle(tester);

    await tester.tap(find.text('Videos (3)'));
    await settle(tester);
    expect(find.text('1.4 MB'), findsOneWidget);

    await tester.tap(find.text('1.4 MB'));
    await settle(tester);
    expect(find.text('Video status'), findsOneWidget);
    expect(find.text('Save · 1.4 MB'), findsOneWidget);

    await tester.tap(find.text('Save · 1.4 MB'));
    await settle(tester);
    expect(deviceFiles.imported.single, ['content://statuses/1']);
    expect(find.textContaining('Saved to the Vault'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('tools: WhatsApp access is asked for first', (tester) async {
    await pumpApp(tester);
    deviceFiles.granted = false;
    await openTab(tester, 'Tools');
    await tester.tap(find.text('WhatsApp statuses'));
    await settle(tester);
    expect(find.text('Give access'), findsOneWidget);
    await shoot(tester, '14_whatsapp_setup');

    await tester.tap(find.text('Give access'));
    await settle(tester);
    expect(find.text('Give access'), findsNothing);
    expect(find.text('700 KB'), findsOneWidget);
  });

  testWidgets('settings: switching theme recolours the app and is saved', (
    tester,
  ) async {
    await pumpApp(tester);
    await openTab(tester, 'Settings');
    expect(find.text('Ember'), findsOneWidget);
    expect(AppColors.current.id, 'ember');
    await shoot(tester, '15_settings_ember');

    for (final name in ['Vault', 'Pulse', 'Tide']) {
      final card = find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.text(name),
      );
      // The theme row scrolls sideways; later themes start off screen.
      await tester.scrollUntilVisible(
        card,
        120,
        scrollable: find
            .descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(Scrollable),
            )
            .at(1),
      );
      await tester.ensureVisible(card);
      await tester.pump();
      ScrollPosition themeRow() => tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(SettingsScreen),
                  matching: find.byType(Scrollable),
                )
                .at(1),
          )
          .position;
      final before = themeRow().pixels;
      await tester.tap(card);
      await settle(tester);
      // Recoloured in place: still on Settings, and the theme row has not
      // jumped back to its start.
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(themeRow().pixels, before);
      expect(AppColors.current.name, name);
      expect(
        Theme.of(tester.element(find.byType(SettingsScreen)))
            .colorScheme
            .primary,
        AppColors.current.accent,
      );
      await shoot(tester, '16_settings_${name.toLowerCase()}');
    }

    // The home-screen icon was set at start-up and followed every change.
    expect(iconChanges, ['ember', 'vault', 'pulse', 'tide']);
    expect(themeRow(tester).pixels, greaterThan(0));

    await tester.tap(find.widgetWithText(SwitchListTile, 'Match the app icon'));
    await settle(tester);
    // Turned off: back to the default icon, while the theme stays.
    expect(iconChanges.last, 'ember');
    expect(AppColors.current.name, 'Tide');

    await openTab(tester, 'Home');
    await shoot(tester, '17_home_tide');
  });

  testWidgets('settings: download options, lock, accounts and updates', (
    tester,
  ) async {
    await pumpApp(tester, signedIn: {PlatformAccount.instagram});
    await openTab(tester, 'Settings');

    await tester.tap(find.text('One-tap download'));
    await settle(tester);
    await tester.tap(find.text('720p').last);
    await settle(tester);
    expect(find.text('720p'), findsOneWidget);

    await tester.tap(find.text('Wi-Fi only'));
    await settle(tester);
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Wi-Fi only'),
          )
          .value,
      isTrue,
    );

    await scrollSettingsTo(tester, find.text('Lock the Vault'));
    await tester.tap(find.text('Lock the Vault'));
    await settle(tester);
    expect(vaultLock.prompts, ['Confirm to lock the Vault']);
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Lock the Vault'),
          )
          .value,
      isTrue,
    );

    await scrollSettingsTo(tester, find.text('Log out'));
    expect(find.text('Signed in'), findsOneWidget);
    await shoot(tester, '18_settings_accounts');
    await tester.tap(find.text('Log out'));
    await settle(tester);
    expect(find.text('Signed in'), findsNothing);

    await scrollSettingsTo(tester, find.text('Update extractors'));
    expect(find.text('1.32.20'), findsOneWidget);
    await tester.tap(find.text('Update extractors'));
    await settle(tester);
    expect(find.text('Updated yt-dlp 2026.11.14.'), findsWidgets);
    await tester.pump(const Duration(seconds: 5));
  });
}
