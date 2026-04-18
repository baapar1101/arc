import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/api_client.dart';
import '../../../core/auth_store.dart';
import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart';
import '../../../services/customer_club_service.dart';
import '../../../utils/snackbar_helper.dart';

/// صفحهٔ اصلی باشگاه مشتریان (تراکنش‌ها، تنظیمات، اصلاح دستی).
class CustomerClubMainPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController? calendarController;

  const CustomerClubMainPage({
    super.key,
    required this.businessId,
    required this.authStore,
    this.calendarController,
  });

  @override
  State<CustomerClubMainPage> createState() => _CustomerClubMainPageState();
}

class _CustomerClubMainPageState extends State<CustomerClubMainPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final CustomerClubService _svc = CustomerClubService();

  List<Map<String, dynamic>> _ledgerRows = [];
  int _ledgerTotal = 0;
  final int _pageSize = 30;

  bool _loadingSettings = true;
  bool _loadingLedger = true;

  /// فرم تنظیمات
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

  /// فرم اصلاح دستی
  final TextEditingController _adjustPersonCtl = TextEditingController();
  final TextEditingController _adjustDeltaCtl = TextEditingController();
  final TextEditingController _adjustDescCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    widget.calendarController?.addListener(_onCalendarChanged);
    _reloadAll();
  }

  void _onCalendarChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.calendarController?.removeListener(_onCalendarChanged);
    _tabController.dispose();
    _percentCtl.dispose();
    _stepAmtCtl.dispose();
    _ptsPerStepCtl.dispose();
    _maxPtsCtl.dispose();
    _minBasisCtl.dispose();
    _currencyValuePerPointCtl.dispose();
    _maxRedeemPerInvCtl.dispose();
    _pointsExpireDaysCtl.dispose();
    _adjustPersonCtl.dispose();
    _adjustDeltaCtl.dispose();
    _adjustDescCtl.dispose();
    super.dispose();
  }

  Future<void> _reloadAll() async {
    await Future.wait([_loadSettings(), _loadLedger(reset: true)]);
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
      });
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: '$e');
    } finally {
      if (mounted) setState(() => _loadingSettings = false);
    }
  }

  String _fmtNum(dynamic v) {
    if (v == null) return '';
    if (v is num && v == v.roundToDouble()) return v.toStringAsFixed(0).replaceFirst(RegExp(r'\.?0+$'), '');
    return v.toString();
  }

  bool get _isJalaliCalendar =>
      widget.calendarController?.isJalali ?? ApiClient.getCalendarController()?.isJalali ?? true;

  /// زمان ثبت تراکنش در دفتر؛ متن خام API را با تقویم انتخاب‌شده کاربر نشان می‌دهد.
  String _formatLedgerCreatedAt(dynamic raw) {
    if (raw == null) return '';
    final s = raw.toString().trim();
    if (s.isEmpty) return '';
    final parsed = DateTime.tryParse(s);
    if (parsed == null) return s;
    return HesabixDateUtils.formatDateTime(parsed.toLocal(), _isJalaliCalendar);
  }

  String _transactionTypeLabel(AppLocalizations t, String? raw) {
    switch (raw) {
      case 'adjustment':
        return t.customerClubTxnAdjustment;
      case 'redeem':
        return t.customerClubTxnRedeem;
      case 'redeem_void':
        return t.customerClubTxnRedeemVoid;
      case 'invoice_sync':
        return t.customerClubTxnInvoiceSync;
      case 'invoice_delete_reversal':
        return t.customerClubTxnInvoiceDeleteReversal;
      case 'invoice_delete_reversal_redeem':
        return t.customerClubTxnInvoiceDeleteReversalRedeem;
      default:
        return raw ?? '—';
    }
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
      };
      await _svc.updateSettings(businessId: widget.businessId, payload: payload);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: t.customerClubSettingsSaved);
      await _loadSettings();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: '$e');
    }
  }

  double? _parseDoubleOrNull(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t.replaceAll(',', ''));
  }

  /// خالی = بدون انقضا (null در API)
  int? _parseOptionalIntNull(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t.replaceAll(',', ''));
  }

  Future<void> _loadLedger({bool reset = false, bool append = false}) async {
    if (!mounted) return;
    setState(() => _loadingLedger = true);
    final skip = append ? _ledgerRows.length : 0;
    try {
      final data = await _svc.listLedger(
        businessId: widget.businessId,
        limit: _pageSize,
        skip: skip,
      );
      if (!mounted) return;
      final items = data['items'];
      final total = data['total'];
      final list = <Map<String, dynamic>>[];
      if (items is List) {
        for (final e in items) {
          if (e is Map) {
            list.add(Map<String, dynamic>.from(e));
          }
        }
      }
      setState(() {
        if (append && !reset) {
          _ledgerRows = [..._ledgerRows, ...list];
        } else {
          _ledgerRows = list;
        }
        _ledgerTotal = total is int ? total : int.tryParse('$total') ?? 0;
      });
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: '$e');
    } finally {
      if (mounted) setState(() => _loadingLedger = false);
    }
  }

  Future<void> _submitAdjustment() async {
    final t = AppLocalizations.of(context);
    final pid = int.tryParse(_adjustPersonCtl.text.trim());
    final delta = double.tryParse(_adjustDeltaCtl.text.trim().replaceAll(',', ''));
    final desc = _adjustDescCtl.text.trim();
    if (pid == null || pid <= 0) {
      SnackBarHelper.showError(context, message: t.customerClubInvalidPersonId);
      return;
    }
    if (delta == null) {
      SnackBarHelper.showError(context, message: t.customerClubInvalidDelta);
      return;
    }
    if (desc.isEmpty) {
      SnackBarHelper.showError(context, message: t.customerClubDescriptionRequired);
      return;
    }
    try {
      await _svc.submitAdjustment(
        businessId: widget.businessId,
        personId: pid,
        deltaPoints: delta,
        description: desc,
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: t.customerClubAdjustmentSaved);
      _adjustDeltaCtl.clear();
      _adjustDescCtl.clear();
      await _loadLedger(reset: true);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final canManage = widget.authStore.currentBusiness?.isOwner == true ||
        widget.authStore.hasBusinessPermission('customer_club', 'manage');
    final canAdjust = widget.authStore.currentBusiness?.isOwner == true ||
        widget.authStore.hasBusinessPermission('customer_club', 'adjust');

    return Scaffold(
      appBar: AppBar(
        title: Text(t.customerClubTitle),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: t.customerClubTabLedger),
            Tab(text: t.customerClubTabSettings),
            Tab(text: t.customerClubTabAdjust),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLedgerTab(theme, t),
          _buildSettingsTab(theme, t, canManage),
          _buildAdjustTab(theme, t, canAdjust),
        ],
      ),
    );
  }

  Widget _buildLedgerTab(ThemeData theme, AppLocalizations t) {
    if (_loadingLedger && _ledgerRows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final hasMore = _ledgerRows.length < _ledgerTotal;
    return RefreshIndicator(
      onRefresh: () => _loadLedger(reset: true),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Text(
                  '${t.customerClubLedgerTotal}: $_ledgerTotal',
                  style: theme.textTheme.titleSmall,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _loadLedger(reset: true),
                  icon: const Icon(Icons.refresh),
                  label: Text(t.refresh),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _ledgerRows.length + (hasMore ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i >= _ledgerRows.length) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: OutlinedButton(
                        onPressed: _loadingLedger
                            ? null
                            : () async {
                                await _loadLedger(append: true);
                              },
                        child: Text(t.customerClubLoadMore),
                      ),
                    ),
                  );
                }
                final r = _ledgerRows[i];
                final dt = _formatLedgerCreatedAt(r['created_at']);
                final docId = r['reference_document_id'];
                final txnRaw = r['transaction_type']?.toString();
                final txnLabel = _transactionTypeLabel(t, txnRaw);
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    title: Text(
                      '${r['delta_points']} ${t.customerClubPointsShort} — $txnLabel',
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: Text(
                      '${t.customerClubBalanceAfter}: ${r['balance_after']} | '
                      '${t.customerClubPerson}: ${r['person_id'] ?? '-'}'
                      '${docId != null ? ' | ${t.customerClubReferenceDocument}: $docId' : ''}\n'
                      '${r['description'] ?? ''}${dt.isEmpty ? '' : '\n$dt'}',
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab(ThemeData theme, AppLocalizations t, bool canManage) {
    if (_loadingSettings) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            title: Text(t.customerClubEnabled),
            value: _enabled,
            onChanged: canManage ? (v) => setState(() => _enabled = v) : null,
          ),
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
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          TextField(
            controller: _percentCtl,
            decoration: InputDecoration(
              labelText: t.customerClubPercentOfBasis,
              helperText: t.customerClubPercentHint,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            readOnly: !canManage,
          ),
          TextField(
            controller: _stepAmtCtl,
            decoration: InputDecoration(labelText: t.customerClubStepAmount),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            readOnly: !canManage,
          ),
          TextField(
            controller: _ptsPerStepCtl,
            decoration: InputDecoration(labelText: t.customerClubPointsPerStep),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            readOnly: !canManage,
          ),
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
          ),
          TextField(
            controller: _minBasisCtl,
            decoration: InputDecoration(labelText: t.customerClubMinBasis),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            readOnly: !canManage,
          ),
          const SizedBox(height: 20),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              t.customerClubRedemptionSection,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _currencyValuePerPointCtl,
            decoration: InputDecoration(
              labelText: t.customerClubCurrencyValuePerPoint,
              helperText: t.customerClubCurrencyValuePerPointHint,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            readOnly: !canManage,
          ),
          TextField(
            controller: _maxRedeemPerInvCtl,
            decoration: InputDecoration(labelText: t.customerClubMaxRedeemPerInvoice),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            readOnly: !canManage,
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
          ),
          SwitchListTile(
            title: Text(t.customerClubRequireCustomerType),
            value: _requireCustomerType,
            onChanged: canManage ? (v) => setState(() => _requireCustomerType = v) : null,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: canManage ? _saveSettings : null,
            icon: const Icon(Icons.save),
            label: Text(t.save),
          ),
        ],
      ),
    );
  }

  Widget _buildAdjustTab(ThemeData theme, AppLocalizations t, bool canAdjust) {
    if (!canAdjust) {
      return Center(child: Text(t.customerClubNoAdjustPermission));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.customerClubAdjustIntro, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _adjustPersonCtl,
            decoration: InputDecoration(labelText: t.customerClubPersonId),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          TextField(
            controller: _adjustDeltaCtl,
            decoration: InputDecoration(labelText: t.customerClubDeltaPoints),
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          ),
          TextField(
            controller: _adjustDescCtl,
            decoration: InputDecoration(labelText: t.description),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submitAdjustment,
            icon: const Icon(Icons.add),
            label: Text(t.customerClubSubmitAdjustment),
          ),
        ],
      ),
    );
  }
}
