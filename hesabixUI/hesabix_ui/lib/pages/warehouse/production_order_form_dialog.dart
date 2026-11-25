import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart' show HesabixDateUtils;
import '../../models/bom_models.dart';
import '../../models/production_order_models.dart';
import '../../services/bom_service.dart';
import '../../services/production_order_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/invoice/product_combobox_widget.dart';
import '../../widgets/invoice/warehouse_combobox_widget.dart';
import '../../widgets/jalali_date_picker.dart';

class ProductionOrderFormDialog extends StatefulWidget {
  final int businessId;
  final ProductionOrder? order;

  const ProductionOrderFormDialog({
    super.key,
    required this.businessId,
    this.order,
  });

  @override
  State<ProductionOrderFormDialog> createState() =>
      _ProductionOrderFormDialogState();
}

class _ProductionOrderFormDialogState extends State<ProductionOrderFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _svc = ProductionOrderService();
  final _bomSvc = BomService();
  final _qtyCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  CalendarController? get _calendar => ApiClient.getCalendarController();

  Map<String, dynamic>? _selectedProduct;
  ProductBOM? _selectedBom;
  List<ProductBOM> _boms = const [];
  int? _warehouseId;
  int? _outputWarehouseId;
  DateTime? _plannedStart;
  DateTime? _dueDate;
  int _priority = 3;
  bool _loadingBoms = false;
  bool _saving = false;

  bool get _isEdit => widget.order != null;

  @override
  void initState() {
    super.initState();
    final order = widget.order;
    if (order != null) {
      _qtyCtrl.text = order.plannedQuantity.toString();
      _notesCtrl.text = order.notes ?? '';
      _warehouseId = order.warehouseId;
      _outputWarehouseId = order.outputWarehouseId;
      _priority = order.priority;
      _plannedStart = _parseDate(order.plannedStartDate);
      _dueDate = _parseDate(order.dueDate);
      _selectedProduct = {
        'id': order.productId,
        'name': order.productName,
        'code': order.productCode,
      };
      _loadBoms(selectBomId: order.bomId);
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw.length >= 10 ? raw.substring(0, 10) : raw);
  }

  String? _iso(DateTime? d) =>
      d == null ? null : d.toIso8601String().split('T').first;

  Future<void> _loadBoms({int? selectBomId}) async {
    final productId = (_selectedProduct?['id'] as num?)?.toInt();
    if (productId == null) return;
    setState(() => _loadingBoms = true);
    try {
      final all = await _bomSvc.list(
        businessId: widget.businessId,
        productId: productId,
      );
      final approved = all
          .where((b) => b.status.toLowerCase() == 'approved')
          .toList();
      if (!mounted) return;
      setState(() {
        _boms = approved;
        if (selectBomId != null) {
          _selectedBom = approved.cast<ProductBOM?>().firstWhere(
            (b) => b?.id == selectBomId,
            orElse: () => approved.isNotEmpty ? approved.first : null,
          );
        } else {
          _selectedBom = approved.cast<ProductBOM?>().firstWhere(
            (b) => b?.isDefault == true,
            orElse: () => approved.isNotEmpty ? approved.first : null,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    } finally {
      if (mounted) setState(() => _loadingBoms = false);
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _plannedStart : _dueDate;
    final picked = await showAdaptiveDatePicker(
      context: context,
      calendarController: _calendar,
      initialDate: current ?? DateTime.now(),
      helpText: isStart ? 'تاریخ برنامه‌ریزی شروع' : 'موعد تحویل',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _plannedStart = picked;
      } else {
        _dueDate = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final productId = (_selectedProduct?['id'] as num?)?.toInt();
    if (productId == null) {
      SnackBarHelper.showError(context, message: 'کالای تولیدی را انتخاب کنید');
      return;
    }
    if (_selectedBom?.id == null && !_isEdit) {
      SnackBarHelper.showError(
        context,
        message: 'فرمول تأییدشده را انتخاب کنید',
      );
      return;
    }
    if (_warehouseId == null || _outputWarehouseId == null) {
      SnackBarHelper.showError(
        context,
        message: 'انبار مصرف و انبار محصول الزامی است',
      );
      return;
    }
    final qty = double.tryParse(_qtyCtrl.text.trim().replaceAll(',', ''));
    if (qty == null || qty <= 0) {
      SnackBarHelper.showError(
        context,
        message: 'مقدار تولید باید بزرگ‌تر از صفر باشد',
      );
      return;
    }
    if (_plannedStart != null &&
        _dueDate != null &&
        _dueDate!.isBefore(_plannedStart!)) {
      SnackBarHelper.showError(
        context,
        message: 'موعد نمی‌تواند قبل از تاریخ شروع باشد',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await _svc.update(
          businessId: widget.businessId,
          orderId: widget.order!.id,
          payload: <String, dynamic>{
            'version': widget.order!.version,
            'quantity': qty,
            'warehouse_id': _warehouseId,
            'output_warehouse_id': _outputWarehouseId,
            'planned_start_date': _iso(_plannedStart),
            'due_date': _iso(_dueDate),
            'priority': _priority,
            'notes': _notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim(),
          },
        );
      } else {
        await _svc.create(
          businessId: widget.businessId,
          payload: <String, dynamic>{
            'product_id': productId,
            'bom_id': _selectedBom!.id,
            'quantity': qty,
            'warehouse_id': _warehouseId,
            'output_warehouse_id': _outputWarehouseId,
            'planned_start_date': _iso(_plannedStart),
            'due_date': _iso(_dueDate),
            'priority': _priority,
            'notes': _notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim(),
          },
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isJalali = _calendar?.isJalali ?? true;
    return AlertDialog(
      title: Text(_isEdit ? 'ویرایش سفارش تولید' : 'سفارش تولید جدید'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ProductComboboxWidget(
                  businessId: widget.businessId,
                  selectedProduct: _selectedProduct,
                  productsOnly: true,
                  onChanged: _isEdit
                      ? (_) {}
                      : (product) {
                          setState(() {
                            _selectedProduct = product;
                            _selectedBom = null;
                            _boms = const [];
                          });
                          if (product != null) _loadBoms();
                        },
                  hintText: 'کالای تولیدی',
                ),
                const SizedBox(height: 12),
                if (_loadingBoms)
                  const LinearProgressIndicator()
                else if (!_isEdit)
                  DropdownButtonFormField<int>(
                    value: _selectedBom?.id,
                    decoration: const InputDecoration(
                      labelText: 'فرمول تأییدشده',
                      border: OutlineInputBorder(),
                    ),
                    items: _boms
                        .where((b) => b.id != null)
                        .map(
                          (b) => DropdownMenuItem(
                            value: b.id,
                            child: Text('${b.name} (v${b.version})'),
                          ),
                        )
                        .toList(),
                    onChanged: (id) {
                      setState(() {
                        _selectedBom = _boms.cast<ProductBOM?>().firstWhere(
                          (b) => b?.id == id,
                          orElse: () => null,
                        );
                      });
                    },
                    validator: (v) => v == null ? 'فرمول الزامی است' : null,
                  )
                else
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'فرمول تولید',
                      border: OutlineInputBorder(),
                    ),
                    child: Text('BOM #${widget.order!.bomId}'),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _qtyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'مقدار برنامه‌ریزی‌شده',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) {
                    final n = double.tryParse((v ?? '').replaceAll(',', ''));
                    if (n == null || n <= 0) return 'مقدار نامعتبر';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                WarehouseComboboxWidget(
                  businessId: widget.businessId,
                  selectedWarehouseId: _warehouseId,
                  label: 'انبار مصرف مواد',
                  isRequired: true,
                  selectDefaultWhenUnset: !_isEdit,
                  onChanged: (id) => setState(() => _warehouseId = id),
                ),
                const SizedBox(height: 12),
                WarehouseComboboxWidget(
                  businessId: widget.businessId,
                  selectedWarehouseId: _outputWarehouseId,
                  label: 'انبار دریافت محصول',
                  isRequired: true,
                  selectDefaultWhenUnset: !_isEdit,
                  onChanged: (id) => setState(() => _outputWarehouseId = id),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(isStart: true),
                        icon: const Icon(Icons.event),
                        label: Text(
                          _plannedStart == null
                              ? 'تاریخ شروع'
                              : HesabixDateUtils.formatApiDateForDisplay(
                                  _iso(_plannedStart),
                                  isJalali,
                                  fallback: _iso(_plannedStart) ?? '',
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(isStart: false),
                        icon: const Icon(Icons.event_available),
                        label: Text(
                          _dueDate == null
                              ? 'موعد'
                              : HesabixDateUtils.formatApiDateForDisplay(
                                  _iso(_dueDate),
                                  isJalali,
                                  fallback: _iso(_dueDate) ?? '',
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _priority,
                  decoration: const InputDecoration(
                    labelText: 'اولویت (۱ بالاترین)',
                    border: OutlineInputBorder(),
                  ),
                  items: List.generate(
                    5,
                    (i) =>
                        DropdownMenuItem(value: i + 1, child: Text('${i + 1}')),
                  ),
                  onChanged: (v) => setState(() => _priority = v ?? 3),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'یادداشت',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (!_isEdit) ...[
                  const SizedBox(height: 12),
                  Text(
                    'با ایجاد سفارش، مواد و خروجی‌ها از BOM تأییدشده به‌صورت چندسطحی snapshot می‌شوند.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEdit ? 'ذخیره' : 'ایجاد'),
        ),
      ],
    );
  }
}
