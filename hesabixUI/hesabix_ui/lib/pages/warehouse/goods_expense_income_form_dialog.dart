import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../models/account_model.dart';
import '../../models/person_model.dart';
import '../../services/goods_expense_income_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;
import '../../utils/snackbar_helper.dart';
import '../../widgets/date_input_field.dart';
import '../../widgets/invoice/account_combobox_widget.dart';
import '../../widgets/invoice/person_combobox_widget.dart';
import '../../widgets/invoice/product_combobox_widget.dart';
import '../../widgets/invoice/warehouse_combobox_widget.dart';
import '../../widgets/invoice/invoice_line_lot_picker_dialog.dart';
import '../../widgets/invoice/unique_product_instance_selector_dialog.dart';
import 'goods_expense_income_list_page.dart' show docKindLabel, geiStatusLabel;
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

const String _kSection = 'goods_expense_income';

class _LineVm {
  Map<String, dynamic>? product;
  int? warehouseId;
  List<Map<String, dynamic>> lotAllocations;
  List<int> selectedInstanceIds;
  DateTime? manufacturingDate;
  DateTime? expiryDate;
  final TextEditingController qtyCtrl;
  final TextEditingController unitCostCtrl;
  final TextEditingController descCtrl;

  _LineVm({
    this.product,
    this.warehouseId,
    List<Map<String, dynamic>>? lotAllocations,
    List<int>? selectedInstanceIds,
    this.manufacturingDate,
    this.expiryDate,
    String qty = '1',
    String unitCost = '0',
    String desc = '',
  })  : lotAllocations = lotAllocations ?? <Map<String, dynamic>>[],
        selectedInstanceIds = selectedInstanceIds ?? <int>[],
        qtyCtrl = TextEditingController(text: qty),
        unitCostCtrl = TextEditingController(text: unitCost),
        descCtrl = TextEditingController(text: desc);

  void dispose() {
    qtyCtrl.dispose();
    unitCostCtrl.dispose();
    descCtrl.dispose();
  }

  double get quantity {
    final raw = qtyCtrl.text.replaceAll(',', '').replaceAll('٬', '').trim();
    return double.tryParse(raw) ?? 0;
  }

  double get unitCost {
    final raw = unitCostCtrl.text.replaceAll(',', '').replaceAll('٬', '').trim();
    return double.tryParse(raw) ?? 0;
  }

  double get amount => quantity * unitCost;
}

class GoodsExpenseIncomeFormDialog extends StatefulWidget {
  final int businessId;
  final int? documentId;
  final String? initialDocKind;
  final CalendarController? calendarController;
  final Map<String, dynamic> settings;

  const GoodsExpenseIncomeFormDialog({
    super.key,
    required this.businessId,
    this.documentId,
    this.initialDocKind,
    this.calendarController,
    this.settings = const {},
  });

  @override
  State<GoodsExpenseIncomeFormDialog> createState() => _GoodsExpenseIncomeFormDialogState();
}

class _GoodsExpenseIncomeFormDialogState extends State<GoodsExpenseIncomeFormDialog> {
  final _svc = GoodsExpenseIncomeService();
  final _descCtrl = TextEditingController();
  AuthStore? get _auth => ApiClient.getAuthStore();

  bool _loading = true;
  bool _saving = false;
  late CalendarController _calendar;
  String _docKind = 'goods_expense';
  String _status = 'draft_ops';
  String? _code;
  DateTime _documentDate = DateTime.now();
  Person? _person;
  Account? _effectAccount;
  final List<_LineVm> _lines = <_LineVm>[];
  Map<String, dynamic> _settings = <String, dynamic>{};
  Map<String, dynamic>? _loadedDoc;

  bool get _isEdit => widget.documentId != null;
  bool get _isTwoStep => (_settings['workflow_mode']?.toString() ?? 'simple') == 'two_step';
  bool get _allowManualCost => _settings['allow_manual_unit_cost'] == true;
  bool get _requirePerson => _settings['require_person'] == true;
  bool get _autoPostSimple => _settings['auto_post_in_simple_mode'] != false;

  bool _can(String action) => _auth?.hasBusinessPermission(_kSection, action) ?? false;

  bool get _canShowAccount {
    if (_can('allocate')) return true;
    if (!_isTwoStep) return true;
    return _status == 'draft_accounting' || _status == 'pending_accounting' || _status == 'posted';
  }

  bool get _accountEditable {
    if (!_can('allocate') && _isTwoStep) return false;
    return _status == 'draft_ops' ||
        _status == 'pending_accounting' ||
        _status == 'draft_accounting';
  }

  bool get _opsEditable {
    if (_status == 'posted' || _status == 'cancelled') return false;
    if (_isTwoStep && !_can('allocate') && _status != 'draft_ops') return false;
    return _can('edit') || (_can('add') && !_isEdit);
  }

  bool get _unitCostEditable =>
      _opsEditable && _allowManualCost && _can('change_unit_cost');

  @override
  void initState() {
    super.initState();
    _settings = Map<String, dynamic>.from(widget.settings);
    _docKind = widget.initialDocKind ?? 'goods_expense';
    _lines.add(_LineVm());
    _bootstrap();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    for (final ln in _lines) {
      ln.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      _calendar = widget.calendarController ??
          ApiClient.getCalendarController() ??
          await CalendarController.load();
      if (_settings.isEmpty) {
        _settings = await _svc.getSettings(businessId: widget.businessId);
      }
      if (_isEdit) {
        final doc = await _svc.get(
          businessId: widget.businessId,
          documentId: widget.documentId!,
        );
        _applyDoc(doc);
      } else {
        _applyDefaultAccountCode();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: 'خطا در بارگذاری: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyDefaultAccountCode() {
    final code = _docKind == 'goods_income'
        ? (_settings['default_income_account_code']?.toString() ?? '60103')
        : (_settings['default_expense_account_code']?.toString() ?? '70407');
    _effectAccount = Account(
      id: null,
      name: code,
      code: code,
      accountType: 'accounting_document',
    );
  }

  void _applyDoc(Map<String, dynamic> doc) {
    _loadedDoc = doc;
    _docKind = doc['doc_kind']?.toString() ?? _docKind;
    _status = doc['status']?.toString() ?? _status;
    _code = doc['code']?.toString();
    _descCtrl.text = doc['description']?.toString() ?? '';
    final dateStr = doc['document_date']?.toString();
    if (dateStr != null && dateStr.isNotEmpty) {
      _documentDate = DateTime.tryParse(dateStr) ?? _documentDate;
    }
    final person = doc['person'];
    if (person is Map && person['id'] != null) {
      final now = DateTime.now();
      _person = Person(
        id: (person['id'] as num).toInt(),
        businessId: widget.businessId,
        aliasName: person['name']?.toString() ?? '',
        personTypes: const [],
        createdAt: now,
        updatedAt: now,
      );
    }
    final acc = doc['effect_account'];
    if (acc is Map && acc['id'] != null) {
      _effectAccount = Account(
        id: (acc['id'] as num).toInt(),
        name: acc['name']?.toString() ?? '',
        code: acc['code']?.toString() ?? '',
        accountType: 'accounting_document',
      );
    }
    for (final ln in _lines) {
      ln.dispose();
    }
    _lines.clear();
    final rawLines = (doc['lines'] as List?) ?? const [];
    if (rawLines.isEmpty) {
      _lines.add(_LineVm());
    } else {
      for (final raw in rawLines) {
        final m = Map<String, dynamic>.from(raw as Map);
        final product = <String, dynamic>{
          'id': m['product_id'],
          'name': m['product_name'],
          'code': m['product_code'],
          'base_purchase_price': m['unit_cost'],
          'track_inventory': true,
          'track_expiry': m['track_expiry'] == true,
          'inventory_mode': m['inventory_mode'] ?? 'bulk',
        };
        final extra = m['extra_info'] is Map ? Map<String, dynamic>.from(m['extra_info'] as Map) : <String, dynamic>{};
        final lots = extra['lot_allocations'] is List
            ? (extra['lot_allocations'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : <Map<String, dynamic>>[];
        final rawIds = extra['selected_instance_ids'] ?? extra['instance_ids'];
        final instanceIds = rawIds is List
            ? rawIds.map((e) => (e as num?)?.toInt()).whereType<int>().toList()
            : <int>[];
        _lines.add(
          _LineVm(
            product: product,
            warehouseId: (m['warehouse_id'] as num?)?.toInt(),
            lotAllocations: lots,
            selectedInstanceIds: instanceIds,
            manufacturingDate: DateTime.tryParse(
              extra['manufacturing_date']?.toString() ?? '',
            ),
            expiryDate: DateTime.tryParse(
              extra['expiry_date']?.toString() ?? '',
            ),
            qty: formatWithThousands(m['quantity'] ?? 0, decimalPlaces: 3),
            unitCost: formatWithThousands(m['unit_cost'] ?? 0, decimalPlaces: 2),
            desc: m['description']?.toString() ?? '',
          ),
        );
      }
    }
  }

  Map<String, dynamic> _buildPayload({bool autoPost = true}) {
    final lines = <Map<String, dynamic>>[];
    for (final ln in _lines) {
      final pid = (ln.product?['id'] as num?)?.toInt();
      if (pid == null || ln.warehouseId == null) continue;
      final row = <String, dynamic>{
        'product_id': pid,
        'warehouse_id': ln.warehouseId,
        'quantity': ln.quantity,
        'description': ln.descCtrl.text.trim().isEmpty ? null : ln.descCtrl.text.trim(),
      };
      if (_unitCostEditable) {
        row['unit_cost'] = ln.unitCost;
      }
      final extra = <String, dynamic>{};
      if (ln.lotAllocations.isNotEmpty) {
        extra['lot_allocations'] = ln.lotAllocations;
        row['lot_allocations'] = ln.lotAllocations;
      }
      if (ln.selectedInstanceIds.isNotEmpty) {
        extra['selected_instance_ids'] = ln.selectedInstanceIds;
        extra['instance_ids'] = ln.selectedInstanceIds;
        row['selected_instance_ids'] = ln.selectedInstanceIds;
      }
      if (ln.manufacturingDate != null) {
        extra['manufacturing_date'] =
            ln.manufacturingDate!.toIso8601String().split('T').first;
      }
      if (ln.expiryDate != null) {
        extra['expiry_date'] = ln.expiryDate!.toIso8601String().split('T').first;
      }
      if (extra.isNotEmpty) {
        row['extra_info'] = extra;
      }
      lines.add(row);
    }
    return <String, dynamic>{
      'doc_kind': _docKind,
      'document_date': _documentDate.toIso8601String().split('T').first,
      'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      'person_id': _person?.id,
      if (_effectAccount?.id != null) 'effect_account_id': _effectAccount!.id,
      if (_effectAccount?.id == null && (_effectAccount?.code.isNotEmpty ?? false))
        'effect_account_code': _effectAccount!.code,
      'lines': lines,
      'auto_post': autoPost && !_isTwoStep && _autoPostSimple && _can('post'),
    };
  }

  String? _validate() {
    if (_requirePerson && _person == null) return 'انتخاب شخص الزامی است';
    if (_lines.every((l) => l.product == null || l.warehouseId == null || l.quantity <= 0)) {
      return 'حداقل یک سطر معتبر (کالا، انبار، مقدار) لازم است';
    }
    for (var i = 0; i < _lines.length; i++) {
      final ln = _lines[i];
      if (ln.product == null && ln.warehouseId == null && ln.quantity <= 0) continue;
      if (ln.product == null) return 'سطر ${i + 1}: کالا الزامی است';
      if (ln.warehouseId == null) return 'سطر ${i + 1}: انبار الزامی است';
      if (ln.quantity <= 0) return 'سطر ${i + 1}: مقدار باید مثبت باشد';
      final tracked = ln.product?['track_inventory'];
      if (tracked == false) return 'سطر ${i + 1}: کالا کنترل موجودی ندارد';
    }
    if ((_can('allocate') || !_isTwoStep) &&
        _effectAccount == null &&
        (_status == 'draft_accounting' || !_isTwoStep)) {
      // در simple حساب پیش‌فرض از کد می‌آید؛ اگر خالی بود خطا بده
      if (_effectAccount?.code == null || _effectAccount!.code.isEmpty) {
        return 'حساب هزینه/درآمد الزامی است';
      }
    }
    return null;
  }

  Future<void> _save({bool closeAfter = true}) async {
    final err = _validate();
    if (err != null) {
      SnackBarHelper.showError(context, message: err);
      return;
    }
    setState(() => _saving = true);
    try {
      final payload = _buildPayload();
      Map<String, dynamic> result;
      if (_isEdit) {
        result = await _svc.update(
          businessId: widget.businessId,
          documentId: widget.documentId!,
          payload: payload,
        );
      } else {
        result = await _svc.create(
          businessId: widget.businessId,
          payload: payload,
        );
      }
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        message: result['status'] == 'posted' ? 'سند ایجاد و قطعی شد' : 'سند ذخیره شد',
      );
      if (closeAfter) {
        Navigator.of(context).pop(true);
      } else {
        _applyDoc(result);
        setState(() {});
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: 'خطا در ذخیره: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _runAction(Future<Map<String, dynamic>> Function() action, String okMsg) async {
    setState(() => _saving = true);
    try {
      final result = await action();
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: okMsg);
      _applyDoc(result);
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _onProductSelected(_LineVm line, Map<String, dynamic>? product) {
    setState(() {
      line.product = product;
      final cost = product?['base_purchase_price'];
      if (cost != null) {
        line.unitCostCtrl.text = formatWithThousands(cost, decimalPlaces: 2);
      }
    });
  }

  double get _totalAmount => _lines.fold<double>(0, (s, l) => s + l.amount);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _isEdit
        ? '${docKindLabel(_docKind)} — ${_code ?? ''}'
        : 'ثبت ${docKindLabel(_docKind)}';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 860),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleLarge),
                        if (_isEdit)
                          Text(
                            'وضعیت: ${geiStatusLabel(_status)}',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!_isEdit)
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'goods_expense', label: Text('کالای هزینه‌شده')),
                                ButtonSegment(value: 'goods_income', label: Text('کالای درآمدشده')),
                              ],
                              selected: {_docKind},
                              onSelectionChanged: (s) {
                                if (!_opsEditable) return;
                                setState(() {
                                  _docKind = s.first;
                                  _applyDefaultAccountCode();
                                });
                              },
                            ),
                          if (!_isEdit) const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: DateInputField(
                                  labelText: 'تاریخ سند',
                                  value: _documentDate,
                                  calendarController: _calendar,
                                  enabled: _opsEditable,
                                  onChanged: (d) {
                                    if (d != null) setState(() => _documentDate = d);
                                  },
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: PersonComboboxWidget(
                                  businessId: widget.businessId,
                                  selectedPerson: _person,
                                  isRequired: _requirePerson,
                                  onChanged: _opsEditable
                                      ? (p) => setState(() => _person = p)
                                      : (_) {},
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_canShowAccount)
                            IgnorePointer(
                              ignoring: !_accountEditable,
                              child: Opacity(
                                opacity: _accountEditable ? 1 : 0.7,
                                child: AccountComboboxWidget(
                                  businessId: widget.businessId,
                                  selectedAccount: _effectAccount,
                                  label: _docKind == 'goods_income' ? 'حساب درآمد' : 'حساب هزینه',
                                  isRequired: true,
                                  onChanged: (a) => setState(() => _effectAccount = a),
                                ),
                              ),
                            ),
                          if (_canShowAccount) const SizedBox(height: 12),
                          TextField(
                            controller: _descCtrl,
                            enabled: _opsEditable || _can('allocate'),
                            decoration: const InputDecoration(
                              labelText: 'توضیحات',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Text('اقلام کالا', style: theme.textTheme.titleMedium),
                              const Spacer(),
                              if (_opsEditable)
                                TextButton.icon(
                                  onPressed: () => setState(() => _lines.add(_LineVm())),
                                  icon: Icon(Icons.add),
                                  label: const Text('افزودن سطر'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ..._lines.asMap().entries.map((e) => _buildLineCard(e.key, e.value)),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'جمع مبلغ: ${formatWithThousands(_totalAmount, decimalPlaces: 2)}',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          if (_loadedDoc?['warehouse_document_id'] != null ||
                              _loadedDoc?['accounting_document_id'] != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              'حواله انبار: ${_loadedDoc?['warehouse_document_id'] ?? '-'} | سند حسابداری: ${_loadedDoc?['accounting_document_id'] ?? '-'}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                    child: const Text('بستن'),
                  ),
                  if (_opsEditable && (_status != 'posted'))
                    FilledButton.tonal(
                      onPressed: _saving ? null : () => _save(closeAfter: true),
                      child: Text(_isEdit ? 'ذخیره' : 'ثبت'),
                    ),
                  if (_isEdit &&
                      _isTwoStep &&
                      _status == 'draft_ops' &&
                      _can('submit'))
                    FilledButton(
                      onPressed: _saving
                          ? null
                          : () => _runAction(
                                () => _svc.submit(
                                  businessId: widget.businessId,
                                  documentId: widget.documentId!,
                                ),
                                'به حسابداری ارسال شد',
                              ),
                      child: const Text('ارسال به حسابداری'),
                    ),
                  if (_isEdit &&
                      _can('allocate') &&
                      (_status == 'pending_accounting' ||
                          _status == 'draft_accounting' ||
                          _status == 'draft_ops'))
                    FilledButton.tonal(
                      onPressed: _saving
                          ? null
                          : () => _runAction(
                                () => _svc.allocate(
                                  businessId: widget.businessId,
                                  documentId: widget.documentId!,
                                  payload: {
                                    if (_effectAccount?.id != null)
                                      'effect_account_id': _effectAccount!.id,
                                    if (_effectAccount?.id == null &&
                                        (_effectAccount?.code.isNotEmpty ?? false))
                                      'effect_account_code': _effectAccount!.code,
                                    'description': _descCtrl.text.trim(),
                                  },
                                ),
                                'حساب تخصیص یافت',
                              ),
                      child: const Text('تخصیص حساب'),
                    ),
                  if (_isEdit &&
                      _can('post') &&
                      (_status == 'draft_ops' ||
                          _status == 'pending_accounting' ||
                          _status == 'draft_accounting'))
                    FilledButton(
                      onPressed: _saving
                          ? null
                          : () => _runAction(
                                () => _svc.post(
                                  businessId: widget.businessId,
                                  documentId: widget.documentId!,
                                ),
                                'سند قطعی شد',
                              ),
                      child: const Text('قطعی‌سازی'),
                    ),
                  if (_isEdit && _status == 'posted' && _can('cancel'))
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: SemanticColorResolver.negative(context)),
                      onPressed: _saving
                          ? null
                          : () => _runAction(
                                () => _svc.cancel(
                                  businessId: widget.businessId,
                                  documentId: widget.documentId!,
                                ),
                                'سند ابطال شد',
                              ),
                      child: const Text('ابطال'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLineCard(int index, _LineVm line) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Text('سطر ${index + 1}', style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                if (_opsEditable && _lines.length > 1)
                  IconButton(
                    tooltip: 'حذف سطر',
                    onPressed: () {
                      setState(() {
                        line.dispose();
                        _lines.removeAt(index);
                      });
                    },
                    icon: Icon(Icons.delete_outline, color: SemanticColorResolver.negative(context)),
                  ),
              ],
            ),
            ProductComboboxWidget(
              businessId: widget.businessId,
              selectedProduct: line.product,
              authStore: _auth,
              label: 'کالا',
              onChanged: _opsEditable ? (p) => _onProductSelected(line, p) : (_) {},
            ),
            const SizedBox(height: 8),
            WarehouseComboboxWidget(
              businessId: widget.businessId,
              selectedWarehouseId: line.warehouseId,
              selectDefaultWhenUnset: true,
              onChanged: _opsEditable
                  ? (id) => setState(() => line.warehouseId = id)
                  : (_) {},
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: line.qtyCtrl,
                    enabled: _opsEditable,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,٬]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'مقدار',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: line.unitCostCtrl,
                    enabled: _unitCostEditable,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,٬]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'بهای واحد',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'مبلغ',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(formatWithThousands(line.amount, decimalPlaces: 2)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: line.descCtrl,
              enabled: _opsEditable,
              decoration: const InputDecoration(
                labelText: 'توضیح سطر',
                border: OutlineInputBorder(),
              ),
            ),
            if (line.product?['track_expiry'] == true &&
                (line.product?['inventory_mode']?.toString() ?? 'bulk') != 'unique') ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: !_opsEditable
                      ? null
                      : () async {
                          final pid = (line.product?['id'] as num?)?.toInt();
                          if (pid == null) return;
                          final variantId = line.lotAllocations.isNotEmpty
                              ? (line.lotAllocations.first['variant_id'] as num?)?.toInt()
                              : (line.product?['variant_id'] as num?)?.toInt();
                          final result = await showDialog<List<Map<String, dynamic>>>(
                            context: context,
                            builder: (context) => InvoiceLineLotPickerDialog(
                              businessId: widget.businessId,
                              productId: pid,
                              productName: line.product?['name']?.toString() ?? '',
                              lineQuantity: line.quantity,
                              warehouseId: line.warehouseId,
                              variantId: variantId,
                              initialAllocations: line.lotAllocations,
                              inbound: _docKind == 'goods_income',
                              includeUnsellable: _docKind == 'goods_expense',
                              calendarController: _calendar,
                            ),
                          );
                          if (result != null && mounted) {
                            setState(() => line.lotAllocations = result);
                          }
                        },
                  icon: const Icon(Icons.event),
                  label: Text(
                    line.lotAllocations.isEmpty
                        ? AppLocalizations.of(context).lotAndDates
                        : '${line.lotAllocations.length} ${AppLocalizations.of(context).lotAndDates}',
                  ),
                ),
              ),
            ],
            if ((line.product?['inventory_mode']?.toString() ?? 'bulk') == 'unique' &&
                _docKind == 'goods_income' &&
                line.product?['track_expiry'] == true) ...[
              const SizedBox(height: 8),
              DateInputField(
                calendarController: _calendar,
                value: line.manufacturingDate,
                labelText: AppLocalizations.of(context).expiryColManufacturing,
                enabled: _opsEditable,
                onChanged: (v) => setState(() => line.manufacturingDate = v),
              ),
              DateInputField(
                calendarController: _calendar,
                value: line.expiryDate,
                labelText: AppLocalizations.of(context).expiryDate,
                enabled: _opsEditable,
                onChanged: (v) => setState(() => line.expiryDate = v),
              ),
            ],
            if ((line.product?['inventory_mode']?.toString() ?? 'bulk') == 'unique' &&
                _docKind == 'goods_expense') ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: !_opsEditable
                      ? null
                      : () async {
                          final pid = (line.product?['id'] as num?)?.toInt();
                          if (pid == null) return;
                          final qty = line.quantity.round();
                          if (qty <= 0) {
                            SnackBarHelper.show(
                              context,
                              message: AppLocalizations.of(context).lotPickerMinOne,
                            );
                            return;
                          }
                          final result = await showDialog<Map<String, dynamic>>(
                            context: context,
                            builder: (context) => UniqueProductInstanceSelectorDialog(
                              businessId: widget.businessId,
                              productId: pid,
                              productName: line.product?['name']?.toString() ?? '',
                              warehouseId: line.warehouseId,
                              selectedInstanceIds: line.selectedInstanceIds,
                              requiredQuantity: qty,
                              calendarController: _calendar,
                              includeUnsellable: true,
                            ),
                          );
                          if (result != null && mounted) {
                            final selectedIds = ((result['ids'] as List?) ?? const [])
                                .map((e) => int.tryParse(e.toString()))
                                .whereType<int>()
                                .toList();
                            setState(() {
                              line.selectedInstanceIds = selectedIds;
                              line.qtyCtrl.text = formatWithThousands(
                                selectedIds.length,
                                decimalPlaces: 0,
                              );
                            });
                          }
                        },
                  icon: const Icon(Icons.qr_code_2),
                  label: Text(
                    line.selectedInstanceIds.isEmpty
                        ? AppLocalizations.of(context).selectUnitTitle
                        : '${line.selectedInstanceIds.length} ${AppLocalizations.of(context).selectUnitTitle}',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
