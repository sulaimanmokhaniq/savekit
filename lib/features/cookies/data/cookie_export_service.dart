import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/platform_account.dart';
import 'netscape_cookie_file.dart';

/// Reads the cookies of a URL from the WebView's cookie store.
typedef CookieReader = Future<List<Cookie>> Function(Uri url);

/// Turns the in-app WebView's login sessions into a Netscape `cookies.txt`
/// that the on-device extractors read. Nothing is uploaded anywhere: the file
/// stays in the app's private documents directory.
class CookieExportService {
  CookieExportService({
    this._cookieManager,
    CookieReader? readCookies,
    Future<Directory> Function()? documentsDirectory,
  }) : _readCookiesOverride = readCookies,
       _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory;

  static const fileName = 'cookies.txt';

  final CookieManager? _cookieManager;
  final CookieReader? _readCookiesOverride;
  final Future<Directory> Function() _documentsDirectory;

  CookieManager get _manager => _cookieManager ?? CookieManager.instance();

  Future<List<Cookie>> _readCookies(Uri url) {
    final override = _readCookiesOverride;
    if (override != null) return override(url);
    return _manager.getCookies(url: WebUri.uri(url));
  }

  Future<File> _file() async {
    final directory = await _documentsDirectory();
    return File(p.join(directory.path, fileName));
  }

  /// Path of the exported file, or null when no session has been exported.
  Future<String?> cookiesFilePath() async {
    final file = await _file();
    if (await file.exists() && await file.length() > 0) return file.path;
    return null;
  }

  /// Writes the cookies of every signed-in platform to `cookies.txt` and
  /// returns its path, ready to pass to the engine. Returns null, and removes
  /// any stale file, when no platform is signed in.
  ///
  /// Call this before each extraction and download so the extractors always
  /// see the WebView's current session.
  Future<String?> exportAll() async {
    final cookies = <NetscapeCookie>[];
    for (final account in PlatformAccount.values) {
      final accountCookies = await collect(account);
      if (_hasSession(account, accountCookies)) cookies.addAll(accountCookies);
    }

    final file = await _file();
    if (cookies.isEmpty) {
      if (await file.exists()) await file.delete();
      return null;
    }

    // Write to a sibling and rename, so an extractor never reads half a file.
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      NetscapeCookieFile.serialize(cookies),
      flush: true,
    );
    await temp.rename(file.path);
    return file.path;
  }

  /// The WebView's cookies for [account], converted for the cookie file.
  Future<List<NetscapeCookie>> collect(PlatformAccount account) async {
    final result = <NetscapeCookie>[];
    for (final url in account.cookieUrls) {
      final uri = Uri.parse(url);
      final List<Cookie> cookies;
      try {
        cookies = await _readCookies(uri);
      } catch (_) {
        continue;
      }
      for (final cookie in cookies) {
        final value = cookie.value?.toString() ?? '';
        if (cookie.name.isEmpty) continue;
        result.add(
          NetscapeCookie(
            domain: _domainFor(cookie.domain, uri, account),
            name: cookie.name,
            value: value,
            path: cookie.path ?? '/',
            secure: cookie.isSecure ?? true,
            httpOnly: cookie.isHttpOnly ?? false,
            expires: cookie.expiresDate == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(cookie.expiresDate!),
          ),
        );
      }
    }
    return result;
  }

  Future<bool> isLoggedIn(PlatformAccount account) async =>
      _hasSession(account, await collect(account));

  Future<Map<PlatformAccount, bool>> loginStatuses() async => {
    for (final account in PlatformAccount.values)
      account: await isLoggedIn(account),
  };

  /// Signs out of [account] by deleting its cookies, then rewrites the file.
  Future<void> logout(PlatformAccount account) async {
    for (final url in account.cookieUrls) {
      final uri = WebUri(url);
      await _manager.deleteCookies(url: uri);
      await _manager.deleteCookies(url: uri, domain: account.cookieDomain);
    }
    await exportAll();
  }

  bool _hasSession(PlatformAccount account, List<NetscapeCookie> cookies) {
    return cookies.any(
      (cookie) =>
          account.sessionCookies.contains(cookie.name) &&
          cookie.value.isNotEmpty,
    );
  }

  /// Older Android WebViews report only a cookie's name and value. Without a
  /// domain the cookie is written for the whole platform domain, which is how
  /// these sites scope their session cookies anyway.
  String _domainFor(String? reported, Uri source, PlatformAccount account) {
    if (reported != null && reported.isNotEmpty) return reported;
    final host = source.host;
    final base = account.cookieDomain.substring(1);
    if (host == base || host.endsWith('.$base')) return account.cookieDomain;
    final parts = host.split('.');
    return parts.length >= 2
        ? '.${parts.sublist(parts.length - 2).join('.')}'
        : host;
  }
}
