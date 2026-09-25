import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../models/account_model.dart';
import '../../../widgets/invoice/account_tree_combobox_widget.dart';
import 'payroll_ui.dart';

/// دیالوگ ویرایش/ایجاد آیتم حقوق.
class PayrollItemEditDialog extends StatefulWidget {
  final int businessId;
  final Map<String, dynamic>? existing;
  final List<Map<String, dynamic>> categories;

  const PayrollItemEditDialog({
    super.key,
    required this.businessId,
    this.existing,
    required this.categories,
  });

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required int businessId,
    Map<String, dynamic>? existing,
    required List<Map<String, dynamic>> categories,
  }) {
    return showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (_) => PayrollItemEditDialog(
        businessId: businessId,
        existing: existing,
        categories: categories,
      ),
    );
  }

  @override
  State<PayrollItemEditDialog> createState() => _PayrollItemEditDialogState();
}

class _PayrollItemEditDialogState extends State<PayrollItemEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _defaultAmountCtrl;
  late final TextEditingController _percentCtrl;
  late final TextEditingController _sortCtrl;

  String _itemKind = 'earning';
  String _calculationType = 'manual';
  int? _categoryId;
  Account? _selectedAccount;
  bool _showOnPayslip = true;
  bool _isActive = true;

  bool get _isEdit => widget.existing != null;
  bool get _isSystem => widget.existing?['is_system'] == true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _codeCtrl = TextEditingController(text: '${e?['code'] ?? ''}');
    _nameCtrl = TextEditingController(text: '${e?['name'] ?? ''}');
    _defaultAmountCtrl = TextEditingController(
      text: PayrollUi.formatInputValue(e?['default_amount']),
    );
    _percentCtrl = TextEditingController(
      text: PayrollUi.formatInputValue(e?['percent_value']),
    );
    _sortCtrl = TextEditingController(
      text: PayrollUi.formatInputValue(e?['sort_order'], allowDecimal: false),
    );
    _itemKind = '${e?['item_kind'] ?? 'earning'}';
    _calculationType = '${e?['calculation_type'] ?? 'manual'}';
    _categoryId = (e?['category_id'] as num?)?.toInt();
    final aid = (e?['account_id'] as num?)?.toInt();
    if (aid != null) {
      _selectedAccount = Account(id: aid, code: '', name: '#$aid', accountType: '');
    }
    _showOnPayslip = e?['show_on_payslip'] != false;
    _isActive = e?['is_active'] != false;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _defaultAmountCtrl.dispose();
    _percentCtrl.dispose();
    _sortCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final payload = <String, dynamic>{
      if (!_isEdit || !_isSystem) 'code': _codeCtrl.text.trim().toLowerCase(),
      'name': _nameCtrl.text.trim(),
      if (!_isSystem) 'item_kind': _itemKind,
      if (!_isSystem) 'calculation_type': _calculationType,
      'category_id': _categoryId,
      'account_id': _selectedAccount?.id,
      'default_amount': _defaultAmountCtrl.text.trim().isEmpty
          ? null
          : PayrollUi.parseMoneyInput(_defaultAmountCtrl.text),
      'percent_value': _percentCtrl.text.trim().isEmpty
          ? null
          : PayrollUi.parseDecimalInput(_percentCtrl.text),
      'sort_order': PayrollUi.parseIntInput(_sortCtrl.text) ?? 0,
      'show_on_payslip': _showOnPayslip,
      'is_active': _isActive,
    };
    Navigator.pop(context, payload);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return PayrollUi.dialogShell(
      context: context,
      title: _isEdit ? t.payrollEditItem : t.payrollAddItem,
      icon: Icons.list_alt_outlined,
      maxWidth: 500,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isSystem)
              PayrollUi.infoBanner(
                context: context,
                message: t.payrollSystemItem,
                icon: Icons.lock_outline,
              ),
            if (_isSystem) const SizedBox(height: 12),
            TextFormField(
              controller: _codeCtrl,
              enabled: !_isSystem,
              decoration: PayrollUi.fieldDecoration(context, t.code, prefixIcon: Icons.tag),
              validator: (v) => (v == null || v.trim().isEmpty) ? t.required : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: PayrollUi.fieldDecoration(context, t.payrollItemName, prefixIcon: Icons.label_outline),
              validator: (v) => (v == null || v.trim().isEmpty) ? t.required : null,
            ),
            const SizedBox(height: 12),
            if (!_isSystem)
              DropdownButtonFormField<String>(
                initialValue: _itemKind,
                decoration: PayrollUi.fieldDecoration(context, t.payrollItemKindLabel, prefixIcon: Icons.category_outlined),
                items: [
                  DropdownMenuItem(value: 'earning', child: Text(t.payrollItemKindEarning)),
                  DropdownMenuItem(value: 'deduction', child: Text(t.payrollItemKindDeduction)),
                  DropdownMenuItem(value: 'employer_cost', child: Text(t.payrollItemKindEmployerCost)),
                ],
                onChanged: (v) => setState(() => _itemKind = v ?? 'earning'),
              ),
            if (!_isSystem) const SizedBox(height: 12),
            if (widget.categories.isNotEmpty)
              DropdownButtonFormField<int?>(
                initialValue: _categoryId,
                decoration: PayrollUi.fieldDecoration(context, t.payrollItemCategories, prefixIcon: Icons.folder_outlined),
                items: [
                  DropdownMenuItem<int?>(value: null, child: Text('—')),
                  ...widget.categories.map(
                    (c) => DropdownMenuItem<int?>(
                      value: (c['id'] as num).toInt(),
                      child: Text('${c['name']}'),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            if (widget.categories.isNotEmpty) const SizedBox(height: 12),
            AccountTreeComboboxWidget(
              businessId: widget.businessId,
              selectedAccount: _selectedAccount,
              label: t.payrollSelectAccount,
              dense: true,
              onChanged: (a) => setState(() => _selectedAccount = a),
            ),
            const SizedBox(height: 12),
            if (!_isSystem)
              DropdownButtonFormField<String>(
                initialValue: _calculationType,
                decoration: PayrollUi.fieldDecoration(context, t.payrollCalculationType, prefixIcon: Icons.calculate_outlined),
                items: [
                  DropdownMenuItem(value: 'manual', child: Text(t.payrollCalcManual)),
                  DropdownMenuItem(value: 'fixed', child: Text(t.payrollCalcFixed)),
                  DropdownMenuItem(value: 'percent_of_base', child: Text(t.payrollCalcPercentBase)),
                  DropdownMenuItem(value: 'statutory', child: Text(t.payrollCalcStatutory)),
                ],
                onChanged: (v) => setState(() => _calculationType = v ?? 'manual'),
              ),
            if (!_isSystem) const SizedBox(height: 12),
            if (_calculationType == 'fixed')
              TextFormField(
                controller: _defaultAmountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: PayrollUi.numericInputFormatters(),
                decoration: PayrollUi.fieldDecoration(context, t.payrollDefaultAmount, prefixIcon: Icons.attach_money),
              ),
            if (_calculationType == 'percent_of_base') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _percentCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: PayrollUi.numericInputFormatters(),
                decoration: PayrollUi.fieldDecoration(context, t.payrollPercentValue, prefixIcon: Icons.percent),
              ),
            ],
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.payrollShowOnPayslip),
              value: _showOnPayslip,
              onChanged: (v) => setState(() => _showOnPayslip = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.active),
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: _submit, child: Text(t.save)),
      ],
    );
  }
}
