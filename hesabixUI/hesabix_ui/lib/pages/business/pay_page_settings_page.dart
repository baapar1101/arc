import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/business_named_route_locations.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/business_pay_page_service.dart';
import 'package:hesabix_ui/services/list_filter_preferences_service.dart';
import 'package:hesabix_ui/services/payment_gateway_service.dart';
import 'package:hesabix_ui/utils/api_datetime_display.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/number_formatters.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/business_subpage_back_leading.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class PayPageSettingsPage extends StatefulWidget {
  final int businessId;

  const PayPageSettingsPage({super.key, required this.businessId});

  @override
  State<PayPageSettingsPage> createState() => _PayPageSettingsPageState();
}

class _PayPageSettingsPageState extends State<PayPageSettingsPage>
    with SingleTickerProviderStateMixin {
  final _service = BusinessPayPageService();
  final _gatewayService = PaymentGatewayService(ApiClient());
  final _usernameCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _introCtrl = TextEditingController();
  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();
  Timer? _usernameTimer;

  late final TabController _tabs;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _enabled = false;
  bool _showLogo = true;
  bool _notifyInApp = true;
  bool _notifySms = false;
  bool _matchCustomer = true;
  bool _createCustomer = true;
  bool _useAnonymous = true;
  int? _gatewayId;
  List<Map<String, dynamic>> _gateways = const [];
  Map<String, dynamic> _settings = const {};
  String? _usernameStatus;
  bool? _usernameOk;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _usernameTimer?.cancel();
    _tabs.dispose();
    _usernameCtrl.dispose();
    _titleCtrl.dispose();
    _introCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final gateways = await _gatewayService.listBusinessGateways(widget.businessId);
      final s = await _service.getSettings(widget.businessId);
      if (!mounted) return;
      _applySettings(s);
      setState(() {
        _gateways = gateways;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  void _applySettings(Map<String, dynamic> s) {
    _settings = s;
    _enabled = s['is_enabled'] == true;
    _showLogo = s['show_logo'] != false;
    _notifyInApp = s['notify_inapp'] != false;
    _notifySms = s['notify_sms'] == true;
    _matchCustomer = s['match_customer_by_mobile'] != false;
    _createCustomer = s['create_customer_if_missing'] != false;
    _useAnonymous = s['use_anonymous_if_no_mobile'] != false;
    _usernameCtrl.text = (s['username'] ?? '').toString();
    _titleCtrl.text = (s['display_title'] ?? '').toString();
    _introCtrl.text = (s['intro_text'] ?? '').toString();
    final minAmt = (s['min_amount'] as num?)?.toDouble() ?? 50000;
    _minCtrl.text = formatNumberForInput(minAmt);
    final maxAmt = (s['max_amount'] as num?)?.toDouble();
    _maxCtrl.text = maxAmt == null ? '' : formatNumberForInput(maxAmt);
    final g = s['gateway_id'];
    if (g is int) {
      _gatewayId = g;
    } else if (g is num) {
      _gatewayId = g.toInt();
    } else {
      _gatewayId = int.tryParse(g?.toString() ?? '');
    }
  }

  void _onUsernameChanged(String value) {
    _usernameTimer?.cancel();
    _usernameStatus = null;
    _usernameOk = null;
    final v = value.trim().toLowerCase();
    if (v.length < 3) {
      setState(() {});
      return;
    }
    _usernameTimer = Timer(const Duration(milliseconds: 450), () async {
      try {
        final r = await _service.checkUsername(widget.businessId, v);
        if (!mounted) return;
        setState(() {
          _usernameOk = r['available'] == true;
          _usernameStatus = (r['message'] as String?) ??
              (r['available'] == true
                  ? AppLocalizations.of(context).payPageUsernameAvailable
                  : AppLocalizations.of(context).payPageUsernameTaken);
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _usernameOk = null;
          _usernameStatus = null;
        });
      }
    });
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    if (_enabled) {
      if (_usernameCtrl.text.trim().isEmpty) {
        SnackBarHelper.showError(context, message: t.payPageUsernameInvalid);
        return;
      }
      if (_gateways.isEmpty) {
        SnackBarHelper.showError(context, message: t.payPageNoGateway);
        return;
      }
      if (_gatewayId == null) {
        SnackBarHelper.showError(context, message: t.payPageGateway);
        return;
      }
      if (!_notifyInApp && !_notifySms) {
        SnackBarHelper.showError(context, message: t.payPageNotifyRequired);
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final saved = await _service.updateSettings(widget.businessId, {
        'is_enabled': _enabled,
        'username': _usernameCtrl.text.trim().toLowerCase(),
        'display_title': _titleCtrl.text.trim(),
        'intro_text': _introCtrl.text.trim(),
        'show_logo': _showLogo,
        'gateway_id': _enabled ? _gatewayId : _gatewayId,
        'min_amount': parseFormattedDouble(_minCtrl.text),
        'max_amount': _maxCtrl.text.trim().isEmpty
            ? null
            : parseFormattedDouble(_maxCtrl.text),
        'notify_inapp': _notifyInApp,
        'notify_sms': _notifySms,
        'match_customer_by_mobile': _matchCustomer,
        'create_customer_if_missing': _createCustomer,
        'use_anonymous_if_no_mobile': _useAnonymous,
      });
      if (!mounted) return;
      _applySettings(saved);
      SnackBarHelper.showSuccess(context, message: t.settingsSavedSuccessfully);
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? get _publicUrl {
    final u = _settings['public_url']?.toString();
    if (u != null && u.isNotEmpty) return u;
    final path = _settings['public_path']?.toString();
    if (path == null || path.isEmpty) return null;
    return Uri.base.origin + path;
  }

  Future<void> _copyLink() async {
    final url = _publicUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).payPageLinkCopied);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.businessSettingsPayPage),
        leading: businessSubpageBackLeading(context, widget.businessId),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: t.payPageSettingsTab),
            Tab(text: t.payPagePaymentsTab),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: Text(t.retry),
                        ),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _buildSettings(t),
                    _buildPayments(t),
                  ],
                ),
    );
  }

  Widget _buildSettings(AppLocalizations t) {
    final theme = Theme.of(context);
    final gatewayIds = _gateways.map((g) => (g['id'] as num?)?.toInt()).whereType<int>().toSet();
    final dropdownValue = _gatewayId != null && gatewayIds.contains(_gatewayId) ? _gatewayId : null;
    final url = _publicUrl;
    final currency = (_settings['currency_title'] ?? _settings['currency_code'] ?? '').toString();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t.businessSettingsPayPageDescription, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        SwitchListTile(
          title: Text(t.payPageEnabled),
          subtitle: Text(t.payPageEnabledHint),
          value: _enabled,
          onChanged: _saving ? null : (v) => setState(() => _enabled = v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _usernameCtrl,
          enabled: !_saving,
          textDirection: TextDirection.ltr,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9\-]')),
            LengthLimitingTextInputFormatter(30),
            TextInputFormatter.withFunction((old, neu) {
              return neu.copyWith(text: neu.text.toLowerCase(), selection: neu.selection);
            }),
          ],
          decoration: InputDecoration(
            labelText: t.payPageUsername,
            helperText: _usernameStatus ?? t.payPageUsernameHint,
            helperMaxLines: 2,
            border: const OutlineInputBorder(),
            suffixIcon: _usernameOk == null
                ? null
                : Icon(_usernameOk! ? Icons.check_circle : Icons.error, color: _usernameOk! ? Colors.green : theme.colorScheme.error),
          ),
          onChanged: _onUsernameChanged,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _titleCtrl,
          enabled: !_saving,
          decoration: InputDecoration(
            labelText: t.payPageDisplayTitle,
            helperText: t.payPageDisplayTitleHint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _introCtrl,
          enabled: !_saving,
          maxLines: 3,
          maxLength: 500,
          decoration: InputDecoration(
            labelText: t.payPageIntroText,
            border: const OutlineInputBorder(),
          ),
        ),
        SwitchListTile(
          title: Text(t.payPageShowLogo),
          value: _showLogo,
          onChanged: _saving ? null : (v) => setState(() => _showLogo = v),
        ),
        if (_gateways.isEmpty)
          Text(t.payPageNoGateway, style: TextStyle(color: theme.colorScheme.error))
        else
          DropdownButtonFormField<int?>(
            value: dropdownValue,
            decoration: InputDecoration(
              labelText: t.payPageGateway,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final g in _gateways)
                DropdownMenuItem<int?>(
                  value: (g['id'] as num?)?.toInt(),
                  child: Text('${g['display_name'] ?? g['provider'] ?? g['id']}'),
                ),
            ],
            onChanged: _saving ? null : (v) => setState(() => _gatewayId = v),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _minCtrl,
          enabled: !_saving,
          keyboardType: TextInputType.number,
          inputFormatters: const [EnglishDigitsFormatter(), ThousandsSeparatorInputFormatter()],
          decoration: InputDecoration(
            labelText: t.payPageMinAmount,
            helperText: currency.isEmpty ? null : t.payPageCurrencyHint(currency),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _maxCtrl,
          enabled: !_saving,
          keyboardType: TextInputType.number,
          inputFormatters: const [EnglishDigitsFormatter(), ThousandsSeparatorInputFormatter()],
          decoration: InputDecoration(
            labelText: t.payPageMaxAmount,
            border: const OutlineInputBorder(),
          ),
        ),
        SwitchListTile(
          title: Text(t.payPageNotifyInApp),
          value: _notifyInApp,
          onChanged: _saving
              ? null
              : (v) {
                  setState(() {
                    _notifyInApp = v;
                    if (!_notifyInApp && !_notifySms) _notifySms = true;
                  });
                },
        ),
        SwitchListTile(
          title: Text(t.payPageNotifySms),
          subtitle: Text(t.payPageNotifyRequired),
          value: _notifySms,
          onChanged: _saving
              ? null
              : (v) {
                  setState(() {
                    _notifySms = v;
                    if (!_notifyInApp && !_notifySms) _notifyInApp = true;
                  });
                },
        ),
        SwitchListTile(
          title: Text(t.payPageMatchCustomer),
          subtitle: Text(t.payPageMatchCustomerHint),
          value: _matchCustomer,
          onChanged: _saving ? null : (v) => setState(() => _matchCustomer = v),
        ),
        SwitchListTile(
          title: Text(t.payPageCreateCustomer),
          value: _createCustomer,
          onChanged: _saving ? null : (v) => setState(() => _createCustomer = v),
        ),
        SwitchListTile(
          title: Text(t.payPageUseAnonymous),
          value: _useAnonymous,
          onChanged: _saving ? null : (v) => setState(() => _useAnonymous = v),
        ),
        if (url != null) ...[
          const SizedBox(height: 8),
          SelectableText(url, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Center(
            child: QrImageView(data: url, size: 140),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _copyLink,
                icon: const Icon(Icons.copy),
                label: Text(t.payPageCopyLink),
              ),
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new),
                label: Text(t.payPageOpenPreview),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? '…' : t.save),
        ),
      ],
    );
  }

  Widget _buildPayments(AppLocalizations t) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: DataTableWidget<Map<String, dynamic>>(
        fromJson: (json) => Map<String, dynamic>.from(json),
        config: DataTableConfig<Map<String, dynamic>>(
          endpoint: '/businesses/${widget.businessId}/pay-page/payments/table',
          businessId: widget.businessId,
          persistTableFiltersPageId: ListFilterPageIds.payPagePaymentsTable,
          title: t.payPagePaymentsTab,
          showSearch: true,
          showPagination: true,
          defaultPageSize: 20,
          columns: [
            DateColumn(
              'created_at',
              t.payPagePaidAt,
              filterType: ColumnFilterType.dateRange,
              showTime: true,
              formatter: (it) {
                if (it is Map<String, dynamic>) {
                  final display = resolveApiDateTimeDisplay(it, 'created_at');
                  if (display.isNotEmpty) return display;
                }
                return HesabixDateUtils.formatApiDateForDisplay(
                  it is Map ? it['created_at'] : it,
                  Localizations.localeOf(context).languageCode == 'fa',
                );
              },
            ),
            TextColumn('payer_name', t.payPagePayerName, formatter: (it) => (it['payer_name'] ?? '').toString()),
            TextColumn('payer_mobile', t.payPagePayerMobile, formatter: (it) => (it['payer_mobile'] ?? '').toString()),
            TextColumn('payer_note', t.payPagePayerNote, overflow: true, maxLines: 2, formatter: (it) => (it['payer_note'] ?? '').toString()),
            NumberColumn(
              'amount',
              t.payPageAmount,
              formatter: (it) {
                final n = it['amount'];
                return formatWithThousands((n is num) ? n.toDouble() : double.tryParse('$n') ?? 0);
              },
            ),
            TextColumn(
              'status',
              t.payPageStatus,
              formatter: (it) {
                switch ((it['status'] ?? '').toString().toLowerCase()) {
                  case 'succeeded':
                    return t.payPageStatusSucceeded;
                  case 'failed':
                    return t.payPageStatusFailed;
                  case 'pending':
                    return t.payPageStatusPending;
                  default:
                    return (it['status'] ?? '').toString();
                }
              },
            ),
            TextColumn(
              'person_name',
              t.payPageCustomer,
              formatter: (it) => (it['person_name'] ?? t.payPageAnonymousCustomer).toString(),
            ),
          ],
          onRowTap: (row) async {
            final docId = row['document_id'];
            if (docId == null) return;
            if (!mounted) return;
            await BusinessNamedRoutes.pushNamed(
              context,
              businessId: widget.businessId,
              routeName: 'business_documents',
              pathParameters: {'business_id': widget.businessId.toString()},
              extra: {'focus_document_id': docId},
            );
          },
        ),
      ),
    );
  }
}
