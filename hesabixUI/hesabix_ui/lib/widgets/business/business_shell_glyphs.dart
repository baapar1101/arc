import 'package:flutter/material.dart';

/// آیکن‌های نوار ابزار پنل کسب‌وکار بدون وابستگی به فونت MaterialIcons (وب در صورت ۴۰۴ فونت، آیکن خالی نمی‌ماند).
class BusinessShellMenuGlyph extends StatelessWidget {
  const BusinessShellMenuGlyph({
    super.key,
    required this.color,
    this.size = 24,
    this.sidebarOpen = false,
  });

  final Color color;
  final double size;
  /// اگر منوی کناری (ریل) باز باشد، نماد شبیه [Icons.menu_open]؛ وگرنه همبرگر.
  final bool sidebarOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MenuGlyphPainter(color: color, sidebarOpen: sidebarOpen),
      ),
    );
  }
}

class BusinessShellStorefrontGlyph extends StatelessWidget {
  const BusinessShellStorefrontGlyph({
    super.key,
    required this.color,
    this.size = 18,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _StorefrontGlyphPainter(color: color),
      ),
    );
  }
}

class _MenuGlyphPainter extends CustomPainter {
  _MenuGlyphPainter({required this.color, required this.sidebarOpen});

  final Color color;
  final bool sidebarOpen;

  @override
  void paint(Canvas canvas, Size size) {
    final sw = (size.shortestSide * 0.085).clamp(1.2, 2.8);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    final h = size.height;

    if (!sidebarOpen) {
      for (var i = 0; i < 3; i++) {
        final y = h * (0.28 + i * 0.22);
        canvas.drawLine(Offset(w * 0.18, y), Offset(w * 0.82, y), stroke);
      }
      return;
    }

    // منو باز: نوار عمودی + سه خط (هم‌معنا با menu_open)
    canvas.drawLine(Offset(w * 0.22, h * 0.18), Offset(w * 0.22, h * 0.82), stroke);
    for (var i = 0; i < 3; i++) {
      final y = h * (0.28 + i * 0.22);
      canvas.drawLine(Offset(w * 0.42, y), Offset(w * 0.82, y), stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _MenuGlyphPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.sidebarOpen != sidebarOpen;
}

class _StorefrontGlyphPainter extends CustomPainter {
  _StorefrontGlyphPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sw = (size.shortestSide * 0.09).clamp(1.0, 2.4);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    final awning = Path()
      ..moveTo(w * 0.08, h * 0.42)
      ..lineTo(w * 0.5, h * 0.14)
      ..lineTo(w * 0.92, h * 0.42);
    canvas.drawPath(awning, stroke);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.14, h * 0.40, w * 0.72, h * 0.48),
        Radius.circular(w * 0.06),
      ),
      stroke,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.38, h * 0.58, w * 0.24, h * 0.28),
        Radius.circular(w * 0.04),
      ),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _StorefrontGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
}
