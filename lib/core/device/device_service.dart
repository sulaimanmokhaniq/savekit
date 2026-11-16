import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../native/youtube_dl_native_service.dart';

/// Facts about the installed app and the phone.
class AppInfo {
  const AppInfo({
    required this.version,
    this.android = '',
    this.sdk = 0,
    this.device = '',
    this.abi = '',
  });

  /// The app's version name, e.g. "1.0.15".
  final String version;
  final String android;
  final int sdk;
  final String device;
  final String abi;
}

/// Small questions for Android; a seam for tests.
abstract interface class DeviceService {
  Future<AppInfo> appInfo();
  Future<bool> isCharging();

  /// Opens an https address in the phone's browser.
  Future<bool> openUrl(String url);

  /// How the app's process ended recently (crash, freeze…), newest first,
  /// as text lines for a problem report.
  Future<List<String>> exitReasons();
}

class ChannelDeviceService implements DeviceService {
  const ChannelDeviceService();

  static const _channel = MethodChannel(YoutubeDlNativeService.engineChannel);

  @override
  Future<AppInfo> appInfo() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('getAppInfo');
      return AppInfo(
        version: map?['version'] as String? ?? '',
        android: map?['android'] as String? ?? '',
        sdk: (map?['sdk'] as num?)?.toInt() ?? 0,
        device: map?['device'] as String? ?? '',
        abi: map?['abi'] as String? ?? '',
      );
    } catch (_) {
      return const AppInfo(version: '');
    }
  }

  @override
  Future<bool> isCharging() async {
    try {
      return await _channel.invokeMethod<bool>('isCharging') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<String>> exitReasons() async {
    try {
      final exits = await _channel.invokeListMethod<Map>('getExitReasons');
      return [
        for (final exit in exits ?? const <Map>[])
          [
            '${exit['time']}  ${exit['reason']}'
                '${exit['description'] == null ? '' : ' · ${exit['description']}'}',
            if (exit['trace'] != null)
              '    ${(exit['trace'] as String).replaceAll('\n', '\n    ')}',
          ].join('\n'),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<bool> openUrl(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ??
          false;
    } catch (_) {
      return false;
    }
  }
}

final deviceServiceProvider = Provider<DeviceService>(
  (ref) => const ChannelDeviceService(),
);

final appInfoProvider = FutureProvider<AppInfo>(
  (ref) => ref.watch(deviceServiceProvider).appInfo(),
);

/// Whether the phone is charging, checked every minute while the app runs.
final chargingProvider = StreamProvider<bool>((ref) async* {
  final device = ref.watch(deviceServiceProvider);
  yield await device.isCharging();
  yield* Stream<void>.periodic(const Duration(minutes: 1))
      .asyncMap((_) => device.isCharging())
      .distinct();
});
