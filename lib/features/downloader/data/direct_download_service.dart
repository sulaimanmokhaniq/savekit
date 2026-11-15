import 'dart:async';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;

import '../../extractor/data/web_page_extractor.dart';
import '../domain/download_progress.dart';

/// Returns the `Cookie` header value to send to [url], or null for none.
typedef CookieHeaderProvider = Future<String?> Function(Uri url);

/// Downloads files whose addresses are already known (photos read from a page
/// by the WebView extractor) over plain HTTP, reporting progress in the same
/// shape as the native engine so the queue treats every task alike.
class DirectDownloadService {
  DirectDownloadService({
    CookieHeaderProvider? cookieHeader,
    HttpClient Function()? httpClient,
  }) : _cookieHeader = cookieHeader ?? _webViewCookieHeader,
       _httpClient = httpClient ?? HttpClient.new;

  final CookieHeaderProvider _cookieHeader;
  final HttpClient Function() _httpClient;
  final _progress = StreamController<DownloadProgress>.broadcast();
  final _running = <String, _DirectTask>{};

  Stream<DownloadProgress> get progressStream => _progress.stream;

  bool isRunning(String taskId) => _running.containsKey(taskId);

  /// Starts downloading [urls] into [outputDir]. Returns immediately; the
  /// outcome arrives on [progressStream]. The task completes when at least
  /// one file was saved, and fails only when none could be.
  void start({
    required String taskId,
    required List<String> urls,
    required String outputDir,
    String? referer,
    String namePrefix = 'savekit',
  }) {
    if (_running.containsKey(taskId)) return;
    final task = _DirectTask(_httpClient());
    _running[taskId] = task;
    _emit(DownloadProgress(taskId: taskId, status: DownloadStatus.starting));
    unawaited(_run(taskId, task, urls, outputDir, referer, namePrefix));
  }

  /// Stops a running task. Returns false when it was not running.
  bool cancel(String taskId) {
    final task = _running[taskId];
    if (task == null) return false;
    task.canceled = true;
    task.client.close(force: true);
    return true;
  }

  void dispose() {
    for (final task in _running.values) {
      task.canceled = true;
      task.client.close(force: true);
    }
    _progress.close();
  }

  Future<void> _run(
    String taskId,
    _DirectTask task,
    List<String> urls,
    String outputDir,
    String? referer,
    String namePrefix,
  ) async {
    final saved = <File>[];
    String? lastError;
    final stamp = DateTime.now().millisecondsSinceEpoch;

    try {
      await Directory(outputDir).create(recursive: true);

      for (var index = 0; index < urls.length; index++) {
        if (task.canceled) break;
        try {
          final file = await _downloadOne(
            task: task,
            url: Uri.parse(urls[index]),
            referer: referer,
            outputDir: outputDir,
            baseName: urls.length == 1
                ? '${namePrefix}_$stamp'
                : '${namePrefix}_${stamp}_${index + 1}',
            onBytes: (received, total, speed) {
              final fraction = total > 0 ? received / total : 0.0;
              _emit(
                DownloadProgress(
                  taskId: taskId,
                  status: DownloadStatus.downloading,
                  progressPercent: ((index + fraction) / urls.length * 100)
                      .clamp(0, 99)
                      .toDouble(),
                  speed: urls.length > 1
                      ? '${index + 1}/${urls.length} files'
                      : speed,
                ),
              );
            },
          );
          saved.add(file);
        } catch (error) {
          if (task.canceled) break;
          lastError = _describe(error);
        }
      }
    } catch (error) {
      lastError = _describe(error);
    } finally {
      _running.remove(taskId);
      task.client.close(force: true);
    }

    if (task.canceled) {
      for (final file in saved) {
        try {
          await file.delete();
        } catch (_) {}
      }
      _emit(DownloadProgress(taskId: taskId, status: DownloadStatus.canceled));
      return;
    }
    if (saved.isEmpty) {
      _emit(
        DownloadProgress(
          taskId: taskId,
          status: DownloadStatus.failed,
          error: lastError ?? 'No files could be downloaded.',
        ),
      );
      return;
    }

    var totalSize = 0;
    for (final file in saved) {
      totalSize += await file.length();
    }
    _emit(
      DownloadProgress(
        taskId: taskId,
        status: DownloadStatus.completed,
        progressPercent: 100,
        eta: 0,
        filePath: saved.first.path,
        filePaths: [for (final file in saved) file.path],
        fileSize: totalSize,
      ),
    );
  }

  Future<File> _downloadOne({
    required _DirectTask task,
    required Uri url,
    required String? referer,
    required String outputDir,
    required String baseName,
    required void Function(int received, int total, String speed) onBytes,
  }) async {
    final request = await task.client.getUrl(url);
    request.followRedirects = true;
    request.headers.set(
      HttpHeaders.userAgentHeader,
      WebPageExtractor.desktopUserAgent,
    );
    request.headers.set(HttpHeaders.acceptHeader, '*/*');
    if (referer != null) {
      request.headers.set(HttpHeaders.refererHeader, referer);
    }
    final cookies = await _cookieHeader(url);
    if (cookies != null && cookies.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, cookies);
    }

    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw HttpException('Server answered ${response.statusCode}', uri: url);
    }

    final extension = _extensionFor(response.headers.contentType, url);
    final target = await _uniqueFile(outputDir, baseName, extension);
    final part = File('${target.path}.part');
    final sink = part.openWrite();
    final total = response.contentLength;
    final watch = Stopwatch()..start();
    var received = 0;
    var lastReport = Duration.zero;

    try {
      await for (final chunk in response) {
        if (task.canceled) throw const _Canceled();
        sink.add(chunk);
        received += chunk.length;
        final elapsed = watch.elapsed;
        if (elapsed - lastReport >= const Duration(milliseconds: 300)) {
          lastReport = elapsed;
          onBytes(received, total, _formatSpeed(received, elapsed));
        }
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close().catchError((_) {});
      if (await part.exists()) await part.delete();
      rethrow;
    }

    if (received == 0) {
      await part.delete();
      throw HttpException('Server sent an empty file', uri: url);
    }
    return part.rename(target.path);
  }

  void _emit(DownloadProgress progress) {
    if (!_progress.isClosed) _progress.add(progress);
  }

  static Future<String?> _webViewCookieHeader(Uri url) async {
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri.uri(url),
      );
      if (cookies.isEmpty) return null;
      return cookies.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (_) {
      return null;
    }
  }

  static const _extensionsByMimeType = {
    'image/jpeg': 'jpg',
    'image/jpg': 'jpg',
    'image/png': 'png',
    'image/webp': 'webp',
    'image/gif': 'gif',
    'image/heic': 'heic',
    'image/avif': 'avif',
    'video/mp4': 'mp4',
    'video/webm': 'webm',
    'video/quicktime': 'mov',
    'application/pdf': 'pdf',
  };

  static String _extensionFor(ContentType? contentType, Uri url) {
    final byType = _extensionsByMimeType[contentType?.mimeType.toLowerCase()];
    if (byType != null) return byType;
    final fromUrl = p.extension(url.path).replaceFirst('.', '').toLowerCase();
    if (RegExp(r'^[a-z0-9]{2,5}$').hasMatch(fromUrl)) return fromUrl;
    return 'jpg';
  }

  static Future<File> _uniqueFile(
    String directory,
    String baseName,
    String extension,
  ) async {
    var file = File(p.join(directory, '$baseName.$extension'));
    var index = 1;
    while (await file.exists()) {
      file = File(p.join(directory, '$baseName ($index).$extension'));
      index++;
    }
    return file;
  }

  static String _formatSpeed(int bytes, Duration elapsed) {
    if (elapsed.inMilliseconds <= 0) return '';
    final perSecond = bytes * 1000 / elapsed.inMilliseconds;
    if (perSecond >= 1024 * 1024) {
      return '${(perSecond / (1024 * 1024)).toStringAsFixed(1)}MiB/s';
    }
    if (perSecond >= 1024) {
      return '${(perSecond / 1024).toStringAsFixed(0)}KiB/s';
    }
    return '${perSecond.toStringAsFixed(0)}B/s';
  }

  static String _describe(Object error) {
    if (error is HttpException) return error.message;
    if (error is SocketException) return 'Network error: ${error.message}';
    return error.toString();
  }
}

class _DirectTask {
  _DirectTask(this.client);

  final HttpClient client;
  bool canceled = false;
}

class _Canceled implements Exception {
  const _Canceled();
}
