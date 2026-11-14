import '../../../core/platform/media_platform.dart';

/// A platform the user can sign in to inside the app so that content needing
/// an account (stories, age-restricted or private posts) can be extracted.
enum PlatformAccount {
  instagram(
    platform: MediaPlatform.instagram,
    loginUrl: 'https://www.instagram.com/accounts/login/',
    cookieUrls: ['https://www.instagram.com/', 'https://i.instagram.com/'],
    cookieDomain: '.instagram.com',
    sessionCookies: ['sessionid'],
  ),
  x(
    platform: MediaPlatform.x,
    loginUrl: 'https://x.com/i/flow/login',
    cookieUrls: ['https://x.com/', 'https://twitter.com/'],
    cookieDomain: '.x.com',
    sessionCookies: ['auth_token'],
  ),
  tiktok(
    platform: MediaPlatform.tiktok,
    loginUrl: 'https://www.tiktok.com/login',
    cookieUrls: ['https://www.tiktok.com/'],
    cookieDomain: '.tiktok.com',
    sessionCookies: ['sessionid', 'sid_tt'],
  ),
  linkedin(
    platform: MediaPlatform.linkedin,
    loginUrl: 'https://www.linkedin.com/login',
    cookieUrls: ['https://www.linkedin.com/'],
    cookieDomain: '.linkedin.com',
    sessionCookies: ['li_at'],
  );

  const PlatformAccount({
    required this.platform,
    required this.loginUrl,
    required this.cookieUrls,
    required this.cookieDomain,
    required this.sessionCookies,
  });

  final MediaPlatform platform;

  /// Page opened in the login WebView.
  final String loginUrl;

  /// Addresses whose cookies make up the session.
  final List<String> cookieUrls;

  /// Domain written for cookies the WebView reports without one.
  final String cookieDomain;

  /// Cookies that exist only while signed in; any one present means logged in.
  final List<String> sessionCookies;

  String get label => platform.label;
}
