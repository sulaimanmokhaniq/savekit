import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'core/log/app_log.dart';
import 'core/providers.dart';
import 'core/settings/app_settings.dart';
import 'features/downloader/data/download_repository.dart';
import 'features/vault/application/folders_controller.dart';
import 'features/player/audio_player_controller.dart';
import 'features/player/player_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Problems are recorded for "Send a report", and kept across restarts.
  try {
    AppLog.attach(
      File(p.join((await getApplicationSupportDirectory()).path, 'log.txt')),
    );
  } catch (_) {
    // The report then only covers this run.
  }
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    AppLog.add('App error', '${details.exceptionAsString()}\n${details.stack}');
    previousOnError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.add('App error', '$error\n$stack');
    return false;
  };

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
  FolderRepository folders;
  try {
    repository = await HiveDownloadRepository.open();
    settings = await HiveSettingsRepository.open();
    positions = await HivePositionStore.open();
    folders = await HiveFolderRepository.open();
  } catch (_) {
    repository = InMemoryDownloadRepository();
    settings = InMemorySettingsRepository();
    positions = MemoryPositionStore();
    folders = InMemoryFolderRepository();
  }

  runApp(
    ProviderScope(
      overrides: [
        downloadRepositoryProvider.overrideWithValue(repository),
        settingsRepositoryProvider.overrideWithValue(settings),
        positionStoreProvider.overrideWithValue(positions),
        folderRepositoryProvider.overrideWithValue(folders),
      ],
      child: const SaveKitApp(),
    ),
  );
}
