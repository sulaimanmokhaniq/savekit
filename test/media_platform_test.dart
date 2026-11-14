import 'package:flutter_test/flutter_test.dart';
import 'package:savekit/core/platform/media_platform.dart';

void main() {
  group('MediaPlatform.fromUrl', () {
    const cases = {
      'https://www.youtube.com/watch?v=abc': MediaPlatform.youtube,
      'https://youtu.be/abc': MediaPlatform.youtube,
      'https://vm.tiktok.com/ZM123/': MediaPlatform.tiktok,
      'https://www.instagram.com/reel/abc/': MediaPlatform.instagram,
      'https://www.snapchat.com/spotlight/abc': MediaPlatform.snapchat,
      'https://x.com/user/status/1': MediaPlatform.x,
      'https://twitter.com/user/status/1': MediaPlatform.x,
      'https://www.linkedin.com/posts/abc': MediaPlatform.linkedin,
      'https://lnkd.in/abc': MediaPlatform.linkedin,
      'https://example.com/video': MediaPlatform.other,
      // A lookalike host must not match by suffix alone.
      'https://notx.com/a': MediaPlatform.other,
      'not a url': MediaPlatform.other,
    };
    cases.forEach((url, platform) {
      test(url, () => expect(MediaPlatform.fromUrl(url), platform));
    });
  });

  test('fromId maps the engine identifiers', () {
    expect(MediaPlatform.fromId('twitter'), MediaPlatform.x);
    expect(MediaPlatform.fromId('TikTok'), MediaPlatform.tiktok);
    expect(MediaPlatform.fromId('vimeo'), MediaPlatform.other);
    expect(MediaPlatform.fromId(null), MediaPlatform.other);
  });

  group('extractFirstUrl', () {
    test('finds a link inside shared text', () {
      expect(
        extractFirstUrl('Check this out! https://vm.tiktok.com/ZM123/ so good'),
        'https://vm.tiktok.com/ZM123/',
      );
    });

    test('drops trailing sentence punctuation', () {
      expect(
        extractFirstUrl('Watch (https://youtu.be/abc).'),
        'https://youtu.be/abc',
      );
    });

    test('returns null without a link', () {
      expect(extractFirstUrl('nothing here'), isNull);
      expect(extractFirstUrl(null), isNull);
      expect(extractFirstUrl('https://'), isNull);
    });
  });
}
