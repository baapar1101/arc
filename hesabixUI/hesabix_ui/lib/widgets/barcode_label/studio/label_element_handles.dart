import 'package:flutter/material.dart';

import '../../../models/barcode_label/label_design_v1.dart';

enum LabelHandleKind { nw, n, ne, e, se, s, sw, w, rotate }

/// دستگیره‌های تغییر اندازه و چرخش روی المان انتخاب‌شده.
class LabelElementTransformHandles extends StatelessWidget {
  final LabelElement element;
  final double pxPerMm;
  final bool enabled;
  final void Function(LabelHandleKind kind, double dxPx, double dyPx) onDrag;
  final VoidCallback? onDragEnd;

  const LabelElementTransformHandles({
    super.key,
    required this.element,
    required this.pxPerMm,
    required this.enabled,
    required this.onDrag,
    this.onDragEnd,
  });

  static const _handleSize = 10.0;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    final w = element.wMm * pxPerMm;
    final h = element.hMm * pxPerMm;
    final cs = Theme.of(context).colorScheme;

    Widget handle(LabelHandleKind kind, double left, double top, {IconData? icon}) {
      return Positioned(
        left: left - _handleSize / 2,
        top: top - _handleSize / 2,
        child: MouseRegion(
          cursor: _cursorFor(kind),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => onDrag(kind, d.delta.dx, d.delta.dy),
            onPanEnd: (_) => onDragEnd?.call(),
            child: Container(
              width: _handleSize,
              height: _handleSize,
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border.all(color: cs.primary, width: 1.5),
                shape: kind == LabelHandleKind.rotate ? BoxShape.circle : BoxShape.rectangle,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 2),
                ],
              ),
              child: icon != null ? Icon(icon, size: 8, color: cs.primary) : null,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: w,
      height: h + 22,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: w,
            height: h,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: cs.primary, width: 1.4),
                ),
              ),
            ),
          ),
          // rotate handle above top-center
          handle(LabelHandleKind.rotate, w / 2, -18, icon: Icons.rotate_right),
          CustomPaint(
            size: Size(w, 18),
            painter: _RotateStemPainter(color: cs.primary, width: w),
          ),
          handle(LabelHandleKind.nw, 0, 0),
          handle(LabelHandleKind.n, w / 2, 0),
          handle(LabelHandleKind.ne, w, 0),
          handle(LabelHandleKind.e, w, h / 2),
          handle(LabelHandleKind.se, w, h),
          handle(LabelHandleKind.s, w / 2, h),
          handle(LabelHandleKind.sw, 0, h),
          handle(LabelHandleKind.w, 0, h / 2),
        ],
      ),
    );
  }

  MouseCursor _cursorFor(LabelHandleKind k) {
    switch (k) {
      case LabelHandleKind.nw:
      case LabelHandleKind.se:
        return SystemMouseCursors.resizeUpLeftDownRight;
      case LabelHandleKind.ne:
      case LabelHandleKind.sw:
        return SystemMouseCursors.resizeUpRightDownLeft;
      case LabelHandleKind.n:
      case LabelHandleKind.s:
        return SystemMouseCursors.resizeUpDown;
      case LabelHandleKind.e:
      case LabelHandleKind.w:
        return SystemMouseCursors.resizeLeftRight;
      case LabelHandleKind.rotate:
        return SystemMouseCursors.grab;
    }
  }
}

class _RotateStemPainter extends CustomPainter {
  final Color color;
  final double width;

  _RotateStemPainter({required this.color, required this.width});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    canvas.drawLine(Offset(width / 2, 0), Offset(width / 2, 18), p);
  }

  @override
  bool shouldRepaint(covariant _RotateStemPainter oldDelegate) => false;
}

/// اعمال drag دستگیره روی هندسه المان (خروجی mm).
LabelElement applyHandleDrag({
  required LabelElement element,
  required LabelHandleKind kind,
  required double dxMm,
  required double dyMm,
  required double canvasW,
  required double canvasH,
  double minSize = 2,
  bool keepAspect = false,
}) {
  var x = element.xMm;
  var y = element.yMm;
  var w = element.wMm;
  var h = element.hMm;
  var rot = element.rotationDeg;

  switch (kind) {
    case LabelHandleKind.rotate:
      // تقریبی: حرکت افقی = چرخش
      rot = (rot + dxMm * 8) % 360;
      if (rot < 0) rot += 360;
      return element.copyWith(rotationDeg: rot);
    case LabelHandleKind.e:
      w = (w + dxMm).clamp(minSize, canvasW - x);
      break;
    case LabelHandleKind.w:
      final nw = (w - dxMm).clamp(minSize, w + x);
      x = x + (w - nw);
      w = nw;
      break;
    case LabelHandleKind.s:
      h = (h + dyMm).clamp(minSize, canvasH - y);
      break;
    case LabelHandleKind.n:
      final nh = (h - dyMm).clamp(minSize, h + y);
      y = y + (h - nh);
      h = nh;
      break;
    case LabelHandleKind.se:
      w = (w + dxMm).clamp(minSize, canvasW - x);
      h = keepAspect ? w * (element.hMm / element.wMm) : (h + dyMm).clamp(minSize, canvasH - y);
      break;
    case LabelHandleKind.nw:
      final nw = (w - dxMm).clamp(minSize, w + x);
      final nh = keepAspect ? nw * (element.hMm / element.wMm) : (h - dyMm).clamp(minSize, h + y);
      x = x + (w - nw);
      y = y + (h - nh);
      w = nw;
      h = nh;
      break;
    case LabelHandleKind.ne:
      w = (w + dxMm).clamp(minSize, canvasW - x);
      final nh = keepAspect ? w * (element.hMm / element.wMm) : (h - dyMm).clamp(minSize, h + y);
      y = y + (h - nh);
      h = nh;
      break;
    case LabelHandleKind.sw:
      final nw = (w - dxMm).clamp(minSize, w + x);
      x = x + (w - nw);
      w = nw;
      h = keepAspect ? w * (element.hMm / element.wMm) : (h + dyMm).clamp(minSize, canvasH - y);
      break;
  }

  x = x.clamp(0, canvasW - minSize);
  y = y.clamp(0, canvasH - minSize);
  return element.copyWith(xMm: x, yMm: y, wMm: w, hMm: h);
}
