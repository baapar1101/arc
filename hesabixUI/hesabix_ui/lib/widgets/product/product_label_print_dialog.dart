import 'dart:math' as math;

import 'package:barcode/barcode.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../utils/snackbar_helper.dart';
import '../data_table/helpers/file_saver.dart';
import 'label_pdf_preview_embed.dart';
import 'product_label_pdf_text.dart';

/// یک واحد کالای یونیک (یا تجمیع چند کالا) برای چاپ برچسب بارکد / QR.
class ProductLabelPrintItem {
  final String productName;
  final String productCode;
  final String serialNumber;
  final String? instanceBarcode;
  final String? warehouseLabel;
  final String status;

  const ProductLabelPrintItem({
    required this.productName,
    required this.productCode,
    required this.serialNumber,
    this.instanceBarcode,
    this.warehouseLabel,
    this.status = '',
  });

  String get scanValue {
    final b = instanceBarcode?.trim();
    if (b != null && b.isNotEmpty) return b;
    return serialNumber.trim();
  }
}

enum _PaperKind { a4, a5, letter }

extension on _PaperKind {
  String get label {
    switch (this) {
      case _PaperKind.a4:
        return 'A4';
      case _PaperKind.a5:
        return 'A5';
      case _PaperKind.letter:
        return 'Letter';
    }
  }

  PdfPageFormat baseFormat() {
    switch (this) {
      case _PaperKind.a4:
        return PdfPageFormat.a4;
      case _PaperKind.a5:
        return PdfPageFormat.a5;
      case _PaperKind.letter:
        return PdfPageFormat.letter;
    }
  }
}

/// دیالوگ پیش‌نمایش و ذخیره/اشتراک PDF برچسب‌ها.
class ProductLabelPrintDialog extends StatefulWidget {
  final List<ProductLabelPrintItem> items;

  const ProductLabelPrintDialog({super.key, required this.items});

  static Future<void> show(BuildContext context, {required List<ProductLabelPrintItem> items}) {
    if (items.isEmpty) return Future.value();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ProductLabelPrintDialog(items: items),
    );
  }

  @override
  State<ProductLabelPrintDialog> createState() => _ProductLabelPrintDialogState();
}

class _ProductLabelPrintDialogState extends State<ProductLabelPrintDialog> {
  bool _showLinear = true;
  bool _showQr = true;
  bool _showProductName = true;
  bool _showSerialLine = true;
  int _columns = 2;
  double _marginPt = 28;
  _PaperKind _paper = _PaperKind.a4;
  bool _landscape = false;

  PdfPageFormat get _pageFormat {
    final b = _paper.baseFormat();
    return _landscape ? b.landscape : b;
  }

  /// مقدار امن برای بارکد خطی (Code128 زیرمجموعهٔ ASCII).
  static String _asciiForBarcode(String raw) {
    final b = StringBuffer();
    for (final c in raw.codeUnits) {
      if (c >= 32 && c < 127) b.write(String.fromCharCode(c));
    }
    final s = b.toString().trim();
    if (s.isEmpty) return '0';
    return s.length > 80 ? s.substring(0, 80) : s;
  }

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    try {
      return await _buildPdfUnsafe(format);
    } catch (e, st) {
      debugPrint('ProductLabelPrintDialog PDF error: $e\n$st');
      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: format,
          build: (ctx) => pw.Center(
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(24),
              child: pw.Text(
                shapePdfPersianText('خطا در ساخت فایل PDF.\n$e'),
                textAlign: pw.TextAlign.center,
                textDirection: pw.TextDirection.ltr,
              ),
            ),
          ),
        ),
      );
      return doc.save();
    }
  }

  Future<Uint8List> _buildPdfUnsafe(PdfPageFormat format) async {
    // همان خانوادهٔ فونت خروجی PDF فاکتور (قالب‌های HTML / Hesabix API)
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

    final doc = pw.Document();
    final items = widget.items;
    final margin = _marginPt;
    final contentWidth = math.max(100.0, format.width - (margin * 2));
    final contentHeight = math.max(100.0, format.height - (margin * 2));
    final colWidth = math.max(100.0, (contentWidth / _columns) - 8);

    const slotHeightEstimate = 175.0;
    final rowsPerPage = math.max(1, (contentHeight / slotHeightEstimate).floor());
    final slotsPerPage = math.max(1, rowsPerPage * _columns);

    pw.TextStyle faStyle(pw.Font? f, double size, {pw.FontWeight? weight}) => pw.TextStyle(
          font: f,
          fontSize: size,
          fontWeight: weight,
          letterSpacing: 0,
          wordSpacing: 0,
        );

    pw.Widget labelCard(ProductLabelPrintItem item, double cellW) {
      final rawScan = item.scanValue.trim();
      final hasScan = rawScan.isNotEmpty;
      final scan = hasScan ? _asciiForBarcode(rawScan) : '';
      final barW = math.max(72.0, cellW - 20);

      final children = <pw.Widget>[
        if (_showProductName)
          pw.Text(
            shapePdfPersianText(item.productName),
            style: faStyle(fontBold ?? fontRegular, 9, weight: pw.FontWeight.bold),
            maxLines: 2,
            textAlign: pw.TextAlign.center,
            textDirection: pw.TextDirection.ltr,
          ),
        if (_showProductName) pw.SizedBox(height: 2),
        pw.Text(
          shapePdfPersianText(item.productCode),
          style: faStyle(fontRegular, 7),
          textAlign: pw.TextAlign.center,
          textDirection: pw.TextDirection.ltr,
        ),
        if (_showSerialLine) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            shapePdfPersianText('سریال: ${item.serialNumber}'),
            style: faStyle(fontRegular, 7),
            textAlign: pw.TextAlign.center,
            textDirection: pw.TextDirection.ltr,
          ),
        ],
        if (item.instanceBarcode != null && item.instanceBarcode!.trim().isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            shapePdfPersianText('بارکد: ${item.instanceBarcode}'),
            style: faStyle(fontRegular, 7),
            textAlign: pw.TextAlign.center,
            textDirection: pw.TextDirection.ltr,
          ),
        ],
        if (item.warehouseLabel != null && item.warehouseLabel!.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            shapePdfPersianText(item.warehouseLabel!),
            style: faStyle(fontRegular, 6),
            textAlign: pw.TextAlign.center,
            textDirection: pw.TextDirection.ltr,
          ),
        ],
        if (item.status.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            shapePdfPersianText(item.status),
            style: faStyle(fontRegular, 6),
            textAlign: pw.TextAlign.center,
            textDirection: pw.TextDirection.ltr,
          ),
        ],
      ];

      if (_showLinear && hasScan && scan.isNotEmpty) {
        children.add(pw.SizedBox(height: 4));
        children.add(
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: Barcode.code128(),
              data: scan,
              width: barW,
              height: 34,
              drawText: true,
            ),
          ),
        );
      }

      if (_showQr && hasScan && scan.isNotEmpty) {
        children.add(pw.SizedBox(height: 4));
        children.add(
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: Barcode.qrCode(),
              data: scan,
              width: 72,
              height: 72,
            ),
          ),
        );
      }

      return pw.Container(
        width: cellW,
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.5, color: PdfColors.grey700),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          mainAxisSize: pw.MainAxisSize.min,
          children: children,
        ),
      );
    }

    for (var start = 0; start < items.length; start += slotsPerPage) {
      final end = math.min(start + slotsPerPage, items.length);
      final pageItems = items.sublist(start, end);
      final rowCount = (pageItems.length / _columns).ceil();

      doc.addPage(
        pw.Page(
          pageFormat: format,
          margin: pw.EdgeInsets.all(margin),
          theme: theme,
          // چیدمان ستون‌ها چپ→راست؛ متن فارسی با shapePdfPersianText + ltr رندر می‌شود.
          textDirection: pw.TextDirection.ltr,
          build: (ctx) {
            final rows = <pw.Widget>[];
            for (var r = 0; r < rowCount; r++) {
              final cells = <pw.Widget>[];
              for (var c = 0; c < _columns; c++) {
                final i = r * _columns + c;
                final w = colWidth + 8;
                final child = i < pageItems.length
                    ? pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: labelCard(pageItems[i], colWidth),
                      )
                    : pw.SizedBox(width: w);
                cells.add(
                  pw.SizedBox(
                    width: w,
                    child: child,
                  ),
                );
              }
              rows.add(
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: cells,
                ),
              );
            }
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: rows,
            );
          },
        ),
      );
    }

    return doc.save();
  }

  Future<void> _onSavePdf(BuildContext context) async {
    try {
      final bytes = await _buildPdf(_pageFormat);
      final name = 'product-labels-${DateTime.now().millisecondsSinceEpoch}.pdf';
      await FileSaver.saveBytes(bytes, name);
      if (!context.mounted) return;
      SnackBarHelper.show(context, message: 'فایل PDF ذخیره شد');
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(context, message: 'ذخیره PDF ناموفق: $e');
    }
  }

  Future<void> _onSharePdf(BuildContext context) async {
    try {
      final bytes = await _buildPdf(_pageFormat);
      await Printing.sharePdf(bytes: bytes, filename: 'product-labels.pdf');
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(context, message: 'اشتراک‌گذاری ناموفق: $e');
    }
  }

  Widget _settingsPanel(BuildContext context, {required bool narrow}) {
    final theme = Theme.of(context);
    final chipsCard = Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('محتوای برچسب', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('بارکد خطی'),
                  selected: _showLinear,
                  onSelected: (v) => setState(() => _showLinear = v),
                ),
                FilterChip(
                  label: const Text('QR'),
                  selected: _showQr,
                  onSelected: (v) => setState(() => _showQr = v),
                ),
                FilterChip(
                  label: const Text('نام کالا'),
                  selected: _showProductName,
                  onSelected: (v) => setState(() => _showProductName = v),
                ),
                FilterChip(
                  label: const Text('سریال (متن)'),
                  selected: _showSerialLine,
                  onSelected: (v) => setState(() => _showSerialLine = v),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('صفحه و چیدمان', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            DropdownButtonFormField<_PaperKind>(
              key: ValueKey(_paper),
              initialValue: _paper,
              decoration: const InputDecoration(
                labelText: 'سایز کاغذ',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _PaperKind.values
                  .map(
                    (p) => DropdownMenuItem(value: p, child: Text(p.label)),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _paper = v);
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('افقی (Landscape)'),
              value: _landscape,
              onChanged: (v) => setState(() => _landscape = v),
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: ValueKey(_columns),
                    initialValue: _columns,
                    decoration: const InputDecoration(
                      labelText: 'تعداد ستون',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [1, 2, 3, 4]
                        .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _columns = v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('حاشیه صفحه: ${_marginPt.toStringAsFixed(0)} pt'),
            Slider(
              value: _marginPt,
              min: 12,
              max: 48,
              divisions: 12,
              label: _marginPt.toStringAsFixed(0),
              onChanged: (v) => setState(() => _marginPt = v),
            ),
          ],
        ),
      ),
    );

    if (narrow) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: chipsCard,
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: chipsCard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewKey = ValueKey(
      '${_showLinear}_${_showQr}_${_columns}_${_marginPt.toStringAsFixed(0)}'
      '_${_showProductName}_${_showSerialLine}_${_paper}_${_landscape}_${widget.items.length}',
    );

    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1100,
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.label_outline, color: theme.colorScheme.primary, size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'چاپ برچسب',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${widget.items.length} برچسب · سایز: ${_paper.label} · ${_landscape ? 'افقی' : 'عمودی'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('بستن'),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 760;
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 320, child: _settingsPanel(context, narrow: false)),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: _previewArea(context, previewKey),
                        ),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(
                        flex: 2,
                        child: _settingsPanel(context, narrow: true),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        flex: 3,
                        child: _previewArea(context, previewKey),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Material(
              color: theme.colorScheme.surface,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _onSavePdf(context),
                        icon: const Icon(Icons.save_alt_outlined),
                        label: const Text('ذخیره PDF'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _onSharePdf(context),
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('اشتراک'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewArea(BuildContext context, Key previewKey) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(
                children: [
                  Icon(Icons.visibility_outlined, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'پیش‌نمایش',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        kIsWeb
                            ? 'در وب: پیش‌نمایش با نمایشگر PDF مرورگر (زوم از منوی راست‌کلیک یا Ctrl±)'
                            : 'زوم و پیمایش از نوار پیش‌نمایش',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LabelPdfPreviewEmbed(
                key: previewKey,
                pageFormat: _pageFormat,
                buildPdf: _buildPdf,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
