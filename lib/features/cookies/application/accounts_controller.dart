import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../domain/platform_account.dart';

/// Which platforms are signed in, read from the WebView's cookies.
class AccountsController extends AsyncNotifier<Map<PlatformAccount, bool>> {
  @override
  Future<Map<PlatformAccount, bool>> build() =>
      ref.read(cookieExportServiceProvider).loginStatuses();

  /// Re-reads the sessions and rewrites `cookies.txt`; call after the login
  /// screen closes.
  Future<void> refresh() async {
    final cookies = ref.read(cookieExportServiceProvider);
    try {
      await cookies.exportAll();
    } catch (_) {
      // The statuses below are still worth showing.
    }
    final statuses = await cookies.loginStatuses();
    if (ref.mounted) state = AsyncData(statuses);
  }

  Future<void> logout(PlatformAccount account) async {
    await ref.read(cookieExportServiceProvider).logout(account);
    await refresh();
  }
}

final accountsControllerProvider =
    AsyncNotifierProvider<AccountsController, Map<PlatformAccount, bool>>(
      AccountsController.new,
    );
