import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

/// پیش‌نمایش PDF (موبایل/دسکتاپ) — از raster داخلی printing استفاده می‌کند.
class LabelPdfPreviewEmbed extends StatelessWidget {
  final PdfPageFormat pageFormat;
  final Future<Uint8List> Function(PdfPageFormat format) buildPdf;

  const LabelPdfPreviewEmbed({
    super.key,
    required this.pageFormat,
    required this.buildPdf,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: PdfPreview(
        initialPageFormat: pageFormat,
        build: (_) => buildPdf(pageFormat),
        allowPrinting: false,
        allowSharing: false,
        canChangePageFormat: false,
        canChangeOrientation: false,
        maxPageWidth: 640,
        pdfFileName: 'product-labels.pdf',
        scrollViewDecoration: const BoxDecoration(),
      ),
    );
  }
}
