import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/theme/app_theme.dart';
import '../core/widgets/savekit_logo.dart';

/// The logo animation as the app opens. It starts exactly where Android's
/// own splash leaves off (the same logo, size and background, in the theme's
/// colours), drops the arrow into the tray, then fades away to show the app.
/// About 0.7 s in all; it never blocks taps.
class OpeningSplash extends StatefulWidget {
  const OpeningSplash({super.key, required this.palette, required this.onDone});

  final AppPalette palette;
  final VoidCallback onDone;

  /// Android draws the splash logo's tile 120 dp wide; the artwork's tile
  /// fills 92 of its 96 units.
  static const logoSize = 120 * 96 / 92;

  static const duration = Duration(milliseconds: 720);

  @override
  State<OpeningSplash> createState() => _OpeningSplashState();
}

class _OpeningSplashState extends State<OpeningSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: OpeningSplash.duration,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          // 0 – 0.5: the arrow drops into the tray and settles back.
          final drop = t < 0.5 ? math.sin(t / 0.5 * math.pi) * 9 : 0.0;
          // 0.45 – 1: the logo grows a little while everything fades out.
          final leave = Curves.easeIn.transform(
            ((t - 0.45) / 0.55).clamp(0.0, 1.0),
          );
          return Opacity(
            opacity: 1 - leave,
            child: ColoredBox(
              color: widget.palette.background,
              child: Center(
                child: Transform.scale(
                  scale: 1 + leave * 0.18,
                  child: SaveKitLogo(
                    size: OpeningSplash.logoSize,
                    palette: widget.palette,
                    arrowDrop: drop,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
