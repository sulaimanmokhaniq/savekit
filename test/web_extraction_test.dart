import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:savekit/core/platform/media_platform.dart';
import 'package:savekit/features/extractor/data/web_extraction_rules.dart';
import 'package:savekit/features/extractor/data/web_page_extractor.dart';
import 'package:savekit/features/extractor/domain/media_format.dart';

void main() {
  final rules = WebExtractionRules.parse(
    File('assets/web_rules.json').readAsStringSync(),
  );

  group('bundled rules', () {
    test('pick the site rule by host', () {
      expect(
        rules.forUrl('https://www.linkedin.com/posts/x').hostSuffix,
        'linkedin.com',
      );
      expect(
        rules.forUrl('https://www.snapchat.com/add/x').hostSuffix,
        'snapchat.com',
      );
      expect(rules.forUrl('https://example.com/a').hostSuffix, isEmpty);
      expect(rules.forUrl('https://notlinkedin.com/a').hostSuffix, isEmpty);
    });

    test('LinkedIn keeps post images and drops profile chrome', () {
      final rule = rules.forUrl('https://www.linkedin.com/posts/x');
      const post =
          'https://media.licdn.com/dms/image/v2/D4D22AQGabc/feedshare-shrink_';
      final kept = rule.filter([
        const WebMediaCandidate(
          url: '${post}800/0/1?e=1&v=beta',
          width: 800,
          height: 600,
        ),
        // Same image, larger rendition: must replace the smaller one.
        const WebMediaCandidate(
          url: '${post}2048_1536/0/1?e=1&v=beta',
          width: 2048,
          height: 1536,
        ),
        const WebMediaCandidate(
          url: 'https://media.licdn.com/dms/image/v2/D4D22AQGxyz/feedshare-shrink_1280/0/2',
          source: 'data',
        ),
        const WebMediaCandidate(
          url: 'https://media.licdn.com/dms/image/v2/C4D03AQ/profile-displayphoto-shrink_400_400/0/3',
          width: 400,
          height: 400,
        ),
        const WebMediaCandidate(
          url: 'https://media.licdn.com/dms/image/v2/C4D0BAQ/company-logo_200_200/0/4',
          width: 200,
          height: 200,
        ),
        const WebMediaCandidate(
          url: 'https://static.licdn.com/aero-v1/sc/h/abc',
          width: 900,
          height: 900,
        ),
        const WebMediaCandidate(
          url: 'data:image/png;base64,AAAA',
          width: 900,
          height: 900,
        ),
      ]);
      expect(kept.map((c) => c.url), [
        '${post}2048_1536/0/1?e=1&v=beta',
        'https://media.licdn.com/dms/image/v2/D4D22AQGxyz/feedshare-shrink_1280/0/2',
      ]);
    });

    test('LinkedIn recognises its login redirects', () {
      final rule = rules.forUrl('https://www.linkedin.com/posts/x');
      expect(
        rule.isLoginWall('https://www.linkedin.com/authwall?trk=x'),
        isTrue,
      );
      expect(
        rule.isLoginWall(
          'https://www.linkedin.com/uas/login?session_redirect=x',
        ),
        isTrue,
      );
      expect(
        rule.isLoginWall('https://www.linkedin.com/posts/someone_activity-1'),
        isFalse,
      );
    });

    test('the default rule keeps only clear content', () {
      final kept = rules.defaultRule.filter([
        const WebMediaCandidate(
          url: 'https://cdn.example.com/photo-large.jpg',
          width: 1600,
          height: 1200,
        ),
        const WebMediaCandidate(
          url: 'https://cdn.example.com/thumb.jpg',
          width: 120,
          height: 90,
        ),
        const WebMediaCandidate(
          url: 'https://cdn.example.com/site-logo.png',
          width: 900,
          height: 900,
        ),
        const WebMediaCandidate(url: 'https://cdn.example.com/unsized.jpg'),
        const WebMediaCandidate(
          url: 'https://cdn.example.com/preview.jpg',
          source: 'og',
        ),
        const WebMediaCandidate(
          url: 'https://cdn.example.com/from-json.jpg',
          source: 'data',
        ),
        const WebMediaCandidate(
          url: 'https://cdn.example.com/clip.mp4',
          source: 'video',
          isVideo: true,
        ),
      ]);
      expect(kept.map((c) => Uri.parse(c.url).pathSegments.last), [
        'photo-large.jpg',
        'preview.jpg',
        'clip.mp4',
      ]);
    });

    test('a malformed pattern is ignored instead of failing', () {
      final rule = SiteRule(allow: ['(unclosed', r'ok\.jpg']);
      expect(rule.allow, hasLength(1));
    });
  });

  group('WebPageSnapshot', () {
    final source = jsonEncode({
      'title': '  Launch day  ',
      'author': 'Sam',
      'images': [
        {
          'url': 'https://media.licdn.com/dms/image/v2/AAA/feedshare-shrink_1280/0/1',
          'w': 1280,
          'h': 720,
          'source': 'img',
        },
        {
          'url': 'https://media.licdn.com/dms/image/v2/BBB/feedshare-shrink_1280/0/1',
          'w': 1280,
          'h': 720,
          'source': 'img',
        },
        {
          'url': 'https://media.licdn.com/dms/image/v2/CCC/profile-displayphoto-shrink_100_100/0/1',
          'w': 100,
          'h': 100,
          'source': 'img',
        },
      ],
      'videos': <String>[],
      'data': <String>[],
    });

    test('becomes a photo option downloaded directly', () {
      final snapshot = WebPageSnapshot.fromJson(
        source,
        finalUrl: 'https://www.linkedin.com/posts/sam_activity-1',
      );
      final info = WebPageExtractor.buildMediaInfo(
        url: 'https://lnkd.in/abc',
        snapshot: snapshot,
        rule: rules.forUrl(snapshot.finalUrl),
      );

      expect(info.title, 'Launch day');
      expect(info.uploader, 'Sam');
      expect(info.platform, MediaPlatform.linkedin);
      expect(info.url, 'https://lnkd.in/abc');
      expect(info.thumbnail, contains('/AAA/'));
      expect(info.hasVideo, isFalse);

      final option = info.galleryOption!;
      expect(option.label, 'Photos (2)');
      expect(option.engine, DownloadEngineKind.direct);
      expect(option.itemCount, 2);
      expect(option.directUrls, hasLength(2));
      expect(option.referer, 'https://www.linkedin.com/posts/sam_activity-1');
      expect(info.defaultOption, same(option));
    });

    test('with nothing usable reports no media', () {
      final snapshot = WebPageSnapshot.fromJson(
        jsonEncode({
          'title': 'Empty',
          'images': <Object>[],
          'videos': <Object>[],
          'data': <Object>[],
        }),
        finalUrl: 'https://example.com/a',
      );
      expect(
        () => WebPageExtractor.buildMediaInfo(
          url: 'https://example.com/a',
          snapshot: snapshot,
          rule: rules.defaultRule,
        ),
        throwsA(isA<WebExtractionException>()),
      );
    });
  });

  group('WebExtractionRulesStore', () {
    late Directory directory;
    setUp(
      () async =>
          directory = await Directory.systemTemp.createTemp('savekit_rules'),
    );
    tearDown(() => directory.delete(recursive: true));

    String rulesJson(int version, String host) => jsonEncode({
      'version': version,
      'default': <String, Object>{},
      'sites': [
        {'hostSuffix': host},
      ],
    });

    test(
      'prefers a newer downloaded set and ignores older or corrupt ones',
      () async {
        WebExtractionRulesStore store() => WebExtractionRulesStore(
          supportDirectory: () async => directory,
          loadBundled: () async => rulesJson(5, 'bundled.com'),
        );
        final override = File('${directory.path}/web_rules.json');

        expect((await store().load()).sites.single.hostSuffix, 'bundled.com');

        override.writeAsStringSync(rulesJson(6, 'downloaded.com'));
        expect(
          (await store().load()).sites.single.hostSuffix,
          'downloaded.com',
        );

        override.writeAsStringSync(rulesJson(4, 'stale.com'));
        expect((await store().load()).sites.single.hostSuffix, 'bundled.com');

        override.writeAsStringSync('{not json');
        expect((await store().load()).sites.single.hostSuffix, 'bundled.com');
      },
    );
  });
}
