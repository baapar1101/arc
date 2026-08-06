import 'dart:math' as math;

import 'package:barcode/barcode.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../models/barcode_label/label_design_v1.dart';
import '../../product/product_label_pdf_text.dart';

/// رزولور binding برای چاپ/پیش‌نمایش.
String resolveLabelBinding(String? binding, Map<String, dynamic> context) {
  final key = (binding ?? '').trim();
  if (key.isEmpty) return '';
  final indexed = RegExp(r'^product\.general_barcode\[(\d+)\]$').firstMatch(key);
  if (indexed != null) {
    final raw = '${(context['product'] as Map?)?['general_barcode'] ?? ''}';
    final parts = raw
        .split(RegExp(r'[,،\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final i = int.parse(indexed.group(1)!);
    return (i >= 0 && i < parts.length) ? parts[i] : '';
  }
  dynamic cur = context;
  for (final part in key.split('.')) {
    if (cur is! Map) return '';
    cur = cur[part];
  }
  if (cur == null) return '';
  if (cur is num) {
    if (cur is int || cur == cur.roundToDouble()) return '${cur.round()}';
    return '$cur';
  }
  return '$cur';
}

String resolveElementValue(LabelElement el, Map<String, dynamic> context) {
  final props = el.props;
  final mode = (props['content_mode'] ?? 'fixed').toString();
  if (mode == 'binding') {
    return resolveLabelBinding(props['binding']?.toString(), context);
  }
  return (props['value'] ?? props['text'] ?? '').toString();
}

Barcode _linearBarcode(String symbology) {
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

String _asciiForBarcode(String input) {
  final buf = StringBuffer();
  for (final r in input.runes) {
    if (r >= 32 && r <= 126) {
      buf.writeCharCode(r);
    }
  }
  final s = buf.toString().trim();
  return s.isEmpty ? input.replaceAll(RegExp(r'\s+'), '') : s;
}

PdfPageFormat _paperFormat(LabelSheet sheet) {
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
  if (sheet.orientation == 'landscape') {
    return base.landscape;
  }
  return base;
}

/// موتور رندر واحد PDF از `label_design_v1` (منبع حقیقت چاپ).
class LabelPdfRenderer {
  static Future<pw.Font?> _loadFont(String asset) async {
    try {
      final data = await rootBundle.load(asset);
      return pw.Font.ttf(data);
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List> render({
    required LabelDesignDocument design,
    required LabelSheet sheet,
    required List<Map<String, dynamic>> contexts, // one per label
    /// یک برچسب در هر صفحه با اندازه بوم — مناسب چاپگر رولی/pdf_spooler
    bool rollMode = false,
  }) async {
    if (contexts.isEmpty) {
      throw ArgumentError('contexts must not be empty');
    }

    final fontRegular = await _loadFont('assets/fonts/YekanBakhFaNum-Regular.ttf') ??
        await _loadFont('assets/fonts/Vazirmatn-Regular.ttf');
    final fontBold = await _loadFont('assets/fonts/YekanBakhFaNum-Bold.ttf') ??
        await _loadFont('assets/fonts/Vazirmatn-Bold.ttf') ??
        fontRegular;

    final theme = pw.ThemeData.withFont(
      base: fontRegular,
      bold: fontBold,
    );

    final doc = pw.Document(theme: theme);
    final labelW = design.canvas.widthMm * PdfPageFormat.mm;
    final labelH = design.canvas.heightMm * PdfPageFormat.mm;
    final format = rollMode
        ? PdfPageFormat(labelW, labelH, marginAll: 0)
        : _paperFormat(sheet);
    final margin = rollMode
        ? pw.EdgeInsets.zero
        : pw.EdgeInsets.only(
            top: (sheet.marginMm['top'] ?? 8) * PdfPageFormat.mm,
            right: (sheet.marginMm['right'] ?? 8) * PdfPageFormat.mm,
            bottom: (sheet.marginMm['bottom'] ?? 8) * PdfPageFormat.mm,
            left: (sheet.marginMm['left'] ?? 8) * PdfPageFormat.mm,
          );
    final gapX = (sheet.gapMm['x'] ?? 2) * PdfPageFormat.mm;
    final gapY = (sheet.gapMm['y'] ?? 2) * PdfPageFormat.mm;
    final cols = rollMode ? 1 : math.max<int>(1, sheet.columns);
    final rows = rollMode ? 1 : math.max<int>(1, sheet.rows);
    final int slots = cols * rows;

    pw.Widget buildLabel(Map<String, dynamic> ctx) {
      final children = <pw.Widget>[];
      final els = List<LabelElement>.from(design.elements)
        ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
      for (final el in els) {
        if (!el.visible) continue;
        final content = _buildElement(el, ctx, fontRegular, fontBold);
        children.add(
          pw.Positioned(
            left: el.xMm * PdfPageFormat.mm,
            top: el.yMm * PdfPageFormat.mm,
            child: pw.SizedBox(
              width: el.wMm * PdfPageFormat.mm,
              height: el.hMm * PdfPageFormat.mm,
              child: el.rotationDeg.abs() < 0.01
                  ? content
                  : pw.Transform.rotate(
                      angle: el.rotationDeg * math.pi / 180.0,
                      child: content,
                    ),
            ),
          ),
        );
      }
      return pw.Container(
        width: labelW,
        height: labelH,
        decoration: rollMode
            ? null
            : pw.BoxDecoration(
                border: pw.Border.all(width: 0.2, color: PdfColors.grey400),
              ),
        child: pw.Stack(children: children),
      );
    }

    for (var start = 0; start < contexts.length; start += slots) {
      final end = math.min(start + slots, contexts.length);
      final pageContexts = contexts.sublist(start, end);
      doc.addPage(
        pw.Page(
          pageFormat: format,
          margin: margin,
          textDirection: pw.TextDirection.ltr,
          build: (context) {
            final rowWidgets = <pw.Widget>[];
            for (var r = 0; r < rows; r++) {
              final cells = <pw.Widget>[];
              for (var c = 0; c < cols; c++) {
                final i = r * cols + c;
                if (i < pageContexts.length) {
                  cells.add(buildLabel(pageContexts[i]));
                } else {
                  cells.add(pw.SizedBox(width: labelW, height: labelH));
                }
                if (c < cols - 1) {
                  cells.add(pw.SizedBox(width: gapX));
                }
              }
              rowWidgets.add(
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: cells,
                ),
              );
              if (r < rows - 1) {
                rowWidgets.add(pw.SizedBox(height: gapY));
              }
            }
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: rowWidgets,
            );
          },
        ),
      );
    }

    return doc.save();
  }

  static pw.Widget _buildElement(
    LabelElement el,
    Map<String, dynamic> ctx,
    pw.Font? regular,
    pw.Font? bold,
  ) {
    final props = el.props;
    switch (el.type) {
      case LabelElementType.text:
        final raw = resolveElementValue(el, ctx);
        final text = shapePdfPersianText(raw);
        final size = (props['font_size_pt'] as num?)?.toDouble() ?? 9;
        final weight = (props['font_weight']?.toString() == 'bold')
            ? pw.FontWeight.bold
            : pw.FontWeight.normal;
        final align = switch (props['align']?.toString()) {
          'left' => pw.TextAlign.left,
          'right' => pw.TextAlign.right,
          _ => pw.TextAlign.center,
        };
        final color = _parseColor(props['color']?.toString());
        return pw.Container(
          alignment: _align(props['align']?.toString(), props['valign']?.toString()),
          child: pw.Text(
            text,
            textAlign: align,
            textDirection: pw.TextDirection.ltr,
            maxLines: props['wrap'] == false ? 1 : 4,
            style: pw.TextStyle(
              font: weight == pw.FontWeight.bold ? (bold ?? regular) : regular,
              fontSize: size,
              fontWeight: weight,
              color: color,
            ),
          ),
        );
      case LabelElementType.barcode:
        final value = _asciiForBarcode(resolveElementValue(el, ctx));
        if (value.isEmpty) return pw.SizedBox();
        final sym = props['symbology']?.toString() ?? 'code128';
        try {
          return pw.BarcodeWidget(
            barcode: _linearBarcode(sym),
            data: value,
            drawText: props['show_text'] != false,
            textStyle: pw.TextStyle(
              fontSize: (props['text_size_pt'] as num?)?.toDouble() ?? 7,
            ),
          );
        } catch (_) {
          return pw.Center(
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 7)),
          );
        }
      case LabelElementType.qr:
        final value = resolveElementValue(el, ctx);
        if (value.isEmpty) return pw.SizedBox();
        return pw.BarcodeWidget(
          barcode: Barcode.qrCode(),
          data: value,
          drawText: false,
        );
      case LabelElementType.datamatrix:
        final value = resolveElementValue(el, ctx);
        if (value.isEmpty) return pw.SizedBox();
        try {
          return pw.BarcodeWidget(
            barcode: Barcode.dataMatrix(),
            data: value,
            drawText: false,
          );
        } catch (_) {
          return pw.BarcodeWidget(
            barcode: Barcode.qrCode(),
            data: value,
            drawText: false,
          );
        }
      case LabelElementType.shape:
        final stroke = _parseColor(props['stroke']?.toString() ?? '#000000');
        final fillRaw = props['fill']?.toString();
        final fill = (fillRaw == null || fillRaw.isEmpty) ? null : _parseColor(fillRaw);
        final sw = ((props['stroke_width_mm'] as num?)?.toDouble() ?? 0.3) * PdfPageFormat.mm;
        if (props['shape'] == 'ellipse') {
          return pw.Container(
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              border: pw.Border.all(color: stroke, width: sw),
              color: fill,
            ),
          );
        }
        return pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: stroke, width: sw),
            color: fill,
          ),
        );
      case LabelElementType.line:
        final stroke = _parseColor(props['stroke']?.toString() ?? '#000000');
        final sw = ((props['stroke_width_mm'] as num?)?.toDouble() ?? 0.3) * PdfPageFormat.mm;
        return pw.Container(
          alignment: pw.Alignment.centerLeft,
          child: pw.Container(height: sw, color: stroke),
        );
      case LabelElementType.image:
        // Phase A: placeholder box; image bytes wiring in later iteration.
        return pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: 0.4),
            color: PdfColors.grey200,
          ),
          alignment: pw.Alignment.center,
          child: pw.Text('IMG', style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
        );
    }
  }

  static PdfColor _parseColor(String? hex) {
    final h = (hex ?? '#000000').replaceAll('#', '');
    if (h.length != 6) return PdfColors.black;
    final v = int.tryParse(h, radix: 16) ?? 0;
    return PdfColor.fromInt(0xFF000000 | v);
  }

  static pw.Alignment _align(String? align, String? valign) {
    final ax = switch (align) {
      'left' => -1.0,
      'right' => 1.0,
      _ => 0.0,
    };
    final ay = switch (valign) {
      'top' => -1.0,
      'bottom' => 1.0,
      _ => 0.0,
    };
    return pw.Alignment(ax, ay);
  }
}
