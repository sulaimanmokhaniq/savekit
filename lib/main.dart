import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'core/providers.dart';
import 'core/settings/app_settings.dart';
import 'features/downloader/data/download_repository.dart';
import 'features/player/audio_player_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Background playback has to be set up before the first player exists.
  try {
    await initBackgroundAudio();
  } catch (_) {
    // The player still works while the app is open.
  }

  // The queue reads its history synchronously, so storage is opened first.
  // If it cannot be opened the app still works, without saved history or
  // saved preferences.
  DownloadRepository repository;
  SettingsRepository settings;
  PositionStore positions;
  try {
    repository = await HiveDownloadRepository.open();
    settings = await HiveSettingsRepository.open();
    positions = await HivePositionStore.open();
  } catch (_) {
    repository = InMemoryDownloadRepository();
    settings = InMemorySettingsRepository();
    positions = MemoryPositionStore();
  }

  runApp(
    ProviderScope(
      overrides: [
        downloadRepositoryProvider.overrideWithValue(repository),
        settingsRepositoryProvider.overrideWithValue(settings),
        positionStoreProvider.overrideWithValue(positions),
      ],
      child: const SaveKitApp(),
    ),
  );
}
