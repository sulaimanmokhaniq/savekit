import '../../../core/native/youtube_dl_native_service.dart';
import '../../cookies/data/cookie_export_service.dart';
import '../domain/media_info.dart';
import 'web_page_extractor.dart';

/// Thrown when no extractor could read a link.
class MediaExtractionException implements Exception {
  const MediaExtractionException(this.message, {this.loginRequired = false});

  final String message;

  /// Signing in to the platform is likely to fix it.
  final bool loginRequired;

  @override
  String toString() => message;
}

/// The single entry point for "what can be downloaded from this link?".
///
/// 1. The native engine asks yt-dlp (video, audio) and gallery-dl (photos).
/// 2. If neither can read the link, the post is opened in a hidden WebView
///    and its photos are read from the page.
///
/// The current WebView login cookies are exported first, so every layer sees
/// the user's sessions.
class MediaExtractor {
  MediaExtractor({
    required this._native,
    required this._cookies,
    required this._webPage,
  });

  final YoutubeDlNativeService _native;
  final CookieExportService _cookies;
  final WebPageExtractor _webPage;

  static final _loginHints = RegExp(
    r'log ?in|sign ?in|cookies|authenticat|401|403|private|restricted|rate.?limit',
    caseSensitive: false,
  );

  Future<MediaInfo> fetch(String url) async {
    final cookiesFilePath = await _cookies.exportAll();

    final EngineException engineError;
    try {
      return await _native.getMediaInfo(url, cookiesFilePath: cookiesFilePath);
    } on EngineException catch (error) {
      engineError = error;
    }

    try {
      return await _webPage.extract(url);
    } on WebExtractionException catch (webError) {
      if (webError.loginRequired) {
        throw MediaExtractionException(webError.message, loginRequired: true);
      }
      // The extractor's own message is the more specific one.
      throw MediaExtractionException(
        engineError.message,
        loginRequired: _loginHints.hasMatch(engineError.message),
      );
    } catch (_) {
      throw MediaExtractionException(
        engineError.message,
        loginRequired: _loginHints.hasMatch(engineError.message),
      );
    }
  }
}
