import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:savekit/app/app.dart';
import 'package:savekit/core/theme/app_theme.dart';
import 'package:savekit/features/tools/application/storage_controller.dart';
import 'package:savekit/features/transfer/transfer_controller.dart';
import 'package:savekit/features/transfer/transfer_screen.dart';

import 'app_test.dart' show loadFonts;
import 'support/fakes.dart';

final bool screenshots = Platform.environment['SAVEKIT_SCREENSHOTS'] == '1';

void main() {
  setUpAll(loadFonts);

  final screenOn = <bool>[];

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 450));
  }

  Future<void> open(WidgetTester tester, List<String> addresses) async {
    screenOn.clear();
    tester.view.physicalSize = const Size(824, 1830);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(() => AppColors.current = AppPalette.fallback);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...uiOverrides(
            native: UiFakeNative(),
            storage: const StorageSnapshot(),
          ),
          localAddressesProvider.overrideWithValue(() async => addresses),
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
        matching: find.text('Tools'),
      ),
    );
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Wireless transfer'), 200);
    await tester.tap(find.text('Wireless transfer'));
    // Opening a real socket needs real time.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await settle(tester);
  }

  testWidgets('shows the address and code, and stops when left', (
    tester,
  ) async {
    await open(tester, ['192.168.1.20']);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TransferScreen)),
    );
    final state = container.read(transferProvider);
    expect(state.phase, TransferPhase.running);
    expect(state.address, startsWith('http://192.168.1.20:'));
    expect(state.code, matches(RegExp(r'^\d{4}$')));
    expect(find.text(state.address), findsOneWidget);
    expect(find.text(state.code), findsOneWidget);
    expect(screenOn, [true]);
    if (screenshots) {
      await expectLater(
        find.byType(SaveKitApp),
        matchesGoldenFile('screenshots/34_transfer.png'),
      );
    }

    // Leaving the screen stops sharing and lets the display sleep again.
    // (That a stopped server no longer answers is covered by its own test.)
    await tester.pageBack();
    await settle(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester);
    expect(find.byType(TransferScreen), findsNothing);
    expect(screenOn, [true, false]);
  });

  testWidgets('says so when the phone is not on Wi-Fi', (tester) async {
    await open(tester, []);
    expect(find.text('No Wi-Fi'), findsOneWidget);
    expect(screenOn, isEmpty);
  });
}
