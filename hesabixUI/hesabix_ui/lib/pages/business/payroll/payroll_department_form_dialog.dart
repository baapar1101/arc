import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import 'payroll_ui.dart';

/// دیالوگ ایجاد یا ویرایش بخش سازمانی.
class PayrollDepartmentFormDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;

  const PayrollDepartmentFormDialog({super.key, this.existing});

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    Map<String, dynamic>? existing,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => PayrollDepartmentFormDialog(existing: existing),
    );
  }

  @override
  State<PayrollDepartmentFormDialog> createState() => _PayrollDepartmentFormDialogState();
}

class _PayrollDepartmentFormDialogState extends State<PayrollDepartmentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _sortCtrl;
  bool _isActive = true;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _codeCtrl = TextEditingController(text: '${e?['code'] ?? ''}');
    _nameCtrl = TextEditingController(text: '${e?['name'] ?? ''}');
    _sortCtrl = TextEditingController(
      text: PayrollUi.formatInputValue(e?['sort_order'], allowDecimal: false),
    );
    _isActive = e?['is_active'] != false;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _sortCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final payload = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'sort_order': PayrollUi.parseIntInput(_sortCtrl.text.trim()) ?? 0,
    };
    if (!_isEdit) {
      payload['code'] = _codeCtrl.text.trim().toLowerCase();
    }
    if (_isEdit) {
      payload['is_active'] = _isActive;
    }
    Navigator.of(context).pop(payload);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return PayrollUi.dialogShell(
      context: context,
      title: _isEdit ? t.payrollEditDepartment : t.payrollAddDepartment,
      icon: Icons.apartment_outlined,
      maxWidth: 440,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_isEdit)
              TextFormField(
                controller: _codeCtrl,
                decoration: PayrollUi.fieldDecoration(context, t.payrollDepartmentCode, prefixIcon: Icons.tag),
                validator: (v) => (v == null || v.trim().isEmpty) ? t.requiredField : null,
              ),
            if (!_isEdit) const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: PayrollUi.fieldDecoration(context, t.payrollDepartmentName, prefixIcon: Icons.badge_outlined),
              validator: (v) => (v == null || v.trim().isEmpty) ? t.requiredField : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _sortCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: PayrollUi.numericInputFormatters(allowDecimal: false),
              decoration: PayrollUi.fieldDecoration(context, t.payrollSortOrder, prefixIcon: Icons.sort),
            ),
            if (_isEdit) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.active),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
            ],
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
