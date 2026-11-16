import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:savekit/app/app.dart';
import 'package:savekit/core/theme/app_theme.dart';
import 'package:savekit/features/downloader/application/download_queue_controller.dart';
import 'package:savekit/features/tools/application/space_saver_controller.dart';
import 'package:savekit/features/tools/application/storage_controller.dart';
import 'package:savekit/features/tools/presentation/space_saver_screen.dart';

import 'app_test.dart' show loadFonts;
import 'support/fakes.dart';

final bool screenshots = Platform.environment['SAVEKIT_SCREENSHOTS'] == '1';

const mb = 1024 * 1024;

PhoneMedia photo(String name, int size, {int day = 1}) => PhoneMedia(
  uri: 'content://media/images/$name',
  path: '/storage/DCIM/$name',
  name: name,
  size: size,
  date: DateTime(2026, 5, day),
  width: 4000,
  height: 3000,
);

PhoneMedia clip(
  String name,
  int size, {
  int seconds = 60,
  int width = 1920,
  int height = 1080,
}) => PhoneMedia(
  uri: 'content://media/video/$name',
  path: '/storage/DCIM/$name',
  name: name,
  size: size,
  date: DateTime(2026, 4, 2),
  width: width,
  height: height,
  duration: Duration(seconds: seconds),
  isVideo: true,
);

class FakeSpace implements SpaceService {
  FakeSpace(this.result, {this.access = true});

  SpaceScan result;
  bool access;
  int scans = 0;

  @override
  Future<bool> requestAccess() async => access;

  @override
  Future<SpaceScan> scan() async {
    scans++;
    return result;
  }

  @override
  Future<ScanProgress> progress() async => const ScanProgress();

  @override
  Future<void> cancel() async {}

  @override
  Future<Uint8List?> preview(String uri, {int size = 256}) async => null;
}

/// Records what the space saver asks Android to delete.
class DeletingNative extends UiFakeNative {
  final deleted = <String>[];
  bool allow = true;

  @override
  Future<bool> deleteFromMediaStore({
    required List<String> locations,
    required List<String> names,
  }) async {
    if (allow) deleted.addAll(locations);
    return allow;
  }
}

void main() {
  setUpAll(loadFonts);

  group('compress plan', () {
    test('a long Full HD recording gets much smaller, same picture size', () {
      // 60 s at about 17 Mbps, as a phone camera records.
      final plan = compressPlanFor(
        clip('a.mp4', 128 * mb),
        CompressQuality.good,
      )!;
      expect(plan.shortSide, isNull);
      // (5000 + 96) kbps for 60 s.
      expect(plan.targetBytes, 38220000);
    });

    test('4K is brought down to the quality’s picture size', () {
      final video = clip('b.mp4', 400 * mb, width: 3840, height: 2160);
      expect(compressPlanFor(video, CompressQuality.good)!.shortSide, 1080);
      expect(compressPlanFor(video, CompressQuality.small)!.shortSide, 720);
    });

    test('upright videos are measured by their shorter side', () {
      final video = clip('c.mp4', 200 * mb, width: 1080, height: 1920);
      expect(compressPlanFor(video, CompressQuality.good)!.shortSide, isNull);
    });

    test('nothing is offered when little would be saved', () {
      // Already about as small as the plan would make it.
      expect(
        compressPlanFor(clip('d.mp4', 40 * mb), CompressQuality.good),
        isNull,
      );
      // Too small to bother with.
      expect(
        compressPlanFor(
          clip('e.mp4', 10 * mb, seconds: 5),
          CompressQuality.good,
        ),
        isNull,
      );
      // Unknown length.
      expect(
        compressPlanFor(
          clip('f.mp4', 300 * mb, seconds: 0),
          CompressQuality.good,
        ),
        isNull,
      );
      expect(
        compressPlanFor(photo('g.jpg', 30 * mb), CompressQuality.good),
        isNull,
      );
    });
  });

  test('deleted files leave the scan, and groups of one disappear', () {
    final a = photo('a.jpg', 4 * mb);
    final b = photo('b.jpg', 4 * mb);
    final c = photo('c.jpg', 3 * mb);
    final d = photo('d.jpg', 3 * mb);
    final e = photo('e.jpg', 2 * mb);
    final scan = SpaceScan(
      items: [a, b, c, d, e],
      duplicates: [
        [a, b],
      ],
      similar: [
        [c, d, e],
      ],
    );
    expect(scan.duplicateBytes, 4 * mb);
    expect(scan.similarBytes, 5 * mb);

    final after = scan.without({b.uri, e.uri});
    expect(after.items, [a, c, d]);
    expect(after.duplicates, isEmpty);
    expect(after.similar.single, [c, d]);
  });

  group('screen', () {
    late DeletingNative native;
    late FakeSpace space;

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

    Future<void> open(WidgetTester tester, SpaceScan scan) async {
      native = DeletingNative();
      space = FakeSpace(scan);
      tester.view.physicalSize = const Size(824, 1830);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      addTearDown(() => AppColors.current = AppPalette.fallback);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...uiOverrides(native: native, storage: const StorageSnapshot()),
            spaceServiceProvider.overrideWithValue(space),
          ],
          child: const SaveKitApp(),
        ),
      );
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Tools'),
        ),
      );
      await settle(tester);
      await tester.scrollUntilVisible(find.text('Space saver'), 200);
      await tester.tap(find.text('Space saver'));
      await settle(tester);
    }

    final a = photo('a.jpg', 4 * mb);
    final b = photo('b.jpg', 4 * mb);
    final c = photo('c.jpg', 3 * mb, day: 2);
    final d = photo('d.jpg', 3 * mb, day: 2);
    final big = clip('holiday.mp4', 128 * mb);
    final scan = SpaceScan(
      items: [a, b, c, d, big],
      duplicates: [
        [a, b],
      ],
      similar: [
        [c, d],
      ],
    );

    testWidgets('scans, then deletes the extra copies after asking', (
      tester,
    ) async {
      await open(tester, scan);
      expect(find.text('Find space on this phone'), findsOneWidget);
      await shoot(tester, '30_space_intro');

      await tester.tap(find.text('Scan my phone'));
      await settle(tester);
      expect(space.scans, 1);
      // 4 MB of copies, 3 MB of look-alikes and about 91.6 MB from the video.
      expect(find.textContaining('can be freed'), findsOneWidget);
      expect(find.text('Copies (1)'), findsOneWidget);
      expect(find.text('Look-alikes (1)'), findsOneWidget);
      expect(find.text('Videos (1)'), findsOneWidget);
      // The extra copy starts ticked.
      expect(find.text('Delete 1 · 4.0 MB'), findsOneWidget);
      await shoot(tester, '31_space_copies');

      await tester.tap(find.text('Delete 1 · 4.0 MB'));
      await settle(tester);
      expect(find.text('Delete this file?'), findsOneWidget);
      expect(native.deleted, isEmpty);
      await tester.tap(find.text('Delete').last);
      await settle(tester);
      // The newer of the two went; the older one stays.
      expect(native.deleted, [b.uri]);
      expect(find.text('Copies (0)'), findsOneWidget);
      expect(find.text('No copies found'), findsOneWidget);
    });

    testWidgets('one file of each group always stays', (tester) async {
      await open(tester, scan);
      await tester.tap(find.text('Scan my phone'));
      await settle(tester);
      await tester.tap(find.text('Look-alikes (1)'));
      await settle(tester);
      // Nothing is ticked for look-alikes until the user chooses.
      expect(find.text('Tap the files to delete'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey(d.uri)));
      await settle(tester);
      expect(find.text('Delete 1 · 3.0 MB'), findsOneWidget);
      await shoot(tester, '32_space_alike');

      await tester.tap(find.byKey(ValueKey(c.uri)));
      await settle(tester);
      expect(find.text('Keep at least one of each group.'), findsOneWidget);
      expect(find.text('Delete 1 · 3.0 MB'), findsOneWidget);
    });

    testWidgets('makes a video smaller through the queue', (tester) async {
      await open(tester, scan);
      await tester.tap(find.text('Scan my phone'));
      await settle(tester);
      await tester.tap(find.text('Videos (1)'));
      await settle(tester);
      expect(find.text('holiday.mp4'), findsOneWidget);
      expect(find.textContaining('128 MB now'), findsOneWidget);

      await tester.tap(find.text('holiday.mp4'));
      await settle(tester);
      await shoot(tester, '33_space_videos');
      await tester.tap(find.textContaining('Make 1 smaller'));
      await settle(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SpaceSaverScreen)),
      );
      final task = container.read(downloadQueueControllerProvider).single;
      expect(task.format.formatSelection, 'compress');
      expect(task.format.options['replaces'], big.uri);
      expect(task.format.options['shortSide'], isNull);
      expect(task.url, big.path);
      // The original is untouched.
      expect(native.deleted, isEmpty);
      // It cannot be queued twice while it is being made.
      expect(find.text('Making a smaller copy…'), findsOneWidget);
    });

    testWidgets('explains when access is refused', (tester) async {
      await open(tester, scan);
      space.access = false;
      await tester.tap(find.text('Scan my phone'));
      await settle(tester);
      expect(space.scans, 0);
      expect(find.textContaining('needs access to your photos'), findsOne);
    });
  });
}
