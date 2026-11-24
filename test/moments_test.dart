import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:savekit/app/app.dart';
import 'package:savekit/core/platform/media_platform.dart';
import 'package:savekit/core/theme/app_theme.dart';
import 'package:savekit/features/downloader/application/download_queue_controller.dart';
import 'package:savekit/features/downloader/domain/download_progress.dart';
import 'package:savekit/features/moments/moments_controller.dart';
import 'package:savekit/features/tools/application/storage_controller.dart';

import 'support/fakes.dart';

void main() {
  test('moments keep their place and note through storage', () {
    final repository = InMemoryMomentRepository();
    final container = ProviderContainer(
      overrides: [momentRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final moments = container.read(momentsProvider.notifier);
    final first = moments.add(
      taskId: 't',
      path: '/a.mp4',
      position: const Duration(minutes: 3, seconds: 7),
      note: '  the answer ',
    );
    moments.editNote(first.id, 'the real answer');
    final stored = Moment.fromMap(repository.load().single.toMap());
    expect(stored.position, const Duration(minutes: 3, seconds: 7));
    expect(stored.note, 'the real answer');
    moments.remove(first.id);
    expect(container.read(momentsProvider), isEmpty);
  });

  testWidgets('moments are listed by file and can become clips', (
    tester,
  ) async {
    final folder = Directory.systemTemp.createTempSync('savekit-moments');
    addTearDown(() => folder.deleteSync(recursive: true));
    final video = (File('${folder.path}/talk.mp4')..writeAsBytesSync([0])).path;
    final native = UiFakeNative();
    tester.view.physicalSize = const Size(824, 1830);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(() => AppColors.current = AppPalette.fallback);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...uiOverrides(
            native: native,
            storage: const StorageSnapshot(),
            tasks: [
              storedTask(
                'talk',
                'A long talk',
                MediaPlatform.youtube,
                videoFormat(720),
                DownloadStatus.completed,
                files: [video],
              ),
            ],
          ),
          momentRepositoryProvider.overrideWithValue(
            InMemoryMomentRepository([
              Moment(
                id: 'm1',
                taskId: 'talk',
                path: video,
                position: const Duration(minutes: 12, seconds: 5),
                note: 'The main point',
                createdAt: DateTime(2026, 11, 20),
              ),
              Moment(
                id: 'gone',
                taskId: 'deleted',
                path: '/nowhere.mp4',
                position: Duration.zero,
                createdAt: DateTime(2026, 11, 20),
              ),
            ]),
          ),
        ],
        child: const SaveKitApp(),
      ),
    );
    Future<void> settle() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump(const Duration(milliseconds: 450));
    }

    await settle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Tools'),
      ),
    );
    await settle();
    await tester.scrollUntilVisible(find.text('Moments'), 200);
    await tester.tap(find.text('Moments'));
    await settle();

    expect(find.text('A long talk'), findsOneWidget);
    expect(find.text('12:05'), findsOneWidget);
    expect(find.text('The main point'), findsOneWidget);

    await tester.tap(find.byTooltip('More'));
    await settle();
    await tester.tap(find.text('Save as a clip'));
    await settle();
    await tester.tap(find.text('30 seconds'));
    await settle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SaveKitApp)),
    );
    final clip = container.read(downloadQueueControllerProvider).first;
    expect(clip.format.formatSelection, 'clip');
    expect(clip.format.options, {'start': '725.00', 'length': '30'});
    expect(clip.title, 'The main point');
    await tester.pump(const Duration(seconds: 5));
  });
}
