import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:savekit/app/app.dart';
import 'package:savekit/core/platform/media_platform.dart';
import 'package:savekit/features/cookies/domain/platform_account.dart';
import 'package:savekit/features/downloader/domain/download_progress.dart';
import 'package:savekit/features/downloader/domain/download_task.dart';
import 'package:savekit/features/extractor/data/media_extractor.dart';

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
  for (final family in ['MaterialIcons', 'packages/material_ui/MaterialIcons']) {
    final icons = FontLoader(family)..addFont(bytes('MaterialIcons-Regular.otf'));
    await icons.load();
  }
}

void main() {
  setUpAll(() async {
    if (screenshots) await loadFonts();
  });

  late UiFakeNative native;

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
  }) async {
    native = UiFakeNative();
    tester.view.physicalSize = const Size(824, 1830);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: uiOverrides(
          native: native,
          extraction: extraction,
          tasks: tasks,
          signedIn: signedIn,
          clipboard: clipboard,
          shareSource: shareSource,
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

  testWidgets('home shows the engine, platforms and a copied link', (tester) async {
    await pumpApp(tester, clipboard: 'https://www.instagram.com/reel/Cabc123/');

    expect(find.text('SaveKit'), findsOneWidget);
    expect(find.textContaining('Engine ready · yt-dlp 2026.11.10'), findsOneWidget);
    for (final platform in MediaPlatform.featured) {
      expect(find.text(platform.label), findsWidgets);
    }
    expect(find.text('Link copied — tap to fetch'), findsOneWidget);
    await shoot(tester, '1_home');

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.text('Link copied — tap to fetch'), findsNothing);
  });

  testWidgets('pasting a link opens the picker and queues the download', (tester) async {
    await pumpApp(tester);

    await tester.enterText(find.byType(TextField), 'https://www.tiktok.com/@studio/video/1');
    await tester.tap(find.text('Find media'));
    await settle(tester);

    expect(find.text('Golden hour timelapse over the old harbour'), findsOneWidget);
    expect(find.text('Best No-Watermark'), findsOneWidget);
    expect(find.text('4K'), findsOneWidget);
    expect(find.text('3:07'), findsOneWidget);
    await shoot(tester, '2_format_picker');

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
    await shoot(tester, '3_format_picker_photos');

    await tester.tap(find.byIcon(Icons.download_rounded));
    await settle(tester);
    expect(find.text('Added to the queue.'), findsOneWidget);
    expect(native.started, hasLength(1));

    await openTab(tester, 'Queue');
    expect(find.text('TikTok · Photos (4)'), findsOneWidget);
    // Let the snackbar's timer finish.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a failed lookup offers to log in', (tester) async {
    await pumpApp(
      tester,
      extraction: const MediaExtractionException(
        'This story is only visible to logged-in users.',
        loginRequired: true,
      ),
    );
    await tester.enterText(find.byType(TextField), 'https://www.instagram.com/stories/a/1/');
    await tester.tap(find.text('Find media'));
    await settle(tester);

    expect(find.text('Couldn’t read this link'), findsOneWidget);
    expect(find.text('This story is only visible to logged-in users.'), findsOneWidget);
    await shoot(tester, '4_lookup_failed');

    await tester.tap(find.text('Log in to this platform'));
    await settle(tester);
    expect(find.text('PLATFORM ACCOUNTS'), findsOneWidget);
  });

  testWidgets('a link shared from another app opens the picker', (tester) async {
    final share = UiFakeShareSource();
    await pumpApp(tester, shareSource: share);
    await openTab(tester, 'Vault');

    share.stream.add('Watch this https://www.tiktok.com/@studio/video/1');
    await settle(tester);

    expect(find.text('Golden hour timelapse over the old harbour'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('queue shows progress, failures and retry', (tester) async {
    await pumpApp(
      tester,
      tasks: [
        storedTask('a', 'Street food tour: 12 stalls in one night', MediaPlatform.youtube, videoFormat(1080), DownloadStatus.downloading, minutesAgo: 1),
        storedTask('b', 'Launch keynote highlights', MediaPlatform.linkedin, mp3Format, DownloadStatus.queued, minutesAgo: 2),
        storedTask('c', 'Weekend in the mountains', MediaPlatform.instagram, photosFormat, DownloadStatus.failed, minutesAgo: 3, error: 'This post is private. Log in to Instagram to save it.'),
      ],
    );
    native.events.add(
      const DownloadProgress(taskId: 'a', status: DownloadStatus.downloading, progressPercent: 62, speed: '4.8MiB/s', eta: 14),
    );
    await settle(tester);
    await openTab(tester, 'Queue');

    expect(find.text('62% · 4.8MiB/s'), findsOneWidget);
    expect(find.text('14s left'), findsOneWidget);
    expect(find.text('This post is private. Log in to Instagram to save it.'), findsOneWidget);
    expect(find.text('Clear failed'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('2')),
      findsOneWidget,
    );
    await shoot(tester, '5_queue');

    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(native.started, contains('c'));
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('vault lists finished downloads, filters and deletes', (tester) async {
    await pumpApp(
      tester,
      tasks: [
        storedTask('v1', 'Golden hour timelapse', MediaPlatform.tiktok, videoFormat(1080), DownloadStatus.completed, files: ['/none/a.mp4'], size: 148 * 1024 * 1024),
        storedTask('v2', 'Lo-fi study mix', MediaPlatform.youtube, mp3Format, DownloadStatus.completed, minutesAgo: 5, files: ['/none/b.mp3'], size: 9 * 1024 * 1024),
        storedTask('v3', 'Product launch photos', MediaPlatform.linkedin, photosFormat, DownloadStatus.completed, minutesAgo: 9, files: ['/none/1.jpg', '/none/2.jpg'], size: 3 * 1024 * 1024),
        storedTask('v4', 'Harbour at dusk', MediaPlatform.instagram, videoFormat(720), DownloadStatus.completed, minutesAgo: 20, files: ['/none/c.mp4'], size: 40 * 1024 * 1024),
      ],
    );
    await openTab(tester, 'Vault');

    expect(find.text('Golden hour timelapse'), findsOneWidget);
    expect(find.text('1080p · 148 MB'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    await shoot(tester, '6_vault_grid');

    await tester.tap(find.byTooltip('Show as list'));
    await settle(tester);
    await shoot(tester, '7_vault_list');

    await tester.tap(find.widgetWithText(ChoiceChip, 'YouTube'));
    await settle(tester);
    expect(find.text('Lo-fi study mix'), findsOneWidget);
    expect(find.text('Golden hour timelapse'), findsNothing);

    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(find.text('Delete this download?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await settle(tester);

    // The filter's last item is gone, so the vault falls back to everything.
    expect(find.text('Lo-fi study mix'), findsNothing);
    expect(find.text('Golden hour timelapse'), findsOneWidget);
  });

  testWidgets('settings shows accounts and extractor versions', (tester) async {
    await pumpApp(tester, signedIn: {PlatformAccount.instagram});
    await openTab(tester, 'Settings');

    expect(find.text('Signed in'), findsOneWidget);
    expect(find.text('Not signed in'), findsNWidgets(3));
    expect(find.text('Log out'), findsOneWidget);
    expect(find.text('1.32.20'), findsOneWidget);
    await shoot(tester, '8_settings');

    await tester.tap(find.text('Log out'));
    await settle(tester);
    expect(find.text('Not signed in'), findsNWidgets(4));

    await tester.scrollUntilVisible(find.text('Update extractors'), 200);
    await tester.tap(find.text('Update extractors'));
    await settle(tester);
    expect(find.text('Updated yt-dlp 2026.11.14.'), findsWidgets);
    await tester.pump(const Duration(seconds: 5));
  });
}
