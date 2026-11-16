import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:savekit/app/app.dart';
import 'package:savekit/core/platform/media_platform.dart';
import 'package:savekit/core/theme/app_theme.dart';
import 'package:savekit/features/downloader/application/download_queue_controller.dart';
import 'package:savekit/features/downloader/domain/download_progress.dart';
import 'package:savekit/features/downloader/domain/download_task.dart';
import 'package:savekit/features/tools/application/storage_controller.dart';
import 'package:savekit/features/vault/application/folders_controller.dart';
import 'package:savekit/features/vault/application/phone_import.dart';

import 'app_test.dart' show loadFonts;
import 'support/fakes.dart';

final bool screenshots = Platform.environment['SAVEKIT_SCREENSHOTS'] == '1';

/// Picks [picked] and "copies" each into a real file in [folder].
class FakePhoneMedia implements PhoneMediaService {
  FakePhoneMedia(this.picked, this.folder);

  List<PickedMedia> picked;
  final Directory folder;
  final copiedFrom = <String>[];

  @override
  Future<List<PickedMedia>> pick() async => picked;

  @override
  Future<Map<String, String>> copy(
    List<PickedMedia> items,
    String outputDir,
  ) async => {
    for (final item in items)
      item.uri: (File(
        '${folder.path}/${item.name}',
      )..writeAsBytesSync(List.filled(item.size, 0))).path,
  }..forEach((uri, _) => copiedFrom.add(uri));
}

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

  group('folders', () {
    test('keep their items, order and colour, and survive a restart', () {
      final repository = InMemoryFolderRepository();
      final container = ProviderContainer(
        overrides: [folderRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final folders = container.read(foldersProvider.notifier);

      final trips = folders.create('  Trips ', colorIndex: 3);
      final recipes = folders.create('Recipes');
      folders
        ..add(trips, ['a', 'b'])
        // Already there: stays once, moves to the top.
        ..add(trips, ['c', 'a'])
        ..remove(trips, ['b'])
        ..move(recipes, -1)
        ..rename(trips, 'Travel');

      final saved = container.read(foldersProvider);
      expect([for (final folder in saved) folder.name], ['Recipes', 'Travel']);
      expect(saved[1].taskIds, ['c', 'a']);
      expect(saved[1].color, folderColors[3]);

      // What the repository keeps reads back the same.
      final reloaded = [
        for (final folder in repository.load())
          VaultFolder.fromMap(folder.toMap()),
      ];
      expect(reloaded[1].taskIds, ['c', 'a']);
      expect(reloaded[1].name, 'Travel');

      folders.delete(recipes);
      expect(container.read(foldersProvider).single.name, 'Travel');
    });

    test('readable locations drop the storage root', () {
      expect(
        readableLocation(
          '/storage/emulated/0/Android/data/com.savekit.app/files/downloads',
        ),
        'Android/data/com.savekit.app/files/downloads',
      );
      expect(
        const PickedMedia(
          uri: 'u',
          name: 'IMG_1.jpg',
          size: 1,
          folder: 'DCIM/Camera/',
        ).location,
        'DCIM/Camera/IMG_1.jpg',
      );
    });
  });

  group('screens', () {
    late Directory temp;
    late DeletingNative native;
    late FakePhoneMedia phone;
    late UiFakeGallery gallery;

    setUp(() => temp = Directory.systemTemp.createTempSync('savekit-folders'));
    tearDown(() => temp.deleteSync(recursive: true));

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
      List<DownloadTask> tasks = const [],
      List<PickedMedia> picked = const [],
    }) async {
      native = DeletingNative();
      gallery = UiFakeGallery();
      phone = FakePhoneMedia(picked, temp);
      tester.view.physicalSize = const Size(824, 1830);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      addTearDown(() => AppColors.current = AppPalette.fallback);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...uiOverrides(
              native: native,
              tasks: tasks,
              gallery: gallery,
              storage: const StorageSnapshot(),
            ),
            phoneMediaServiceProvider.overrideWithValue(phone),
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

    Future<void> newFolder(WidgetTester tester, String name) async {
      await tester.tap(find.text('New folder'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), name);
      await tester.pump();
      await tester.tap(find.text('Create'));
      await settle(tester);
    }

    testWidgets('make a folder and put Vault items in it', (tester) async {
      final file = File('${temp.path}/clip.mp4')..writeAsBytesSync([0]);
      final container = await open(
        tester,
        tasks: [
          storedTask(
            't1',
            'Harbour at dawn',
            MediaPlatform.youtube,
            videoFormat(1080),
            DownloadStatus.completed,
            files: [file.path],
          ),
        ],
      );

      await newFolder(tester, 'Trips');
      // A new folder opens straight away, empty.
      expect(find.text('This folder is empty'), findsOneWidget);
      await shoot(tester, '36_folder_empty');
      await tester.pageBack();
      await settle(tester);
      expect(find.text('Trips'), findsOneWidget);
      expect(find.text('0 items'), findsOneWidget);
      await shoot(tester, '37_vault_folders');

      // Select a download and add it to the folder.
      await tester.longPress(find.text('Harbour at dawn'));
      await settle(tester);
      await tester.tap(find.byTooltip('Add to folder'));
      await settle(tester);
      await tester.tap(find.text('Trips').last);
      await settle(tester);
      expect(find.text('Added 1 to Trips.'), findsOneWidget);
      expect(find.text('1 item'), findsOneWidget);

      // Inside, it can be taken out again; it stays in the Vault.
      await tester.tap(find.text('Trips'));
      await settle(tester);
      expect(find.byTooltip('Add from phone'), findsOneWidget);
      expect(find.text('Harbour at dawn'), findsOneWidget);
      await tester.longPress(find.text('Harbour at dawn'));
      await settle(tester);
      await tester.tap(find.byTooltip('Remove from folder'));
      await settle(tester);
      expect(find.text('This folder is empty'), findsOneWidget);
      expect(container.read(completedDownloadsProvider), hasLength(1));
    });

    const fromCamera = PickedMedia(
      uri: 'content://docs/image:1',
      name: 'IMG_0001.jpg',
      size: 2048,
      mediaUri: 'content://media/external/images/media/1',
      folder: 'DCIM/Camera/',
    );
    const fromCamera2 = PickedMedia(
      uri: 'content://docs/video:2',
      name: 'VID_0002.mp4',
      size: 4096,
      isVideo: true,
      mediaUri: 'content://media/external/video/media/2',
      folder: 'DCIM/Camera/',
    );
    const fromDrive = PickedMedia(
      uri: 'content://drive/abc',
      name: 'scan.jpg',
      size: 1024,
    );

    testWidgets('moving from the phone shows both paths, then asks Android', (
      tester,
    ) async {
      final container = await open(tester, picked: [fromCamera, fromCamera2]);
      await newFolder(tester, 'Private');
      await tester.tap(find.text('Add from phone'));
      await settle(tester);

      // Where each file is now, and where it goes.
      expect(find.text('DCIM/Camera/IMG_0001.jpg'), findsOneWidget);
      expect(find.text('DCIM/Camera/VID_0002.mp4'), findsOneWidget);
      expect(find.text('savekit/downloads'), findsNothing);
      expect(find.text('/savekit/downloads'), findsOneWidget);
      expect(find.text('Copy 2 files'), findsOneWidget);

      await tester.tap(find.text('Move'));
      await settle(tester);
      expect(find.text('MOVING TO'), findsOneWidget);
      expect(find.textContaining('leave your gallery'), findsOneWidget);
      await shoot(tester, '38_import_move');

      await tester.tap(find.text('Move 2 files'));
      await settle(tester);
      expect(phone.copiedFrom, [fromCamera.uri, fromCamera2.uri]);
      // The originals are deleted through Android, by their media entries.
      expect(native.deleted, [fromCamera.mediaUri, fromCamera2.mediaUri]);
      // …and not copied back into the gallery.
      expect(gallery.exportedPaths, isEmpty);
      expect(find.text('2 files moved into SaveKit.'), findsOneWidget);

      final folder = container.read(foldersProvider).single;
      final inFolder = container.read(folderTasksProvider(folder.id));
      expect(
        [for (final task in inFolder) task.title],
        ['IMG_0001', 'VID_0002'],
      );
      expect(inFolder.first.platform, MediaPlatform.device);
    });

    testWidgets('a refused delete keeps both copies and says so', (
      tester,
    ) async {
      await open(tester, picked: [fromCamera]);
      native.allow = false;
      await newFolder(tester, 'Private');
      await tester.tap(find.text('Add from phone'));
      await settle(tester);
      await tester.tap(find.text('Move'));
      await settle(tester);
      await tester.tap(find.text('Move 1 file'));
      await settle(tester);
      expect(find.textContaining('originals are still on the phone'), findsOne);
      expect(find.text('IMG_0001'), findsOneWidget);
    });

    testWidgets('files from elsewhere can only be copied', (tester) async {
      await open(tester, picked: [fromCamera, fromDrive]);
      await newFolder(tester, 'Scans');
      await tester.tap(find.text('Add from phone'));
      await settle(tester);
      expect(find.textContaining('copy only'), findsOneWidget);
      expect(find.textContaining('Moving works only'), findsOneWidget);
      // Move is offered but cannot be chosen.
      await tester.tap(find.text('Move'));
      await settle(tester);
      expect(find.text('Copy 2 files'), findsOneWidget);
      await tester.tap(find.text('Copy 2 files'));
      await settle(tester);
      expect(native.deleted, isEmpty);
      expect(find.text('2 files copied into SaveKit.'), findsOneWidget);
    });

    testWidgets('deleting a folder keeps its items', (tester) async {
      final file = File('${temp.path}/clip.mp4')..writeAsBytesSync([0]);
      final container = await open(
        tester,
        tasks: [
          storedTask(
            't1',
            'Harbour at dawn',
            MediaPlatform.youtube,
            videoFormat(1080),
            DownloadStatus.completed,
            files: [file.path],
          ),
        ],
      );
      final id = container.read(foldersProvider.notifier).create('Trips');
      container.read(foldersProvider.notifier).add(id, ['t1']);
      await settle(tester);

      await tester.longPress(find.text('Trips'));
      await settle(tester);
      await tester.tap(find.text('Delete folder'));
      await settle(tester);
      expect(find.textContaining('Everything in it stays'), findsOneWidget);
      await tester.tap(find.text('Delete folder').last);
      await settle(tester);
      expect(container.read(foldersProvider), isEmpty);
      expect(find.text('Harbour at dawn'), findsOneWidget);
    });
  });
}
