import '../../../core/l10n/l10n.dart';

/// The words for a download's stage. While [starting], before any data
/// arrives, it says what is being prepared.
String stageLabel(String stage, {required bool starting}) => switch (stage) {
  'info' => tr('Reading the video’s details…'),
  'video' => tr('Downloading the video'),
  'audio' => tr('Downloading the sound'),
  'file' => tr('Downloading'),
  'subtitles' => tr('Downloading subtitles'),
  'merge' => tr('Joining video and sound…'),
  'convert' => tr('Converting…'),
  'finishing' => tr('Finishing…'),
  _ => starting ? tr('Connecting…') : tr('Downloading'),
};
