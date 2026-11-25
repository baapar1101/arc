import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/auth_store.dart';
import '../../../core/date_utils.dart';
import '../../../core/permission_guard.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/digipay_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/number_formatters.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/business_subpage_back_leading.dart';
import '../../../widgets/invoice/bank_account_combobox_widget.dart';
import '../../../widgets/jalali_date_picker.dart';

class DigipayHubPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const DigipayHubPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<DigipayHubPage> createState() => _DigipayHubPageState();
}

class _DigipayHubPageState extends State<DigipayHubPage>
    with SingleTickerProviderStateMixin {
  final DigipayService _svc = DigipayService();
  late final TabController _tabs;

  bool get _isOwner => widget.authStore.currentBusiness?.isOwner == true;
  bool get _canView =>
      _isOwner || widget.authStore.hasBusinessPermission('digipay', 'view');
  bool get _canManage =>
      _isOwner || widget.authStore.hasBusinessPermission('digipay', 'manage');
  bool get _canOperate =>
      _isOwner || widget.authStore.hasBusinessPermission('digipay', 'operate');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!_canView) {
      return Scaffold(
        appBar: AppBar(title: Text(t.digipayMenuTitle)),
        body: PermissionGuard.buildAccessDeniedPage(),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(t.digipayMenuTitle),
        leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: t.digipaySettingsTab),
            Tab(text: t.digipayPurchasesTab),
            Tab(text: t.digipaySettlementsTab),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _DigipaySettingsTab(
            businessId: widget.businessId,
            canManage: _canManage,
            service: _svc,
          ),
          _DigipayPurchasesTab(
            businessId: widget.businessId,
            canOperate: _canOperate,
            service: _svc,
          ),
          _DigipaySettlementsTab(
            businessId: widget.businessId,
            canManage: _canManage,
            service: _svc,
          ),
        ],
      ),
    );
  }
}

class _DigipaySettingsTab extends StatefulWidget {
  final int businessId;
  final bool canManage;
  final DigipayService service;

  const _DigipaySettingsTab({
    required this.businessId,
    required this.canManage,
    required this.service,
  });

  @override
  State<_DigipaySettingsTab> createState() => _DigipaySettingsTabState();
}

class _DigipaySettingsTabState extends State<_DigipaySettingsTab> {
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic> _settings = const {};
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _clientId = TextEditingController();
  final _clientSecret = TextEditingController();
  final _sellerId = TextEditingController();
  final _commission = TextEditingController();
  final _vat = TextEditingController();
  String _environment = 'sandbox';
  bool _autoDeliver = true;
  String? _bankId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _clientId.dispose();
    _clientSecret.dispose();
    _sellerId.dispose();
    _commission.dispose();
    _vat.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await widget.service.getSettings(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _settings = data;
        _environment = (data['environment'] ?? 'sandbox').toString();
        _sellerId.text = data['seller_id']?.toString() ?? '';
        _commission.text = '${data['commission_percent'] ?? 0}';
        _vat.text = '${data['vat_on_commission_percent'] ?? 10}';
        _autoDeliver = data['auto_deliver_in_store'] != false;
        _bankId = data['settlement_bank_account_id']?.toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.show(
        context,
        message: ErrorExtractor.userMessage(e, AppLocalizations.of(context)),
        isError: true,
      );
    }
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await widget.service.updateSettings(
        businessId: widget.businessId,
        payload: {
          'environment': _environment,
          if (_username.text.trim().isNotEmpty) 'username': _username.text.trim(),
          if (_password.text.isNotEmpty) 'password': _password.text,
          if (_clientId.text.trim().isNotEmpty) 'client_id': _clientId.text.trim(),
          if (_clientSecret.text.isNotEmpty) 'client_secret': _clientSecret.text,
          'seller_id': _sellerId.text.trim(),
          'commission_percent': num.tryParse(_commission.text.replaceAll(',', '.')) ?? 0,
          'vat_on_commission_percent': num.tryParse(_vat.text.replaceAll(',', '.')) ?? 10,
          'auto_deliver_in_store': _autoDeliver,
          'settlement_bank_account_id': int.tryParse(_bankId ?? '') ?? 0,
        },
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: t.digipaySettingsSaved);
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: ErrorExtractor.userMessage(e, t),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    final t = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await widget.service.testConnection(businessId: widget.businessId);
      if (!mounted) return;
      SnackBarHelper.show(context, message: t.digipayConnectionOk);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: ErrorExtractor.userMessage(e, t),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t.digipaySettingsIntro, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 12),
        Text('${t.digipayPersonLabel}: ${_settings['person_name'] ?? '-'}'),
        const SizedBox(height: 12),
        InputDecorator(
          decoration: InputDecoration(labelText: t.digipayEnvironmentLabel),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _environment,
              items: [
                DropdownMenuItem(value: 'sandbox', child: Text(t.digipayEnvironmentSandbox)),
                DropdownMenuItem(value: 'live', child: Text(t.digipayEnvironmentLive)),
              ],
              onChanged: widget.canManage ? (v) => setState(() => _environment = v ?? 'sandbox') : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _username,
          enabled: widget.canManage,
          decoration: InputDecoration(
            labelText: t.digipayUsernameLabel,
            hintText: _settings['username_masked']?.toString(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _password,
          enabled: widget.canManage,
          obscureText: true,
          decoration: InputDecoration(labelText: t.password),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _clientId,
          enabled: widget.canManage,
          decoration: InputDecoration(
            labelText: t.digipayClientIdLabel,
            hintText: _settings['client_id_masked']?.toString(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _clientSecret,
          enabled: widget.canManage,
          obscureText: true,
          decoration: InputDecoration(labelText: t.digipayClientSecretLabel),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _sellerId,
          enabled: widget.canManage,
          decoration: InputDecoration(labelText: t.digipaySellerIdLabel),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _commission,
          enabled: widget.canManage,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: t.digipayCommissionPercentLabel),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _vat,
          enabled: widget.canManage,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: t.digipayVatOnCommissionLabel),
        ),
        const SizedBox(height: 8),
        BankAccountComboboxWidget(
          businessId: widget.businessId,
          selectedAccountId: _bankId,
          label: t.digipaySettlementBankLabel,
          onChanged: widget.canManage
              ? (BankAccountOption? opt) => setState(() => _bankId = opt?.id)
              : (_) {},
        ),
        SwitchListTile(
          value: _autoDeliver,
          onChanged: widget.canManage ? (v) => setState(() => _autoDeliver = v) : null,
          title: Text(t.digipayAutoDeliverLabel),
        ),
        if (widget.canManage)
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(t.save),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : _test,
                icon: const Icon(Icons.wifi_tethering),
                label: Text(t.digipayTestConnection),
              ),
            ],
          ),
      ],
    );
  }
}

class _DigipayPurchasesTab extends StatefulWidget {
  final int businessId;
  final bool canOperate;
  final DigipayService service;

  const _DigipayPurchasesTab({
    required this.businessId,
    required this.canOperate,
    required this.service,
  });

  @override
  State<_DigipayPurchasesTab> createState() => _DigipayPurchasesTabState();
}

class _DigipayPurchasesTabState extends State<_DigipayPurchasesTab> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = const [];
  String? _status;
  DateTime? _from;
  DateTime? _to;

  bool get _isJalali => ApiClient.getCalendarController()?.isJalali ?? true;

  String? _fmtFilter(DateTime? d) {
    if (d == null) return null;
    return _isJalali
        ? HesabixDateUtils.formatForDisplay(d, true)
        : HesabixDateUtils.formatForApiDate(d);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await widget.service.listPurchases(
        businessId: widget.businessId,
        status: _status,
        dateFrom: _fmtFilter(_from),
        dateTo: _fmtFilter(_to),
      );
      final items = data['items'];
      if (!mounted) return;
      setState(() {
        _items = items is List
            ? items.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : const [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.show(
        context,
        message: ErrorExtractor.userMessage(e, AppLocalizations.of(context)),
        isError: true,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _pick(bool from) async {
    final t = AppLocalizations.of(context);
    final picked = await showAdaptiveDatePicker(
      context: context,
      initialDate: from ? _from : _to,
      helpText: from ? t.digipayDateFrom : t.digipayDateTo,
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
    await _load();
  }

  Future<void> _deliver(int id) async {
    try {
      await widget.service.deliverPurchase(
        businessId: widget.businessId,
        purchaseId: id,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: ErrorExtractor.userMessage(e, AppLocalizations.of(context)),
        isError: true,
      );
    }
  }

  Future<void> _refund(int id) async {
    try {
      await widget.service.refundPurchase(
        businessId: widget.businessId,
        purchaseId: id,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: ErrorExtractor.userMessage(e, AppLocalizations.of(context)),
        isError: true,
      );
    }
  }

  String _statusLabel(AppLocalizations t, String? status) {
    switch (status) {
      case 'pending':
        return t.digipayStatusPending;
      case 'paid':
        return t.digipayStatusPaid;
      case 'verified':
        return t.digipayStatusVerified;
      case 'delivered':
        return t.digipayStatusDelivered;
      case 'settled':
        return t.digipayStatusSettled;
      case 'failed':
        return t.digipayStatusFailed;
      case 'refunded':
        return t.digipayStatusRefunded;
      default:
        return status ?? '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DropdownButton<String?>(
                value: _status,
                hint: Text(t.digipayStatusFilter),
                items: [
                  DropdownMenuItem(value: null, child: Text(t.digipayStatusAll)),
                  DropdownMenuItem(value: 'pending', child: Text(t.digipayStatusPending)),
                  DropdownMenuItem(value: 'verified', child: Text(t.digipayStatusVerified)),
                  DropdownMenuItem(value: 'delivered', child: Text(t.digipayStatusDelivered)),
                  DropdownMenuItem(value: 'settled', child: Text(t.digipayStatusSettled)),
                  DropdownMenuItem(value: 'failed', child: Text(t.digipayStatusFailed)),
                ],
                onChanged: (v) {
                  setState(() => _status = v);
                  _load();
                },
              ),
              OutlinedButton(
                onPressed: () => _pick(true),
                child: Text(_from == null ? t.digipayDateFrom : HesabixDateUtils.formatForDisplay(_from, _isJalali)),
              ),
              OutlinedButton(
                onPressed: () => _pick(false),
                child: Text(_to == null ? t.digipayDateTo : HesabixDateUtils.formatForDisplay(_to, _isJalali)),
              ),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final row = _items[index];
                final id = (row['id'] as num?)?.toInt();
                final status = row['status']?.toString();
                return ListTile(
                  title: Text('${row['provider_id'] ?? ''} • ${formatWithThousands(row['amount'] ?? 0)}'),
                  subtitle: Text(
                    '${_statusLabel(t, status)} • ${row['created_at'] ?? ''} • ${row['tracking_code'] ?? ''}',
                  ),
                  trailing: widget.canOperate && id != null
                      ? Wrap(
                          children: [
                            if (status == 'verified' || status == 'paid')
                              IconButton(
                                tooltip: t.digipayDeliverAction,
                                onPressed: () => _deliver(id),
                                icon: const Icon(Icons.local_shipping_outlined),
                              ),
                            if (status == 'verified' || status == 'delivered')
                              IconButton(
                                tooltip: t.digipayRefundAction,
                                onPressed: () => _refund(id),
                                icon: const Icon(Icons.undo),
                              ),
                          ],
                        )
                      : null,
                );
              },
            ),
          ),
      ],
    );
  }
}

class _DigipaySettlementsTab extends StatefulWidget {
  final int businessId;
  final bool canManage;
  final DigipayService service;

  const _DigipaySettlementsTab({
    required this.businessId,
    required this.canManage,
    required this.service,
  });

  @override
  State<_DigipaySettlementsTab> createState() => _DigipaySettlementsTabState();
}

class _DigipaySettlementsTabState extends State<_DigipaySettlementsTab> {
  bool _loading = true;
  Map<String, dynamic> _preview = const {};
  List<Map<String, dynamic>> _rows = const [];
  DateTime _date = DateTime.now();
  String? _bankId;
  bool _saving = false;

  bool get _isJalali => ApiClient.getCalendarController()?.isJalali ?? true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final preview = await widget.service.previewSettlement(businessId: widget.businessId);
      final list = await widget.service.listSettlements(businessId: widget.businessId);
      final settings = await widget.service.getSettings(businessId: widget.businessId);
      final items = list['items'];
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _rows = items is List
            ? items.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : const [];
        _bankId ??= settings['settlement_bank_account_id']?.toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.show(
        context,
        message: ErrorExtractor.userMessage(e, AppLocalizations.of(context)),
        isError: true,
      );
    }
  }

  Future<void> _register() async {
    final t = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      final dateStr = _isJalali
          ? HesabixDateUtils.formatForDisplay(_date, true)
          : HesabixDateUtils.formatForApiDate(_date);
      await widget.service.registerSettlement(
        businessId: widget.businessId,
        settlementDate: dateStr,
        bankAccountId: int.tryParse(_bankId ?? ''),
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: t.digipaySettlementSaved);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: ErrorExtractor.userMessage(e, t),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t.digipaySettlementHelp),
        const SizedBox(height: 8),
        Text('${t.digipayGrossAmount}: ${formatWithThousands(_preview['gross_amount'] ?? 0)}'),
        Text('${t.digipayCommissionAmount}: ${formatWithThousands(_preview['commission_amount'] ?? 0)}'),
        Text('${t.digipayVatAmount}: ${formatWithThousands(_preview['vat_amount'] ?? 0)}'),
        Text('${t.digipayNetAmount}: ${formatWithThousands(_preview['net_amount'] ?? 0)}'),
        const SizedBox(height: 8),
        Text(t.digipayAccountsHint),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await showAdaptiveDatePicker(
              context: context,
              initialDate: _date,
              helpText: t.digipaySettlementDate,
            );
            if (picked != null) setState(() => _date = picked);
          },
          icon: const Icon(Icons.event),
          label: Text(
            '${t.digipaySettlementDate}: ${HesabixDateUtils.formatForDisplay(_date, _isJalali)}',
          ),
        ),
        const SizedBox(height: 8),
        BankAccountComboboxWidget(
          businessId: widget.businessId,
          selectedAccountId: _bankId,
          label: t.digipaySettlementBankLabel,
          onChanged: (opt) => setState(() => _bankId = opt?.id),
        ),
        if (widget.canManage) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _register,
            icon: const Icon(Icons.account_balance_outlined),
            label: Text(t.digipayRegisterSettlement),
          ),
        ],
        const Divider(height: 32),
        Text(t.digipaySettlementHistory, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ..._rows.map(
          (row) => ListTile(
            title: Text(row['settlement_date']?.toString() ?? ''),
            subtitle: Text(
              '${t.digipayNetAmount}: ${formatWithThousands(row['net_amount'] ?? 0)} • ${t.digipayGrossAmount}: ${formatWithThousands(row['gross_amount'] ?? 0)}',
            ),
          ),
        ),
      ],
    );
  }
}
