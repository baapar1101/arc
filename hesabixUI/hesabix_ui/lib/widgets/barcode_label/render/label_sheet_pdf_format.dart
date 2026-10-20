import 'package:pdf/pdf.dart';

import '../../../models/barcode_label/label_design_v1.dart';

/// اندازه صفحه PDF متناسب با sheet و بوم — مشترک بین استودیو و دیالوگ چاپ.
PdfPageFormat pdfPageFormatForLabelSheet(
  LabelSheet sheet, {
  required double labelWidthMm,
  required double labelHeightMm,
  int labelCount = 1,
}) {
  if (sheet.isRollMode) {
    final left = sheet.rollMarginMm['left'] ?? 0;
    final right = sheet.rollMarginMm['right'] ?? 0;
    final top = sheet.rollMarginMm['top'] ?? 0;
    final bottom = sheet.rollMarginMm['bottom'] ?? 0;
    final columns = sheet.rollColumns.clamp(1, 20).toInt();
    final gapX = sheet.rollGapMm['x'] ?? 2;
    final gapY = sheet.rollGapMm['y'] ?? 2;
    final widthMm = sheet.rollPaperWidthMm > 0
        ? sheet.rollPaperWidthMm
        : left + right + columns * labelWidthMm + (columns - 1) * gapX;
    final rows = ((labelCount.clamp(1, 10000).toInt() + columns - 1) ~/ columns);
    final heightMm = top + bottom + rows * labelHeightMm + (rows - 1) * gapY;
    return PdfPageFormat(widthMm * PdfPageFormat.mm, heightMm * PdfPageFormat.mm, marginAll: 0);
  }
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
