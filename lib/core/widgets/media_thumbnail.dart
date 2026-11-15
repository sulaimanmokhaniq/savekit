import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Rounded thumbnail from a local file or a web address, with an icon when
/// neither can be shown.
class MediaThumbnail extends StatelessWidget {
  const MediaThumbnail({
    super.key,
    this.url,
    this.filePath,
    this.width,
    this.height,
    this.radius = AppRadius.control,
    this.fallbackIcon = Icons.movie_outlined,
  });

  final String? url;

  /// Shown in preference to [url]; use for downloaded photos.
  final String? filePath;
  final double? width;
  final double? height;
  final double radius;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: AppColors.surfaceHigh,
      child: Center(
        child: Icon(fallbackIcon, color: AppColors.textMuted, size: 24),
      ),
    );

    Widget image;
    final file = filePath;
    final address = url;
    if (file != null) {
      image = Image.file(
        File(file),
        fit: BoxFit.cover,
        cacheWidth: 600,
        errorBuilder: (_, _, _) => placeholder,
      );
    } else if (address != null && address.isNotEmpty) {
      image = Image.network(
        address,
        fit: BoxFit.cover,
        cacheWidth: 600,
        errorBuilder: (_, _, _) => placeholder,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : placeholder,
      );
    } else {
      image = placeholder;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: width, height: height, child: image),
    );
  }
}

/// Centered icon, title and hint for a screen with nothing to show yet.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, color: AppColors.textMuted, size: 28),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
