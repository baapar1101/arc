import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/invoice/product_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/warehouse_combobox_widget.dart';
import 'package:hesabix_ui/widgets/banking/currency_picker_widget.dart';
import 'package:hesabix_ui/services/inventory_transfer_service.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';

class InventoryTransferFormDialog extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;

  const InventoryTransferFormDialog({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<InventoryTransferFormDialog> createState() => _InventoryTransferFormDialogState();
}

class _InventoryTransferFormDialogState extends State<InventoryTransferFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final InventoryTransferService _service = InventoryTransferService();

  DateTime _documentDate = DateTime.now();
  int? _currencyId;
  String? _description;

  final List<_TransferRow> _rows = <_TransferRow>[];

  void _addRow() {
    setState(() => _rows.add(_TransferRow()));
  }

  void _removeRow(int index) {
    setState(() => _rows.removeAt(index));
  }

  Future<void> _submit() async {
    if (_currencyId == null) {
      _showError('انتخاب ارز الزامی است');
      return;
    }
    if (_rows.isEmpty) {
      _showError('حداقل یک ردیف انتقال اضافه کنید');
      return;
    }
    for (int i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      if (r.productId == null) { _showError('محصول ردیف ${i + 1} انتخاب نشده است'); return; }
      if ((r.quantity ?? 0) <= 0) { _showError('تعداد ردیف ${i + 1} باید > 0 باشد'); return; }
      if (r.sourceWarehouseId == null || r.destinationWarehouseId == null) { _showError('انبار مبدا و مقصد در ردیف ${i + 1} الزامی است'); return; }
      if (r.sourceWarehouseId == r.destinationWarehouseId) { _showError('انبار مبدا و مقصد در ردیف ${i + 1} نمی‌تواند یکسان باشد'); return; }
    }

    final payload = <String, dynamic>{
      'document_date': _documentDate.toIso8601String().substring(0, 10),
      'currency_id': _currencyId,
      if ((_description ?? '').isNotEmpty) 'description': _description,
      'lines': _rows.map((r) => {
        'product_id': r.productId,
        'quantity': r.quantity,
        'source_warehouse_id': r.sourceWarehouseId,
        'destination_warehouse_id': r.destinationWarehouseId,
        if ((r.description ?? '').isNotEmpty) 'description': r.description,
      }).toList(),
    };

    try {
      await _service.create(businessId: widget.businessId, payload: payload);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      _showError('خطا در ثبت انتقال: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('انتقال موجودی بین انبارها'),
      content: SizedBox(
        width: 900,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DateInputField(
                      value: _documentDate,
                      labelText: 'تاریخ سند *',
                      calendarController: widget.calendarController,
                      onChanged: (d) => setState(() => _documentDate = d ?? DateTime.now()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CurrencyPickerWidget(
                      businessId: widget.businessId,
                      selectedCurrencyId: _currencyId,
                      onChanged: (cid) => setState(() => _currencyId = cid),
                      label: 'ارز *',
                      hintText: 'انتخاب ارز',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'شرح',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => _description = v.trim(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton.icon(onPressed: _addRow, icon: const Icon(Icons.add), label: const Text('افزودن ردیف')),
                ],
              ),
              const SizedBox(height: 8),
              _rows.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text('ردیفی افزوده نشده است'),
                    )
                  : Column(
                      children: _rows.asMap().entries.map((e) => _buildRow(context, e.key, e.value)).toList(),
                    ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('انصراف')),
        FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.save), label: const Text('ثبت انتقال')),
      ],
    );
  }

  Widget _buildRow(BuildContext context, int index, _TransferRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 260,
            height: 36,
            child: ProductComboboxWidget(
              businessId: widget.businessId,
              selectedProduct: row.productId != null ? {'id': row.productId, 'code': row.productCode, 'name': row.productName} : null,
              onChanged: (p) => setState(() {
                if (p == null) {
                  row.productId = null;
                  row.productCode = null;
                  row.productName = null;
                } else {
                  row.productId = int.tryParse('${p['id']}');
                  row.productCode = p['code']?.toString();
                  row.productName = p['name']?.toString();
                }
              }),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            height: 36,
            child: TextFormField(
              initialValue: (row.quantity ?? 0).toString(),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                EnglishDigitsFormatter(),
                FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
              ],
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'تعداد'),
              onChanged: (v) => row.quantity = num.tryParse(v.replaceAll(',', '')) ?? 0,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 220,
            height: 36,
            child: WarehouseComboboxWidget(
              businessId: widget.businessId,
              selectedWarehouseId: row.sourceWarehouseId,
              onChanged: (wid) => setState(() => row.sourceWarehouseId = wid),
              label: 'انبار مبدا',
              hintText: 'انتخاب انبار مبدا',
              isRequired: true,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 220,
            height: 36,
            child: WarehouseComboboxWidget(
              businessId: widget.businessId,
              selectedWarehouseId: row.destinationWarehouseId,
              onChanged: (wid) => setState(() => row.destinationWarehouseId = wid),
              label: 'انبار مقصد',
              hintText: 'انتخاب انبار مقصد',
              isRequired: true,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 220,
            height: 36,
            child: TextFormField(
              initialValue: row.description ?? '',
              onChanged: (v) => row.description = v.trim(),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                hintText: 'شرح ردیف',
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(onPressed: () => _removeRow(index), icon: const Icon(Icons.delete, color: Colors.red)),
        ],
      ),
    );
  }
}

class _TransferRow {
  int? productId;
  String? productCode;
  String? productName;
  num? quantity = 1;
  int? sourceWarehouseId;
  int? destinationWarehouseId;
  String? description;
}


