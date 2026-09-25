import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart';
import '../../../models/person_model.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/date_input_field.dart';
import '../../../widgets/invoice/person_combobox_widget.dart';
import 'payroll_ui.dart';

/// دیالوگ ثبت/ویرایش پرسنل حقوق.
class PayrollEmployeeFormDialog extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final List<Map<String, dynamic>> departments;
  final Map<String, dynamic>? existing;

  const PayrollEmployeeFormDialog({
    super.key,
    required this.businessId,
    required this.calendarController,
    this.departments = const [],
    this.existing,
  });

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required int businessId,
    required CalendarController calendarController,
    List<Map<String, dynamic>> departments = const [],
    Map<String, dynamic>? existing,
  }) {
    return showGlassDialog<Map<String, dynamic>?>(
      context: context,
      builder: (_) => PayrollEmployeeFormDialog(
        businessId: businessId,
        calendarController: calendarController,
        departments: departments,
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
  int? _departmentId;
  String _employmentType = 'full_time';
  bool _isActive = true;
  DateTime? _hireDate;
  DateTime? _terminationDate;

  bool get _isEdit => widget.existing != null;

  List<Map<String, dynamic>> get _activeDepartments =>
      widget.departments.where((d) => d['is_active'] != false).toList();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _codeCtrl = TextEditingController(text: '${e?['employee_code'] ?? ''}');
    _jobCtrl = TextEditingController(text: '${e?['job_title'] ?? ''}');
    _salaryCtrl = TextEditingController(
      text: PayrollUi.formatInputValue(e?['base_salary']),
    );
    _insuranceCtrl = TextEditingController(text: '${e?['insurance_number'] ?? ''}');
    _taxCtrl = TextEditingController(text: '${e?['tax_id'] ?? ''}');
    _employmentType = '${e?['employment_type'] ?? 'full_time'}';
    _isActive = e?['is_active'] != false;
    _departmentId = (e?['department_id'] as num?)?.toInt();
    _hireDate = HesabixDateUtils.parseApiDate(e?['hire_date']);
    _terminationDate = HesabixDateUtils.parseApiDate(e?['termination_date']);
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
    if (!_isEdit) {
      if (_person == null) return;
      if (!_person!.personTypes.contains(PersonType.employee)) {
        SnackBarHelper.showError(context, message: AppLocalizations.of(context).payrollEmployeePersonHint);
        return;
      }
    }
    final payload = <String, dynamic>{
      if (!_isEdit) 'person_id': _person!.id,
      'employee_code': _codeCtrl.text.trim(),
      'job_title': _jobCtrl.text.trim().isEmpty ? null : _jobCtrl.text.trim(),
      'employment_type': _employmentType,
      'department_id': _departmentId,
      'base_salary': _salaryCtrl.text.trim().isEmpty
          ? null
          : PayrollUi.parseMoneyInput(_salaryCtrl.text),
      'insurance_number': _insuranceCtrl.text.trim().isEmpty ? null : _insuranceCtrl.text.trim(),
      'tax_id': _taxCtrl.text.trim().isEmpty ? null : _taxCtrl.text.trim(),
      'is_active': _isActive,
    };
    if (_isEdit) {
      payload['hire_date'] =
          _hireDate != null ? HesabixDateUtils.formatForApiDate(_hireDate!) : null;
      payload['termination_date'] = _terminationDate != null
          ? HesabixDateUtils.formatForApiDate(_terminationDate!)
          : null;
    } else {
      if (_hireDate != null) payload['hire_date'] = HesabixDateUtils.formatForApiDate(_hireDate!);
      if (_terminationDate != null) {
        payload['termination_date'] = HesabixDateUtils.formatForApiDate(_terminationDate!);
      }
    }
    Navigator.pop(context, payload);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return PayrollUi.dialogShell(
      context: context,
      title: _isEdit ? t.payrollEditEmployee : t.payrollAddEmployee,
      icon: Icons.badge_outlined,
      maxWidth: 500,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_isEdit) ...[
              PersonComboboxWidget(
                businessId: widget.businessId,
                selectedPerson: _person,
                onChanged: (p) => setState(() => _person = p),
                label: t.customerClubPerson,
                isRequired: true,
                personTypes: [PersonType.employee.persianName],
              ),
              const SizedBox(height: 8),
              PayrollUi.infoBanner(context: context, message: t.payrollEmployeePersonHint, icon: Icons.info_outline),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _codeCtrl,
              decoration: PayrollUi.fieldDecoration(context, t.payrollEmployeeCode, prefixIcon: Icons.pin),
              validator: (v) => (v == null || v.trim().isEmpty) ? t.required : null,
            ),
            const SizedBox(height: 12),
            if (_activeDepartments.isNotEmpty) ...[
              DropdownButtonFormField<int?>(
                initialValue: _departmentId,
                decoration: PayrollUi.fieldDecoration(context, t.payrollEmployeeDepartment, prefixIcon: Icons.apartment),
                items: [
                  DropdownMenuItem<int?>(value: null, child: Text('—')),
                  ..._activeDepartments.map(
                    (d) => DropdownMenuItem<int?>(
                      value: (d['id'] as num).toInt(),
                      child: Text('${d['name'] ?? d['code']}'),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _departmentId = v),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _jobCtrl,
              decoration: PayrollUi.fieldDecoration(context, t.payrollJobTitle, prefixIcon: Icons.work_outline),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _salaryCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: PayrollUi.numericInputFormatters(),
              decoration: PayrollUi.fieldDecoration(context, t.payrollBaseSalary, prefixIcon: Icons.payments_outlined),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _employmentType,
              decoration: PayrollUi.fieldDecoration(context, t.payrollEmploymentType, prefixIcon: Icons.schedule),
              items: [
                DropdownMenuItem(value: 'full_time', child: Text(t.payrollEmploymentFullTime)),
                DropdownMenuItem(value: 'part_time', child: Text(t.payrollEmploymentPartTime)),
                DropdownMenuItem(value: 'contract', child: Text(t.payrollEmploymentContract)),
              ],
              onChanged: (v) => setState(() => _employmentType = v ?? 'full_time'),
            ),
            const SizedBox(height: 12),
            DateInputField(
              value: _hireDate,
              calendarController: widget.calendarController,
              labelText: t.payrollHireDate,
              onChanged: (d) => setState(() => _hireDate = d),
            ),
            const SizedBox(height: 12),
            DateInputField(
              value: _terminationDate,
              calendarController: widget.calendarController,
              labelText: t.payrollTerminationDate,
              onChanged: (d) => setState(() => _terminationDate = d),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _insuranceCtrl,
              decoration: PayrollUi.fieldDecoration(context, t.payrollInsuranceNumber, prefixIcon: Icons.health_and_safety_outlined),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _taxCtrl,
              decoration: PayrollUi.fieldDecoration(context, t.payrollTaxId, prefixIcon: Icons.receipt_long_outlined),
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
