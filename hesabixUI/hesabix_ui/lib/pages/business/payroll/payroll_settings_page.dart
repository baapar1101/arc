import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../models/account_model.dart';
import '../../../services/payroll_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/invoice/account_tree_combobox_widget.dart';
import '../../../core/permission_guard.dart';
import 'payroll_item_edit_dialog.dart';
import 'payroll_ui.dart';

/// تنظیمات افزونه حقوق و دستمزد: آیتم‌ها، حساب‌های پیش‌فرض و قوانین.
class PayrollSettingsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const PayrollSettingsPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<PayrollSettingsPage> createState() => _PayrollSettingsPageState();
}

class _PayrollSettingsPageState extends State<PayrollSettingsPage> {
  final PayrollService _svc = PayrollService();

  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic> _settings = const {};
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _categories = [];

  Account? _wagesPayableAccount;
  Account? _expenseAccount;
  Account? _taxAccount;
  Account? _insuranceAccount;

  bool _statutoryEnabled = false;
  bool _requireApproval = false;
  bool _autoPostOnFinalize = false;
  final TextEditingController _insEmpRateCtrl = TextEditingController(text: '7');
  final TextEditingController _insErRateCtrl = TextEditingController(text: '20');
  final TextEditingController _insUnempRateCtrl = TextEditingController(text: '3');
  final TextEditingController _taxFlatRateCtrl = TextEditingController(text: '10');
  final TextEditingController _taxExemptionCtrl = TextEditingController(text: '0');

  bool get _canManage =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('payroll', 'manage');

  @override
  void dispose() {
    _insEmpRateCtrl.dispose();
    _insErRateCtrl.dispose();
    _insUnempRateCtrl.dispose();
    _taxFlatRateCtrl.dispose();
    _taxExemptionCtrl.dispose();
    super.dispose();
  }

  void _applyStatutoryFromSettings(Map<String, dynamic> settings) {
    final extra = settings['extra_settings'];
    final rules = extra is Map ? extra['statutory_rules'] : null;
    final ins = rules is Map ? rules['insurance'] : null;
    final tax = rules is Map ? rules['tax'] : null;
    _statutoryEnabled = rules is Map && rules['enabled'] == true;
    _requireApproval = settings['require_approval'] == true;
    _autoPostOnFinalize = settings['auto_post_on_finalize'] == true;
    _insEmpRateCtrl.text = '${ins is Map ? ins['employee_rate_percent'] ?? 7 : 7}';
    _insErRateCtrl.text = '${ins is Map ? ins['employer_rate_percent'] ?? 20 : 20}';
    _insUnempRateCtrl.text = '${ins is Map ? ins['unemployment_employer_rate_percent'] ?? 3 : 3}';
    _taxFlatRateCtrl.text = '${tax is Map ? tax['flat_rate_percent'] ?? 10 : 10}';
    _taxExemptionCtrl.text = '${tax is Map ? tax['exemption_amount'] ?? 0 : 0}';
  }

  Future<void> _saveStatutoryRules() async {
    final insEmp = double.tryParse(_insEmpRateCtrl.text.replaceAll(',', '')) ?? 7;
    final insEr = double.tryParse(_insErRateCtrl.text.replaceAll(',', '')) ?? 20;
    final insUnemp = double.tryParse(_insUnempRateCtrl.text.replaceAll(',', '')) ?? 3;
    final taxRate = double.tryParse(_taxFlatRateCtrl.text.replaceAll(',', '')) ?? 10;
    final exemption = double.tryParse(_taxExemptionCtrl.text.replaceAll(',', '')) ?? 0;
    final extra = Map<String, dynamic>.from(
      _settings['extra_settings'] is Map ? _settings['extra_settings'] as Map : const {},
    );
    extra['statutory_rules'] = {
      'enabled': _statutoryEnabled,
      'insurance': {
        'employee_rate_percent': insEmp,
        'employer_rate_percent': insEr,
        'unemployment_employer_rate_percent': insUnemp,
      },
      'tax': {
        'mode': 'flat_percent',
        'flat_rate_percent': taxRate,
        'exemption_amount': exemption,
      },
    };
    await _saveSettings({
      'extra_settings': extra,
      'require_approval': _requireApproval,
      'auto_post_on_finalize': _autoPostOnFinalize,
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Account? _accountFromId(dynamic id) {
    if (id == null) return null;
    return Account(id: (id as num).toInt(), code: '', name: '#$id', accountType: '');
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _svc.getSettings(businessId: widget.businessId),
        _svc.listItems(businessId: widget.businessId, includeInactive: true),
        _svc.listItemCategories(businessId: widget.businessId, includeInactive: true),
      ]);
      if (!mounted) return;
      final settings = Map<String, dynamic>.from(results[0] as Map);
      setState(() {
        _settings = settings;
        _items = List<Map<String, dynamic>>.from(results[1] as List);
        _categories = List<Map<String, dynamic>>.from(results[2] as List);
        _wagesPayableAccount = _accountFromId(settings['wages_payable_account_id']);
        _expenseAccount = _accountFromId(settings['payroll_expense_account_id']);
        _taxAccount = _accountFromId(settings['tax_payable_account_id']);
        _insuranceAccount = _accountFromId(settings['insurance_payable_account_id']);
        _applyStatutoryFromSettings(settings);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _saveSettings(Map<String, dynamic> patch) async {
    if (!_canManage) return;
    setState(() => _saving = true);
    try {
      final updated = await _svc.updateSettings(
        businessId: widget.businessId,
        payload: patch,
      );
      if (!mounted) return;
      setState(() {
        _settings = updated;
        _saving = false;
      });
      SnackBarHelper.show(context, message: AppLocalizations.of(context).saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _toggleEnabled(bool value) => _saveSettings({'enabled': value});

  Future<void> _saveDefaultAccounts() async {
    await _saveSettings({
      'wages_payable_account_id': _wagesPayableAccount?.id,
      'payroll_expense_account_id': _expenseAccount?.id,
      'tax_payable_account_id': _taxAccount?.id,
      'insurance_payable_account_id': _insuranceAccount?.id,
    });
  }

  Future<void> _editItem(Map<String, dynamic>? existing) async {
    final payload = await PayrollItemEditDialog.show(
      context,
      businessId: widget.businessId,
      existing: existing,
      categories: _categories,
    );
    if (payload == null) return;
    try {
      if (existing != null) {
        await _svc.updateItem(
          businessId: widget.businessId,
          itemId: (existing['id'] as num).toInt(),
          payload: payload,
        );
      } else {
        await _svc.createItem(businessId: widget.businessId, payload: payload);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  String _kindLabel(AppLocalizations t, String? kind) {
    switch (kind) {
      case 'earning':
        return t.payrollItemKindEarning;
      case 'deduction':
        return t.payrollItemKindDeduction;
      case 'employer_cost':
        return t.payrollItemKindEmployerCost;
      default:
        return kind ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!_canManage && widget.authStore.currentBusiness?.isOwner != true) {
      return PermissionGuard.buildAccessDeniedPage();
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'settings')),
        ),
        title: Text(t.businessSettingsPayroll),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: PayrollUi.pagePadding,
              children: [
                PayrollUi.sectionCard(
                  context: context,
                  title: t.payrollSettingsEnabled,
                  icon: Icons.power_settings_new,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.payrollSettingsEnabled),
                    subtitle: Text(t.payrollSettingsEnabledDescription),
                    value: _settings['enabled'] == true,
                    onChanged: _canManage && !_saving ? _toggleEnabled : null,
                  ),
                ),
                const SizedBox(height: 16),
                PayrollUi.sectionCard(
                  context: context,
                  title: t.payrollItemsTab,
                  icon: Icons.list_alt_outlined,
                  trailing: TextButton.icon(
                    onPressed: _canManage ? () => _editItem(null) : null,
                    icon: const Icon(Icons.add),
                    label: Text(t.payrollAddItem),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.payrollSettingsItemsDescription,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 12),
                      ..._items.map((item) {
                        final hasAccount = item['account_id'] != null;
                        final kind = item['item_kind'] as String?;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: PayrollUi.listTileCard(
                            context: context,
                            leading: Icon(
                              hasAccount ? Icons.account_balance_outlined : Icons.link_off,
                              color: hasAccount
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outline,
                            ),
                            title: Text('${item['name']}'),
                            subtitle: Text('${item['code'] ?? ''}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (item['is_system'] == true)
                                  PayrollUi.statusChip(context, t.payrollSystemItem),
                                if (item['is_system'] != true)
                                  PayrollUi.kindChip(context, _kindLabel(t, kind), kind),
                              ],
                            ),
                            onTap: _canManage ? () => _editItem(item) : null,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PayrollUi.sectionCard(
                  context: context,
                  title: t.payrollWorkflowSettings,
                  icon: Icons.account_tree_outlined,
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t.payrollRequireApproval),
                        subtitle: Text(t.payrollRequireApprovalHint),
                        value: _requireApproval,
                        onChanged: _canManage && !_saving
                            ? (v) => setState(() => _requireApproval = v)
                            : null,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t.payrollAutoPostOnFinalize),
                        subtitle: Text(t.payrollAutoPostOnFinalizeHint),
                        value: _autoPostOnFinalize,
                        onChanged: _canManage && !_saving
                            ? (v) => setState(() => _autoPostOnFinalize = v)
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PayrollUi.sectionCard(
                  context: context,
                  title: t.payrollStatutoryRules,
                  icon: Icons.gavel_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.payrollStatutoryRulesHint, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t.payrollStatutoryEnabled),
                        value: _statutoryEnabled,
                        onChanged: _canManage && !_saving
                            ? (v) => setState(() => _statutoryEnabled = v)
                            : null,
                      ),
                      TextFormField(
                        controller: _insEmpRateCtrl,
                        enabled: _canManage && !_saving,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: PayrollUi.fieldDecoration(context, t.payrollInsuranceEmployeeRate),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _insErRateCtrl,
                        enabled: _canManage && !_saving,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: PayrollUi.fieldDecoration(context, t.payrollInsuranceEmployerRate),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _insUnempRateCtrl,
                        enabled: _canManage && !_saving,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: PayrollUi.fieldDecoration(context, t.payrollInsuranceUnemploymentRate),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _taxFlatRateCtrl,
                        enabled: _canManage && !_saving,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: PayrollUi.fieldDecoration(context, t.payrollTaxFlatRate),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _taxExemptionCtrl,
                        enabled: _canManage && !_saving,
                        keyboardType: TextInputType.number,
                        decoration: PayrollUi.fieldDecoration(context, t.payrollTaxExemption),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: FilledButton(
                          onPressed: _canManage && !_saving ? _saveStatutoryRules : null,
                          child: Text(t.save),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                PayrollUi.sectionCard(
                  context: context,
                  title: t.payrollDefaultAccounts,
                  icon: Icons.account_balance_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AccountTreeComboboxWidget(
                        businessId: widget.businessId,
                        selectedAccount: _wagesPayableAccount,
                        label: t.payrollAccountWagesPayable,
                        dense: true,
                        onChanged: (a) => setState(() => _wagesPayableAccount = a),
                      ),
                      const SizedBox(height: 12),
                      AccountTreeComboboxWidget(
                        businessId: widget.businessId,
                        selectedAccount: _expenseAccount,
                        label: t.payrollAccountExpense,
                        dense: true,
                        onChanged: (a) => setState(() => _expenseAccount = a),
                      ),
                      const SizedBox(height: 12),
                      AccountTreeComboboxWidget(
                        businessId: widget.businessId,
                        selectedAccount: _taxAccount,
                        label: t.payrollAccountTaxPayable,
                        dense: true,
                        onChanged: (a) => setState(() => _taxAccount = a),
                      ),
                      const SizedBox(height: 12),
                      AccountTreeComboboxWidget(
                        businessId: widget.businessId,
                        selectedAccount: _insuranceAccount,
                        label: t.payrollAccountInsurancePayable,
                        dense: true,
                        onChanged: (a) => setState(() => _insuranceAccount = a),
                      ),
                      const SizedBox(height: 8),
                      Text(t.payrollDefaultAccountsHint, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: FilledButton(
                          onPressed: _canManage && !_saving ? _saveDefaultAccounts : null,
                          child: Text(t.save),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
