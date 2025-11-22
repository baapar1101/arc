import 'package:flutter/material.dart';
import '../../services/warehouse_service.dart';
import '../../widgets/invoice/product_combobox_widget.dart';
import '../../widgets/invoice/warehouse_combobox_widget.dart';
import '../../utils/number_normalizer.dart' show parseFormattedNumber;
import '../../utils/snackbar_helper.dart';

class WarehouseDocumentFormDialog extends StatefulWidget {
  final int businessId;
  final VoidCallback? onSuccess;
  final String? initialDocType;
  final DateTime? initialDocumentDate;
  final List<Map<String, dynamic>>? initialLines;
  final int? sourceInvoiceId;
  final String? sourceInvoiceCode;
  final String? sourceInvoiceType;
  final bool lockDocType;

  const WarehouseDocumentFormDialog({
    super.key,
    required this.businessId,
    this.onSuccess,
    this.initialDocType,
    this.initialDocumentDate,
    this.initialLines,
    this.sourceInvoiceId,
    this.sourceInvoiceCode,
    this.sourceInvoiceType,
    this.lockDocType = false,
  });

  @override
  State<WarehouseDocumentFormDialog> createState() => _WarehouseDocumentFormDialogState();
}

class _WarehouseDocumentFormDialogState extends State<WarehouseDocumentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _svc = WarehouseService();
  
  String? _docType;
  DateTime? _documentDate;
  int? _warehouseIdFrom;
  int? _warehouseIdTo;
  final List<Map<String, dynamic>> _lines = [];
  bool _saving = false;
  bool get _isFromInvoice => widget.sourceInvoiceId != null;
  bool get _isDocTypeLocked => widget.lockDocType || _isFromInvoice;

  String _movementForDocType(String? docType) {
    if (docType == 'issue' || docType == 'production_out') {
      return 'out';
    }
    return 'in';
  }

  void _syncLineMovementsForDocType() {
    if (_docType == 'adjustment' || _docType == 'transfer') return;
    final movement = _movementForDocType(_docType);
    for (var i = 0; i < _lines.length; i++) {
      _lines[i] = {..._lines[i], 'movement': movement};
    }
  }

  int? _defaultWarehouseForMovement(String? movement) {
    if (movement == 'out') return _warehouseIdFrom;
    if (movement == 'in') return _warehouseIdTo;
    return null;
  }

  List<Map<String, dynamic>> _buildLinePayloads() {
    return _lines.map((line) {
      final movement = (line['movement'] as String?) ?? _movementForDocType(_docType);
      final lineWarehouse = line['warehouse_id'] ?? _defaultWarehouseForMovement(movement);
      final extra = Map<String, dynamic>.from(line['extra_info'] ?? const {});
      if (!extra.containsKey('movement')) {
        extra['movement'] = movement;
      }
      return {
        'product_id': line['product_id'],
        'warehouse_id': lineWarehouse,
        'movement': movement,
        'quantity': line['quantity'],
        'extra_info': extra,
        if (line.containsKey('cost_price')) 'cost_price': line['cost_price'],
      };
    }).toList();
  }

  Widget _buildSourceBanner() {
    final theme = Theme.of(context);
    final invoiceLabel = widget.sourceInvoiceCode ?? '#${widget.sourceInvoiceId}';
    final typeLabel = widget.sourceInvoiceType ?? '';
    return Card(
      color: theme.colorScheme.primaryContainer.withOpacity(0.4),
      elevation: 0,
      child: ListTile(
        leading: Icon(Icons.receipt_long, color: theme.colorScheme.primary),
        title: Text('ایجاد حواله برای فاکتور $invoiceLabel'),
        subtitle: Text(
          typeLabel.isNotEmpty ? 'نوع فاکتور: $typeLabel' : 'شناسه: ${widget.sourceInvoiceId}',
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _docType = widget.initialDocType;
    _documentDate = widget.initialDocumentDate ?? DateTime.now();
    if (widget.initialLines != null && widget.initialLines!.isNotEmpty) {
      for (final raw in widget.initialLines!) {
        final normalized = Map<String, dynamic>.from(raw);
        normalized['extra_info'] = Map<String, dynamic>.from(normalized['extra_info'] ?? const {});
        normalized['movement'] ??= _movementForDocType(_docType);
        normalized['cost_price'] = normalized['cost_price'] ?? 0.0;
        _lines.add(normalized);
      }
    }
  }


  void _addLine() {
    setState(() {
      _lines.add({
        'product_id': null,
        'warehouse_id': null,
        'movement': _movementForDocType(_docType),
        'quantity': 0.0,
        'cost_price': 0.0,
        'extra_info': <String, dynamic>{},
      });
    });
  }

  void _removeLine(int index) {
    setState(() {
      _lines.removeAt(index);
    });
  }

  void _updateLine(int index, Map<String, dynamic> updates) {
    setState(() {
      _lines[index] = {..._lines[index], ...updates};
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_docType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لطفاً نوع حواله را انتخاب کنید')),
      );
      return;
    }
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لطفاً حداقل یک خط اضافه کنید')),
      );
      return;
    }

    // اعتبارسنجی خطوط
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      if (line['product_id'] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خط ${i + 1}: لطفاً محصول را انتخاب کنید')),
        );
        return;
      }
      if ((line['quantity'] as num?) == null || (line['quantity'] as num) <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خط ${i + 1}: تعداد باید مثبت باشد')),
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      if (_isFromInvoice) {
        await _saveFromInvoice();
      } else {
        await _saveManual();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _saveManual() async {
    final payload = {
      'doc_type': _docType,
      'document_date': _documentDate?.toIso8601String().split('T')[0],
      'warehouse_id_from': _warehouseIdFrom,
      'warehouse_id_to': _warehouseIdTo,
      'lines': _buildLinePayloads(),
    };

    await _svc.createManual(businessId: widget.businessId, payload: payload);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('حواله ایجاد شد')),
    );
    Navigator.of(context).pop();
    widget.onSuccess?.call();
  }

  Future<void> _saveFromInvoice() async {
    final payload = {
      'doc_type': _docType,
      'lines': _buildLinePayloads(),
    };

    await _svc.createFromInvoice(
      businessId: widget.businessId,
      invoiceId: widget.sourceInvoiceId!,
      body: payload,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('حواله از فاکتور ثبت شد')),
    );
    Navigator.of(context).pop();
    widget.onSuccess?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ایجاد حواله دستی'),
      content: SizedBox(
        width: MediaQuery.of(context).size.width > 800 ? 700 : 600,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isFromInvoice) ...[
                  _buildSourceBanner(),
                  const SizedBox(height: 16),
                ],
                // نوع حواله
                DropdownButtonFormField<String>(
                  value: _docType,
                  decoration: const InputDecoration(
                    labelText: 'نوع حواله *',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'receipt', child: Text('حواله ورود')),
                    DropdownMenuItem(value: 'issue', child: Text('حواله خروج')),
                    DropdownMenuItem(value: 'transfer', child: Text('انتقال بین انبارها')),
                    DropdownMenuItem(value: 'adjustment', child: Text('تعدیل موجودی')),
                    DropdownMenuItem(value: 'production_in', child: Text('ورود تولید')),
                    DropdownMenuItem(value: 'production_out', child: Text('خروج تولید')),
                  ],
                  onChanged: _isDocTypeLocked
                      ? null
                      : (value) {
                          setState(() {
                            _docType = value;
                            _syncLineMovementsForDocType();
                          });
                        },
                  validator: (value) => value == null ? 'لطفاً نوع حواله را انتخاب کنید' : null,
                ),
                const SizedBox(height: 16),
                // تاریخ
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'تاریخ *',
                    border: OutlineInputBorder(),
                  ),
                  readOnly: true,
                  controller: TextEditingController(
                    text: _documentDate != null
                        ? '${_documentDate!.year}-${_documentDate!.month.toString().padLeft(2, '0')}-${_documentDate!.day.toString().padLeft(2, '0')}'
                        : '',
                  ),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _documentDate ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (date != null) {
                      setState(() => _documentDate = date);
                    }
                  },
                  validator: (value) => _documentDate == null ? 'لطفاً تاریخ را انتخاب کنید' : null,
                ),
                const SizedBox(height: 16),
                // انبارها بر اساس نوع حواله
                if (_docType == 'transfer') ...[
                  WarehouseComboboxWidget(
                    businessId: widget.businessId,
                    selectedWarehouseId: _warehouseIdFrom,
                    onChanged: (id) => setState(() => _warehouseIdFrom = id),
                    label: 'انبار مبدا *',
                  ),
                  const SizedBox(height: 16),
                  WarehouseComboboxWidget(
                    businessId: widget.businessId,
                    selectedWarehouseId: _warehouseIdTo,
                    onChanged: (id) => setState(() => _warehouseIdTo = id),
                    label: 'انبار مقصد *',
                  ),
                ] else if (_docType == 'issue' || _docType == 'production_out') ...[
                  WarehouseComboboxWidget(
                    businessId: widget.businessId,
                    selectedWarehouseId: _warehouseIdFrom,
                    onChanged: (id) => setState(() => _warehouseIdFrom = id),
                    label: 'انبار *',
                  ),
                ] else if (_docType == 'receipt' || _docType == 'production_in') ...[
                  WarehouseComboboxWidget(
                    businessId: widget.businessId,
                    selectedWarehouseId: _warehouseIdTo,
                    onChanged: (id) => setState(() => _warehouseIdTo = id),
                    label: 'انبار *',
                  ),
                ],
                const SizedBox(height: 16),
                // خطوط
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'خطوط حواله',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: _addLine,
                      tooltip: 'افزودن خط',
                    ),
                  ],
                ),
                if (_lines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: Text('هیچ خطی وجود ندارد')),
                  )
                else
                  ...List.generate(_lines.length, (index) {
                    final line = _lines[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: ProductComboboxWidget(
                                    businessId: widget.businessId,
                                    selectedProduct: line['product_id'] != null
                                        ? {'id': line['product_id']}
                                        : null,
                                    onChanged: (product) {
                                      _updateLine(index, {
                                        'product_id': product?['id'],
                                      });
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _removeLine(index),
                                  color: Colors.red,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (_docType == 'adjustment')
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      value: line['movement'] as String?,
                                      decoration: const InputDecoration(
                                        labelText: 'نوع حرکت',
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      items: const [
                                        DropdownMenuItem(value: 'in', child: Text('ورود')),
                                        DropdownMenuItem(value: 'out', child: Text('خروج')),
                                      ],
                                      onChanged: (value) {
                                        if (value != null) {
                                          _updateLine(index, {'movement': value});
                                        }
                                      },
                                    ),
                                  ),
                                if (_docType == 'adjustment') const SizedBox(width: 8),
                                Expanded(
                                  child: WarehouseComboboxWidget(
                                    businessId: widget.businessId,
                                    selectedWarehouseId: line['warehouse_id'] as int?,
                                    onChanged: (id) => _updateLine(index, {'warehouse_id': id}),
                                    label: 'انبار',
                                    isRequired: true,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    decoration: const InputDecoration(
                                      labelText: 'تعداد *',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    initialValue: line['quantity'].toString(),
                                    onChanged: (value) {
                                      final qty = parseFormattedNumber(value) ?? 0.0;
                                      _updateLine(index, {'quantity': qty});
                                    },
                                    validator: (value) {
                                      final qty = parseFormattedNumber(value) ?? 0.0;
                                      return qty <= 0 ? 'تعداد باید مثبت باشد' : null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    decoration: const InputDecoration(
                                      labelText: 'قیمت واحد',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    initialValue: line['cost_price'] > 0 ? line['cost_price'].toString() : '',
                                    onChanged: (value) {
                                      final price = parseFormattedNumber(value) ?? 0.0;
                                      _updateLine(index, {'cost_price': price});
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('ذخیره'),
        ),
      ],
    );
  }
}

