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

  /// Statuses saved from WhatsApp's folder on the phone, not from a link.
  whatsapp('whatsapp', 'WhatsApp', []),

  /// Files made on the phone itself, such as converted audio.
  device('device', 'This phone', []),
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

/// Every distinct web link in [text], in order. Lets several links be pasted
/// at once, one per line or mixed into other text.
List<String> extractAllUrls(String? text) {
  if (text == null) return const [];
  final urls = <String>[];
  for (final match in _urlPattern.allMatches(text)) {
    final url = extractFirstUrl(match.group(0));
    if (url != null && !urls.contains(url)) urls.add(url);
  }
  return urls;
}

/// Whether [url] is a list of videos rather than a single one: a YouTube
/// playlist page. A video opened from inside a playlist counts as one video.
bool isPlaylistUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  if (MediaPlatform.fromUrl(url) != MediaPlatform.youtube) return false;
  return uri.path.startsWith('/playlist') &&
      (uri.queryParameters['list']?.isNotEmpty ?? false);
}

const _reservedX = {
  'home', 'i', 'search', 'explore', 'settings', 'notifications', 'messages', //
  'compose', 'hashtag', 'login', 'signup', 'tos', 'privacy', 'intent', 'share',
};
const _reservedInstagram = {
  'p', 'reel', 'reels', 'stories', 'tv', 'explore', 'accounts', 'direct', //
  'about', 'legal', 'developer', 'share',
};

/// Whether [url] is an account's page (a channel, a profile, a user's
/// timeline) rather than a single post. Such links list the account's media
/// to choose from instead of opening the format picker.
bool isAccountUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return false;
  final segments = [
    for (final segment in uri.pathSegments)
      if (segment.isNotEmpty) segment,
  ];
  if (segments.isEmpty) return false;
  final first = segments.first.toLowerCase();

  switch (MediaPlatform.fromUrl(url)) {
    case MediaPlatform.youtube:
      return first.startsWith('@') ||
          (segments.length >= 2 &&
              const {'channel', 'c', 'user'}.contains(first));
    case MediaPlatform.x:
      if (_reservedX.contains(first)) return false;
      return segments.length == 1 ||
          (segments.length == 2 &&
              const {'media', 'with_replies'}.contains(segments[1]));
    case MediaPlatform.instagram:
      return segments.length == 1 && !_reservedInstagram.contains(first);
    case MediaPlatform.tiktok:
      return segments.length == 1 && first.startsWith('@');
    case MediaPlatform.snapchat:
      return (segments.length == 1 && first.startsWith('@')) ||
          (segments.length == 2 && first == 'add');
    default:
      return false;
  }
}

/// The address to list an account's media from. X shows text posts on a
/// profile; its media tab is what is wanted here.
String accountMediaUrl(String url) {
  final uri = Uri.parse(url.trim());
  if (MediaPlatform.fromUrl(url) == MediaPlatform.x) {
    final segments = [
      for (final segment in uri.pathSegments)
        if (segment.isNotEmpty) segment,
    ];
    if (segments.length == 1) {
      return uri.replace(pathSegments: [segments.single, 'media']).toString();
    }
  }
  return url.trim();
}

/// Whether [url] belongs to one of the named platforms. Used to decide when a
/// clipboard link is worth offering; any http(s) link can still be pasted by hand.
bool isKnownPlatformUrl(String url) =>
    MediaPlatform.fromUrl(url) != MediaPlatform.other;
