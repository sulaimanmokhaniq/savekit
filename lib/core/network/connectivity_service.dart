import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the phone is on an unmetered-style connection (Wi-Fi or Ethernet).
/// A seam for tests.
abstract interface class ConnectivityService {
  Future<bool> isOnWifi();
  Stream<bool> get wifiChanges;
}

class PlusConnectivityService implements ConnectivityService {
  PlusConnectivityService([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static bool _isWifi(List<ConnectivityResult> results) =>
      results.contains(ConnectivityResult.wifi) ||
      results.contains(ConnectivityResult.ethernet);

  @override
  Future<bool> isOnWifi() async {
    try {
      return _isWifi(await _connectivity.checkConnectivity());
    } catch (_) {
      // Unknown: do not hold downloads hostage to a failed check.
      return true;
    }
  }

  @override
  Stream<bool> get wifiChanges =>
      _connectivity.onConnectivityChanged.map(_isWifi).distinct();
}

final connectivityServiceProvider = Provider<ConnectivityService>(
  (ref) => PlusConnectivityService(),
);

/// Whether the phone is on Wi-Fi right now, updated as the connection changes.
final onWifiProvider = StreamProvider<bool>((ref) async* {
  final service = ref.watch(connectivityServiceProvider);
  yield await service.isOnWifi();
  yield* service.wifiChanges;
});
