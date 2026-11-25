import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/auth_store.dart';
import '../../../core/hesabix_back.dart';
import '../../../core/permission_guard.dart';
import '../../../models/account_model.dart';
import '../../../services/fixed_assets_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/number_normalizer.dart' show parseFormattedDouble, parseFormattedInt;
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/invoice/account_tree_combobox_widget.dart';
import 'fixed_assets_ui.dart';

/// تنظیمات افزونه اموال: حساب‌ها، قرارداد استهلاک، و قواعد قانونی قابل‌تغییر.
class FixedAssetsSettingsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const FixedAssetsSettingsPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<FixedAssetsSettingsPage> createState() => _FixedAssetsSettingsPageState();
}

class _FixedAssetsSettingsPageState extends State<FixedAssetsSettingsPage> {
  final FixedAssetsService _svc = FixedAssetsService();

  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic> _settings = const {};
  List<Map<String, dynamic>> _classes = [];

  Account? _vatIn;
  Account? _vatOut;
  Account? _openingEquity;
  Account? _gain;
  Account? _loss;
  Account? _repair;

  String _convention = 'from_ready_date';
  bool _enabled = true;
  bool _requireCustodian = false;
  final TextEditingController _prefixCtrl = TextEditingController(text: 'FA');
  final TextEditingController _idleMonthsCtrl = TextEditingController(text: '6');
  final TextEditingController _taxReductionCtrl = TextEditingController(text: '30');
  final TextEditingController _accountingReductionCtrl = TextEditingController(text: '0');

  bool get _canManage =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('fixed_assets', 'manage');

  bool get _canView =>
      _canManage ||
      widget.authStore.hasBusinessPermission('fixed_assets', 'view');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _prefixCtrl.dispose();
    _idleMonthsCtrl.dispose();
    _taxReductionCtrl.dispose();
    _accountingReductionCtrl.dispose();
    super.dispose();
  }

  Account? _accountFromId(dynamic id) {
    if (id == null) return null;
    final n = id is num ? id.toInt() : int.tryParse('$id');
    if (n == null) return null;
    return Account(id: n, code: '', name: '#$n', accountType: '');
  }

  String _factorToReductionPercent(dynamic factor, {String fallback = '0'}) {
    final f = parseFormattedDouble('$factor');
    if (f == null) return fallback;
    final pct = ((1 - f) * 100);
    if ((pct - pct.round()).abs() < 0.0001) return '${pct.round()}';
    return pct.toStringAsFixed(2);
  }

  double _reductionPercentToFactor(String raw, {double fallback = 0}) {
    final pct = parseFormattedDouble(raw) ?? fallback;
    var factor = (100 - pct) / 100;
    if (factor < 0) factor = 0;
    if (factor > 1) factor = 1;
    return factor;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _svc.getSettings(businessId: widget.businessId),
        _svc.listClasses(businessId: widget.businessId, includeInactive: true),
      ]);
      if (!mounted) return;
      final settings = Map<String, dynamic>.from(results[0] as Map);
      setState(() {
        _settings = settings;
        _classes = List<Map<String, dynamic>>.from(results[1] as List);
        _enabled = settings['enabled'] == true;
        _requireCustodian = settings['require_custodian'] == true;
        _convention = '${settings['accounting_convention'] ?? 'from_ready_date'}';
        _prefixCtrl.text = '${settings['plaque_prefix'] ?? 'FA'}';
        _idleMonthsCtrl.text = '${settings['tax_idle_months'] ?? 6}';
        _taxReductionCtrl.text = _factorToReductionPercent(settings['tax_idle_factor'], fallback: '30');
        _accountingReductionCtrl.text =
            _factorToReductionPercent(settings['accounting_idle_factor'], fallback: '0');
        _vatIn = _accountFromId(settings['vat_account_id']);
        _vatOut = _accountFromId(settings['vat_output_account_id']);
        _openingEquity = _accountFromId(settings['opening_equity_account_id']);
        _gain = _accountFromId(settings['disposal_gain_account_id']);
        _loss = _accountFromId(settings['disposal_loss_account_id']);
        _repair = _accountFromId(settings['repair_expense_account_id']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _save(Map<String, dynamic> patch) async {
    if (!_canManage) return;
    setState(() => _saving = true);
    try {
      final updated = await _svc.updateSettings(businessId: widget.businessId, payload: patch);
      if (!mounted) return;
      setState(() {
        _settings = updated;
        _saving = false;
      });
      SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).fixedAssetsSaved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _saveLegalAndWorkflow() async {
    final months = parseFormattedInt(_idleMonthsCtrl.text) ?? 6;
    await _save({
      'enabled': _enabled,
      'require_custodian': _requireCustodian,
      'accounting_convention': _convention,
      'plaque_prefix': _prefixCtrl.text.trim(),
      'tax_idle_months': months,
      'tax_idle_factor': _reductionPercentToFactor(_taxReductionCtrl.text, fallback: 30),
      'accounting_idle_factor': _reductionPercentToFactor(_accountingReductionCtrl.text, fallback: 0),
    });
  }

  Future<void> _saveAccounts() async {
    await _save({
      'vat_account_id': _vatIn?.id,
      'vat_output_account_id': _vatOut?.id,
      'opening_equity_account_id': _openingEquity?.id,
      'disposal_gain_account_id': _gain?.id,
      'disposal_loss_account_id': _loss?.id,
      'repair_expense_account_id': _repair?.id,
    });
  }

  Future<void> _saveClassAccounts(Map<String, dynamic> cls, {
    Account? cost,
    Account? accum,
    Account? expense,
  }) async {
    if (!_canManage) return;
    setState(() => _saving = true);
    try {
      await _svc.updateClass(
        businessId: widget.businessId,
        classId: int.parse('${cls['id']}'),
        payload: {
          'cost_account_id': cost?.id,
          'accum_dep_account_id': accum?.id,
          'dep_expense_account_id': expense?.id,
        },
      );
      await _load();
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).fixedAssetsSaved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Widget _section({required String title, required IconData icon, required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!_canView) {
      return PermissionGuard.buildAccessDeniedPage();
    }
    final codes = Map<String, dynamic>.from(_settings['default_codes'] as Map? ?? const {});
    return Scaffold(
      appBar: AppBar(
        leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
        title: Text(t.fixedAssetsSettingsPageTitle),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section(
                  title: t.fixedAssetsEnabled,
                  icon: Icons.power_settings_new,
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.fixedAssetsEnabled),
                    subtitle: Text(t.fixedAssetsEnabledHint),
                    value: _enabled,
                    onChanged: _canManage && !_saving
                        ? (v) {
                            setState(() => _enabled = v);
                            _save({'enabled': v});
                          }
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                _section(
                  title: t.fixedAssetsLegalRules,
                  icon: Icons.gavel_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.fixedAssetsLegalRulesHint, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 12),
                      Text(t.fixedAssetsConventionHint, style: Theme.of(context).textTheme.bodySmall),
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        value: 'from_ready_date',
                        groupValue: _convention,
                        title: Text(t.fixedAssetsConventionFromReady),
                        onChanged: _canManage && !_saving
                            ? (v) => setState(() => _convention = v!)
                            : null,
                      ),
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        value: 'next_month',
                        groupValue: _convention,
                        title: Text(t.fixedAssetsConventionNextMonth),
                        onChanged: _canManage && !_saving
                            ? (v) => setState(() => _convention = v!)
                            : null,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _idleMonthsCtrl,
                        enabled: _canManage && !_saving,
                        keyboardType: TextInputType.number,
                        decoration: FixedAssetsUi.fieldDecoration(context, t.fixedAssetsTaxIdleMonths),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _taxReductionCtrl,
                        enabled: _canManage && !_saving,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: FixedAssetsUi.fieldDecoration(context, t.fixedAssetsTaxIdleReduction),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _accountingReductionCtrl,
                        enabled: _canManage && !_saving,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: FixedAssetsUi.fieldDecoration(context, t.fixedAssetsAccountingIdleReduction),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _prefixCtrl,
                        enabled: _canManage && !_saving,
                        decoration: FixedAssetsUi.fieldDecoration(context, t.fixedAssetsPlaquePrefix),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t.fixedAssetsRequireCustodian),
                        value: _requireCustodian,
                        onChanged: _canManage && !_saving
                            ? (v) => setState(() => _requireCustodian = v)
                            : null,
                      ),
                      if (_canManage)
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: FilledButton(
                            onPressed: _saving ? null : _saveLegalAndWorkflow,
                            child: Text(t.save),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _section(
                  title: t.fixedAssetsSaveAccounts,
                  icon: Icons.account_balance_outlined,
                  child: Column(
                    children: [
                      AccountTreeComboboxWidget(
                        businessId: widget.businessId,
                        selectedAccount: _vatIn,
                        label: '${t.fixedAssetsVatInputAccount} (${codes['vat_input'] ?? '10104'})',
                        dense: true,
                        onChanged: (a) => setState(() => _vatIn = a),
                      ),
                      const SizedBox(height: 12),
                      AccountTreeComboboxWidget(
                        businessId: widget.businessId,
                        selectedAccount: _vatOut,
                        label: '${t.fixedAssetsVatOutputAccount} (${codes['vat_output'] ?? '20101'})',
                        dense: true,
                        onChanged: (a) => setState(() => _vatOut = a),
                      ),
                      const SizedBox(height: 12),
                      AccountTreeComboboxWidget(
                        businessId: widget.businessId,
                        selectedAccount: _openingEquity,
                        label: t.fixedAssetsOpeningEquityAccount,
                        dense: true,
                        onChanged: (a) => setState(() => _openingEquity = a),
                      ),
                      const SizedBox(height: 12),
                      AccountTreeComboboxWidget(
                        businessId: widget.businessId,
                        selectedAccount: _gain,
                        label: '${t.fixedAssetsGainAccount} (${codes['gain_disposal'] ?? '60206'})',
                        dense: true,
                        onChanged: (a) => setState(() => _gain = a),
                      ),
                      const SizedBox(height: 12),
                      AccountTreeComboboxWidget(
                        businessId: widget.businessId,
                        selectedAccount: _loss,
                        label: '${t.fixedAssetsLossAccount} (${codes['loss_disposal'] ?? '70804'})',
                        dense: true,
                        onChanged: (a) => setState(() => _loss = a),
                      ),
                      const SizedBox(height: 12),
                      AccountTreeComboboxWidget(
                        businessId: widget.businessId,
                        selectedAccount: _repair,
                        label: '${t.fixedAssetsRepairAccount} (${codes['repair_expense'] ?? '70404'})',
                        dense: true,
                        onChanged: (a) => setState(() => _repair = a),
                      ),
                      const SizedBox(height: 12),
                      if (_canManage)
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: FilledButton(
                            onPressed: _saving ? null : _saveAccounts,
                            child: Text(t.save),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _section(
                  title: t.fixedAssetsClassesHint,
                  icon: Icons.category_outlined,
                  child: Column(
                    children: [
                      for (final cls in _classes) _ClassAccountEditor(
                        businessId: widget.businessId,
                        cls: cls,
                        canManage: _canManage && !_saving,
                        notDepreciableLabel: t.fixedAssetsNotDepreciable,
                        costLabel: t.fixedAssetsClassCostAccount,
                        accumLabel: t.fixedAssetsClassAccumAccount,
                        expenseLabel: t.fixedAssetsClassExpenseAccount,
                        saveLabel: t.save,
                        onSave: (cost, accum, expense) => _saveClassAccounts(
                          cls,
                          cost: cost,
                          accum: accum,
                          expense: expense,
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

class _ClassAccountEditor extends StatefulWidget {
  final int businessId;
  final Map<String, dynamic> cls;
  final bool canManage;
  final String notDepreciableLabel;
  final String costLabel;
  final String accumLabel;
  final String expenseLabel;
  final String saveLabel;
  final Future<void> Function(Account? cost, Account? accum, Account? expense) onSave;

  const _ClassAccountEditor({
    required this.businessId,
    required this.cls,
    required this.canManage,
    required this.notDepreciableLabel,
    required this.costLabel,
    required this.accumLabel,
    required this.expenseLabel,
    required this.saveLabel,
    required this.onSave,
  });

  @override
  State<_ClassAccountEditor> createState() => _ClassAccountEditorState();
}

class _ClassAccountEditorState extends State<_ClassAccountEditor> {
  Account? _cost;
  Account? _accum;
  Account? _expense;

  @override
  void initState() {
    super.initState();
    _apply(widget.cls);
  }

  @override
  void didUpdateWidget(covariant _ClassAccountEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cls['id'] != widget.cls['id'] ||
        oldWidget.cls['cost_account_id'] != widget.cls['cost_account_id'] ||
        oldWidget.cls['accum_dep_account_id'] != widget.cls['accum_dep_account_id'] ||
        oldWidget.cls['dep_expense_account_id'] != widget.cls['dep_expense_account_id']) {
      _apply(widget.cls);
    }
  }

  void _apply(Map<String, dynamic> cls) {
    _cost = _from(cls['cost_account_id'], cls['cost_account_code']);
    _accum = _from(cls['accum_dep_account_id'], cls['accum_dep_account_code']);
    _expense = _from(cls['dep_expense_account_id'], cls['dep_expense_account_code']);
  }

  Account? _from(dynamic id, dynamic code) {
    final n = id is num ? id.toInt() : int.tryParse('$id');
    if (n == null) return null;
    final codeS = '${code ?? ''}';
    return Account(id: n, code: codeS, name: codeS.isEmpty ? '#$n' : codeS, accountType: '');
  }

  @override
  Widget build(BuildContext context) {
    final depreciable = widget.cls['depreciable'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${widget.cls['name']} (${widget.cls['code']})'
            '${depreciable ? '' : ' — ${widget.notDepreciableLabel}'}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          AccountTreeComboboxWidget(
            businessId: widget.businessId,
            selectedAccount: _cost,
            label: widget.costLabel,
            dense: true,
            onChanged: (a) => setState(() => _cost = a),
          ),
          if (depreciable) ...[
            const SizedBox(height: 14),
            AccountTreeComboboxWidget(
              businessId: widget.businessId,
              selectedAccount: _accum,
              label: widget.accumLabel,
              dense: true,
              onChanged: (a) => setState(() => _accum = a),
            ),
            const SizedBox(height: 14),
            AccountTreeComboboxWidget(
              businessId: widget.businessId,
              selectedAccount: _expense,
              label: widget.expenseLabel,
              dense: true,
              onChanged: (a) => setState(() => _expense = a),
            ),
          ],
          if (widget.canManage)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => widget.onSave(_cost, _accum, _expense),
                child: Text(widget.saveLabel),
              ),
            ),
        ],
      ),
    );
  }
}
