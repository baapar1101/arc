import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Application-wide animated smoky backdrop inspired by the supplied 21st.dev
/// WebGL theme. It is intentionally implemented with Flutter painting APIs so
/// the same visual language works on web, desktop, Android and iOS.
class SmokeyBackground extends StatefulWidget {
  final bool dark;
  final Widget? child;

  const SmokeyBackground({
    super.key,
    required this.dark,
    this.child,
  });

  @override
  State<SmokeyBackground> createState() => _SmokeyBackgroundState();
}

class _SmokeyBackgroundState extends State<SmokeyBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    Widget background;
    if (reduceMotion) {
      background = CustomPaint(
        painter: _SmokeyPainter(progress: 0.18, dark: widget.dark),
        child: const SizedBox.expand(),
      );
    } else {
      background = RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _SmokeyPainter(
              progress: _controller.value,
              dark: widget.dark,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(child: background),

        // Real optical blur. All transparent Material surfaces above this layer
        // reveal a softened version of the animated smoke instead of a flat
        // translucent color, which makes the whole application read as glass.
        Positioned.fill(
          child: IgnorePointer(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: widget.dark ? 18 : 14,
                sigmaY: widget.dark ? 18 : 14,
              ),
              child: ColoredBox(
                color: widget.dark
                    ? const Color(0x12000000)
                    : const Color(0x18FFFFFF),
              ),
            ),
          ),
        ),

        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _SmokeyPainter extends CustomPainter {
  final double progress;
  final bool dark;

  const _SmokeyPainter({
    required this.progress,
    required this.dark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = dark ? const Color(0xFF0A0F1D) : const Color(0xFFF3F7FF);
    canvas.drawRect(rect, Paint()..color = base);

    final t = progress * math.pi * 2;
    final shortest = math.min(size.width, size.height);

    _blob(
      canvas,
      center: Offset(
        size.width * (0.20 + 0.08 * math.sin(t)),
        size.height * (0.22 + 0.07 * math.cos(t * 0.8)),
      ),
      radius: shortest * 0.78,
      color: dark ? const Color(0xFF1E40AF) : const Color(0xFF60A5FA),
      opacity: dark ? 0.42 : 0.30,
    );

    _blob(
      canvas,
      center: Offset(
        size.width * (0.78 + 0.10 * math.cos(t * 0.72)),
        size.height * (0.68 + 0.10 * math.sin(t * 0.9)),
      ),
      radius: shortest * 0.72,
      color: dark ? const Color(0xFF2563EB) : const Color(0xFF93C5FD),
      opacity: dark ? 0.28 : 0.34,
    );

    _blob(
      canvas,
      center: Offset(
        size.width * (0.52 + 0.12 * math.sin(t * 0.55 + 1.4)),
        size.height * (0.46 + 0.10 * math.cos(t * 0.65 + 0.8)),
      ),
      radius: shortest * 0.62,
      color: dark ? const Color(0xFF0F172A) : const Color(0xFFFFFFFF),
      opacity: dark ? 0.74 : 0.70,
    );

    final veil = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: dark
            ? const [
                Color(0x1AFFFFFF),
                Color(0x00000000),
                Color(0x55000000),
              ]
            : const [
                Color(0x99FFFFFF),
                Color(0x22FFFFFF),
                Color(0x110F172A),
              ],
      ).createShader(rect);
    canvas.drawRect(rect, veil);
  }

  void _blob(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color color,
    required double opacity,
  }) {
    final shader = RadialGradient(
      colors: [
        color.withValues(alpha: opacity),
        color.withValues(alpha: opacity * 0.35),
        color.withValues(alpha: 0),
      ],
      stops: const [0, 0.48, 1],
    ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _SmokeyPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.dark != dark;
}
