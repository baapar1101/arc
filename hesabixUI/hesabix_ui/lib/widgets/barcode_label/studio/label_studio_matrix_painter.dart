import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';

/// رسم DataMatrix واقعی در بوم استودیو (پکیج barcode — بدون وابستگی پلتفرمی).
class LabelStudioMatrixPainter extends CustomPainter {
  final String data;

  LabelStudioMatrixPainter({required this.data});

  static const _fallback = 'DM-SAMPLE';

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final sample = data.trim().isEmpty ? _fallback : data.trim();
    final bc = Barcode.dataMatrix();
    if (!bc.isValid(sample)) {
      _drawPlaceholder(canvas, size);
      return;
    }
    try {
      final ops = bc.make(sample, width: size.width, height: size.height, drawText: false);
      for (final op in ops) {
        if (op is BarcodeBar && op.black) {
          canvas.drawRect(
            Rect.fromLTWH(op.left, op.top, op.width, op.height),
            Paint()..color = Colors.black87,
          );
        }
      }
    } catch (_) {
      _drawPlaceholder(canvas, size);
    }
  }

  void _drawPlaceholder(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.black12,
    );
  }

  @override
  bool shouldRepaint(covariant LabelStudioMatrixPainter oldDelegate) =>
      oldDelegate.data != data;
}
