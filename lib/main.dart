import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'core/providers.dart';
import 'features/downloader/data/download_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The queue reads its history synchronously, so storage is opened first.
  // If it cannot be opened the app still works, without saved history.
  DownloadRepository repository;
  try {
    repository = await HiveDownloadRepository.open();
  } catch (_) {
    repository = InMemoryDownloadRepository();
  }

  runApp(
    ProviderScope(
      overrides: [downloadRepositoryProvider.overrideWithValue(repository)],
      child: const SaveKitApp(),
    ),
  );
}
