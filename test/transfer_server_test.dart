import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:savekit/features/transfer/transfer_server.dart';

void main() {
  late Directory folder;
  late TransferServer server;
  late HttpClient client;
  final uploaded = <String>[];

  Uri at(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  /// One request; returns the response and its body.
  Future<(HttpClientResponse, List<int>)> send(
    String method,
    String path, {
    String? cookie,
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    final request = await client.openUrl(method, at(path));
    request.followRedirects = false;
    if (cookie != null) request.headers.set('Cookie', cookie);
    headers.forEach(request.headers.set);
    if (body != null) request.add(body);
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      [],
      (all, part) => all..addAll(part),
    );
    return (response, bytes);
  }

  /// Enters the right code and returns the session cookie.
  Future<String> signIn() async {
    final (response, _) = await send(
      'POST',
      '/enter',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: utf8.encode('code=${server.code}'),
    );
    expect(response.statusCode, HttpStatus.seeOther);
    final cookie = response.cookies.single;
    return '${cookie.name}=${cookie.value}';
  }

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('savekit-transfer');
    File('${folder.path}/clip.mp4')
        .writeAsBytesSync(List.generate(1000, (i) => i % 256));
    File('${folder.path}/secret.txt').writeAsStringSync('not shared');
    uploaded.clear();
    server = TransferServer(
      files: () => [
        SharedFile(
          path: '${folder.path}/clip.mp4',
          title: 'Harbour at dawn',
          kind: 'video',
        ),
        // Deleted since it was saved: left out of the list.
        SharedFile(
          path: '${folder.path}/gone.mp4',
          title: 'Gone',
          kind: 'video',
        ),
      ],
      uploadDirectory: () async => '${folder.path}/in',
      onUploaded: (path) async => uploaded.add(path),
      random: Random(7),
    );
    await server.start(preferredPort: 0);
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
    folder.deleteSync(recursive: true);
  });

  test('nothing is served without the code', () async {
    expect(server.code, matches(RegExp(r'^\d{4}$')));

    final (page, body) = await send('GET', '/');
    expect(page.statusCode, HttpStatus.ok);
    expect(utf8.decode(body), contains('Enter the code shown on the phone'));
    expect(utf8.decode(body), isNot(contains('Harbour')));

    for (final path in ['/api/files', '/file/1', '/file/1?dl']) {
      expect((await send('GET', path)).$1.statusCode, HttpStatus.forbidden);
    }
    final (upload, _) = await send('POST', '/upload?name=x.txt', body: [1]);
    expect(upload.statusCode, HttpStatus.forbidden);
    expect(Directory('${folder.path}/in').existsSync(), isFalse);

    // A made-up session is no better.
    final (forged, _) = await send('GET', '/api/files', cookie: 'savekit=abc');
    expect(forged.statusCode, HttpStatus.forbidden);
  });

  test('wrong codes are refused, and too many lock the door', () async {
    Future<int> tryCode(String code) async => (await send(
      'POST',
      '/enter',
      body: utf8.encode('code=$code'),
    )).$1.statusCode;

    final wrong = server.code == '0000' ? '1111' : '0000';
    for (var i = 0; i < 8; i++) {
      expect(await tryCode(wrong), HttpStatus.forbidden);
    }
    // Even the right code no longer works until the transfer is restarted.
    expect(await tryCode(server.code), HttpStatus.forbidden);
    final (page, body) = await send('GET', '/');
    expect(page.statusCode, HttpStatus.ok);
    expect(utf8.decode(body), contains('Too many wrong codes'));

    await server.start(preferredPort: 0);
    expect(await tryCode(server.code), HttpStatus.seeOther);
  });

  test('a scanned link carries the code', () async {
    final (response, _) = await send('GET', '/?code=${server.code}');
    expect(response.statusCode, HttpStatus.seeOther);
    final cookie = response.cookies.single;
    final (page, body) = await send(
      'GET',
      '/',
      cookie: '${cookie.name}=${cookie.value}',
    );
    expect(page.statusCode, HttpStatus.ok);
    expect(utf8.decode(body), contains('Send files to the phone'));
  });

  test('lists and serves only the shared files', () async {
    final cookie = await signIn();
    final (_, listing) = await send('GET', '/api/files', cookie: cookie);
    final files = jsonDecode(utf8.decode(listing)) as List;
    expect(files, hasLength(1));
    expect(files.single, {
      'id': 1,
      'name': 'clip.mp4',
      'title': 'Harbour at dawn',
      'kind': 'video',
      'size': 1000,
      'thumb': null,
    });

    final (whole, bytes) = await send('GET', '/file/1?dl', cookie: cookie);
    expect(whole.statusCode, HttpStatus.ok);
    expect(bytes, hasLength(1000));
    expect(whole.headers.contentType?.mimeType, 'video/mp4');
    expect(
      whole.headers.value('content-disposition'),
      startsWith('attachment;'),
    );

    // Files are known by number only: paths and other numbers lead nowhere.
    for (final path in [
      '/file/2',
      '/file/secret.txt',
      '/file/..%2Fsecret.txt',
      '/secret.txt',
    ]) {
      final (response, _) = await send('GET', path, cookie: cookie);
      expect(response.statusCode, HttpStatus.notFound, reason: path);
    }
  });

  test('serves parts of a file, for playing and skipping', () async {
    final cookie = await signIn();
    await send('GET', '/api/files', cookie: cookie);

    final (middle, bytes) = await send(
      'GET',
      '/file/1',
      cookie: cookie,
      headers: {'Range': 'bytes=10-19'},
    );
    expect(middle.statusCode, HttpStatus.partialContent);
    expect(middle.headers.value('content-range'), 'bytes 10-19/1000');
    expect(bytes, [10, 11, 12, 13, 14, 15, 16, 17, 18, 19]);

    final (tail, last) = await send(
      'GET',
      '/file/1',
      cookie: cookie,
      headers: {'Range': 'bytes=-4'},
    );
    expect(tail.headers.value('content-range'), 'bytes 996-999/1000');
    expect(last, hasLength(4));

    final (open, rest) = await send(
      'GET',
      '/file/1',
      cookie: cookie,
      headers: {'Range': 'bytes=990-'},
    );
    expect(open.headers.value('content-range'), 'bytes 990-999/1000');
    expect(rest, hasLength(10));

    final (beyond, _) = await send(
      'GET',
      '/file/1',
      cookie: cookie,
      headers: {'Range': 'bytes=5000-'},
    );
    expect(beyond.statusCode, HttpStatus.requestedRangeNotSatisfiable);
  });

  test('receives files, keeping them inside the folder', () async {
    final cookie = await signIn();
    Future<String> upload(String name, String text) async {
      final (response, body) = await send(
        'POST',
        '/upload?name=${Uri.encodeQueryComponent(name)}',
        cookie: cookie,
        body: utf8.encode(text),
      );
      expect(response.statusCode, HttpStatus.ok);
      return (jsonDecode(utf8.decode(body)) as Map)['name'] as String;
    }

    expect(await upload('notes.txt', 'one'), 'notes.txt');
    // The same name again does not overwrite.
    expect(await upload('notes.txt', 'two'), 'notes (1).txt');
    // Names that try to climb out of the folder are cut down to the file.
    expect(await upload('../../evil.txt', 'x'), 'evil.txt');
    expect(await upload(r'..\..\win.txt', 'x'), 'win.txt');
    expect(await upload('.hidden', 'x'), 'hidden');
    expect(await upload('', 'x'), 'file');

    final inbox = '${folder.path}/in';
    expect(File('$inbox/notes.txt').readAsStringSync(), 'one');
    expect(File('$inbox/notes (1).txt').readAsStringSync(), 'two');
    expect(uploaded, hasLength(6));
    expect(uploaded.every((path) => path.startsWith('$inbox/')), isTrue);
    expect(File('${folder.path}/evil.txt').existsSync(), isFalse);
    // No half-written files are left behind.
    expect(
      Directory(inbox).listSync().where((f) => f.path.endsWith('.part')),
      isEmpty,
    );
  });

  test('stopping ends every session', () async {
    final cookie = await signIn();
    await server.stop();
    expect(server.running, isFalse);
    await server.start(preferredPort: 0);
    final (response, _) = await send('GET', '/api/files', cookie: cookie);
    expect(response.statusCode, HttpStatus.forbidden);
  });
}
