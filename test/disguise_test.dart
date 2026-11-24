import 'dart:io';

import 'app_test.dart' show loadFonts;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:savekit/app/app.dart';
import 'package:savekit/core/settings/app_settings.dart';
import 'package:savekit/core/theme/app_theme.dart';
import 'package:savekit/features/disguise/calculator.dart';
import 'package:savekit/features/disguise/calculator_screen.dart';
import 'package:savekit/features/tools/application/storage_controller.dart';

import 'support/fakes.dart';

void main() {
  setUpAll(loadFonts);
  group('calculator', () {
    Calculator typed(String keys) {
      final calculator = Calculator();
      for (final key in keys.split(' ')) {
        switch (key) {
          case '+' || '−' || '×' || '÷':
            calculator.operator(key);
          case '=':
            calculator.equals();
          case '.':
            calculator.point();
          case '%':
            calculator.percent();
          case 'C':
            calculator.clear();
          default:
            for (final d in key.split('')) {
              calculator.digit(d);
            }
        }
      }
      return calculator;
    }

    test('does sums like any calculator', () {
      expect(typed('12 + 30 =').display, '42');
      expect(typed('7 × 6 =').display, '42');
      expect(typed('1 ÷ 4 =').display, '0.25');
      expect(
        typed('10 − 3 × 2 =').display,
        '14',
      ); // left to right, as phones do
      expect(typed('2 . 5 + 2 . 5 =').display, '5');
      expect(typed('50 %').display, '0.5');
      expect(typed('1 ÷ 0 =').display, 'Error');
      expect(typed('1 ÷ 3 =').display, '0.333333333333');
    });

    test('remembers the digits typed for the secret code', () {
      final calculator = Calculator();
      for (final d in '2580'.split('')) {
        calculator.digit(d);
      }
      expect(calculator.equals(), '2580');
      expect(calculator.typed, '');
      calculator
        ..digit('1')
        ..digit('2')
        ..backspace()
        ..digit('3');
      expect(calculator.equals(), '13');
    });
  });

  group('disguise', () {
    Future<ProviderContainer> open(
      WidgetTester tester, {
      required String code,
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
              storage: const StorageSnapshot(),
              settings: AppSettings(disguiseCode: code),
            ),
            taskLabelProvider.overrideWithValue((_) async {}),
          ],
          child: const SaveKitApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      return ProviderScope.containerOf(tester.element(find.byType(SaveKitApp)));
    }

    Future<void> press(WidgetTester tester, String keys) async {
      for (final key in keys.split('')) {
        await tester.tap(find.text(key).last);
        await tester.pump();
      }
    }

    testWidgets('opens on a calculator; the code and = open SaveKit', (
      tester,
    ) async {
      await open(tester, code: '2580');
      expect(find.byType(CalculatorScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      // A wrong code just calculates.
      await press(tester, '12+30=');
      expect(find.text('42'), findsOneWidget);
      if (const bool.fromEnvironment('dart.vm.product') == false &&
          Platform.environment['SAVEKIT_SCREENSHOTS'] == '1') {
        await expectLater(
          find.byType(SaveKitApp),
          matchesGoldenFile('screenshots/41_calculator.png'),
        );
      }
      expect(find.byType(NavigationBar), findsNothing);

      await tester.tap(find.text('AC'));
      await press(tester, '2580=');
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.byType(CalculatorScreen), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('holding = opens it with the phone lock', (tester) async {
      await open(tester, code: '2580');
      await tester.longPress(find.text('='));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    test('the disguise changes the icon and splash, and is stored', () {
      const shown = AppSettings(themeId: 'tide', iconId: 'rose');
      final hidden = shown.copyWith(disguiseCode: '2580');
      expect(hidden.launcherIconId, 'calculator');
      expect(hidden.splashId, 'calculator');
      expect(AppSettings.fromMap(hidden.toMap()).disguiseCode, '2580');
      final back = hidden.copyWith(clearDisguise: true);
      expect(back.launcherIconId, 'rose');
      expect(back.splashId, 'tide');
    });
  });
}
