import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:hesabix_ui/widgets/product/product_label_pdf_text.dart';

/// متن خوانا روی پوستر: بدون https و بدون مسیر /u/ تا از فاصله دیده شود.
String payPagePosterDisplayUrl(String url) {
  var value = url.trim();
  value = value.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
  final slash = value.indexOf('/');
  if (slash <= 0) return value;
  final host = value.substring(0, slash);
  var path = value.substring(slash);
  if (path.startsWith('/u/')) {
    path = path.substring(2);
  }
  return '$host$path';
}

Future<Uint8List> buildPayPagePosterPdf({
  required String title,
  required String url,
  required String scanTitle,
  required String scanHint,
  required String urlLabel,
  required String footer,
  String? introText,
  Uint8List? logoBytes,
  required bool isPersian,
}) async {
  pw.Font? fontRegular;
  pw.Font? fontBold;
  try {
    final reg = await rootBundle.load('assets/fonts/YekanBakhFaNum-Regular.ttf');
    final bld = await rootBundle.load('assets/fonts/YekanBakhFaNum-Bold.ttf');
    fontRegular = pw.Font.ttf(reg);
    fontBold = pw.Font.ttf(bld);
  } catch (_) {
    try {
      final v = await rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf');
      fontRegular = pw.Font.ttf(v);
      fontBold = fontRegular;
    } catch (_) {
      fontRegular = null;
      fontBold = null;
    }
  }

  final theme = fontRegular != null
      ? pw.ThemeData.withFont(base: fontRegular, bold: fontBold ?? fontRegular)
      : pw.ThemeData.base();

  String t(String value) => isPersian ? shapePdfPersianText(value) : value;

  pw.TextStyle style(double size, {bool bold = false}) => pw.TextStyle(
        font: bold ? (fontBold ?? fontRegular) : fontRegular,
        fontSize: size,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      );

  pw.ImageProvider? logo;
  if (logoBytes != null && logoBytes.isNotEmpty) {
    try {
      logo = pw.MemoryImage(logoBytes);
    } catch (_) {
      logo = null;
    }
  }

  final intro = (introText ?? '').trim();
  final doc = pw.Document(theme: theme);
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 40),
      // شکل‌دهی فارسی با shapePdfPersianText برای نقاشی LTR است؛ RTL دوباره bidi می‌زند.
      textDirection: pw.TextDirection.ltr,
      build: (context) {
        return pw.Center(
          child: pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey700, width: 1.4),
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null) ...[
                  pw.Image(logo, height: 72, fit: pw.BoxFit.contain),
                  pw.SizedBox(height: 16),
                ],
                pw.Text(
                  t(title),
                  textAlign: pw.TextAlign.center,
                  textDirection: pw.TextDirection.ltr,
                  style: style(26, bold: true),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  t(scanTitle),
                  textAlign: pw.TextAlign.center,
                  textDirection: pw.TextDirection.ltr,
                  style: style(16, bold: true),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  t(scanHint),
                  textAlign: pw.TextAlign.center,
                  textDirection: pw.TextDirection.ltr,
                  style: style(12),
                ),
                pw.SizedBox(height: 22),
                pw.BarcodeWidget(
                  barcode: Barcode.qrCode(),
                  data: url,
                  width: 220,
                  height: 220,
                ),
                pw.SizedBox(height: 22),
                pw.Text(
                  t(urlLabel),
                  textAlign: pw.TextAlign.center,
                  textDirection: pw.TextDirection.ltr,
                  style: style(14, bold: true),
                ),
                pw.SizedBox(height: 10),
                pw.Directionality(
                  textDirection: pw.TextDirection.ltr,
                  child: pw.Text(
                    payPagePosterDisplayUrl(url),
                    textAlign: pw.TextAlign.center,
                    style: style(28, bold: true),
                  ),
                ),
                if (intro.isNotEmpty) ...[
                  pw.SizedBox(height: 18),
                  pw.Text(
                    t(intro),
                    textAlign: pw.TextAlign.center,
                    textDirection: pw.TextDirection.ltr,
                    style: style(11),
                  ),
                ],
                pw.SizedBox(height: 24),
                pw.Text(
                  t(footer),
                  textAlign: pw.TextAlign.center,
                  textDirection: pw.TextDirection.ltr,
                  style: style(10),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  return doc.save();
}
