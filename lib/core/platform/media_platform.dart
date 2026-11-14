/// The platforms SaveKit knows by name. Anything else yt-dlp or gallery-dl can
/// read still works and is reported as [MediaPlatform.other].
enum MediaPlatform {
  youtube('youtube', 'YouTube', ['youtube.com', 'youtu.be']),
  tiktok('tiktok', 'TikTok', ['tiktok.com']),
  instagram('instagram', 'Instagram', ['instagram.com', 'instagr.am']),
  snapchat('snapchat', 'Snapchat', ['snapchat.com']),
  x('x', 'X', ['x.com', 'twitter.com', 't.co']),
  linkedin('linkedin', 'LinkedIn', ['linkedin.com', 'lnkd.in']),
  facebook('facebook', 'Facebook', ['facebook.com', 'fb.watch']),
  other('other', 'Web', []);

  const MediaPlatform(this.id, this.label, this.hosts);

  /// Stable identifier, matching the `platform` value sent by the native engine.
  final String id;
  final String label;
  final List<String> hosts;

  /// The platforms shown as "supported" pills on the home screen.
  static const featured = [youtube, tiktok, instagram, snapchat, x, linkedin];

  static MediaPlatform fromId(String? id) {
    if (id == null) return other;
    final normalized = id.toLowerCase();
    if (normalized == 'twitter') return x;
    for (final platform in values) {
      if (platform.id == normalized) return platform;
    }
    return other;
  }

  static MediaPlatform fromUrl(String url) {
    final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
    if (host.isEmpty) return other;
    for (final platform in values) {
      for (final known in platform.hosts) {
        if (host == known || host.endsWith('.$known')) return platform;
      }
    }
    return other;
  }
}

final _urlPattern = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

/// Finds the first web link in [text]. Share sheets and clipboards often wrap
/// the link in a sentence ("Check this out https://…"), so the text is scanned
/// rather than parsed as a whole.
String? extractFirstUrl(String? text) {
  if (text == null) return null;
  final match = _urlPattern.firstMatch(text);
  if (match == null) return null;
  var url = match.group(0)!;
  // Trailing punctuation belongs to the sentence, not the link.
  while (url.isNotEmpty && '.,;:!?)]}\'"'.contains(url[url.length - 1])) {
    url = url.substring(0, url.length - 1);
  }
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return null;
  return url;
}

/// Whether [url] belongs to one of the named platforms. Used to decide when a
/// clipboard link is worth offering; any http(s) link can still be pasted by hand.
bool isKnownPlatformUrl(String url) =>
    MediaPlatform.fromUrl(url) != MediaPlatform.other;
