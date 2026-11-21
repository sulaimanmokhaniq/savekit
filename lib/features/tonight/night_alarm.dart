import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/native/youtube_dl_native_service.dart';
import '../../core/settings/app_settings.dart';

/// Asks Android to wake the app when the night begins. A sleeping phone
/// pauses the app's own timers, so without this the night downloads would
/// start only whenever the phone next woke up by itself.
class NightAlarm {
  const NightAlarm();

  static const _channel = MethodChannel(YoutubeDlNativeService.engineChannel);

  Future<void> wakeAt(DateTime time) async {
    try {
      await _channel.invokeMethod<void>('scheduleNightWake', {
        'at': time.millisecondsSinceEpoch,
      });
    } catch (_) {
      // Not on Android: the app's own timer still checks while it is awake.
    }
  }

  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancelNightWake');
    } catch (_) {
      // Nothing was scheduled.
    }
  }
}

final nightAlarmProvider = Provider<NightAlarm>((ref) => const NightAlarm());

/// Counts the times Android woke the app for the night; the queue listens
/// to it and starts the night downloads.
class NightWakeController extends Notifier<int> {
  @override
  int build() {
    // Android calls back on the engine channel when the alarm goes off.
    try {
      NightAlarm._channel.setMethodCallHandler((call) async {
        if (call.method == 'nightWake' && ref.mounted) woke();
      });
      ref.onDispose(() => NightAlarm._channel.setMethodCallHandler(null));
    } catch (_) {
      // No Flutter binding (plain tests): there is no Android to call back.
    }
    return 0;
  }

  void woke() => state++;
}

final nightWakeProvider = NotifierProvider<NightWakeController, int>(
  NightWakeController.new,
);

/// "Starts at 11:00 PM on Wi-Fi", in the phone's time format.
String nightStartText(AppSettings settings) =>
    tr('Starts at ${formatNightStart(settings.nightStart)} on Wi-Fi');

/// A time of day given in minutes after midnight, such as "11:00 PM".
String formatNightStart(int minutes) {
  final hour = minutes ~/ 60;
  final minute = (minutes % 60).toString().padLeft(2, '0');
  final twelve = hour % 12 == 0 ? 12 : hour % 12;
  return '$twelve:$minute ${hour < 12 ? tr('AM') : tr('PM')}';
}

/// Whether Android lets SaveKit run while the phone sleeps (it is exempt from
/// battery optimisation). Without it, night downloads on an unplugged phone
/// can lose the network once the phone falls into deep sleep.
class BackgroundPermission {
  const BackgroundPermission();

  static const _channel = MethodChannel(YoutubeDlNativeService.engineChannel);

  Future<bool> granted() async {
    try {
      return await _channel.invokeMethod<bool>('runsInBackground') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Shows Android's own question.
  Future<void> request() async {
    try {
      await _channel.invokeMethod<void>('allowInBackground');
    } catch (_) {
      // Not on Android.
    }
  }
}

final backgroundPermissionProvider = Provider<BackgroundPermission>(
  (ref) => const BackgroundPermission(),
);

/// Re-read whenever the Tonight screen is shown, so it follows the answer.
final runsInBackgroundProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(backgroundPermissionProvider).granted(),
);
