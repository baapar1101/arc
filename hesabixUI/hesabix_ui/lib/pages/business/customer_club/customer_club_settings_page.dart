import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/auth_store.dart';
import '../../../services/customer_club_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/business_subpage_back_leading.dart';

/// تنظیمات قوانین باشگاه مشتریان (مسیر جدا از صفحهٔ تراکنش‌ها).
class CustomerClubSettingsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const CustomerClubSettingsPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<CustomerClubSettingsPage> createState() => _CustomerClubSettingsPageState();
}

class _CustomerClubSettingsPageState extends State<CustomerClubSettingsPage> {
  final CustomerClubService _svc = CustomerClubService();

  bool _loadingSettings = true;

  bool _enabled = true;
  String _earnMode = 'percent_basis';
  String _amountBasis = 'net';
  final TextEditingController _percentCtl = TextEditingController();
  final TextEditingController _stepAmtCtl = TextEditingController();
  final TextEditingController _ptsPerStepCtl = TextEditingController();
  final TextEditingController _maxPtsCtl = TextEditingController();
  final TextEditingController _minBasisCtl = TextEditingController(text: '0');
  final TextEditingController _currencyValuePerPointCtl = TextEditingController();
  final TextEditingController _maxRedeemPerInvCtl = TextEditingController();
  final TextEditingController _pointsExpireDaysCtl = TextEditingController();
  String _rounding = 'floor';
  bool _requireCustomerType = true;

  bool _rfmAnalyticsEnabled = false;
  bool _clvAnalyticsEnabled = false;
  final TextEditingController _rfmWindowMonthsCtl = TextEditingController(text: '12');
  String _rfmMonetaryBasis = 'net';
  String _rfmScoringMethod = 'quintiles';
  final TextEditingController _rfmWeightRCtl = TextEditingController();
  final TextEditingController _rfmWeightFCtl = TextEditingController();
  final TextEditingController _rfmWeightMCtl = TextEditingController();
  String _clvFormula = 'historical_total';
  final TextEditingController _clvLifespanCtl = TextEditingController(text: '3');
  String _loyaltyRfmIntegrationMode = 'decoupled';

  bool _computeCanManage() {
    return widget.authStore.currentBusiness?.isOwner == true ||
        widget.authStore.hasBusinessPermission('customer_club', 'manage');
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _percentCtl.dispose();
    _stepAmtCtl.dispose();
    _ptsPerStepCtl.dispose();
    _maxPtsCtl.dispose();
    _minBasisCtl.dispose();
    _currencyValuePerPointCtl.dispose();
    _maxRedeemPerInvCtl.dispose();
    _pointsExpireDaysCtl.dispose();
    _rfmWindowMonthsCtl.dispose();
    _rfmWeightRCtl.dispose();
    _rfmWeightFCtl.dispose();
    _rfmWeightMCtl.dispose();
    _clvLifespanCtl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    if (!mounted) return;
    setState(() => _loadingSettings = true);
    try {
      final data = await _svc.getSettings(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _enabled = data['enabled'] == true;
        _earnMode = (data['earn_mode'] ?? 'percent_basis').toString();
        _amountBasis = (data['amount_basis'] ?? 'net').toString();
        _percentCtl.text = _fmtNum(data['percent_of_basis']);
        _stepAmtCtl.text = _fmtNum(data['step_currency_amount']);
        _ptsPerStepCtl.text = _fmtNum(data['points_per_step']);
        _maxPtsCtl.text = _fmtNum(data['max_points_per_invoice']);
        _minBasisCtl.text = _fmtNum(data['min_basis_amount']);
        _currencyValuePerPointCtl.text = _fmtNum(data['currency_value_per_point']);
        _maxRedeemPerInvCtl.text = _fmtNum(data['max_redeem_points_per_invoice']);
        final exp = data['points_expire_after_days'];
        _pointsExpireDaysCtl.text = exp == null ? '' : exp.toString();
        _rounding = (data['rounding_mode'] ?? 'floor').toString();
        _requireCustomerType = data['require_customer_person_type'] != false;
        _rfmAnalyticsEnabled = data['rfm_analytics_enabled'] == true;
        _clvAnalyticsEnabled = data['clv_analytics_enabled'] == true;
        _rfmWindowMonthsCtl.text = '${data['rfm_analysis_window_months'] ?? 12}';
        _rfmMonetaryBasis = (data['rfm_monetary_basis'] ?? 'net').toString();
        _rfmScoringMethod = (data['rfm_scoring_method'] ?? 'quintiles').toString();
        _rfmWeightRCtl.text = _fmtNum(data['rfm_weight_recency']);
        _rfmWeightFCtl.text = _fmtNum(data['rfm_weight_frequency']);
        _rfmWeightMCtl.text = _fmtNum(data['rfm_weight_monetary']);
        _clvFormula = (data['clv_formula'] ?? 'historical_total').toString();
        _clvLifespanCtl.text = _fmtNum(data['clv_avg_lifespan_years']);
        _loyaltyRfmIntegrationMode = (data['loyalty_rfm_integration_mode'] ?? 'decoupled').toString();
      });
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loadingSettings = false);
    }
  }

  String _fmtNum(dynamic v) {
    if (v == null) return '';
    if (v is num && v == v.roundToDouble()) return v.toStringAsFixed(0).replaceFirst(RegExp(r'\.?0+$'), '');
    return v.toString();
  }

  String _composeSettingsSummary(AppLocalizations t) {
    if (!_enabled) return t.customerClubSummaryInactive;
    final basisLabel = _amountBasis == 'net' ? t.customerClubBasisNet : t.customerClubBasisTotal;
    if (_earnMode == 'percent_basis') {
      final p = _percentCtl.text.trim();
      return '${t.customerClubEarnPercent}${p.isEmpty ? '' : ': $p'} · ${t.customerClubAmountBasis}: $basisLabel';
    }
    return '${t.customerClubEarnPerCurrency} · ${t.customerClubAmountBasis}: $basisLabel';
  }

  Widget _settingsSummaryBanner(ThemeData theme, AppLocalizations t) {
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.customerClubSettingsSummaryTitle,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(_composeSettingsSummary(t), style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required ThemeData theme,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              children[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _roundingModeMenuItem(String value, AppLocalizations t) {
    final label = switch (value) {
      'floor' => t.customerClubRoundingFloor,
      'ceil' => t.customerClubRoundingCeil,
      'round' => t.customerClubRoundingRound,
      _ => value,
    };
    return Text(label);
  }

  Future<void> _saveSettings() async {
    final t = AppLocalizations.of(context);
    try {
      final payload = <String, dynamic>{
        'enabled': _enabled,
        'earn_mode': _earnMode,
        'amount_basis': _amountBasis,
        'rounding_mode': _rounding,
        'require_customer_person_type': _requireCustomerType,
        'percent_of_basis': _parseDoubleOrNull(_percentCtl.text),
        'step_currency_amount': _parseDoubleOrNull(_stepAmtCtl.text),
        'points_per_step': _parseDoubleOrNull(_ptsPerStepCtl.text),
        'max_points_per_invoice': _parseDoubleOrNull(_maxPtsCtl.text),
        'min_basis_amount': double.tryParse(_minBasisCtl.text.trim()) ?? 0,
        'currency_value_per_point': _parseDoubleOrNull(_currencyValuePerPointCtl.text),
        'max_redeem_points_per_invoice': _parseDoubleOrNull(_maxRedeemPerInvCtl.text),
        'points_expire_after_days': _parseOptionalIntNull(_pointsExpireDaysCtl.text),
        'rfm_analytics_enabled': _rfmAnalyticsEnabled,
        'clv_analytics_enabled': _clvAnalyticsEnabled,
        'rfm_analysis_window_months': int.tryParse(_rfmWindowMonthsCtl.text.trim().replaceAll(',', '')) ?? 12,
        'rfm_monetary_basis': _rfmMonetaryBasis,
        'rfm_scoring_method': _rfmScoringMethod,
        'rfm_weight_recency': _parseDoubleOrNull(_rfmWeightRCtl.text),
        'rfm_weight_frequency': _parseDoubleOrNull(_rfmWeightFCtl.text),
        'rfm_weight_monetary': _parseDoubleOrNull(_rfmWeightMCtl.text),
        'clv_formula': _clvFormula,
        'clv_avg_lifespan_years': _parseDoubleOrNull(_clvLifespanCtl.text),
        'loyalty_rfm_integration_mode': _loyaltyRfmIntegrationMode,
      };
      await _svc.updateSettings(businessId: widget.businessId, payload: payload);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: t.customerClubSettingsSaved);
      await _loadSettings();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  double? _parseDoubleOrNull(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t.replaceAll(',', ''));
  }

  int? _parseOptionalIntNull(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t.replaceAll(',', ''));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final canManage = _computeCanManage();

    return Scaffold(
      appBar: AppBar(
        title: Text('${t.customerClubMenu} — ${t.customerClubTabSettings}'),
        leading: businessSubpageBackLeading(context, widget.businessId),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save_outlined),
              label: Text(t.save),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: _loadingSettings
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _settingsSummaryBanner(theme, t),
                  const SizedBox(height: 24),
                  _sectionCard(
                    theme: theme,
                    title: t.customerClubSettingsSectionActivation,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t.customerClubEnabled),
                        value: _enabled,
                        onChanged: canManage ? (v) => setState(() => _enabled = v) : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _sectionCard(
                    theme: theme,
                    title: t.customerClubSettingsSectionEarning,
                    children: _earningFields(t, canManage),
                  ),
                  const SizedBox(height: 24),
                  _sectionCard(
                    theme: theme,
                    title: t.customerClubRedemptionSection,
                    children: [
                      TextField(
                        controller: _currencyValuePerPointCtl,
                        decoration: InputDecoration(
                          labelText: t.customerClubCurrencyValuePerPoint,
                          helperText: t.customerClubCurrencyValuePerPointHint,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        readOnly: !canManage,
                        onChanged: (_) => setState(() {}),
                      ),
                      TextField(
                        controller: _maxRedeemPerInvCtl,
                        decoration: InputDecoration(labelText: t.customerClubMaxRedeemPerInvoice),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        readOnly: !canManage,
                        onChanged: (_) => setState(() {}),
                      ),
                      TextField(
                        controller: _pointsExpireDaysCtl,
                        decoration: InputDecoration(
                          labelText: t.customerClubPointsExpireAfterDays,
                          helperText: t.customerClubPointsExpireAfterDaysHint,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        readOnly: !canManage,
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _sectionCard(
                    theme: theme,
                    title: t.customerClubSettingsSectionLoyaltyRfm,
                    children: [
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: t.customerClubLoyaltyRfmMode,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                        ),
                        value: _loyaltyRfmIntegrationMode == 'rfm_based_tiers' ? 'rfm_based_tiers' : 'decoupled',
                        items: [
                          DropdownMenuItem(value: 'decoupled', child: Text(t.customerClubLoyaltyRfmDecoupled)),
                          DropdownMenuItem(value: 'rfm_based_tiers', child: Text(t.customerClubLoyaltyRfmTiers)),
                        ],
                        onChanged: canManage
                            ? (v) {
                                if (v != null) setState(() => _loyaltyRfmIntegrationMode = v);
                              }
                            : null,
                      ),
                      Material(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.link, size: 20, color: theme.colorScheme.primary),
                              const SizedBox(width: 10),
                              Expanded(child: Text(t.customerClubLoyaltyRfmHint, style: theme.textTheme.bodySmall)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _sectionCard(
                    theme: theme,
                    title: t.customerClubSettingsSectionAnalytics,
                    children: _analyticsFields(t, canManage),
                  ),
                  const SizedBox(height: 24),
                  _sectionCard(
                    theme: theme,
                    title: t.customerClubSettingsSectionAccess,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t.customerClubRequireCustomerType),
                        value: _requireCustomerType,
                        onChanged: canManage ? (v) => setState(() => _requireCustomerType = v) : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  List<Widget> _earningFields(AppLocalizations t, bool canManage) {
    return [
      DropdownButtonFormField<String>(
        decoration: InputDecoration(labelText: t.customerClubEarnMode),
        value: _earnMode,
        items: [
          DropdownMenuItem(value: 'percent_basis', child: Text(t.customerClubEarnPercent)),
          DropdownMenuItem(value: 'points_per_currency', child: Text(t.customerClubEarnPerCurrency)),
        ],
        onChanged: canManage
            ? (v) {
                if (v != null) setState(() => _earnMode = v);
              }
            : null,
      ),
      DropdownButtonFormField<String>(
        decoration: InputDecoration(labelText: t.customerClubAmountBasis),
        value: _amountBasis,
        items: [
          DropdownMenuItem(value: 'net', child: Text(t.customerClubBasisNet)),
          DropdownMenuItem(value: 'total_with_tax', child: Text(t.customerClubBasisTotal)),
        ],
        onChanged: canManage
            ? (v) {
                if (v != null) setState(() => _amountBasis = v);
              }
            : null,
      ),
      if (_earnMode == 'percent_basis')
        TextField(
          controller: _percentCtl,
          decoration: InputDecoration(
            labelText: t.customerClubPercentOfBasis,
            helperText: t.customerClubPercentHint,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          readOnly: !canManage,
          onChanged: (_) => setState(() {}),
        ),
      if (_earnMode == 'points_per_currency') ...[
        TextField(
          controller: _stepAmtCtl,
          decoration: InputDecoration(labelText: t.customerClubStepAmount),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          readOnly: !canManage,
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          controller: _ptsPerStepCtl,
          decoration: InputDecoration(labelText: t.customerClubPointsPerStep),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          readOnly: !canManage,
          onChanged: (_) => setState(() {}),
        ),
      ],
      DropdownButtonFormField<String>(
        decoration: InputDecoration(labelText: t.customerClubRounding),
        value: _rounding,
        items: [
          DropdownMenuItem(value: 'floor', child: _roundingModeMenuItem('floor', t)),
          DropdownMenuItem(value: 'ceil', child: _roundingModeMenuItem('ceil', t)),
          DropdownMenuItem(value: 'round', child: _roundingModeMenuItem('round', t)),
        ],
        onChanged: canManage
            ? (v) {
                if (v != null) setState(() => _rounding = v);
              }
            : null,
      ),
      TextField(
        controller: _maxPtsCtl,
        decoration: InputDecoration(labelText: t.customerClubMaxPointsInvoice),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        readOnly: !canManage,
        onChanged: (_) => setState(() {}),
      ),
      TextField(
        controller: _minBasisCtl,
        decoration: InputDecoration(labelText: t.customerClubMinBasis),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        readOnly: !canManage,
        onChanged: (_) => setState(() {}),
      ),
    ];
  }

  List<Widget> _analyticsFields(AppLocalizations t, bool canManage) {
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(t.customerClubRfmEnabled),
        value: _rfmAnalyticsEnabled,
        onChanged: canManage ? (v) => setState(() => _rfmAnalyticsEnabled = v) : null,
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(t.customerClubClvEnabled),
        value: _clvAnalyticsEnabled,
        onChanged: canManage ? (v) => setState(() => _clvAnalyticsEnabled = v) : null,
      ),
      TextField(
        controller: _rfmWindowMonthsCtl,
        decoration: InputDecoration(labelText: t.customerClubRfmWindowMonths),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        readOnly: !canManage,
        onChanged: (_) => setState(() {}),
      ),
      DropdownButtonFormField<String>(
        decoration: InputDecoration(labelText: t.customerClubRfmMonetaryBasisLabel),
        value: _rfmMonetaryBasis,
        items: [
          DropdownMenuItem(value: 'net', child: Text(t.customerClubBasisNet)),
          DropdownMenuItem(value: 'total_with_tax', child: Text(t.customerClubBasisTotal)),
        ],
        onChanged: canManage
            ? (v) {
                if (v != null) setState(() => _rfmMonetaryBasis = v);
              }
            : null,
      ),
      DropdownButtonFormField<String>(
        decoration: InputDecoration(labelText: t.customerClubRfmScoringLabel),
        value: _rfmScoringMethod,
        items: [
          DropdownMenuItem(value: 'quintiles', child: Text(t.customerClubRfmScoringQuintiles)),
          DropdownMenuItem(value: 'weighted', child: Text(t.customerClubRfmScoringWeighted)),
        ],
        onChanged: canManage
            ? (v) {
                if (v != null) setState(() => _rfmScoringMethod = v);
              }
            : null,
      ),
      if (_rfmScoringMethod == 'weighted') ...[
        TextField(
          controller: _rfmWeightRCtl,
          decoration: InputDecoration(labelText: t.customerClubRfmWeightR),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          readOnly: !canManage,
        ),
        TextField(
          controller: _rfmWeightFCtl,
          decoration: InputDecoration(labelText: t.customerClubRfmWeightF),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          readOnly: !canManage,
        ),
        TextField(
          controller: _rfmWeightMCtl,
          decoration: InputDecoration(labelText: t.customerClubRfmWeightM),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          readOnly: !canManage,
        ),
      ],
      DropdownButtonFormField<String>(
        decoration: InputDecoration(labelText: t.customerClubClvFormulaLabel),
        value: _clvFormula,
        items: [
          DropdownMenuItem(value: 'historical_total', child: Text(t.customerClubClvFormulaHistorical)),
          DropdownMenuItem(value: 'avg_order_projection', child: Text(t.customerClubClvFormulaProjection)),
        ],
        onChanged: canManage
            ? (v) {
                if (v != null) setState(() => _clvFormula = v);
              }
            : null,
      ),
      TextField(
        controller: _clvLifespanCtl,
        decoration: InputDecoration(
          labelText: t.customerClubClvLifespanYears,
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        readOnly: !canManage,
      ),
      Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(t.customerClubAnalyticsHint, style: Theme.of(context).textTheme.bodySmall)),
            ],
          ),
        ),
      ),
    ];
  }
}
