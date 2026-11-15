import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// Fingerprint, face or screen-lock confirmation; a seam for tests.
abstract interface class VaultLockService {
  /// Whether the phone has any screen lock or biometric set up.
  Future<bool> isAvailable();

  /// Shows the system prompt. Returns true when the user proved who they are.
  Future<bool> authenticate(String reason);
}

class LocalAuthVaultLockService implements VaultLockService {
  LocalAuthVaultLockService([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      // The device PIN or pattern is accepted too, so a phone without a
      // fingerprint reader can still use the lock.
      return await _auth.authenticate(localizedReason: reason);
    } catch (_) {
      return false;
    }
  }
}

final vaultLockServiceProvider = Provider<VaultLockService>(
  (ref) => LocalAuthVaultLockService(),
);

/// Whether the Vault has been unlocked since the app last came to the front.
class VaultUnlockedController extends Notifier<bool> {
  @override
  bool build() => false;

  void unlock() => state = true;
  void lock() => state = false;
}

final vaultUnlockedProvider = NotifierProvider<VaultUnlockedController, bool>(
  VaultUnlockedController.new,
);
