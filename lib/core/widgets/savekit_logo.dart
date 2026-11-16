import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// The SaveKit mark: an arrow dropping into a tray, on a rounded-square tile
/// in the theme's accent colour.
class SaveKitLogo extends StatelessWidget {
  const SaveKitLogo({
    super.key,
    this.size = 32,
    this.palette,
    this.arrowDrop = 0,
  });

  final double size;

  /// How far the arrow is pushed down, in units of the 96-unit artwork; for
  /// the opening animation.
  final double arrowDrop;

  /// Colours to draw with; defaults to the active theme.
  final AppPalette? palette;

  @override
  Widget build(BuildContext context) {
    final colors = palette ?? AppColors.current;
    return CustomPaint(
      size: Size.square(size),
      painter: _LogoPainter(colors.accent, colors.onAccent, arrowDrop),
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter(this.tile, this.mark, [this.arrowDrop = 0]);

  final Color tile;
  final Color mark;
  final double arrowDrop;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 96-unit grid.
    final unit = size.width / 96;
    canvas
      ..save()
      ..scale(unit);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(2, 2, 92, 92),
        const Radius.circular(24),
      ),
      Paint()..color = tile,
    );

    final stroke = Paint()
      ..color = mark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final arrow = Path()
      ..moveTo(48, 22 + arrowDrop)
      ..lineTo(48, 52 + arrowDrop)
      ..moveTo(33, 41 + arrowDrop)
      ..lineTo(48, 56 + arrowDrop)
      ..lineTo(63, 41 + arrowDrop);
    final tray = Path()
      ..moveTo(25, 58)
      ..lineTo(25, 66)
      ..arcToPoint(
        const Offset(33, 74),
        radius: const Radius.circular(8),
        clockwise: false,
      )
      ..lineTo(63, 74)
      ..arcToPoint(
        const Offset(71, 66),
        radius: const Radius.circular(8),
        clockwise: false,
      )
      ..lineTo(71, 58);
    canvas
      ..drawPath(arrow, stroke)
      ..drawPath(tray, stroke)
      ..restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.tile != tile || old.mark != mark || old.arrowDrop != arrowDrop;
}

/// Draws the logo in [palette]'s colours onto [canvas], filling [size].
/// For pictures made outside the widget tree, such as the player's cover.
void paintSaveKitLogo(Canvas canvas, Size size, AppPalette palette) =>
    _LogoPainter(palette.accent, palette.onAccent).paint(canvas, size);
