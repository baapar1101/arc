import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

/// پد امضای لمسی برای POD — مختصات نسبت به خود پد است.
class DistributionSignaturePad extends StatefulWidget {
  const DistributionSignaturePad({
    super.key,
    required this.onChanged,
    this.height = 168,
  });

  final ValueChanged<String?> onChanged;
  final double height;

  @override
  State<DistributionSignaturePad> createState() => _DistributionSignaturePadState();
}

class _DistributionSignaturePadState extends State<DistributionSignaturePad> {
  final _padKey = GlobalKey();
  final _strokes = <List<Offset>>[];
  List<Offset> _current = [];

  bool get _hasInk => _strokes.any((s) => s.length > 1);

  Offset? _norm(Offset global) {
    final box = _padKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0 || box.size.height <= 0) return null;
    final local = box.globalToLocal(global);
    return Offset(
      (local.dx / box.size.width).clamp(0.0, 1.0),
      (local.dy / box.size.height).clamp(0.0, 1.0),
    );
  }

  Future<void> _emit() async {
    if (!_hasInk) {
      widget.onChanged(null);
      return;
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = Size(400, 180);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final stroke in _strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx * size.width, stroke.first.dy * size.height);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx * size.width, p.dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.toInt(), size.height.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      widget.onChanged(null);
      return;
    }
    widget.onChanged('data:image/png;base64,${base64Encode(Uint8List.view(bytes.buffer))}');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.distributionSignatureTitle, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(t.distributionSignatureHint, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Container(
          key: _padKey,
          height: widget.height,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GestureDetector(
              onPanStart: (d) {
                final p = _norm(d.globalPosition);
                if (p == null) return;
                setState(() => _current = [p]);
              },
              onPanUpdate: (d) {
                final p = _norm(d.globalPosition);
                if (p == null) return;
                setState(() => _current.add(p));
              },
              onPanEnd: (_) {
                setState(() {
                  if (_current.isNotEmpty) _strokes.add(List.of(_current));
                  _current = [];
                });
                _emit();
              },
              child: CustomPaint(
                painter: _SigPainter([..._strokes, if (_current.isNotEmpty) _current], cs.primary),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: () {
              setState(() {
                _strokes.clear();
                _current = [];
              });
              widget.onChanged(null);
            },
            child: Text(t.distributionSignatureClear),
          ),
        ),
      ],
    );
  }
}

class _SigPainter extends CustomPainter {
  _SigPainter(this.strokes, this.color);
  final List<List<Offset>> strokes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx * size.width, stroke.first.dy * size.height);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx * size.width, p.dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SigPainter oldDelegate) => true;
}
