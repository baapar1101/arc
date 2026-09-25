import 'package:hesabix_ui/theme/glass.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../services/product_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../common/excel_import_dialog_shell.dart';
import 'label_print_job_dialog.dart';

/// چاپ برچسب از فایل اکسل (کد/بارکد + تعداد).
class LabelExcelPrintDialog extends StatefulWidget {
  final int businessId;

  const LabelExcelPrintDialog({super.key, required this.businessId});

  static Future<void> show(BuildContext context, {required int businessId}) {
    return showGlassDialog<void>(
      context: context,
      builder: (ctx) => LabelExcelPrintDialog(businessId: businessId),
    );
  }

  @override
  State<LabelExcelPrintDialog> createState() => _LabelExcelPrintDialogState();
}

class _LabelExcelPrintDialogState extends State<LabelExcelPrintDialog> {
  final _products = ProductService();
  bool _busy = false;
  String? _fileName;
  List<LabelPrintJobRow> _rows = const [];
  List<String> _errors = const [];

  Future<void> _pickAndParse() async {
    final t = AppLocalizations.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls', 'csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      SnackBarHelper.showError(context, message: t.barcodeLabelExcelReadFailed);
      return;
    }
    setState(() {
      _busy = true;
      _fileName = file.name;
      _errors = const [];
      _rows = const [];
    });
    try {
      // Lightweight CSV-first parse; for xlsx ask user to export CSV or use simple line parse of text.
      final text = String.fromCharCodes(bytes);
      final parsed = _parseDelimited(text);
      final rows = <LabelPrintJobRow>[];
      final errs = <String>[];

      for (var i = 0; i < parsed.length; i++) {
        final lineNo = i + 2; // after header
        final map = parsed[i];
        final code = (map['code'] ?? map['کد'] ?? '').trim();
        final barcode = (map['barcode'] ?? map['بارکد'] ?? '').trim();
        final name = (map['name'] ?? map['نام'] ?? '').trim();
        final qty = int.tryParse((map['qty'] ?? map['تعداد'] ?? '1').trim()) ?? 1;
        if (code.isEmpty && barcode.isEmpty) {
          errs.add(t.barcodeLabelExcelRowError(lineNo, 'code/barcode'));
          continue;
        }
        Map<String, dynamic>? product;
        try {
          if (code.isNotEmpty) {
            final items = await _products.searchProducts(
              businessId: widget.businessId,
              searchQuery: code,
              limit: 8,
            );
            for (final m in items) {
              if (m['code']?.toString() == code) {
                product = m;
                break;
              }
            }
          }
        } catch (_) {}

        final rowMap = product ??
            {
              'id': 'excel-$lineNo',
              'name': name.isNotEmpty ? name : (barcode.isNotEmpty ? barcode : code),
              'code': code,
              'general_barcodes': barcode.isNotEmpty ? barcode : code,
            };
        rows.add(
          LabelPrintJobDialog.fromProductMap(
            rowMap,
            barcodeOverride: barcode.isNotEmpty ? barcode : null,
            qty: qty.clamp(1, 9999),
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _errors = errs;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  List<Map<String, String>> _parseDelimited(String text) {
    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return const [];
    final delim = lines.first.contains('\t') ? '\t' : ',';
    final headers = lines.first.split(delim).map((e) => e.trim().replaceAll('"', '').toLowerCase()).toList();
    // normalize FA headers
    final mappedHeaders = headers.map((h) {
      switch (h) {
        case 'کد':
          return 'code';
        case 'بارکد':
          return 'barcode';
        case 'نام':
          return 'name';
        case 'تعداد':
          return 'qty';
        default:
          return h;
      }
    }).toList();
    final out = <Map<String, String>>[];
    for (var i = 1; i < lines.length; i++) {
      final parts = lines[i].split(delim).map((e) => e.trim().replaceAll('"', '')).toList();
      final row = <String, String>{};
      for (var c = 0; c < mappedHeaders.length && c < parts.length; c++) {
        row[mappedHeaders[c]] = parts[c];
      }
      out.add(row);
    }
    return out;
  }

  Future<void> _continue() async {
    if (_rows.isEmpty) return;
    Navigator.pop(context);
    await LabelPrintJobDialog.show(
      context,
      businessId: widget.businessId,
      rows: _rows,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return ExcelImportDialogShell(
      title: t.barcodeLabelExcelPrintTitle,
      onClose: () => Navigator.pop(context),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(
          onPressed: _rows.isEmpty || _busy ? null : _continue,
          child: Text(t.barcodeLabelContinueToPrint),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.barcodeLabelExcelPrintHint),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickAndParse,
            icon: const Icon(Icons.upload_file),
            label: Text(_fileName ?? t.barcodeLabelPickExcel),
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(t.barcodeLabelExcelReady(_rows.length, _rows.fold<int>(0, (s, r) => s + r.qty))),
          ],
          if (_errors.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(t.barcodeLabelExcelErrors, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ..._errors.take(8).map((e) => Text('• $e')),
          ],
        ],
      ),
    );
  }
}
