import '../../../models/barcode_label/label_design_v1.dart';
import 'label_pdf_renderer.dart';

/// تولید دستورات ESC/POS خام برای چاپگر حرارتی (متن + بارکد خطی).
class LabelEscPosGenerator {
  static const esc = 0x1B;
  static const gs = 0x1D;

  static List<int> forContexts({
    required LabelDesignDocument design,
    required List<Map<String, dynamic>> contexts,
    int dpi = 203,
  }) {
    final out = <int>[];
    final dotsPerMm = dpi / 25.4;
    for (final ctx in contexts) {
      out.addAll([esc, 0x40]); // init
      final els = List<LabelElement>.from(design.elements)
        ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
      for (final el in els) {
        if (!el.visible) continue;
        _writeElement(out, el: el, ctx: ctx, dotsPerMm: dotsPerMm);
      }
      out.addAll([gs, 0x56, 0x00]); // cut partial (printer dependent)
    }
    return out;
  }

  static void _writeElement(
    List<int> out, {
    required LabelElement el,
    required Map<String, dynamic> ctx,
    required double dotsPerMm,
  }) {
    final value = resolveElementValue(el, ctx);
    switch (el.type) {
      case LabelElementType.text:
        if (value.isEmpty) return;
        out.addAll([esc, 0x61, 0x01]); // center
        out.addAll(_textBytes(value));
        out.add(0x0A);
        out.addAll([esc, 0x61, 0x00]);
        break;
      case LabelElementType.barcode:
        if (value.isEmpty) return;
        final h = ((el.hMm * dotsPerMm) / 8).round().clamp(1, 255);
        out.addAll([gs, 0x68, h]); // barcode height
        out.addAll([gs, 0x77, 2]); // module width
        out.addAll([gs, 0x48, el.props['show_text'] != false ? 2 : 0]);
        out.addAll(_barcodeBytes(value, el.props['symbology']?.toString()));
        break;
      case LabelElementType.qr:
      case LabelElementType.datamatrix:
        // QR native در ESC/POS متغیر است — متن جایگزین
        if (value.isEmpty) return;
        out.addAll(_textBytes('[${el.type.name}: $value]'));
        out.add(0x0A);
        break;
      case LabelElementType.line:
      case LabelElementType.shape:
      case LabelElementType.image:
        break;
    }
  }

  static List<int> _textBytes(String text) => text.codeUnits;

  /// GS k — CODE128 (type 73) در بسیاری از چاپگرها
  static List<int> _barcodeBytes(String data, String? symbology) {
    final ascii = data.codeUnits.where((c) => c >= 32 && c <= 126).toList();
    if (ascii.isEmpty) return const [];
    final sym = (symbology ?? 'code128').toLowerCase();
    final type = switch (sym) {
      'ean13' => 67,
      'ean8' => 68,
      'code39' => 69,
      'codabar' => 71,
      _ => 73, // CODE128
    };
    return [gs, 0x6B, type, ascii.length, ...ascii];
  }
}
