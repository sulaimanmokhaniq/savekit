import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/engine/engine_controller.dart';
import 'core/providers.dart';
import 'features/downloader/application/download_queue_controller.dart';
import 'features/downloader/data/download_repository.dart';
import 'features/extractor/application/incoming_link_controller.dart';

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

/// Temporary shell: boots the engine, the queue and the share/clipboard
/// listeners and reports their state. The navigation shell and screens of
/// Phase 4 replace it.
class SaveKitApp extends StatelessWidget {
  const SaveKitApp({super.key});

  static const background = Color(0xFF0D0F14);
  static const surface = Color(0xFF161922);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SaveKit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(surface: surface),
      ),
      home: const EngineStatusScreen(),
    );
  }
}

class EngineStatusScreen extends ConsumerWidget {
  const EngineStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(engineControllerProvider);
    final queued = ref.watch(downloadQueueControllerProvider).length;
    final links = ref.watch(incomingLinkControllerProvider);
    final incoming = links.shared ?? links.clipboard;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: engine.when(
            loading: () => const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Preparing the download engine…'),
              ],
            ),
            error: (error, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 16),
                Text(
                  'Engine failed to start\n$error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => ref.invalidate(engineControllerProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
            data: (state) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline, size: 40),
                const SizedBox(height: 16),
                Text(
                  'Engine ready\n'
                  'yt-dlp ${state.version}\n'
                  'gallery-dl ${state.galleryVersion}\n'
                  '$queued saved download(s)'
                  '${incoming == null ? '' : '\nLink received: $incoming'}',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
