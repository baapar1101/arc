import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';

/// رسم بارکد خطی واقعی در بوم استودیو (هم‌راستا با PDF).
Barcode linearBarcodeForSymbology(String symbology) {
  switch (symbology) {
    case 'code39':
      return Barcode.code39();
    case 'code93':
      return Barcode.code93();
    case 'ean8':
      return Barcode.ean8();
    case 'ean13':
      return Barcode.ean13();
    case 'codabar':
      return Barcode.codabar();
    case 'code128':
    default:
      return Barcode.code128();
  }
}

String sampleDataForSymbology(String symbology, String preferred) {
  final p = preferred.trim();
  if (p.isNotEmpty) {
    try {
      linearBarcodeForSymbology(symbology).verify(p);
      return p;
    } catch (_) {}
  }
  switch (symbology) {
    case 'ean13':
      return '5901234123457';
    case 'ean8':
      return '96385074';
    case 'code39':
      return 'CODE39';
    case 'code93':
      return 'CODE93';
    case 'codabar':
      return 'A40156B';
    case 'code128':
    default:
      return '123456789012';
  }
}

class LabelStudioBarcodePainter extends CustomPainter {
  final String symbology;
  final String data;
  final bool showText;

  LabelStudioBarcodePainter({
    required this.symbology,
    required this.data,
    this.showText = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final sample = sampleDataForSymbology(symbology, data);
    final bc = linearBarcodeForSymbology(symbology);
    if (!bc.isValid(sample)) {
      _drawInvalid(canvas, size);
      return;
    }

    try {
      final ops = bc.make(
        sample,
        width: size.width,
        height: size.height,
        drawText: showText,
        fontHeight: showText ? (size.height * 0.18).clamp(7.0, 12.0) : null,
        textPadding: 1,
      );
      for (final op in ops) {
        if (op is BarcodeBar && op.black) {
          canvas.drawRect(
            Rect.fromLTWH(op.left, op.top, op.width, op.height),
            Paint()..color = Colors.black87,
          );
        } else if (op is BarcodeText && showText) {
          final tp = TextPainter(
            text: TextSpan(
              text: op.text,
              style: TextStyle(fontSize: op.height * 0.75, color: Colors.black87),
            ),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
          )..layout(maxWidth: op.width);
          final dx = op.left + (op.width - tp.width) / 2;
          final dy = op.top + (op.height - tp.height) / 2;
          tp.paint(canvas, Offset(dx, dy));
        }
      }
    } catch (_) {
      _drawInvalid(canvas, size);
    }
  }

  void _drawInvalid(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black26;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant LabelStudioBarcodePainter oldDelegate) =>
      oldDelegate.symbology != symbology ||
      oldDelegate.data != data ||
      oldDelegate.showText != showText;
}
