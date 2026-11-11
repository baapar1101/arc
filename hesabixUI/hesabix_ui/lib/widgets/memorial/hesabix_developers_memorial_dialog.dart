import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens/theme_catalog.dart';

/// صفحهٔ گرامیداشت (میانبر مخفی Q سپس jam).
///
/// پرترهٔ secret.png عمداً بدون نام و بدون عنوان است؛
/// تصویر به‌جای نام می‌ایستد.
class HesabixDevelopersMemorialDialog extends StatefulWidget {
  const HesabixDevelopersMemorialDialog({super.key});

  static const String _portraitAsset = 'assets/images/secret.png';

  static const List<String> _names = <String>[
    'محمد رضایی جم',
    'مصطفی شادمان',
  ];

  static Future<void> show(BuildContext context) {
    final barrierLabel =
        Localizations.of<MaterialLocalizations>(
          context,
          MaterialLocalizations,
        )?.modalBarrierDismissLabel ??
        'بستن';

    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: barrierLabel,
      barrierColor: const Color(0xFF07080C),
      useRootNavigator: true,
      transitionDuration: const Duration(milliseconds: 820),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const HesabixDevelopersMemorialDialog();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurveTween(curve: Curves.easeOutCubic).transform(
          animation.value,
        );
        return Opacity(
          opacity: curved,
          child: Transform.scale(
            scale: lerpDouble(1.02, 1, curved)!,
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<HesabixDevelopersMemorialDialog> createState() =>
      _HesabixDevelopersMemorialDialogState();
}

class _HesabixDevelopersMemorialDialogState
    extends State<HesabixDevelopersMemorialDialog>
    with TickerProviderStateMixin {
  late final AnimationController _enter;
  late final AnimationController _breath;
  late final AnimationController _orbit;
  late final Listenable _fieldTick;
  late final Listenable _portraitTick;

  ThemeData? _dark;
  Color? _appliedSeed;
  Color _candle = const Color(0xFFE6C79A);
  bool _motionConfigured = false;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1680),
    );
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    );
    _orbit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 26000),
    );
    _fieldTick = Listenable.merge([_enter, _orbit]);
    _portraitTick = Listenable.merge([_enter, _breath, _orbit]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final seed = Theme.of(context).colorScheme.primary;
    if (_appliedSeed != seed || _dark == null) {
      _appliedSeed = seed;
      final dark = AppTheme.build(
        isDark: true,
        locale: const Locale('fa'),
        themeDef: _closestTheme(seed),
      );
      _dark = dark;
      _candle = Color.lerp(
        const Color(0xFFE6C79A),
        dark.colorScheme.primary,
        0.22,
      )!;
    }
    _syncMotion();
  }

  void _syncMotion() {
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) {
      _enter.value = 1;
      _breath.value = 0.4;
      _orbit.value = 0.18;
      _breath.stop();
      _orbit.stop();
      _motionConfigured = true;
      return;
    }
    if (!_motionConfigured) {
      _motionConfigured = true;
      _enter.forward();
    }
    if (!_breath.isAnimating) _breath.repeat(reverse: true);
    if (!_orbit.isAnimating) _orbit.repeat();
  }

  @override
  void dispose() {
    _enter.dispose();
    _breath.dispose();
    _orbit.dispose();
    super.dispose();
  }

  void _close() {
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final dark = _dark!;
    final scheme = dark.colorScheme;
    final bg = Color.lerp(const Color(0xFF07080C), scheme.surface, 0.62)!;
    final onSurface = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    final width = MediaQuery.sizeOf(context).width;
    final gutter = width < 420 ? 18.0 : 28.0;
    // قاب پرتره به‌علاوهٔ هاله نباید از عرض صفحه بزند بیرون.
    final side = (width - gutter * 2 - 96).clamp(150.0, 280.0);

    final titleStyle = dark.textTheme.headlineMedium?.copyWith(
      fontSize: 40,
      fontWeight: FontWeight.w500,
      height: 1.15,
      color: onSurface,
    );
    final bodyStyle = dark.textTheme.bodyLarge?.copyWith(
      fontSize: 16.5,
      height: 2.05,
      fontWeight: FontWeight.w400,
      color: onSurface.withValues(alpha: 0.88),
    );
    final nameStyle = dark.textTheme.titleMedium?.copyWith(
      fontSize: 18,
      height: 1.4,
      fontWeight: FontWeight.w600,
      color: onSurface,
    );
    final closingStyle = dark.textTheme.bodyMedium?.copyWith(
      fontSize: 13.5,
      height: 1.8,
      color: muted.withValues(alpha: 0.92),
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: dark,
        child: Semantics(
          namesRoute: true,
          label: 'یاد و گرامیداشت',
          child: Scaffold(
            backgroundColor: bg,
            body: Stack(
              fit: StackFit.expand,
              children: [
                const RepaintBoundary(
                  child: CustomPaint(painter: _GrainPainter()),
                ),
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _fieldTick,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _MoteFieldPainter(
                          turn: _orbit.value,
                          appear: _span(_enter.value, 0.05, 0.55),
                          color: _candle,
                        ),
                      );
                    },
                  ),
                ),
                const IgnorePointer(child: _Vignette()),
                SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(gutter, 72, gutter, 36),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: math.max(0, constraints.maxHeight - 108),
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 480),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _Portrait(
                                    tick: _portraitTick,
                                    enter: _enter,
                                    breath: _breath,
                                    orbit: _orbit,
                                    side: side,
                                    candle: _candle,
                                    asset: HesabixDevelopersMemorialDialog
                                        ._portraitAsset,
                                  ),
                                  const SizedBox(height: 36),
                                  _CenterRule(
                                    animation: _enter,
                                    start: 0.18,
                                    end: 0.46,
                                    color: _candle,
                                    width: 72,
                                  ),
                                  const SizedBox(height: 26),
                                  _Reveal(
                                    animation: _enter,
                                    start: 0.24,
                                    end: 0.5,
                                    child: Text(
                                      'یاد',
                                      textAlign: TextAlign.center,
                                      style: titleStyle,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  _Reveal(
                                    animation: _enter,
                                    start: 0.34,
                                    end: 0.64,
                                    dy: 12,
                                    child: Text(
                                      'برای آنان که در این پروژه بودند،\n'
                                      'مشارکت داشتند،\n'
                                      'برای تغییر تلاش کردند\n'
                                      'و اکنون در میان ما نیستند.',
                                      textAlign: TextAlign.center,
                                      style: bodyStyle,
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                  _CenterRule(
                                    animation: _enter,
                                    start: 0.52,
                                    end: 0.74,
                                    color: _candle,
                                    width: 36,
                                  ),
                                  const SizedBox(height: 22),
                                  for (var i = 0;
                                      i <
                                          HesabixDevelopersMemorialDialog
                                              ._names
                                              .length;
                                      i++) ...[
                                    if (i > 0) const SizedBox(height: 12),
                                    _Reveal(
                                      animation: _enter,
                                      start: 0.6 + i * 0.08,
                                      end: 0.84 + i * 0.07,
                                      child: _NameLine(
                                        breath: _breath,
                                        name: HesabixDevelopersMemorialDialog
                                            ._names[i],
                                        color: _candle,
                                        style: nameStyle,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 28),
                                  _Reveal(
                                    animation: _enter,
                                    start: 0.78,
                                    end: 1,
                                    dy: 8,
                                    child: Text(
                                      'آنچه ساختند، در این مسیر مانده است.',
                                      textAlign: TextAlign.center,
                                      style: closingStyle,
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                  _Reveal(
                                    animation: _enter,
                                    start: 0.86,
                                    end: 1,
                                    dy: 6,
                                    child: TextButton(
                                      onPressed: _close,
                                      style: TextButton.styleFrom(
                                        foregroundColor:
                                            onSurface.withValues(alpha: 0.78),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 22,
                                          vertical: 12,
                                        ),
                                      ),
                                      child: const Text('بستن'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                PositionedDirectional(
                  top: 0,
                  end: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        top: 6,
                        end: 6,
                      ),
                      child: _Reveal(
                        animation: _enter,
                        start: 0.4,
                        end: 0.72,
                        dy: 0,
                        child: IconButton(
                          onPressed: _close,
                          tooltip: 'بستن',
                          icon: Icon(
                            Icons.close_rounded,
                            color: onSurface.withValues(alpha: 0.72),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Portrait extends StatelessWidget {
  const _Portrait({
    required this.tick,
    required this.enter,
    required this.breath,
    required this.orbit,
    required this.side,
    required this.candle,
    required this.asset,
  });

  final Listenable tick;
  final Animation<double> enter;
  final Animation<double> breath;
  final Animation<double> orbit;
  final double side;
  final Color candle;
  final String asset;

  @override
  Widget build(BuildContext context) {
    final frame = side;
    return SizedBox(
      width: frame + 88,
      height: frame + 88,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          _Reveal(
            animation: enter,
            start: 0,
            end: 0.42,
            dy: 0,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Opacity(
                opacity: 0.42,
                child: ClipOval(
                  child: Image.asset(
                    asset,
                    width: frame * 0.72,
                    height: frame * 0.72,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    excludeFromSemantics: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: tick,
              builder: (context, _) {
                final appear = _span(enter.value, 0, 0.46);
                final breathe = Curves.easeInOut.transform(breath.value);
                final turn = orbit.value;
                final ken = 1 + 0.04 * (0.5 - 0.5 * math.cos(turn * math.pi * 2));
                final drift = Offset(
                  math.sin(turn * math.pi * 2) * 3.2,
                  math.cos(turn * math.pi * 2) * 2.2,
                );
                final sheen = _span(enter.value, 0.12, 0.88);

                return Opacity(
                  opacity: appear,
                  child: Transform.scale(
                    scale: 0.96 + 0.04 * appear,
                    child: SizedBox(
                      width: frame + 28,
                      height: frame + 28,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: frame * (0.86 + 0.06 * breathe),
                            height: frame * (0.86 + 0.06 * breathe),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: candle.withValues(
                                    alpha: 0.16 + 0.14 * breathe,
                                  ),
                                  blurRadius: 56,
                                  spreadRadius: 8,
                                ),
                              ],
                            ),
                          ),
                          CustomPaint(
                            size: Size.square(frame + 22),
                            painter: _OrbitRingPainter(
                              turn: turn,
                              appear: appear,
                              color: candle,
                            ),
                          ),
                          Container(
                            width: frame,
                            height: frame,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  blurRadius: 28,
                                  offset: const Offset(0, 16),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  const ColoredBox(color: Color(0xFF101218)),
                                  Transform.translate(
                                    offset: drift,
                                    child: Transform.scale(
                                      scale: ken,
                                      child: Image.asset(
                                        asset,
                                        fit: BoxFit.cover,
                                        filterQuality: FilterQuality.medium,
                                        excludeFromSemantics: true,
                                        errorBuilder: (_, _, _) =>
                                            const SizedBox.shrink(),
                                      ),
                                    ),
                                  ),
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: RadialGradient(
                                        radius: 0.95,
                                        colors: [
                                          Colors.transparent,
                                          Colors.black.withValues(alpha: 0.28),
                                        ],
                                        stops: const [0.72, 1],
                                      ),
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Container(
                                      height: frame * 0.38,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.transparent,
                                            candle.withValues(
                                              alpha: 0.05 + 0.07 * breathe,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Transform.translate(
                                    offset: Offset((sheen * 2 - 1) * frame, 0),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                          colors: [
                                            Colors.transparent,
                                            Colors.white.withValues(
                                              alpha: sheen >= 0.98 ? 0 : 0.07,
                                            ),
                                            Colors.transparent,
                                          ],
                                          stops: const [0.35, 0.5, 0.65],
                                        ),
                                      ),
                                    ),
                                  ),
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(28),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NameLine extends StatelessWidget {
  const _NameLine({
    required this.breath,
    required this.name,
    required this.color,
    required this.style,
  });

  final Animation<double> breath;
  final String name;
  final Color color;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: breath,
          builder: (context, _) {
            final glow = Curves.easeInOut.transform(breath.value);
            return Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.55 + 0.45 * glow),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25 + 0.45 * glow),
                    blurRadius: 8 + 6 * glow,
                    spreadRadius: 0.4,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 12),
        Text(name, style: style),
      ],
    );
  }
}

class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.animation,
    required this.start,
    required this.end,
    required this.child,
    this.dy = 16,
  });

  final Animation<double> animation;
  final double start;
  final double end;
  final double dy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = _span(animation.value, start, end);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * dy),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _CenterRule extends StatelessWidget {
  const _CenterRule({
    required this.animation,
    required this.start,
    required this.end,
    required this.color,
    required this.width,
  });

  final Animation<double> animation;
  final double start;
  final double end;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = _span(animation.value, start, end);
        return Center(
          child: Container(
            width: width * t,
            height: 1,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(1),
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0),
                  color.withValues(alpha: 0.92),
                  color.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Vignette extends StatelessWidget {
  const _Vignette();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.15),
          radius: 1.05,
          colors: [
            Color(0x00000000),
            Color(0x99000000),
          ],
          stops: [0.42, 1],
        ),
      ),
    );
  }
}

class _OrbitRingPainter extends CustomPainter {
  const _OrbitRingPainter({
    required this.turn,
    required this.appear,
    required this.color,
  });

  final double turn;
  final double appear;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1.5;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: 0.16 * appear),
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(turn * math.pi * 2);
    canvas.translate(-center.dx, -center.dy);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [
            color.withValues(alpha: 0),
            color.withValues(alpha: 0),
            color.withValues(alpha: 0.95 * appear),
            color.withValues(alpha: 0.12 * appear),
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.58, 0.74, 0.86, 1],
        ).createShader(Offset.zero & size),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OrbitRingPainter oldDelegate) {
    return oldDelegate.turn != turn ||
        oldDelegate.appear != appear ||
        oldDelegate.color != color;
  }
}

class _Mote {
  const _Mote(this.x, this.y, this.radius, this.speed, this.phase, this.alpha);

  final double x;
  final double y;
  final double radius;
  final double speed;
  final double phase;
  final double alpha;
}

final List<_Mote> _motes = _createMotes();

List<_Mote> _createMotes() {
  final random = math.Random(11);
  return List<_Mote>.generate(28, (index) {
    final spread = random.nextDouble();
    final x = (0.5 + (spread - 0.5) * (0.42 + random.nextDouble() * 0.95))
        .clamp(0.05, 0.95);
    return _Mote(
      x,
      random.nextDouble(),
      0.6 + random.nextDouble() * 1.5,
      0.1 + random.nextDouble() * 0.34,
      random.nextDouble(),
      0.1 + random.nextDouble() * 0.34,
    );
  });
}

class _MoteFieldPainter extends CustomPainter {
  const _MoteFieldPainter({
    required this.turn,
    required this.appear,
    required this.color,
  });

  final double turn;
  final double appear;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (appear <= 0) return;
    for (final mote in _motes) {
      var progress = (mote.y - turn * mote.speed) % 1;
      if (progress < 0) progress += 1;
      final fade = math.sin(progress * math.pi) * appear;
      if (fade <= 0.01) continue;
      final x = size.width * mote.x +
          math.sin((turn + mote.phase) * math.pi * 2) * 12;
      final y = size.height * (1 - progress);
      final center = Offset(x, y);
      canvas.drawCircle(
        center,
        mote.radius * 3.4,
        Paint()..color = color.withValues(alpha: mote.alpha * fade * 0.22),
      );
      canvas.drawCircle(
        center,
        mote.radius,
        Paint()..color = color.withValues(alpha: mote.alpha * fade),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MoteFieldPainter oldDelegate) {
    return oldDelegate.turn != turn ||
        oldDelegate.appear != appear ||
        oldDelegate.color != color;
  }
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter();

  static final List<Offset> _points = _grain();

  static List<Offset> _grain() {
    final random = math.Random(3);
    return List<Offset>.generate(240, (_) {
      return Offset(random.nextDouble(), random.nextDouble());
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x0DFFFFFF);
    for (final point in _points) {
      canvas.drawCircle(
        Offset(point.dx * size.width, point.dy * size.height),
        0.6,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GrainPainter oldDelegate) => false;
}

AppThemeDefinition _closestTheme(Color seed) {
  final seedArgb = seed.toARGB32();
  var best = kAppThemeCatalog.first;
  var bestScore = 1 << 30;
  for (final def in kAppThemeCatalog) {
    final lifted = Color.lerp(def.primary, Colors.white, 0.08)!;
    final score = math.min(
      _argbDistance(def.primary.toARGB32(), seedArgb),
      _argbDistance(lifted.toARGB32(), seedArgb),
    );
    if (score < bestScore) {
      best = def;
      bestScore = score;
    }
  }
  return best;
}

int _argbDistance(int a, int b) {
  final dr = ((a >> 16) & 255) - ((b >> 16) & 255);
  final dg = ((a >> 8) & 255) - ((b >> 8) & 255);
  final db = (a & 255) - (b & 255);
  return dr * dr + dg * dg + db * db;
}

double _span(double t, double start, double end) {
  if (t <= start) return 0;
  if (t >= end) return 1;
  return Curves.easeOutCubic.transform((t - start) / (end - start));
}
