part of 'hesabix_developers_memorial_dialog.dart';

/// سایه‌ای کوچک در پایین صفحه: دختری تنها، بدون چهره، در برف و تاریکی.
///
/// عمداً ریز و کم‌نور است تا پرتره و متن اصلی بمانند.
class _NightSnowWalk extends StatefulWidget {
  const _NightSnowWalk({
    required this.appear,
    required this.groundLift,
  });

  final Animation<double> appear;
  final double groundLift;

  @override
  State<_NightSnowWalk> createState() => _NightSnowWalkState();
}

class _NightSnowWalkState extends State<_NightSnowWalk>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock;
  final Stopwatch _elapsed = Stopwatch();

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) {
      _clock.stop();
      _elapsed.stop();
      return;
    }
    if (!_elapsed.isRunning) _elapsed.start();
    if (!_clock.isAnimating) _clock.repeat();
  }

  @override
  void dispose() {
    _clock.dispose();
    _elapsed.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: Listenable.merge([_clock, widget.appear]),
      builder: (context, _) {
        final seconds = reduce ? 1.35 : _elapsed.elapsedMicroseconds / 1e6;
        final shown = _span(widget.appear.value, 0.4, 0.95);
        return CustomPaint(
          painter: _SnowWalkPainter(
            seconds: seconds,
            appear: shown,
            groundLift: widget.groundLift,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _SnowFlake {
  const _SnowFlake(
    this.x,
    this.y,
    this.radius,
    this.speed,
    this.drift,
    this.alpha,
    this.layer,
  );

  final double x;
  final double y;
  final double radius;
  final double speed;
  final double drift;
  final double alpha;
  final int layer;
}

final List<_SnowFlake> _snowFlakes = _makeSnowFlakes();

List<_SnowFlake> _makeSnowFlakes() {
  final random = math.Random(19);
  final flakes = <_SnowFlake>[];
  for (var i = 0; i < 34; i++) {
    flakes.add(
      _SnowFlake(
        random.nextDouble(),
        random.nextDouble(),
        0.5 + random.nextDouble() * 0.7,
        10 + random.nextDouble() * 8,
        6 + random.nextDouble() * 10,
        0.16 + random.nextDouble() * 0.18,
        0,
      ),
    );
  }
  for (var i = 0; i < 18; i++) {
    flakes.add(
      _SnowFlake(
        random.nextDouble(),
        random.nextDouble(),
        1.1 + random.nextDouble() * 1.1,
        18 + random.nextDouble() * 14,
        14 + random.nextDouble() * 16,
        0.22 + random.nextDouble() * 0.25,
        1,
      ),
    );
  }
  for (var i = 0; i < 8; i++) {
    flakes.add(
      _SnowFlake(
        random.nextDouble(),
        random.nextDouble(),
        2.4 + random.nextDouble() * 2.2,
        28 + random.nextDouble() * 18,
        20 + random.nextDouble() * 18,
        0.08 + random.nextDouble() * 0.08,
        2,
      ),
    );
  }
  return flakes;
}

class _SnowWalkPainter extends CustomPainter {
  const _SnowWalkPainter({
    required this.seconds,
    required this.appear,
    required this.groundLift,
  });

  final double seconds;
  final double appear;
  final double groundLift;

  static const double _cycle = 2.75;
  static const double _reach = 8.5;
  static const double _lift = 6.2;
  static const Color _ink = Color(0xFF1C2633);
  static const Color _rim = Color(0xFFD5E2F0);

  @override
  void paint(Canvas canvas, Size size) {
    if (appear <= 0 || size.isEmpty) return;
    final ground = Offset(
      size.width * 0.38,
      size.height - groundLift - 16,
    );

    _moon(canvas, size);
    _groundPool(canvas, ground);
    _flakes(canvas, size, 0);
    _footprints(canvas, ground);
    _girl(canvas, ground);
    _flakes(canvas, size, 1);
    _flakes(canvas, size, 2);
  }

  void _moon(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.12, size.height * 0.08);
    canvas.drawCircle(
      center,
      78,
      Paint()
        ..color = _rim.withValues(alpha: 0.045 * appear)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 36),
    );
  }

  void _groundPool(Canvas canvas, Offset ground) {
    canvas.drawOval(
      Rect.fromCenter(
        center: ground + const Offset(6, 2),
        width: 108,
        height: 14,
      ),
      Paint()
        ..color = _rim.withValues(alpha: 0.07 * appear)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: ground + const Offset(2, 3),
        width: 46,
        height: 7,
      ),
      Paint()..color = const Color(0xFF07090C).withValues(alpha: 0.35 * appear),
    );
  }

  void _flakes(Canvas canvas, Size size, int layer) {
    final gust = 0.65 + 0.35 * math.sin(seconds * 0.33);
    for (final flake in _snowFlakes) {
      if (flake.layer != layer) continue;
      final fallen = _fract(flake.y + seconds * flake.speed / size.height);
      final y = fallen * size.height;
      final fade = _heightFade(y, size.height);
      if (fade <= 0) continue;
      final wind = seconds * flake.drift * gust / size.width;
      final wobble = math.sin(seconds * 0.8 + flake.x * 12) * flake.radius;
      final x = _fract(flake.x + wind) * size.width + wobble;
      final alpha = flake.alpha * fade * appear;
      final center = Offset(x, y);
      if (layer == 2) {
        canvas.drawCircle(
          center,
          flake.radius,
          Paint()..color = _rim.withValues(alpha: alpha * 0.45),
        );
      }
      canvas.drawCircle(
        center,
        layer == 2 ? flake.radius * 0.38 : flake.radius,
        Paint()..color = const Color(0xFFF4F7FB).withValues(alpha: alpha),
      );
    }
  }

  void _footprints(Canvas canvas, Offset ground) {
    const step = _cycle / 2;
    const stride = 13.0;
    final newest = (seconds / step).floor();
    for (var ageIndex = 0; ageIndex < 8; ageIndex++) {
      final index = newest - ageIndex;
      if (index < 1) continue;
      final age = seconds - index * step;
      if (age < 0 || age > 6.5) continue;
      final fade = (1 - age / 6.5) * appear;
      final x = ground.dx + _reach - age * (stride / step);
      if (x < -20 || x > ground.dx + 30) continue;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, ground.dy + 2.2),
          width: 7.5,
          height: 2.6,
        ),
        Paint()..color = const Color(0xFF06080C).withValues(alpha: 0.42 * fade),
      );
    }
  }

  void _girl(Canvas canvas, Offset ground) {
    final phase = _fract(seconds / _cycle);
    final bob = math.cos(phase * 4 * math.pi) * 1.45;
    final hip = Offset(
      math.sin(phase * math.pi * 2) * 1.05,
      -33.5 + bob,
    );
    final leftPhase = phase;
    final rightPhase = _fract(phase + 0.5);
    final leftFoot = hip + _footOffset(leftPhase);
    final rightFoot = hip + _footOffset(rightPhase);
    final leftHip = hip + const Offset(-2.0, 0);
    final rightHip = hip + const Offset(1.8, 0.3);

    final limb = Paint()
      ..color = _ink.withValues(alpha: appear)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final limbRim = Paint()
      ..color = _rim.withValues(alpha: 0.18 * appear)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.2
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4);
    final fill = Paint()
      ..color = _ink.withValues(alpha: appear)
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(ground.dx, ground.dy);

    _leg(canvas, leftHip, leftFoot, limbRim);
    _leg(canvas, leftHip, leftFoot, limb);
    _boot(canvas, leftHip, leftFoot, fill);
    _leg(canvas, rightHip, rightFoot, limbRim);
    _leg(canvas, rightHip, rightFoot, limb);
    _boot(canvas, rightHip, rightFoot, fill);

    final upper = _upperBody(hip, phase);
    canvas.drawPath(
      upper,
      Paint()
        ..color = _rim.withValues(alpha: 0.22 * appear)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8),
    );
    canvas.drawPath(upper, fill);
    canvas.save();
    canvas.clipPath(upper);
    canvas.drawCircle(
      hip + const Offset(-4, -30),
      24,
      Paint()..color = _rim.withValues(alpha: 0.16 * appear),
    );
    canvas.restore();

    _braid(canvas, hip, phase, fill);
    _kick(canvas, leftFoot, leftPhase);
    _kick(canvas, rightFoot, rightPhase);
    _breath(canvas, hip);

    canvas.restore();
  }

  Path _upperBody(Offset hip, double phase) {
    final sway = math.sin(phase * math.pi * 2) * 2.1;
    final neck = Offset(hip.dx + 0.6, hip.dy - 15);
    final coat = Path()
      ..moveTo(neck.dx - 6.5, neck.dy + 2)
      ..quadraticBezierTo(
        neck.dx - 12,
        neck.dy + 12,
        neck.dx - 12.5 + sway * 0.25,
        hip.dy + 16,
      )
      ..quadraticBezierTo(
        neck.dx - 2,
        hip.dy + 20,
        neck.dx + 3 + sway,
        hip.dy + 17.5,
      )
      ..quadraticBezierTo(
        neck.dx + 11,
        hip.dy + 12,
        neck.dx + 8,
        neck.dy + 7,
      )
      ..quadraticBezierTo(neck.dx + 5, neck.dy + 1, neck.dx + 0.5, neck.dy)
      ..close();

    final hood = Offset(hip.dx + 0.8, hip.dy - 18);
    final hoodPath = Path()
      ..moveTo(hood.dx - 7, hood.dy + 7)
      ..quadraticBezierTo(hood.dx - 15, hood.dy - 2, hood.dx - 3, hood.dy - 13)
      ..quadraticBezierTo(hood.dx + 8, hood.dy - 15.5, hood.dx + 12, hood.dy - 3)
      ..quadraticBezierTo(hood.dx + 13, hood.dy + 3, hood.dx + 5.5, hood.dy + 7)
      ..quadraticBezierTo(hood.dx - 1, hood.dy + 5, hood.dx - 7, hood.dy + 7)
      ..close();

    return Path.combine(PathOperation.union, coat, hoodPath);
  }

  void _braid(Canvas canvas, Offset hip, double phase, Paint fill) {
    final sway = math.sin(phase * math.pi * 2 - 0.9) * 4.5;
    final start = Offset(hip.dx - 7, hip.dy - 12);
    for (var i = 0; i < 5; i++) {
      final t = i / 4;
      canvas.drawCircle(
        Offset(start.dx - t * 6 + sway * t, start.dy + 2 + t * 15),
        3.15 - t * 0.55,
        fill,
      );
    }
  }

  void _leg(Canvas canvas, Offset hip, Offset foot, Paint limb) {
    final knee = _knee(hip, foot, 17.6, 16.8);
    final root = Offset(hip.dx, hip.dy + 8);
    canvas.drawLine(root, knee, limb);
    canvas.drawLine(knee, foot, limb);
  }

  void _boot(Canvas canvas, Offset hip, Offset foot, Paint fill) {
    final knee = _knee(hip, foot, 17.6, 16.8);
    final shin = _unit(foot - knee);
    final onGround = foot.dy > -1.4;
    final sole = onGround
        ? const Offset(0.97, 0.18)
        : _unit(Offset(shin.dx + 0.85, shin.dy * 0.35 + 0.15));
    canvas.drawLine(
      foot,
      foot + sole * 6.8,
      Paint()
        ..color = fill.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round,
    );
  }

  void _kick(Canvas canvas, Offset foot, double legPhase) {
    if (legPhase < 0.5 || legPhase > 0.7) return;
    final u = (legPhase - 0.5) / 0.2;
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(
        foot + Offset(-3 - u * (5 + i * 3.0), -u * (2.5 + i * 1.8)),
        0.8 + i * 0.35,
        Paint()..color = _rim.withValues(alpha: (1 - u) * 0.22 * appear),
      );
    }
  }

  void _breath(Canvas canvas, Offset hip) {
    final cycle = _fract(seconds / 3.5);
    if (cycle > 0.42) return;
    final u = cycle / 0.42;
    canvas.drawCircle(
      hip + Offset(12 + u * 11, -20 - u * 2),
      1.4 + u * 6.5,
      Paint()..color = _rim.withValues(alpha: (1 - u) * 0.11 * appear),
    );
  }

  Offset _footOffset(double legPhase) {
    if (legPhase < 0.5) {
      final u = legPhase / 0.5;
      return Offset(_reach * (1 - 2 * u), 0);
    }
    final u = (legPhase - 0.5) / 0.5;
    final swing = Curves.easeInOut.transform(u);
    return Offset(
      _reach * (-1 + 2 * swing),
      -math.sin(u * math.pi) * _lift,
    );
  }

  Offset _knee(Offset hip, Offset foot, double thigh, double shin) {
    var delta = foot - hip;
    var dist = delta.distance;
    final maxLen = thigh + shin - 0.6;
    final minLen = (thigh - shin).abs() + 0.8;
    if (dist < 0.001) return hip + const Offset(0, thigh);
    final clamped = dist.clamp(minLen, maxLen);
    delta = delta * (clamped / dist);
    dist = clamped;
    final inv = 1 / dist;
    final along = (thigh * thigh - shin * shin + dist * dist) * 0.5 * inv;
    final height = math.sqrt(math.max(0.0, thigh * thigh - along * along));
    final ux = delta.dx * inv;
    final uy = delta.dy * inv;
    // زانو به سمت جلو (+x) خم می‌شود.
    var px = -uy;
    var py = ux;
    if (px < 0) {
      px = -px;
      py = -py;
    }
    return Offset(
      hip.dx + ux * along + px * height,
      hip.dy + uy * along + py * height,
    );
  }

  double _heightFade(double y, double height) {
    final t = (y / height).clamp(0.0, 1.0);
    if (t >= 0.2) return 1;
    return t / 0.2;
  }

  @override
  bool shouldRepaint(covariant _SnowWalkPainter oldDelegate) {
    return oldDelegate.seconds != seconds ||
        oldDelegate.appear != appear ||
        oldDelegate.groundLift != groundLift;
  }
}

Offset _unit(Offset value) {
  final dist = value.distance;
  if (dist < 0.001) return const Offset(1, 0);
  return value / dist;
}

double _fract(double value) {
  final fractional = value - value.floorToDouble();
  return fractional < 0 ? fractional + 1 : fractional;
}
