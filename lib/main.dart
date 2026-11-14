import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  runApp(const SaveKitApp());
}

/// Phase 1 shell: boots the native engine and reports its state, proving the
/// Kotlin bridge, bundled binaries and yt-dlp work on the device. The real
/// navigation shell and screens replace this in Phase 4.
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

class EngineStatusScreen extends StatefulWidget {
  const EngineStatusScreen({super.key});

  @override
  State<EngineStatusScreen> createState() => _EngineStatusScreenState();
}

class _EngineStatusScreenState extends State<EngineStatusScreen> {
  static const _engine = MethodChannel('com.app.downloader/engine');

  late Future<String> _version = _initEngine();

  Future<String> _initEngine() async {
    final result = await _engine.invokeMapMethod<String, dynamic>('initEngine');
    return (result?['version'] as String?) ?? 'unknown';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: FutureBuilder<String>(
            future: _version,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Preparing the download engine…'),
                  ],
                );
              }
              if (snapshot.hasError) {
                final error = snapshot.error;
                final message = error is PlatformException
                    ? (error.message ?? error.code)
                    : error.toString();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 40),
                    const SizedBox(height: 16),
                    Text(
                      'Engine failed to start\n$message',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: () => setState(() => _version = _initEngine()),
                      child: const Text('Retry'),
                    ),
                  ],
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_outline, size: 40),
                  const SizedBox(height: 16),
                  Text(
                    'Engine ready\nyt-dlp ${snapshot.data}',
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
