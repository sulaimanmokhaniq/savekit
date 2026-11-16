import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/l10n/l10n.dart';
import '../../core/native/youtube_dl_native_service.dart';
import '../../core/platform/media_platform.dart';
import '../../core/providers.dart';
import '../downloader/application/download_queue_controller.dart';
import '../downloader/data/gallery_export_service.dart';
import '../extractor/domain/media_format.dart';
import 'transfer_server.dart';

/// The phone's addresses on the local network; a seam for tests.
final localAddressesProvider = Provider<Future<List<String>> Function()>(
  (ref) => localAddresses,
);

/// Keeps the display awake (or lets it sleep again); a seam for tests.
final keepScreenOnProvider = Provider<Future<void> Function(bool on)>(
  (ref) => (on) async {
    try {
      await const MethodChannel(YoutubeDlNativeService.engineChannel)
          .invokeMethod<void>('keepScreenOn', {'on': on});
    } catch (_) {
      // Not on Android: the screen follows its own settings.
    }
  },
);

enum TransferPhase { starting, running, noNetwork, failed }

class TransferState {
  const TransferState({
    this.phase = TransferPhase.starting,
    this.address = '',
    this.code = '',
    this.received = const [],
  });

  final TransferPhase phase;

  /// What to type in the other device's browser, such as
  /// `http://192.168.1.20:8080`.
  final String address;

  /// The four digits the browser asks for.
  final String code;

  /// Names of the files sent to the phone this session, newest first.
  final List<String> received;

  /// The address with the code attached, for the QR code.
  String get link => '$address/?code=$code';
}

/// Shares the Vault with browsers on the same Wi-Fi while its screen is
/// open, and files what they send back into the Vault.
class TransferController extends Notifier<TransferState> {
  TransferServer? _server;

  late Future<void> Function(bool on) _keepScreenOn;
  bool _screenKeptOn = false;

  @override
  TransferState build() {
    // Read now: providers cannot be read while this one is being disposed.
    _keepScreenOn = ref.read(keepScreenOnProvider);
    ref.onDispose(() {
      unawaited(_server?.stop());
      if (_screenKeptOn) unawaited(_keepScreenOn(false));
    });
    return const TransferState();
  }

  List<SharedFile> _files() => [
    for (final task in ref.read(completedDownloadsProvider))
      for (final path in task.filePaths)
        SharedFile(
          path: path,
          title: task.title,
          kind: savedFileKindOf(path).name,
          thumbnail: (task.thumbnail?.startsWith('http') ?? false)
              ? task.thumbnail
              : null,
        ),
  ];

  /// A file arrived from the browser: put it in the Vault (and the gallery,
  /// when that is where the user saves).
  Future<void> _received(String path) async {
    if (!ref.mounted) return;
    final kind = savedFileKindOf(path);
    await ref
        .read(downloadQueueControllerProvider.notifier)
        .addCompleted(
          title: p.basenameWithoutExtension(path),
          platform: MediaPlatform.device,
          format: MediaFormat(
            id: 'transfer',
            kind: switch (kind) {
              SavedFileKind.video => MediaFormatKind.video,
              SavedFileKind.audio => MediaFormatKind.audio,
              _ => MediaFormatKind.gallery,
            },
            label: 'Sent from another device',
            itemCount: 1,
            imageCount: kind == SavedFileKind.image ? 1 : 0,
            videoCount: kind == SavedFileKind.video ? 1 : 0,
          ),
          filePaths: [path],
        );
    if (!ref.mounted) return;
    state = TransferState(
      phase: state.phase,
      address: state.address,
      code: state.code,
      received: [p.basename(path), ...state.received],
    );
  }

  /// Starts sharing (again). Safe to call when already running.
  Future<void> start() async {
    await _server?.stop();
    if (!ref.mounted) return;
    state = const TransferState();
    final addresses = await ref.read(localAddressesProvider)();
    if (!ref.mounted) return;
    if (addresses.isEmpty) {
      state = const TransferState(phase: TransferPhase.noNetwork);
      return;
    }
    final server = TransferServer(
      files: _files,
      uploadDirectory: ref.read(appPathsProvider).downloadDirectory,
      onUploaded: _received,
      texts: TransferTexts(
        rtl: L10n.isArabic,
        enterCode: tr('Enter the code shown on the phone'),
        open: tr('Open'),
        wrongCode: tr('Wrong code. Check the phone and try again.'),
        locked: tr('Too many wrong codes. Restart the transfer on the phone.'),
        onPhone: tr('On the phone'),
        empty: tr('Nothing saved yet.'),
        download: tr('Download'),
        send: tr('Send files to the phone'),
        sendHint: tr('Choose files, or drop them here.'),
        sent: tr('Saved on the phone'),
        failed: tr('Could not be sent'),
        all: tr('All'),
        videos: tr('Videos'),
        audio: tr('Audio'),
        photos: tr('Photos'),
      ),
    );
    try {
      await server.start();
    } catch (_) {
      if (ref.mounted) state = const TransferState(phase: TransferPhase.failed);
      return;
    }
    if (!ref.mounted) {
      await server.stop();
      return;
    }
    _server = server;
    _screenKeptOn = true;
    unawaited(_keepScreenOn(true));
    state = TransferState(
      phase: TransferPhase.running,
      address: 'http://${addresses.first}:${server.port}',
      code: server.code,
    );
  }
}

/// Lives only while the transfer screen is open: leaving it stops sharing.
final transferProvider =
    NotifierProvider.autoDispose<TransferController, TransferState>(
      TransferController.new,
    );
