import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:savekit/core/native/youtube_dl_native_service.dart';
import 'package:savekit/core/platform/media_platform.dart';
import 'package:savekit/core/providers.dart';
import 'package:savekit/features/extractor/application/extraction_controller.dart';
import 'package:savekit/features/extractor/application/incoming_link_controller.dart';
import 'package:savekit/features/extractor/data/media_extractor.dart';
import 'package:savekit/features/extractor/domain/media_format.dart';
import 'package:savekit/features/extractor/domain/media_info.dart';

class FakeShareSource implements ShareSource {
  FakeShareSource({this.initial});

  final String? initial;
  final stream = StreamController<String>.broadcast();
  var resets = 0;

  @override
  Future<String?> initialText() async => initial;

  @override
  Stream<String> textStream() => stream.stream;

  @override
  Future<void> reset() async => resets++;
}

class FakeExtractor implements MediaExtractor {
  final pending = <String, Completer<MediaInfo>>{};

  @override
  Future<MediaInfo> fetch(String url) =>
      (pending[url] = Completer<MediaInfo>()).future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 500));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IncomingLinkController', () {
    late FakeShareSource source;
    String? clipboard;

    ProviderContainer create() {
      final container = ProviderContainer(
        overrides: [
          shareSourceProvider.overrideWithValue(source),
          clipboardReaderProvider.overrideWithValue(() async => clipboard),
        ],
      );
      addTearDown(container.dispose);
      container.listen(incomingLinkControllerProvider, (_, _) {});
      return container;
    }

    setUp(() => clipboard = null);

    test('picks up the share that launched the app', () async {
      source = FakeShareSource(
        initial: 'Look at this https://vm.tiktok.com/ZM1/ wow',
      );
      final container = create();
      await settle();

      expect(
        container.read(incomingLinkControllerProvider).shared,
        'https://vm.tiktok.com/ZM1/',
      );
      expect(source.resets, 1);

      container.read(incomingLinkControllerProvider.notifier).consumeShared();
      expect(container.read(incomingLinkControllerProvider).shared, isNull);
    });

    test('picks up shares while running and ignores text without a link', () async {
      source = FakeShareSource();
      final container = create();
      await settle();

      source.stream.add('no link here');
      await settle();
      expect(container.read(incomingLinkControllerProvider).shared, isNull);

      source.stream.add('https://www.instagram.com/p/abc/');
      await settle();
      expect(
        container.read(incomingLinkControllerProvider).shared,
        'https://www.instagram.com/p/abc/',
      );
    });

    test('offers a supported clipboard link once', () async {
      source = FakeShareSource();
      clipboard = 'https://youtu.be/abc';
      final container = create();
      final notifier = container.read(incomingLinkControllerProvider.notifier);
      await settle();
      expect(
        container.read(incomingLinkControllerProvider).clipboard,
        'https://youtu.be/abc',
      );

      notifier.dismissClipboard();
      await notifier.checkClipboard();
      expect(container.read(incomingLinkControllerProvider).clipboard, isNull);

      clipboard = 'https://x.com/u/status/2';
      await notifier.checkClipboard();
      expect(
        container.read(incomingLinkControllerProvider).clipboard,
        'https://x.com/u/status/2',
      );
    });

    test('ignores clipboard text that is not a supported link', () async {
      source = FakeShareSource();
      clipboard = 'https://example.com/article';
      final container = create();
      await settle();
      expect(container.read(incomingLinkControllerProvider).clipboard, isNull);

      clipboard = 'just some words';
      await container
          .read(incomingLinkControllerProvider.notifier)
          .checkClipboard();
      expect(container.read(incomingLinkControllerProvider).clipboard, isNull);
    });

    test('does not suggest a link that was just shared or pasted', () async {
      source = FakeShareSource(initial: 'https://youtu.be/shared');
      clipboard = 'https://youtu.be/shared';
      final container = create();
      final notifier = container.read(incomingLinkControllerProvider.notifier);
      await settle();
      expect(container.read(incomingLinkControllerProvider).clipboard, isNull);

      notifier.markHandled('https://youtu.be/pasted');
      clipboard = 'https://youtu.be/pasted';
      await notifier.checkClipboard();
      expect(container.read(incomingLinkControllerProvider).clipboard, isNull);
    });
  });

  group('ExtractionController', () {
    late FakeExtractor extractor;
    late ProviderContainer container;

    const option = MediaFormat(
      id: 'video_720',
      kind: MediaFormatKind.video,
      label: '720p',
    );
    MediaInfo media(String url, {bool empty = false}) => MediaInfo(
      url: url,
      title: 'T',
      platform: MediaPlatform.youtube,
      videoOptions: empty ? const [] : const [option],
    );

    setUp(() {
      extractor = FakeExtractor();
      container = ProviderContainer(
        overrides: [mediaExtractorProvider.overrideWithValue(extractor)],
      );
      addTearDown(container.dispose);
      container.listen(extractionControllerProvider, (_, _) {});
    });

    ExtractionController notifier() =>
        container.read(extractionControllerProvider.notifier);
    ExtractionState state() => container.read(extractionControllerProvider);

    test('goes from loading to loaded', () async {
      final fetch = notifier().fetch(' https://youtu.be/a ');
      expect(state(), isA<ExtractionLoading>());
      extractor.pending['https://youtu.be/a']!.complete(media('https://youtu.be/a'));
      await fetch;
      expect((state() as ExtractionLoaded).info.title, 'T');
    });

    test('rejects text that is not a link without calling the extractor', () async {
      await notifier().fetch('hello');
      expect(state(), isA<ExtractionFailed>());
      expect(extractor.pending, isEmpty);
    });

    test('reports extractor errors and whether logging in would help', () async {
      final fetch = notifier().fetch('https://www.instagram.com/p/a/');
      extractor.pending.values.single.completeError(
        const MediaExtractionException('Login required', loginRequired: true),
      );
      await fetch;
      final failed = state() as ExtractionFailed;
      expect(failed.message, 'Login required');
      expect(failed.loginRequired, isTrue);
    });

    test('treats a result with no options as a failure', () async {
      final fetch = notifier().fetch('https://youtu.be/a');
      extractor.pending.values.single.complete(media('https://youtu.be/a', empty: true));
      await fetch;
      expect(state(), isA<ExtractionFailed>());
    });

    test('a newer lookup wins over an older one that finishes later', () async {
      final first = notifier().fetch('https://youtu.be/first');
      final second = notifier().fetch('https://youtu.be/second');
      extractor.pending['https://youtu.be/second']!.complete(
        media('https://youtu.be/second'),
      );
      await second;
      extractor.pending['https://youtu.be/first']!.complete(
        media('https://youtu.be/first'),
      );
      await first;
      expect((state() as ExtractionLoaded).info.url, 'https://youtu.be/second');
    });

    test('clear abandons a lookup in flight', () async {
      final fetch = notifier().fetch('https://youtu.be/a');
      notifier().clear();
      extractor.pending.values.single.complete(media('https://youtu.be/a'));
      await fetch;
      expect(state(), isA<ExtractionIdle>());
    });
  });

  test('EngineException keeps the extractor message', () {
    expect(const EngineException('X', 'Video unavailable').toString(), 'Video unavailable');
  });
}
