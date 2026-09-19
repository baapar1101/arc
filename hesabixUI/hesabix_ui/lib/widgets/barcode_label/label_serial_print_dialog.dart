import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../utils/snackbar_helper.dart';
import 'label_print_job_dialog.dart';

/// چاپ سریالی بارکد با prefix/start/end/pad.
class LabelSerialPrintDialog extends StatefulWidget {
  final int businessId;

  const LabelSerialPrintDialog({super.key, required this.businessId});

  static Future<void> show(BuildContext context, {required int businessId}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => LabelSerialPrintDialog(businessId: businessId),
    );
  }

  @override
  State<LabelSerialPrintDialog> createState() => _LabelSerialPrintDialogState();
}

class _LabelSerialPrintDialogState extends State<LabelSerialPrintDialog> {
  final _prefixCtrl = TextEditingController();
  final _suffixCtrl = TextEditingController();
  final _startCtrl = TextEditingController(text: '1');
  final _endCtrl = TextEditingController(text: '10');
  final _padCtrl = TextEditingController(text: '4');
  final _qtyCtrl = TextEditingController(text: '1');

  @override
  void dispose() {
    _prefixCtrl.dispose();
    _suffixCtrl.dispose();
    _startCtrl.dispose();
    _endCtrl.dispose();
    _padCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  List<String> _previewValues({int limit = 10}) {
    final start = int.tryParse(_startCtrl.text.trim()) ?? 1;
    final end = int.tryParse(_endCtrl.text.trim()) ?? start;
    final pad = (int.tryParse(_padCtrl.text.trim()) ?? 0).clamp(0, 12);
    final prefix = _prefixCtrl.text;
    final suffix = _suffixCtrl.text;
    final out = <String>[];
    final lo = start <= end ? start : end;
    final hi = start <= end ? end : start;
    for (var n = lo; n <= hi && out.length < limit; n++) {
      final body = pad > 0 ? n.toString().padLeft(pad, '0') : '$n';
      out.add('$prefix$body$suffix');
    }
    return out;
  }

  int _totalCount() {
    final start = int.tryParse(_startCtrl.text.trim()) ?? 1;
    final end = int.tryParse(_endCtrl.text.trim()) ?? start;
    return (end - start).abs() + 1;
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    final start = int.tryParse(_startCtrl.text.trim());
    final end = int.tryParse(_endCtrl.text.trim());
    final pad = int.tryParse(_padCtrl.text.trim()) ?? 0;
    final qtyEach = (int.tryParse(_qtyCtrl.text.trim()) ?? 1).clamp(1, 999);
    if (start == null || end == null) {
      SnackBarHelper.showError(context, message: t.barcodeLabelSerialInvalidRange);
      return;
    }
    final count = (end - start).abs() + 1;
    final total = count * qtyEach;
    if (total > 10000) {
      SnackBarHelper.showError(context, message: t.barcodeLabelSerialTooMany);
      return;
    }
    final lo = start <= end ? start : end;
    final hi = start <= end ? end : start;
    final rows = <LabelPrintJobRow>[];
    for (var n = lo; n <= hi; n++) {
      final body = pad > 0 ? n.toString().padLeft(pad, '0') : '$n';
      final value = '${_prefixCtrl.text}$body${_suffixCtrl.text}';
      rows.add(
        LabelPrintJobRow(
          key: 'serial-$value',
          title: value,
          subtitle: t.barcodeLabelSerialItem,
          qty: qtyEach,
          context: {
            'product': {
              'name': value,
              'code': value,
              'general_barcode': value,
              'price': '',
              'sale_price': '',
            },
            'instance': {'serial': value, 'barcode': value},
            'warehouse': {'name': ''},
            'business': {'name': ''},
            'print': {'counter': 1, 'copy_index': 1},
          },
        ),
      );
    }
    if (!mounted) return;
    Navigator.pop(context);
    await LabelPrintJobDialog.show(
      context,
      businessId: widget.businessId,
      rows: rows,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final preview = _previewValues();
    return AlertDialog(
      title: Text(t.barcodeLabelSerialPrintTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.barcodeLabelSerialPrintHint),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: TextField(controller: _prefixCtrl, decoration: InputDecoration(labelText: t.barcodeLabelSerialPrefix), onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _suffixCtrl, decoration: InputDecoration(labelText: t.barcodeLabelSerialSuffix), onChanged: (_) => setState(() {}))),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: TextField(controller: _startCtrl, decoration: InputDecoration(labelText: t.barcodeLabelSerialStart), keyboardType: TextInputType.number, onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _endCtrl, decoration: InputDecoration(labelText: t.barcodeLabelSerialEnd), keyboardType: TextInputType.number, onChanged: (_) => setState(() {}))),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: TextField(controller: _padCtrl, decoration: InputDecoration(labelText: t.barcodeLabelSerialPad), keyboardType: TextInputType.number, onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _qtyCtrl, decoration: InputDecoration(labelText: t.barcodeLabelSerialQtyEach), keyboardType: TextInputType.number)),
                ],
              ),
              const SizedBox(height: 12),
              Text(t.barcodeLabelSerialPreview(_totalCount())),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final v in preview) Chip(label: Text(v, style: const TextStyle(fontFamily: 'monospace'))),
                  if (_totalCount() > preview.length) Chip(label: Text('…')),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: _submit, child: Text(t.barcodeLabelContinueToPrint)),
      ],
    );
  }
}
