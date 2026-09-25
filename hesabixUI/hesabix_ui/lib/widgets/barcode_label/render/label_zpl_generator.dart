import 'dart:typed_data';

import '../../../models/barcode_label/label_design_v1.dart';
import 'label_image_raster.dart';
import 'label_image_resolver.dart';
import 'label_pdf_renderer.dart';

/// تولید ZPL از طرح — symbology، چرخش، QR/DataMatrix، تصویر.
class LabelZplGenerator {
  static String escape(String input) {
    return input.replaceAll('^', ' ').replaceAll('~', ' ').replaceAll('\n', ' ');
  }

  static Future<String> forContexts({
    required LabelDesignDocument design,
    required List<Map<String, dynamic>> contexts,
    int dpi = 203,
    int? businessId,
  }) async {
    final buf = StringBuffer();
    final dotsPerMm = dpi / 25.4;
    for (var ci = 0; ci < contexts.length; ci++) {
      final ctx = contexts[ci];
      buf.writeln('^XA');
      buf.writeln('^CI28');
      final labelW = (design.canvas.widthMm * dotsPerMm).round();
      final labelH = (design.canvas.heightMm * dotsPerMm).round();
      buf.writeln('^PW$labelW');
      buf.writeln('^LL$labelH');
      final els = List<LabelElement>.from(design.elements)
        ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
      for (final el in els) {
        if (!el.visible) continue;
        Uint8List? imageBytes;
        if (el.type == LabelElementType.image) {
          imageBytes = await LabelImageResolver.resolveElement(
            el,
            context: ctx,
            businessId: businessId,
          );
        }
        await _writeElement(
          buf,
          el: el,
          ctx: ctx,
          dotsPerMm: dotsPerMm,
          imageBytes: imageBytes,
        );
      }
      buf.writeln('^XZ');
    }
    return buf.toString();
  }

  static Future<void> _writeElement(
    StringBuffer buf, {
    required LabelElement el,
    required Map<String, dynamic> ctx,
    required double dotsPerMm,
    Uint8List? imageBytes,
  }) async {
    final orient = _zplOrientation(el.rotationDeg);
    final x = (el.xMm * dotsPerMm).round().clamp(0, 9999);
    final y = (el.yMm * dotsPerMm).round().clamp(0, 9999);
    final w = (el.wMm * dotsPerMm).round().clamp(1, 9999);
    final h = (el.hMm * dotsPerMm).round().clamp(1, 9999);
    final value = escape(resolveElementValue(el, ctx));
    buf.writeln('^FW$orient');
    switch (el.type) {
      case LabelElementType.text:
        if (value.isEmpty) break;
        final fontPt = (el.props['font_size_pt'] as num?)?.toDouble() ?? 9;
        final fh = (fontPt * 203 / 72).round().clamp(10, 200);
        buf.writeln('^FO$x,$y^A0$orient,$fh,$fh^FD$value^FS');
        break;
      case LabelElementType.barcode:
        if (value.isEmpty) break;
        _writeLinearBarcode(
          buf,
          x: x,
          y: y,
          h: h,
          value: value,
          symbology: el.props['symbology']?.toString(),
          orient: orient,
          showText: el.props['show_text'] != false,
        );
        break;
      case LabelElementType.qr:
        if (value.isEmpty) break;
        final mag = (w / 80).round().clamp(2, 10);
        buf.writeln('^FO$x,$y^BQN,2,$mag^FDQA,$value^FS');
        break;
      case LabelElementType.datamatrix:
        if (value.isEmpty) break;
        final mag = (w / 40).round().clamp(4, 12);
        buf.writeln('^FO$x,$y^BXN,$mag,200^FD$value^FS');
        break;
      case LabelElementType.line:
        buf.writeln('^FO$x,$y^GB$w,2,2^FS');
        break;
      case LabelElementType.shape:
        buf.writeln('^FO$x,$y^GB$w,$h,2^FS');
        break;
      case LabelElementType.image:
        if (imageBytes == null || imageBytes.isEmpty) break;
        final raster = await LabelImageRaster.toZplGfaBytes(
          imageBytes,
          widthPx: w,
          heightPx: h,
        );
        if (raster == null) break;
        final bytesPerRow = (w + 7) ~/ 8;
        final totalBytes = bytesPerRow * h;
        final hex = raster.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join();
        buf.writeln('^FO$x,$y^GFA,$totalBytes,$totalBytes,$bytesPerRow,$hex^FS');
        break;
    }
    buf.writeln('^FWN');
  }

  static void _writeLinearBarcode(
    StringBuffer buf, {
    required int x,
    required int y,
    required int h,
    required String value,
    required String? symbology,
    required String orient,
    required bool showText,
  }) {
    final sym = (symbology ?? 'code128').toLowerCase();
    final bh = h.clamp(20, 400);
    final show = showText ? 'Y' : 'N';
    switch (sym) {
      case 'code39':
        buf.writeln('^FO$x,$y^BY2^B3$orient,N,$bh,$show,N,N^FD$value^FS');
        break;
      case 'ean13':
        buf.writeln('^FO$x,$y^BY2^BE$orient,$bh,$show,N^FD$value^FS');
        break;
      case 'ean8':
        buf.writeln('^FO$x,$y^BY2^B8$orient,$bh,$show,N^FD$value^FS');
        break;
      case 'codabar':
        buf.writeln('^FO$x,$y^BY2^BK$orient,N,$bh,$show,N,A,A^FD$value^FS');
        break;
      case 'code93':
      case 'code128':
      default:
        buf.writeln('^FO$x,$y^BY2^BC$orient,$bh,$show,N,N^FD$value^FS');
        break;
    }
  }

  static String _zplOrientation(double deg) {
    final d = deg % 360;
    if (d >= 45 && d < 135) return 'R';
    if (d >= 135 && d < 225) return 'I';
    if (d >= 225 && d < 315) return 'B';
    return 'N';
  }
}
