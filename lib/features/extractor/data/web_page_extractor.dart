import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Size;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/platform/media_platform.dart';
import '../domain/media_format.dart';
import '../domain/media_info.dart';
import 'web_extraction_rules.dart';

class WebExtractionException implements Exception {
  const WebExtractionException(this.message, {this.loginRequired = false});

  final String message;

  /// The site showed a login page instead of the post.
  final bool loginRequired;

  @override
  String toString() => message;
}

/// What the in-page script reports back.
class WebPageSnapshot {
  const WebPageSnapshot({
    required this.finalUrl,
    this.title,
    this.author,
    this.candidates = const [],
  });

  final String finalUrl;
  final String? title;
  final String? author;
  final List<WebMediaCandidate> candidates;

  /// Parses the JSON string returned by [WebPageExtractor.collectorScript].
  factory WebPageSnapshot.fromJson(
    String source, {
    required String finalUrl,
    Iterable<String> resourceUrls = const [],
  }) {
    final json = Map<String, dynamic>.from(jsonDecode(source) as Map);
    final candidates = <WebMediaCandidate>[];

    for (final item in (json['images'] as List? ?? const []).whereType<Map>()) {
      final url = item['url'];
      if (url is! String || url.isEmpty) continue;
      candidates.add(
        WebMediaCandidate(
          url: url,
          width: (item['w'] as num?)?.toInt(),
          height: (item['h'] as num?)?.toInt(),
          source: item['source'] as String? ?? 'img',
        ),
      );
    }
    for (final url
        in (json['videos'] as List? ?? const []).whereType<String>()) {
      candidates.add(
        WebMediaCandidate(url: url, source: 'video', isVideo: true),
      );
    }
    for (final url in (json['data'] as List? ?? const []).whereType<String>()) {
      candidates.add(WebMediaCandidate(url: url, source: 'data'));
    }
    for (final url in resourceUrls) {
      candidates.add(WebMediaCandidate(url: url, source: 'resource'));
    }

    String? text(String key) {
      final value = json[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    return WebPageSnapshot(
      finalUrl: finalUrl,
      title: text('title'),
      author: text('author'),
      candidates: candidates,
    );
  }
}

/// Third extraction layer: loads a post in a hidden WebView that shares the
/// login sessions of the "Platform Accounts" screen, and reads the addresses
/// of its photos from the rendered page. Used for sites neither yt-dlp nor
/// gallery-dl handles (LinkedIn photos) and as a general fallback.
class WebPageExtractor {
  WebPageExtractor({
    required this._rules,
    this.timeout = const Duration(seconds: 35),
  });

  final WebExtractionRulesStore _rules;

  /// Upper bound for loading and reading one page.
  final Duration timeout;

  static const desktopUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/130.0.0.0 Safari/537.36';

  static const _videoExtensions = {'mp4', 'mov', 'webm', 'm4v'};

  Future<MediaInfo> extract(String url) async {
    final rules = await _rules.load();
    final rule = rules.forUrl(url);
    final snapshot = await _loadSnapshot(url, rule);

    // A redirect can land on another site's rule (or its login page).
    final finalRule = rules.forUrl(snapshot.finalUrl);
    final activeRule = finalRule.hostSuffix.isEmpty ? rule : finalRule;
    if (activeRule.isLoginWall(snapshot.finalUrl)) {
      throw WebExtractionException(
        activeRule.loginHint ?? 'This post needs an account. Log in under Settings → Platform Accounts.',
        loginRequired: true,
      );
    }

    return buildMediaInfo(url: url, snapshot: snapshot, rule: activeRule);
  }

  /// Turns a page snapshot into the same [MediaInfo] the native engine
  /// produces, with a single "Photos" option downloaded over plain HTTP.
  static MediaInfo buildMediaInfo({
    required String url,
    required WebPageSnapshot snapshot,
    required SiteRule rule,
  }) {
    final media = rule.filter(snapshot.candidates);
    if (media.isEmpty) {
      throw const WebExtractionException(
        'No photos or videos were found on this page.',
      );
    }

    final items = [
      for (final candidate in media)
        GalleryItem(
          url: candidate.url,
          extension: _extensionOf(candidate.url),
          width: candidate.width,
          height: candidate.height,
          isVideo: candidate.isVideo || _isVideoUrl(candidate.url),
          thumbnail: candidate.isVideo ? null : candidate.url,
        ),
    ];
    final videoCount = items.where((item) => item.isVideo).length;
    final imageCount = items.length - videoCount;
    final label = videoCount == 0
        ? (items.length == 1 ? 'Photo' : 'Photos (${items.length})')
        : 'All media (${items.length})';

    final platform = MediaPlatform.fromUrl(snapshot.finalUrl);
    final author = snapshot.author;
    return MediaInfo(
      url: url,
      webpageUrl: snapshot.finalUrl,
      title:
          snapshot.title ??
          (author == null ? '${platform.label} post' : 'Post by $author'),
      uploader: author,
      platform: platform,
      thumbnail: items
          .map((item) => item.thumbnail)
          .firstWhere((thumbnail) => thumbnail != null, orElse: () => null),
      entryCount: items.length,
      galleryOption: MediaFormat(
        id: 'gallery',
        kind: MediaFormatKind.gallery,
        label: label,
        engine: DownloadEngineKind.direct,
        ext: items.first.extension.isEmpty ? null : items.first.extension,
        itemCount: items.length,
        imageCount: imageCount,
        videoCount: videoCount,
        directUrls: [for (final item in items) item.url],
        referer: snapshot.finalUrl,
      ),
      galleryItems: items,
    );
  }

  Future<WebPageSnapshot> _loadSnapshot(String url, SiteRule rule) async {
    final completer = Completer<WebPageSnapshot>();
    final resourceUrls = <String>{};
    Timer? settleTimer;
    HeadlessInAppWebView? webView;
    var collecting = false;

    Future<void> collect(InAppWebViewController controller) async {
      if (collecting || completer.isCompleted) return;
      collecting = true;
      try {
        final result = await controller.evaluateJavascript(
          source: collectorScript,
        );
        final finalUrl = (await controller.getUrl())?.toString() ?? url;
        if (result is! String) {
          throw const WebExtractionException('The page could not be read.');
        }
        if (!completer.isCompleted) {
          completer.complete(
            WebPageSnapshot.fromJson(
              result,
              finalUrl: finalUrl,
              resourceUrls: resourceUrls,
            ),
          );
        }
      } catch (error) {
        if (!completer.isCompleted) {
          completer.completeError(
            error is WebExtractionException
                ? error
                : WebExtractionException('The page could not be read: $error'),
          );
        }
      } finally {
        collecting = false;
      }
    }

    webView = HeadlessInAppWebView(
      // A phone-sized viewport makes sites serve their full-size post images.
      initialSize: const Size(412, 915),
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        useOnLoadResource: true,
        mediaPlaybackRequiresUserGesture: true,
        userAgent: rule.desktopUserAgent ? desktopUserAgent : null,
      ),
      onLoadResource: (controller, resource) {
        final resourceUrl = resource.url?.toString();
        if (resourceUrl == null) return;
        final type = resource.initiatorType;
        if (type == 'img' || type == 'video' || type == 'css') {
          resourceUrls.add(resourceUrl);
        }
      },
      onLoadStop: (controller, _) {
        // Posts keep rendering after "load"; wait for the page to settle, and
        // start over if it navigates again (redirects, consent screens).
        settleTimer?.cancel();
        settleTimer = Timer(
          Duration(milliseconds: rule.settleMs),
          () => collect(controller),
        );
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame != true || completer.isCompleted) return;
        completer.completeError(
          WebExtractionException(
            'The page could not be loaded: ${error.description}',
          ),
        );
      },
    );

    try {
      await webView.run();
      return await completer.future.timeout(
        timeout,
        onTimeout: () async {
          // Slow page: read whatever has rendered so far.
          final controller = webView?.webViewController;
          if (controller == null) {
            throw const WebExtractionException(
              'The page took too long to load.',
            );
          }
          await collect(controller);
          return completer.future;
        },
      );
    } finally {
      settleTimer?.cancel();
      await webView.dispose();
    }
  }

  static String _extensionOf(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot < path.lastIndexOf('/')) return '';
    final extension = path.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{2,5}$').hasMatch(extension) ? extension : '';
  }

  static bool _isVideoUrl(String url) =>
      _videoExtensions.contains(_extensionOf(url));

  /// Runs inside the page and returns a JSON string describing its media:
  /// rendered images with their real sizes, the declared preview images,
  /// structured data, direct video sources, and media-looking addresses found
  /// in the page's embedded data.
  static const collectorScript = r'''
(function () {
  function abs(u) {
    try { return new URL(u, document.baseURI).href; } catch (e) { return null; }
  }
  function meta(names) {
    for (var i = 0; i < names.length; i++) {
      var el = document.querySelector(
        'meta[property="' + names[i] + '"], meta[name="' + names[i] + '"]');
      if (el && el.content) return el.content;
    }
    return null;
  }
  var images = [], videos = [], data = [], seen = {};
  function addImage(u, w, h, source) {
    u = u && abs(u);
    if (!u || u.indexOf('http') !== 0) return;
    var key = source + '|' + u;
    if (seen[key]) return;
    seen[key] = true;
    images.push({ url: u, w: w || null, h: h || null, source: source });
  }
  function bestOfSrcset(srcset) {
    var best = null, bestWidth = 0;
    (srcset || '').split(',').forEach(function (part) {
      var bits = part.trim().split(/\s+/);
      if (!bits[0]) return;
      var width = parseFloat(bits[1]) || 0;
      if (best === null || width > bestWidth) { best = bits[0]; bestWidth = width; }
    });
    return best;
  }

  var imgs = document.querySelectorAll('img');
  for (var i = 0; i < imgs.length; i++) {
    var img = imgs[i];
    var src = bestOfSrcset(img.getAttribute('srcset')) || img.currentSrc ||
      img.getAttribute('src') || img.getAttribute('data-delayed-url') ||
      img.getAttribute('data-src');
    var w = img.naturalWidth || 0;
    var h = img.naturalHeight || 0;
    // An image that has not loaded yet has no size; report it as unknown.
    addImage(src, w > 1 ? w : null, h > 1 ? h : null, 'img');
  }

  var ogs = document.querySelectorAll(
    'meta[property="og:image"], meta[property="og:image:secure_url"], meta[name="twitter:image"]');
  for (var j = 0; j < ogs.length; j++) addImage(ogs[j].content, null, null, 'og');

  var author = meta(['author', 'article:author', 'og:article:author']);
  function fromLd(node) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { node.forEach(fromLd); return; }
    var image = node.image;
    (Array.isArray(image) ? image : [image]).forEach(function (entry) {
      if (typeof entry === 'string') addImage(entry, null, null, 'jsonld');
      else if (entry && entry.url) addImage(entry.url, entry.width, entry.height, 'jsonld');
    });
    if (!author && node.author) {
      var a = Array.isArray(node.author) ? node.author[0] : node.author;
      author = typeof a === 'string' ? a : (a && a.name) || null;
    }
    if (node['@graph']) fromLd(node['@graph']);
  }
  var lds = document.querySelectorAll('script[type="application/ld+json"]');
  for (var k = 0; k < lds.length; k++) {
    try { fromLd(JSON.parse(lds[k].textContent)); } catch (e) {}
  }

  var vids = document.querySelectorAll('video, video source');
  for (var v = 0; v < vids.length; v++) {
    var vs = vids[v].currentSrc || vids[v].getAttribute('src');
    vs = vs && abs(vs);
    if (vs && vs.indexOf('http') === 0 && videos.indexOf(vs) < 0) videos.push(vs);
  }

  var blocks = document.querySelectorAll(
    'script#__NEXT_DATA__, script[type="application/json"], code[id^="bpr-guid"]');
  var pattern = /https?:(?:\\\/|\/){2}[^"'\s<>\\]+(?:\\\/[^"'\s<>\\]*)*/g;
  for (var b = 0; b < blocks.length && data.length < 400; b++) {
    var text = blocks[b].textContent || '';
    if (text.length > 3000000) continue;
    var found = text.match(pattern) || [];
    for (var f = 0; f < found.length && data.length < 400; f++) {
      var clean = found[f].replace(/\\u002F/gi, '/').replace(/\\\//g, '/')
        .replace(/&amp;/g, '&');
      if (data.indexOf(clean) < 0) data.push(clean);
    }
  }

  return JSON.stringify({
    title: meta(['og:title', 'twitter:title']) || document.title || null,
    author: author,
    images: images,
    videos: videos,
    data: data
  });
})();
''';
}
