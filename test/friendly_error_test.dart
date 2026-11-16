import 'package:flutter_test/flutter_test.dart';
import 'package:savekit/core/errors/friendly_error.dart';
import 'package:savekit/core/log/app_log.dart';

void main() {
  group('describeError', () {
    const cases = {
      'ERROR: [youtube] abc: Sign in to confirm your age. This video may be inappropriate':
          'age-restricted',
      'ERROR: [Instagram] xyz: This content is only visible to followers':
          'private',
      'ERROR: [twitter] 1: NSFW tweet requires authentication. Use --cookies':
          'needs an account',
      'HTTP Error 429: Too Many Requests': 'limiting requests',
      'The uploader has not made this video available in your country':
          'your country',
      'ERROR: [youtube] abc: Video unavailable. This video has been removed':
          'no longer available',
      'ERROR: Requested format is not available': 'quality is not offered',
      "ERROR: Unsupported URL: https://example.com/a":
          'cannot read this kind of link',
      'OSError: [Errno 28] No space left on device': 'out of storage',
      'Unable to download webpage: <urlopen error [Errno 7] No address associated with hostname>':
          'connection problem',
      'ERROR: [youtube] abc: nsig extraction failed': 'Update the engine',
    };
    cases.forEach((raw, expected) {
      test(expected, () {
        final error = describeError(raw);
        expect(error.message, contains(expected));
        expect(error.raw, raw);
        expect(error.isRewritten, isTrue);
      });
    });

    test('says when logging in would help', () {
      expect(
        describeError('Sign in to confirm your age').loginRequired,
        isTrue,
      );
      expect(describeError('HTTP Error 429').loginRequired, isFalse);
    });

    test('passes unknown messages through and handles nothing at all', () {
      final unknown = describeError('Something nobody has seen before');
      expect(unknown.message, 'Something nobody has seen before');
      expect(unknown.isRewritten, isFalse);
      expect(describeError(null).message, 'Something went wrong.');
      expect(describeError('  ').message, 'Something went wrong.');
    });
  });

  test('AppLog keeps recent events, oldest first, within its limit', () {
    AppLog.clear();
    AppLog.add('first');
    AppLog.add('second', 'line one\nline two');
    expect(AppLog.lines, hasLength(2));
    expect(AppLog.lines.first, endsWith('first'));
    expect(AppLog.lines.last, contains('second\n    line one\n    line two'));

    for (var i = 0; i < 300; i++) {
      AppLog.add('event $i');
    }
    expect(AppLog.lines, hasLength(200));
    expect(AppLog.lines.last, endsWith('event 299'));
    AppLog.clear();
  });
}
