import '../../../core/settings/app_settings.dart';
import 'media_format.dart';
import 'media_info.dart';

/// Chooses the option to download when the picker is skipped. Returns null
/// when [preference] is "ask" or nothing sensible matches, in which case the
/// picker should be shown.
MediaFormat? pickPreferredFormat(MediaInfo info, QualityPreference preference) {
  if (preference == QualityPreference.ask) return null;

  if (preference.isAudio) {
    final wanted = preference == QualityPreference.mp3 ? 'mp3' : 'm4a';
    for (final option in info.audioOptions) {
      if (option.audioFormat == wanted) return option;
    }
    return info.audioOptions.isEmpty ? null : info.audioOptions.first;
  }

  // A post that only has photos: those are what the user wants.
  if (!info.hasVideo) return info.galleryOption;

  // TikTok and Snapchat: the clean stream beats any watermarked quality.
  final clean = info.noWatermarkOption;
  if (clean != null) return clean;

  final videos = info.videoOptions;
  if (videos.isEmpty) return null;
  final limit = preference.height;
  if (limit == null) return videos.first;

  // Options are listed best first: take the best one within the limit, or
  // the smallest available when everything is larger.
  for (final option in videos) {
    final height = option.height;
    if (height == null || height <= limit) return option;
  }
  return videos.last;
}
