import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:savekit/app/app.dart';
import 'package:savekit/app/opening_splash.dart';
import 'package:savekit/core/settings/app_settings.dart';
import 'package:savekit/core/theme/app_theme.dart';
import 'package:savekit/features/tools/application/storage_controller.dart';

import 'support/fakes.dart';

final bool screenshots = Platform.environment['SAVEKIT_SCREENSHOTS'] == '1';

void main() {
  testWidgets('the logo opens the app in the theme, then gets out of the way', (
    tester,
  ) async {
    final splashThemes = <String>[];
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
            settings: const AppSettings(themeId: 'tide'),
          ),
          splashThemeProvider.overrideWithValue(
            (theme) async => splashThemes.add(theme),
          ),
        ],
        child: const SaveKitApp(),
      ),
    );

    // The first frame is the logo on the theme's background, as Android's
    // splash showed it.
    expect(find.byType(OpeningSplash), findsOneWidget);
    final background = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(OpeningSplash),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(background.color, AppPalette.byId('tide').background);
    // The next launch's splash is told the theme as well.
    expect(splashThemes, ['tide']);

    for (final (frame, ms) in [(1, 120), (2, 240), (3, 480)]) {
      await tester.pump(Duration(milliseconds: ms - (frame == 1 ? 0 : 0)));
      if (screenshots) {
        await expectLater(
          find.byType(SaveKitApp),
          matchesGoldenFile('screenshots/35_opening_$frame.png'),
        );
      }
    }

    // It never blocks a tap, and is gone soon after.
    await tester.pump(OpeningSplash.duration);
    await tester.pump();
    expect(find.byType(OpeningSplash), findsNothing);

    // Choosing another theme updates the next launch's splash.
    ProviderScope.containerOf(tester.element(find.byType(NavigationBar)))
        .read(settingsControllerProvider.notifier)
        .setTheme('rose');
    await tester.pump();
    expect(splashThemes, ['tide', 'rose']);
  });
}
