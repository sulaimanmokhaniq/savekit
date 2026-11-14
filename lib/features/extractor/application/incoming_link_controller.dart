import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../../core/platform/media_platform.dart';

/// Links arriving from outside the app.
class IncomingLinks {
  const IncomingLinks({this.shared, this.clipboard});

  /// A link another app shared to SaveKit. The UI should fetch it right away
  /// and open the format picker, then call
  /// [IncomingLinkController.consumeShared].
  final String? shared;

  /// A supported link found on the clipboard, to offer with a one-tap banner.
  final String? clipboard;
}

/// Source of text shared to the app; a seam for tests.
abstract interface class ShareSource {
  Future<String?> initialText();
  Stream<String> textStream();
  Future<void> reset();
}

class ReceiveSharingIntentSource implements ShareSource {
  const ReceiveSharingIntentSource();

  /// For a text share the plugin puts the shared text in `path`.
  static String? _textOf(List<SharedMediaFile> files) {
    for (final file in files) {
      if (file.type == SharedMediaType.text || file.type == SharedMediaType.url) {
        if (file.path.isNotEmpty) return file.path;
      }
    }
    return null;
  }

  @override
  Future<String?> initialText() async =>
      _textOf(await ReceiveSharingIntent.instance.getInitialMedia());

  @override
  Stream<String> textStream() => ReceiveSharingIntent.instance
      .getMediaStream()
      .map(_textOf)
      .where((text) => text != null)
      .cast<String>();

  @override
  Future<void> reset() async => ReceiveSharingIntent.instance.reset();
}

final shareSourceProvider = Provider<ShareSource>(
  (ref) => const ReceiveSharingIntentSource(),
);

/// Reads the clipboard's text; a seam for tests.
typedef ClipboardReader = Future<String?> Function();

final clipboardReaderProvider = Provider<ClipboardReader>(
  (ref) => () async {
    try {
      return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (_) {
      return null;
    }
  },
);

/// Collects links shared from other apps (the Android share sheet) and
/// supported links sitting on the clipboard when the app comes to the front.
class IncomingLinkController extends Notifier<IncomingLinks> {
  /// Clipboard links already offered or handled, so each is suggested once.
  final _seenClipboard = <String>{};

  @override
  IncomingLinks build() {
    final source = ref.read(shareSourceProvider);

    final subscription = source.textStream().listen(_onSharedText);
    ref.onDispose(subscription.cancel);

    // The share that launched the app, if any.
    unawaited(
      source.initialText().then((text) {
        if (text != null) _onSharedText(text);
      }).catchError((_) {}),
    );

    final lifecycle = AppLifecycleListener(onResume: checkClipboard);
    ref.onDispose(lifecycle.dispose);
    // Also check once at startup; onResume does not fire for the first frame.
    unawaited(Future<void>.microtask(checkClipboard));

    return const IncomingLinks();
  }

  void _onSharedText(String text) {
    final url = extractFirstUrl(text);
    if (url == null) return;
    // A shared link is being handled; it must not come back as a suggestion.
    _seenClipboard.add(url);
    state = IncomingLinks(shared: url, clipboard: state.clipboard);
    unawaited(ref.read(shareSourceProvider).reset().catchError((_) {}));
  }

  /// Looks for a supported link on the clipboard and offers it once.
  Future<void> checkClipboard() async {
    // Android only lets the focused app read the clipboard, and focus arrives
    // a moment after the app resumes.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!ref.mounted) return;
    final url = extractFirstUrl(await ref.read(clipboardReaderProvider)());
    if (!ref.mounted) return;
    if (url == null || !isKnownPlatformUrl(url)) return;
    if (!_seenClipboard.add(url)) return;
    state = IncomingLinks(shared: state.shared, clipboard: url);
  }

  /// Call once the shared link has been handed to the extractor.
  void consumeShared() {
    if (state.shared == null) return;
    state = IncomingLinks(clipboard: state.clipboard);
  }

  /// Call when the clipboard banner is used or dismissed.
  void dismissClipboard() {
    if (state.clipboard == null) return;
    state = IncomingLinks(shared: state.shared);
  }

  /// Marks a link the user pasted by hand as handled, so the banner does not
  /// suggest it again.
  void markHandled(String url) => _seenClipboard.add(url);
}

final incomingLinkControllerProvider =
    NotifierProvider<IncomingLinkController, IncomingLinks>(
      IncomingLinkController.new,
    );
