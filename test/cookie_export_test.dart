import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:savekit/features/cookies/data/cookie_export_service.dart';
import 'package:savekit/features/cookies/data/netscape_cookie_file.dart';
import 'package:savekit/features/cookies/domain/platform_account.dart';

void main() {
  group('NetscapeCookieFile.serialize', () {
    final now = DateTime.utc(2026, 1, 1);

    test('writes the seven tab-separated fields', () {
      final text = NetscapeCookieFile.serialize([
        NetscapeCookie(
          domain: '.instagram.com',
          name: 'sessionid',
          value: 'abc%3A123',
          expires: DateTime.utc(2027, 1, 1),
        ),
      ], now: now);

      expect(text, startsWith('# Netscape HTTP Cookie File\n'));
      final line = text.trim().split('\n').last;
      expect(line.split('\t'), [
        '.instagram.com',
        'TRUE',
        '/',
        'TRUE',
        '${DateTime.utc(2027, 1, 1).millisecondsSinceEpoch ~/ 1000}',
        'sessionid',
        'abc%3A123',
      ]);
    });

    test('marks HttpOnly, host-only and insecure cookies', () {
      final text = NetscapeCookieFile.serialize([
        const NetscapeCookie(
          domain: 'www.linkedin.com',
          name: 'li_at',
          value: 'v',
          path: '/feed',
          secure: false,
          httpOnly: true,
        ),
      ], now: now);
      final fields = text.trim().split('\n').last.split('\t');
      expect(fields[0], '#HttpOnly_www.linkedin.com');
      expect(fields[1], 'FALSE');
      expect(fields[2], '/feed');
      expect(fields[3], 'FALSE');
    });

    test('gives session cookies a future expiry', () {
      final text = NetscapeCookieFile.serialize([
        const NetscapeCookie(domain: '.x.com', name: 'auth_token', value: 'v'),
      ], now: now);
      final expiry = int.parse(text.trim().split('\n').last.split('\t')[4]);
      expect(expiry, greaterThan(now.millisecondsSinceEpoch ~/ 1000));
    });

    test('skips duplicates and values that would break the format', () {
      final text = NetscapeCookieFile.serialize([
        const NetscapeCookie(domain: '.x.com', name: 'a', value: '1'),
        const NetscapeCookie(domain: '.x.com', name: 'a', value: '2'),
        const NetscapeCookie(domain: '.x.com', name: 'bad', value: 'x\ty'),
        const NetscapeCookie(domain: '.x.com', name: 'bad2', value: 'x\ny'),
        const NetscapeCookie(domain: '.x.com', name: '', value: 'x'),
      ], now: now);
      final lines = text
          .split('\n')
          .where((line) => line.isNotEmpty && !line.startsWith('# '))
          .toList();
      expect(lines, hasLength(1));
      expect(lines.single, endsWith('\ta\t1'));
    });
  });

  group('CookieExportService', () {
    late Directory directory;
    late Map<String, List<Cookie>> store;
    late CookieExportService service;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('savekit_cookies');
      store = {};
      service = CookieExportService(
        readCookies: (url) async => store[url.host] ?? const [],
        documentsDirectory: () async => directory,
      );
    });

    tearDown(() => directory.delete(recursive: true));

    test('exports nothing while signed out', () async {
      // Anonymous cookies alone are not a session.
      store['www.instagram.com'] = [Cookie(name: 'csrftoken', value: 'x')];
      expect(await service.exportAll(), isNull);
      expect(await service.cookiesFilePath(), isNull);
      expect(await service.isLoggedIn(PlatformAccount.instagram), isFalse);
    });

    test('exports signed-in platforms only', () async {
      store['www.instagram.com'] = [
        Cookie(name: 'csrftoken', value: 'x'),
        // Reported without a domain, as older WebViews do.
        Cookie(name: 'sessionid', value: 'secret'),
      ];
      store['www.linkedin.com'] = [Cookie(name: 'lang', value: 'en')];
      store['twitter.com'] = [
        Cookie(name: 'auth_token', value: 't', domain: '.twitter.com'),
      ];

      final path = await service.exportAll();
      expect(path, isNotNull);
      expect(await service.cookiesFilePath(), path);
      final text = await File(path!).readAsString();

      expect(text, contains('.instagram.com\tTRUE\t/\tTRUE\t'));
      expect(text, contains('\tsessionid\tsecret'));
      expect(text, contains('\tcsrftoken\tx'));
      expect(text, contains('.twitter.com\tTRUE'));
      expect(text, isNot(contains('linkedin')));

      expect(await service.loginStatuses(), {
        PlatformAccount.instagram: true,
        PlatformAccount.x: true,
        PlatformAccount.tiktok: false,
        PlatformAccount.linkedin: false,
      });
    });

    test('removes the file once every session is gone', () async {
      store['www.tiktok.com'] = [Cookie(name: 'sessionid', value: 's')];
      final path = await service.exportAll();
      expect(File(path!).existsSync(), isTrue);

      store.clear();
      expect(await service.exportAll(), isNull);
      expect(File(path).existsSync(), isFalse);
    });
  });
}
