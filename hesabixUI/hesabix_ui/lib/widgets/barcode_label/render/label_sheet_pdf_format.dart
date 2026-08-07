import 'package:pdf/pdf.dart';

import '../../../models/barcode_label/label_design_v1.dart';

/// اندازه صفحه PDF متناسب با sheet و بوم — مشترک بین استودیو و دیالوگ چاپ.
PdfPageFormat pdfPageFormatForLabelSheet(
  LabelSheet sheet, {
  required double labelWidthMm,
  required double labelHeightMm,
}) {
  if (sheet.isRollMode) {
    return PdfPageFormat(
      labelWidthMm * PdfPageFormat.mm,
      labelHeightMm * PdfPageFormat.mm,
      marginAll: 0,
    );
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
