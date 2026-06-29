import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../models/person_model.dart';
import '../../../widgets/invoice/person_combobox_widget.dart';

/// دیالوگ ثبت/ویرایش پرسنل حقوق.
class PayrollEmployeeFormDialog extends StatefulWidget {
  final int businessId;
  final Map<String, dynamic>? existing;

  const PayrollEmployeeFormDialog({
    super.key,
    required this.businessId,
    this.existing,
  });

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required int businessId,
    Map<String, dynamic>? existing,
  }) {
    return showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (_) => PayrollEmployeeFormDialog(
        businessId: businessId,
        existing: existing,
      ),
    );
  }

  @override
  State<PayrollEmployeeFormDialog> createState() => _PayrollEmployeeFormDialogState();
}

class _PayrollEmployeeFormDialogState extends State<PayrollEmployeeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeCtrl;
  late final TextEditingController _jobCtrl;
  late final TextEditingController _salaryCtrl;
  late final TextEditingController _insuranceCtrl;
  late final TextEditingController _taxCtrl;

  Person? _person;
  String _employmentType = 'full_time';
  bool _isActive = true;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _codeCtrl = TextEditingController(text: '${e?['employee_code'] ?? ''}');
    _jobCtrl = TextEditingController(text: '${e?['job_title'] ?? ''}');
    _salaryCtrl = TextEditingController(
      text: e?['base_salary'] != null ? '${e!['base_salary']}' : '',
    );
    _insuranceCtrl = TextEditingController(text: '${e?['insurance_number'] ?? ''}');
    _taxCtrl = TextEditingController(text: '${e?['tax_id'] ?? ''}');
    _employmentType = '${e?['employment_type'] ?? 'full_time'}';
    _isActive = e?['is_active'] != false;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _jobCtrl.dispose();
    _salaryCtrl.dispose();
    _insuranceCtrl.dispose();
    _taxCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (!_isEdit && _person == null) return;
    final payload = <String, dynamic>{
      if (!_isEdit) 'person_id': _person!.id,
      'employee_code': _codeCtrl.text.trim(),
      'job_title': _jobCtrl.text.trim().isEmpty ? null : _jobCtrl.text.trim(),
      'employment_type': _employmentType,
      'base_salary': _salaryCtrl.text.trim().isEmpty
          ? null
          : double.tryParse(_salaryCtrl.text.replaceAll(',', '')),
      'insurance_number': _insuranceCtrl.text.trim().isEmpty ? null : _insuranceCtrl.text.trim(),
      'tax_id': _taxCtrl.text.trim().isEmpty ? null : _taxCtrl.text.trim(),
      'is_active': _isActive,
    };
    Navigator.pop(context, payload);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(_isEdit ? t.payrollEditEmployee : t.payrollAddEmployee),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_isEdit)
                  PersonComboboxWidget(
                    businessId: widget.businessId,
                    selectedPerson: _person,
                    onChanged: (p) => setState(() => _person = p),
                    label: t.customerClubPerson,
                    isRequired: true,
                  ),
                if (!_isEdit) const SizedBox(height: 12),
                TextFormField(
                  controller: _codeCtrl,
                  decoration: InputDecoration(labelText: t.payrollEmployeeCode),
                  validator: (v) => (v == null || v.trim().isEmpty) ? t.required : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _jobCtrl,
                  decoration: InputDecoration(labelText: t.payrollJobTitle),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _salaryCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: t.payrollBaseSalary),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _employmentType,
                  decoration: InputDecoration(labelText: t.payrollEmploymentType),
                  items: [
                    DropdownMenuItem(value: 'full_time', child: Text(t.payrollEmploymentFullTime)),
                    DropdownMenuItem(value: 'part_time', child: Text(t.payrollEmploymentPartTime)),
                    DropdownMenuItem(value: 'contract', child: Text(t.payrollEmploymentContract)),
                  ],
                  onChanged: (v) => setState(() => _employmentType = v ?? 'full_time'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _insuranceCtrl,
                  decoration: InputDecoration(labelText: t.payrollInsuranceNumber),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _taxCtrl,
                  decoration: InputDecoration(labelText: t.payrollTaxId),
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
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: _submit, child: Text(t.save)),
      ],
    );
  }
}
