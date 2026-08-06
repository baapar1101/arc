import 'package:flutter/material.dart';

/// خط‌کش افقی/عمودی با واحد میلی‌متر.
class LabelRulerBar extends StatelessWidget {
  final bool horizontal;
  final double lengthMm;
  final double pxPerMm;
  final double zoom;
  final double offsetPx;
  final double thickness;

  const LabelRulerBar({
    super.key,
    required this.horizontal,
    required this.lengthMm,
    required this.pxPerMm,
    this.zoom = 1,
    this.offsetPx = 0,
    this.thickness = 24,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.95),
      child: CustomPaint(
        size: horizontal
            ? Size(lengthMm * pxPerMm * zoom + 80, thickness)
            : Size(thickness, lengthMm * pxPerMm * zoom + 80),
        painter: _RulerPainter(
          horizontal: horizontal,
          lengthMm: lengthMm,
          pxPerMm: pxPerMm * zoom,
          offsetPx: offsetPx,
          color: cs.onSurfaceVariant,
          majorColor: cs.onSurface,
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  final bool horizontal;
  final double lengthMm;
  final double pxPerMm;
  final double offsetPx;
  final Color color;
  final Color majorColor;

  _RulerPainter({
    required this.horizontal,
    required this.lengthMm,
    required this.pxPerMm,
    required this.offsetPx,
    required this.color,
    required this.majorColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final majorPaint = Paint()
      ..color = majorColor
      ..strokeWidth = 1.2;

    final maxMm = lengthMm.ceil() + 1;
    for (var mm = 0; mm <= maxMm; mm++) {
      final pos = offsetPx + mm * pxPerMm;
      final isMajor = mm % 5 == 0;
      final tick = isMajor ? (horizontal ? size.height * 0.7 : size.width * 0.7) : (horizontal ? size.height * 0.35 : size.width * 0.35);
      if (horizontal) {
        canvas.drawLine(Offset(pos, size.height - tick), Offset(pos, size.height), isMajor ? majorPaint : paint);
        if (isMajor) {
          final tp = TextPainter(
            text: TextSpan(text: '$mm', style: TextStyle(fontSize: 9, color: majorColor)),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(pos + 2, 2));
        }
      } else {
        canvas.drawLine(Offset(size.width - tick, pos), Offset(size.width, pos), isMajor ? majorPaint : paint);
        if (isMajor) {
          final tp = TextPainter(
            text: TextSpan(text: '$mm', style: TextStyle(fontSize: 9, color: majorColor)),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(2, pos + 2));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) =>
      oldDelegate.lengthMm != lengthMm ||
      oldDelegate.pxPerMm != pxPerMm ||
      oldDelegate.offsetPx != offsetPx;
}
