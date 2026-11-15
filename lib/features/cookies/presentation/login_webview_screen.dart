import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/platform_account.dart';
import '../../../core/l10n/l10n.dart';

/// The platform's own login page in an in-app browser. The password goes to
/// the platform, not to SaveKit; what SaveKit keeps is the resulting session
/// cookie, exported for the on-device extractors. Pops `true` once signed in.
class LoginWebViewScreen extends ConsumerStatefulWidget {
  const LoginWebViewScreen({super.key, required this.account});

  final PlatformAccount account;

  @override
  ConsumerState<LoginWebViewScreen> createState() => _LoginWebViewScreenState();
}

class _LoginWebViewScreenState extends ConsumerState<LoginWebViewScreen> {
  double _progress = 0;
  bool _finishing = false;

  /// After each navigation, see whether the session cookie has appeared.
  Future<void> _checkSignedIn() async {
    if (_finishing || !mounted) return;
    final cookies = ref.read(cookieExportServiceProvider);
    final bool signedIn;
    try {
      signedIn = await cookies.isLoggedIn(widget.account);
    } catch (_) {
      return;
    }
    if (!signedIn || _finishing || !mounted) return;
    _finishing = true;
    try {
      await cookies.exportAll();
    } catch (_) {
      // The account screen exports again on return.
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('Log in to ${widget.account.label}'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _progress < 1
              ? LinearProgressIndicator(value: _progress, minHeight: 2)
              : const SizedBox(height: 2),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(widget.account.loginUrl),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                thirdPartyCookiesEnabled: true,
                supportMultipleWindows: false,
              ),
              onProgressChanged: (_, progress) {
                if (mounted) setState(() => _progress = progress / 100);
              },
              onLoadStop: (_, _) => _checkSignedIn(),
              onUpdateVisitedHistory: (_, _, _) => _checkSignedIn(),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr(
                        'You are signing in on the platform’s own page. '
                        'This screen closes by itself when you are in.',
                      ),
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
