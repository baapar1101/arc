import '../../../models/barcode_label/label_design_v1.dart';
import 'label_pdf_renderer.dart';

/// تولید ZPL ساده از طرح — آزمایشی؛ نیاز به تأیید سخت‌افزاری دارد.
class LabelZplGenerator {
  static String escape(String input) {
    return input.replaceAll('^', ' ').replaceAll('~', ' ').replaceAll('\n', ' ');
  }

  static String forContexts({
    required LabelDesignDocument design,
    required List<Map<String, dynamic>> contexts,
    int dpi = 203,
  }) {
    final buf = StringBuffer();
    final dotsPerMm = dpi / 25.4;
    for (final ctx in contexts) {
      buf.writeln('^XA');
      buf.writeln('^CI28');
      final els = List<LabelElement>.from(design.elements)
        ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
      for (final el in els) {
        if (!el.visible) continue;
        final x = (el.xMm * dotsPerMm).round().clamp(0, 9999);
        final y = (el.yMm * dotsPerMm).round().clamp(0, 9999);
        final w = (el.wMm * dotsPerMm).round().clamp(1, 9999);
        final h = (el.hMm * dotsPerMm).round().clamp(1, 9999);
        final value = escape(resolveElementValue(el, ctx));
        switch (el.type) {
          case LabelElementType.text:
            if (value.isEmpty) break;
            final fontPt = (el.props['font_size_pt'] as num?)?.toDouble() ?? 9;
            final fh = (fontPt * dpi / 72).round().clamp(10, 200);
            buf.writeln('^FO$x,$y^A0N,$fh,$fh^FD$value^FS');
            break;
          case LabelElementType.barcode:
            if (value.isEmpty) break;
            final symbology = (el.props['symbology']?.toString() ?? 'code128').toLowerCase();
            if (symbology.contains('qr') || symbology.contains('datamatrix')) {
              buf.writeln('^FO$x,$y^BQN,2,4^FDQA,$value^FS');
            } else {
              final bh = h.clamp(20, 400);
              buf.writeln('^FO$x,$y^BY2^BCN,$bh,Y,N,N^FD$value^FS');
            }
            break;
          case LabelElementType.qr:
          case LabelElementType.datamatrix:
            if (value.isEmpty) break;
            buf.writeln('^FO$x,$y^BQN,2,4^FDQA,$value^FS');
            break;
          case LabelElementType.line:
          case LabelElementType.shape:
            buf.writeln(
              '^FO$x,$y^GB$w,${el.type == LabelElementType.line ? 2 : h},2^FS',
            );
            break;
          case LabelElementType.image:
            break;
        }
      }
      buf.writeln('^XZ');
    }
    return buf.toString();
  }
}
