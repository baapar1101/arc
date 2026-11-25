import 'package:pdf/pdf.dart';

import '../../../models/barcode_label/label_design_v1.dart';
import 'roll_label_page_metrics.dart';

/// اندازه صفحه PDF متناسب با sheet و بوم — مشترک بین استودیو و دیالوگ چاپ.
///
/// [labelCount] is ignored in roll mode: each row is its own page with a
/// fixed height (top + label + bottom), independent of how many labels print.
PdfPageFormat pdfPageFormatForLabelSheet(
  LabelSheet sheet, {
  required double labelWidthMm,
  required double labelHeightMm,
  int labelCount = 1,
}) {
  if (sheet.isRollMode) {
    final metrics = rollLabelPageMetrics(
      sheet: sheet,
      labelWidthMm: labelWidthMm,
      labelHeightMm: labelHeightMm,
    );
    return PdfPageFormat(metrics.widthMm * PdfPageFormat.mm, metrics.heightMm * PdfPageFormat.mm, marginAll: 0);
  }
  assert(labelCount >= 0);
  if (sheet.paper == 'custom') {
    final w = (sheet.customPaperMm?['width'] ?? 210) * PdfPageFormat.mm;
    final h = (sheet.customPaperMm?['height'] ?? 297) * PdfPageFormat.mm;
    var fmt = PdfPageFormat(w, h, marginAll: 0);
    if (sheet.orientation == 'landscape') fmt = fmt.landscape;
    return fmt;
  }
  PdfPageFormat base;
  switch (sheet.paper) {
    case 'A5':
      base = PdfPageFormat.a5;
      break;
    case 'Letter':
      base = PdfPageFormat.letter;
      break;
    case 'A4':
    default:
      base = PdfPageFormat.a4;
      break;
  }
  return sheet.orientation == 'landscape' ? base.landscape : base;
}
