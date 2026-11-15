import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A media address found on a page, before filtering.
class WebMediaCandidate {
  const WebMediaCandidate({
    required this.url,
    this.width,
    this.height,
    this.source = 'img',
    this.isVideo = false,
  });

  final String url;
  final int? width;
  final int? height;

  /// Where on the page it was found: `img`, `og`, `jsonld`, `data`,
  /// `resource` or `video`.
  final String source;
  final bool isVideo;

  int get area => (width ?? 0) * (height ?? 0);

  /// Smaller side, when the page reported a size.
  int? get minDimension {
    final w = width, h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w < h ? w : h;
  }
}

/// How to recognise a post's own media on one site.
class SiteRule {
  SiteRule({
    this.hostSuffix = '',
    List<String> allow = const [],
    List<String> deny = const [],
    String? dedupeKey,
    this.minDimension = 400,
    this.settleMs = 2500,
    this.desktopUserAgent = false,
    this.loginWall = const [],
    this.loginHint,
  }) : allow = _compile(allow),
       deny = _compile(deny),
       dedupeKey = dedupeKey == null ? null : RegExp(dedupeKey);

  factory SiteRule.fromJson(Map<String, dynamic> json) => SiteRule(
    hostSuffix: json['hostSuffix'] as String? ?? '',
    allow: _strings(json['allow']),
    deny: _strings(json['deny']),
    dedupeKey: json['dedupeKey'] as String?,
    minDimension: (json['minDimension'] as num?)?.toInt() ?? 400,
    settleMs: (json['settleMs'] as num?)?.toInt() ?? 2500,
    desktopUserAgent: json['userAgent'] == 'desktop',
    loginWall: _strings(json['loginWall']),
    loginHint: json['loginHint'] as String?,
  );

  /// Site this rule applies to; empty for the default rule.
  final String hostSuffix;

  /// When non-empty, only addresses matching one of these are post media.
  final List<RegExp> allow;

  /// Addresses matching any of these are never post media (avatars, logos…).
  final List<RegExp> deny;

  /// Captures an image's identity, so several sizes of one image collapse.
  final RegExp? dedupeKey;

  /// Smallest side, in pixels, for an image with a known size to count.
  final int minDimension;

  /// How long to let the page keep loading after it reports "loaded".
  final int settleMs;
  final bool desktopUserAgent;

  /// Path fragments that mean the site redirected to a login page.
  final List<String> loginWall;
  final String? loginHint;

  bool matchesHost(String host) =>
      hostSuffix.isNotEmpty &&
      (host == hostSuffix || host.endsWith('.$hostSuffix'));

  bool isLoginWall(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    return loginWall.any(path.contains);
  }

  /// Keeps the candidates that are the post's own media, one per image, in
  /// page order.
  List<WebMediaCandidate> filter(Iterable<WebMediaCandidate> candidates) {
    final byKey = <String, WebMediaCandidate>{};
    for (final candidate in candidates) {
      if (!_accepts(candidate)) continue;
      final key = _keyOf(candidate.url);
      final existing = byKey[key];
      // Of several sizes of one image, keep the largest known one.
      if (existing == null || candidate.area > existing.area) {
        byKey[key] = candidate;
      }
    }
    return byKey.values.toList(growable: false);
  }

  bool _accepts(WebMediaCandidate candidate) {
    final url = candidate.url;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http')) {
      return false;
    }
    if (deny.any((pattern) => pattern.hasMatch(url))) return false;

    final size = candidate.minDimension;
    if (size != null && size < minDimension) return false;

    if (allow.isNotEmpty) return allow.any((pattern) => pattern.hasMatch(url));

    // Without site-specific patterns, trust only what clearly is content:
    // sufficiently large images, the page's declared preview, and videos.
    if (candidate.isVideo) return true;
    if (candidate.source == 'og' || candidate.source == 'jsonld') return true;
    return candidate.source == 'img' && size != null;
  }

  String _keyOf(String url) {
    final match = dedupeKey?.firstMatch(url);
    if (match != null && match.groupCount >= 1 && match.group(1) != null) {
      return match.group(1)!;
    }
    final uri = Uri.parse(url);
    return '${uri.host}${uri.path}';
  }

  static List<RegExp> _compile(List<String> patterns) {
    final compiled = <RegExp>[];
    for (final pattern in patterns) {
      try {
        compiled.add(RegExp(pattern, caseSensitive: false));
      } on FormatException {
        // A malformed remote pattern must not break extraction.
      }
    }
    return compiled;
  }

  static List<String> _strings(Object? value) =>
      value is List ? value.whereType<String>().toList() : const [];
}

/// The full rule set: a default plus per-site rules.
class WebExtractionRules {
  WebExtractionRules({
    required this.version,
    required this.defaultRule,
    required this.sites,
  });

  factory WebExtractionRules.fromJson(Map<String, dynamic> json) {
    return WebExtractionRules(
      version: (json['version'] as num?)?.toInt() ?? 0,
      defaultRule: SiteRule.fromJson(
        Map<String, dynamic>.from(json['default'] as Map? ?? const {}),
      ),
      sites: (json['sites'] as List? ?? const [])
          .whereType<Map>()
          .map((site) => SiteRule.fromJson(Map<String, dynamic>.from(site)))
          .toList(growable: false),
    );
  }

  factory WebExtractionRules.parse(String source) =>
      WebExtractionRules.fromJson(
        Map<String, dynamic>.from(jsonDecode(source) as Map),
      );

  final int version;
  final SiteRule defaultRule;
  final List<SiteRule> sites;

  SiteRule forUrl(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    for (final site in sites) {
      if (site.matchesHost(host)) return site;
    }
    return defaultRule;
  }
}

/// Loads the rules shipped with the app and lets them be refreshed from the
/// project's repository, so a site changing its page layout can be handled
/// without releasing a new APK. The remote file is static JSON: patterns only,
/// never code.
class WebExtractionRulesStore {
  WebExtractionRulesStore({
    Future<Directory> Function()? supportDirectory,
    Future<String> Function()? loadBundled,
    HttpClient Function()? httpClient,
  }) : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _loadBundled = loadBundled ?? (() => rootBundle.loadString(assetPath)),
       _httpClient = httpClient ?? HttpClient.new;

  static const assetPath = 'assets/web_rules.json';
  static const remoteUrl =
      'https://raw.githubusercontent.com/sulaimanmokhaniq/savekit/main/assets/web_rules.json';
  static const _fileName = 'web_rules.json';

  final Future<Directory> Function() _supportDirectory;
  final Future<String> Function() _loadBundled;
  final HttpClient Function() _httpClient;
  WebExtractionRules? _cached;

  Future<File> _overrideFile() async =>
      File(p.join((await _supportDirectory()).path, _fileName));

  /// The newest rules available on the device: a downloaded set if it is newer
  /// than the one shipped in the app, otherwise the shipped one.
  Future<WebExtractionRules> load() async {
    final cached = _cached;
    if (cached != null) return cached;

    var rules = WebExtractionRules.parse(await _loadBundled());
    try {
      final file = await _overrideFile();
      if (await file.exists()) {
        final downloaded = WebExtractionRules.parse(await file.readAsString());
        if (downloaded.version > rules.version) rules = downloaded;
      }
    } catch (_) {
      // A corrupt download falls back to the bundled rules.
    }
    return _cached = rules;
  }

  /// Fetches the latest rules. Returns true when a newer set was installed.
  Future<bool> updateFromRemote() async {
    final current = await load();
    final client = _httpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(remoteUrl));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Rules server answered ${response.statusCode}');
      }
      final body = await utf8.decodeStream(response);
      final downloaded = WebExtractionRules.parse(body);
      if (downloaded.version <= current.version) return false;

      final file = await _overrideFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(body, flush: true);
      _cached = downloaded;
      return true;
    } finally {
      client.close(force: true);
    }
  }
}
