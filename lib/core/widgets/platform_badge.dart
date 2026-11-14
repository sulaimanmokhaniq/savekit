import 'package:material_ui/material_ui.dart';

import '../platform/media_platform.dart';
import '../theme/app_theme.dart';

/// Icon and tint used for a platform. Generic glyphs, not brand logos.
({IconData icon, Color color}) platformStyle(MediaPlatform platform) {
  return switch (platform) {
    MediaPlatform.youtube => (
      icon: Icons.play_arrow_rounded,
      color: const Color(0xFFFF5A5A),
    ),
    MediaPlatform.tiktok => (
      icon: Icons.music_note_rounded,
      color: const Color(0xFF4DE0E0),
    ),
    MediaPlatform.instagram => (
      icon: Icons.camera_alt_outlined,
      color: const Color(0xFFF078B4),
    ),
    MediaPlatform.snapchat => (
      icon: Icons.bolt_rounded,
      color: const Color(0xFFFFE14D),
    ),
    MediaPlatform.x => (icon: Icons.close_rounded, color: AppColors.text),
    MediaPlatform.linkedin => (
      icon: Icons.work_outline_rounded,
      color: const Color(0xFF5AA9FF),
    ),
    MediaPlatform.facebook => (
      icon: Icons.thumb_up_alt_outlined,
      color: const Color(0xFF6C8CFF),
    ),
    MediaPlatform.other => (
      icon: Icons.public_rounded,
      color: AppColors.textMuted,
    ),
  };
}

/// Rounded-square tile with the platform's glyph.
class PlatformBadge extends StatelessWidget {
  const PlatformBadge(this.platform, {super.key, this.size = 28});

  final MediaPlatform platform;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = platformStyle(platform);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(style.icon, size: size * 0.62, color: style.color),
    );
  }
}

/// Labelled pill for the "supported platforms" row and vault filters.
class PlatformPill extends StatelessWidget {
  const PlatformPill(this.platform, {super.key});

  final MediaPlatform platform;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlatformBadge(platform, size: 24),
          const SizedBox(width: 8),
          Text(
            platform.label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
