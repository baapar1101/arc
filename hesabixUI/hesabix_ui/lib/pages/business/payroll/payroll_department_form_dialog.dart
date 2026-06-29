import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

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
    _sortCtrl = TextEditingController(text: '${e?['sort_order'] ?? 0}');
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
      'sort_order': int.tryParse(_sortCtrl.text.trim()) ?? 0,
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
    return AlertDialog(
      title: Text(_isEdit ? t.payrollEditDepartment : t.payrollAddDepartment),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isEdit)
                TextFormField(
                  controller: _codeCtrl,
                  decoration: InputDecoration(labelText: t.payrollDepartmentCode),
                  validator: (v) => (v == null || v.trim().isEmpty) ? t.requiredField : null,
                ),
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(labelText: t.payrollDepartmentName),
                validator: (v) => (v == null || v.trim().isEmpty) ? t.requiredField : null,
              ),
              TextFormField(
                controller: _sortCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: t.payrollSortOrder),
              ),
              if (_isEdit)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.active),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: _submit, child: Text(t.save)),
      ],
    );
  }
}
