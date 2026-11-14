import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:savekit/features/downloader/data/direct_download_service.dart';
import 'package:savekit/features/downloader/domain/download_progress.dart';

void main() {
  late HttpServer server;
  late Directory output;
  late DirectDownloadService service;
  late List<HttpRequest> requests;
  Completer<void>? holdSlow;

  String url(String path) => 'http://${server.address.host}:${server.port}$path';

  Future<DownloadProgress> finalEvent(String taskId) => service.progressStream
      .firstWhere((e) => e.taskId == taskId && e.status.isTerminal)
      .timeout(const Duration(seconds: 20));

  setUp(() async {
    requests = [];
    holdSlow = null;
    output = await Directory.systemTemp.createTemp('savekit_direct');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request);
      final response = request.response;
      switch (request.uri.path) {
        case '/a':
          response.headers.contentType = ContentType('image', 'jpeg');
          response.add(List.filled(2048, 1));
        case '/b.png':
          response.headers.contentType = ContentType('application', 'octet-stream');
          response.add(List.filled(1024, 2));
        case '/slow':
          response.headers.contentType = ContentType('image', 'webp');
          response.contentLength = 4096;
          response.add(List.filled(1024, 3));
          await response.flush();
          await holdSlow?.future;
          response.add(List.filled(3072, 3));
        default:
          response.statusCode = HttpStatus.notFound;
      }
      await response.close().catchError((_) {});
    });
    service = DirectDownloadService(cookieHeader: (_) async => 'li_at=secret');
  });

  tearDown(() async {
    service.dispose();
    await server.close(force: true);
    await output.delete(recursive: true);
  });

  test('saves every file, named by content type, and sends the session', () async {
    final done = finalEvent('t1');
    service.start(
      taskId: 't1',
      urls: [url('/a'), url('/b.png')],
      outputDir: output.path,
      referer: 'https://www.linkedin.com/posts/x',
      namePrefix: 'linkedin',
    );
    final event = await done;

    expect(event.status, DownloadStatus.completed);
    expect(event.filePaths, hasLength(2));
    expect(event.filePaths[0], endsWith('_1.jpg'));
    expect(event.filePaths[1], endsWith('_2.png'));
    expect(event.fileSize, 3072);
    expect(File(event.filePaths[0]).lengthSync(), 2048);
    expect(output.listSync().where((f) => f.path.endsWith('.part')), isEmpty);

    expect(requests.first.headers.value('cookie'), 'li_at=secret');
    expect(requests.first.headers.value('referer'), 'https://www.linkedin.com/posts/x');
    expect(service.isRunning('t1'), isFalse);
  });

  test('completes with the files that worked', () async {
    final done = finalEvent('t2');
    service.start(taskId: 't2', urls: [url('/missing'), url('/a')], outputDir: output.path);
    final event = await done;
    expect(event.status, DownloadStatus.completed);
    expect(event.filePaths, hasLength(1));
  });

  test('fails with the server reason when nothing could be saved', () async {
    final done = finalEvent('t3');
    service.start(taskId: 't3', urls: [url('/missing')], outputDir: output.path);
    final event = await done;
    expect(event.status, DownloadStatus.failed);
    expect(event.error, contains('404'));
    expect(output.listSync(), isEmpty);
  });

  test('cancel stops the task and leaves no files behind', () async {
    holdSlow = Completer<void>();
    final done = finalEvent('t4');
    final started = service.progressStream.firstWhere(
      (e) => e.taskId == 't4' && e.status == DownloadStatus.starting,
    );
    service.start(taskId: 't4', urls: [url('/a'), url('/slow')], outputDir: output.path);
    await started;
    // Wait until the slow file is mid-transfer.
    while (requests.length < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(service.cancel('t4'), isTrue);
    holdSlow!.complete();
    final event = await done;

    expect(event.status, DownloadStatus.canceled);
    expect(output.listSync(), isEmpty);
    expect(service.cancel('t4'), isFalse);
  });
}
