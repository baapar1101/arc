import 'package:flutter/material.dart';

import '../../../core/auth_store.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/basalam_integration_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';

/// فرم تنظیمات افزونهٔ باسلام (کلید API، سینک، وب‌هوک، واحد پولی).
class BasalamPluginSettingsBody extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const BasalamPluginSettingsBody({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<BasalamPluginSettingsBody> createState() =>
      _BasalamPluginSettingsBodyState();
}

class _BasalamPluginSettingsBodyState extends State<BasalamPluginSettingsBody> {
  final BasalamIntegrationService _svc = BasalamIntegrationService();
  bool _loading = true;
  bool _saving = false;
  bool _loadingCurrencyReadiness = false;
  bool _currencyReady = true;
  List<Map<String, dynamic>> _currencyIssues = const [];
  List<String> _invalidSecondaryCurrencyCodes = const [];

  final _apiKeyCtl = TextEditingController();
  final _apiRefreshTokenCtl = TextEditingController();
  final _baseUrlCtl = TextEditingController();
  final _defaultVendorIdCtl = TextEditingController();
  final _defaultCategoryIdCtl = TextEditingController();
  final _defaultBasalamStockCtl = TextEditingController(text: '1');
  final _webhookSecretCtl = TextEditingController();
  final _defaultTagCtl = TextEditingController();
  final _paymentReconcileToleranceCtl = TextEditingController(text: '1');

  bool _enabled = false;
  bool _webhookEnabled = false;
  bool _chatEnabled = true;
  bool _orderSyncEnabled = true;
  bool _productSyncEnabled = true;
  bool _createInvoiceOnSync = true;
  String _invoiceTypeOnSync = 'invoice_sales';
  String _personMode = 'match_or_create';
  String _productMode = 'match_or_create';
  String _paymentMode = 'manual_review';
  bool _paymentReconcileBlockOverpayment = true;
  String _priceConflictStrategy = 'local_wins';
  String _stockConflictStrategy = 'local_wins';
  String _variantStrategy = 'manual_review';
  String _basalamMonetaryUnit = 'rial';
  String? _lastWebhookEventType;
  String? _lastWebhookEventAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _apiKeyCtl.dispose();
    _apiRefreshTokenCtl.dispose();
    _baseUrlCtl.dispose();
    _defaultVendorIdCtl.dispose();
    _defaultCategoryIdCtl.dispose();
    _defaultBasalamStockCtl.dispose();
    _webhookSecretCtl.dispose();
    _defaultTagCtl.dispose();
    _paymentReconcileToleranceCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await _svc.getSettings(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _enabled = d['enabled'] == true;
        _webhookEnabled = d['webhook_enabled'] == true;
        _chatEnabled = d['chat_enabled'] == true;
        _orderSyncEnabled = d['order_sync_enabled'] == true;
        _productSyncEnabled = d['product_sync_enabled'] == true;
        _createInvoiceOnSync = d['create_sales_invoice_on_sync'] != false;
        _invoiceTypeOnSync = (d['invoice_type_on_sync'] ?? 'invoice_sales')
            .toString();
        _personMode = (d['auto_create_person_mode'] ?? 'match_or_create')
            .toString();
        _productMode = (d['auto_create_product_mode'] ?? 'match_or_create')
            .toString();
        _paymentMode = (d['payment_register_mode'] ?? 'manual_review')
            .toString();
        _paymentReconcileBlockOverpayment =
            d['payment_reconcile_block_overpayment'] != false;
        _paymentReconcileToleranceCtl.text =
            (d['payment_reconcile_tolerance_rial'] ?? 1).toString();
        _priceConflictStrategy =
            (d['product_conflict_price_strategy'] ?? 'local_wins').toString();
        _stockConflictStrategy =
            (d['product_conflict_stock_strategy'] ?? 'local_wins').toString();
        _variantStrategy =
            (d['product_variant_strategy'] ?? 'manual_review').toString();
        final bm = (d['basalam_monetary_unit'] ?? 'rial').toString();
        _basalamMonetaryUnit =
            bm == 'toman' || bm == 'tomman' || bm == 'تومان' ? 'toman' : 'rial';
        _apiKeyCtl.text = (d['api_key'] ?? '').toString();
        _apiRefreshTokenCtl.text = (d['api_refresh_token'] ?? '').toString();
        _baseUrlCtl.text = (d['api_base_url'] ?? 'https://api.basalam.com')
            .toString();
        _defaultVendorIdCtl.text = (d['default_basalam_vendor_id'] ?? '')
            .toString();
        _defaultCategoryIdCtl.text = (d['default_basalam_category_id'] ?? '')
            .toString();
        _defaultBasalamStockCtl.text = (d['default_basalam_stock'] ?? 1)
            .toString();
        _webhookSecretCtl.text = (d['webhook_secret'] ?? '').toString();
        _defaultTagCtl.text = (d['default_order_tag'] ?? 'basalam').toString();
        _lastWebhookEventType = d['last_webhook_event_type']?.toString();
        _lastWebhookEventAt = d['last_webhook_event_at']?.toString();
      });
      await _loadCurrencyReadiness();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCurrencyReadiness() async {
    setState(() => _loadingCurrencyReadiness = true);
    try {
      final d = await _svc.getCurrencyReadiness(businessId: widget.businessId);
      if (!mounted) return;
      final ready = d['ready'] == true;
      final issuesRaw = d['issues'];
      final issues = issuesRaw is List
          ? issuesRaw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      final invRaw = d['invalid_secondary_currency_codes'];
      final inv = invRaw is List
          ? invRaw.map((e) => e.toString()).toList()
          : <String>[];
      setState(() {
        _currencyReady = ready;
        _currencyIssues = issues;
        _invalidSecondaryCurrencyCodes = inv;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _currencyReady = true;
        _currencyIssues = const [];
        _invalidSecondaryCurrencyCodes = const [];
      });
    } finally {
      if (mounted) setState(() => _loadingCurrencyReadiness = false);
    }
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await _svc.updateSettings(
        businessId: widget.businessId,
        payload: <String, dynamic>{
          'enabled': _enabled,
          'api_key': _apiKeyCtl.text.trim(),
          'api_refresh_token': _apiRefreshTokenCtl.text.trim(),
          'api_base_url': _baseUrlCtl.text.trim(),
          'default_basalam_vendor_id': int.tryParse(
            _defaultVendorIdCtl.text.trim(),
          ),
          'default_basalam_category_id': int.tryParse(
            _defaultCategoryIdCtl.text.trim(),
          ),
          'default_basalam_stock':
              int.tryParse(_defaultBasalamStockCtl.text.trim()) ?? 1,
          'webhook_secret': _webhookSecretCtl.text.trim(),
          'webhook_enabled': _webhookEnabled,
          'chat_enabled': _chatEnabled,
          'order_sync_enabled': _orderSyncEnabled,
          'product_sync_enabled': _productSyncEnabled,
          'create_sales_invoice_on_sync': _createInvoiceOnSync,
          'invoice_type_on_sync': _invoiceTypeOnSync,
          'auto_create_person_mode': _personMode,
          'auto_create_product_mode': _productMode,
          'default_order_tag': _defaultTagCtl.text.trim(),
          'payment_register_mode': _paymentMode,
          'payment_reconcile_block_overpayment': _paymentReconcileBlockOverpayment,
          'payment_reconcile_tolerance_rial':
              double.tryParse(_paymentReconcileToleranceCtl.text.trim()) ?? 1.0,
          'product_conflict_price_strategy': _priceConflictStrategy,
          'product_conflict_stock_strategy': _stockConflictStrategy,
          'product_variant_strategy': _variantStrategy,
          'basalam_monetary_unit': _basalamMonetaryUnit,
        },
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        message: t.basalamSettingsSavedSnackbar,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final canManage =
        widget.authStore.hasBusinessPermission('basalam', 'manage') ||
            widget.authStore.currentBusiness?.isOwner == true;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          t.basalamSettingsPageSubtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          value: _enabled,
          onChanged: canManage ? (v) => setState(() => _enabled = v) : null,
          title: Text(t.basalamSettingsEnableConnection),
        ),
        if (_loadingCurrencyReadiness)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (!_currencyReady && _currencyIssues.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              color: theme.colorScheme.errorContainer.withOpacity(0.92),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t.basalamSettingsCurrencyIrrTitle,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._currencyIssues.map(
                      (issue) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          issue['message']?.toString() ??
                              issue['code']?.toString() ??
                              '-',
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                    if (_invalidSecondaryCurrencyCodes.isNotEmpty)
                      Text(
                        '${t.basalamSettingsCurrencyInvalidSecondaries}: ${_invalidSecondaryCurrencyCodes.join(', ')}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      t.basalamSettingsCurrencyFixHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        TextField(
          controller: _apiKeyCtl,
          enabled: canManage,
          decoration: InputDecoration(labelText: t.basalamSettingsApiKey),
        ),
        TextField(
          controller: _apiRefreshTokenCtl,
          enabled: canManage,
          decoration:
              InputDecoration(labelText: t.basalamSettingsRefreshTokenOptional),
        ),
        TextField(
          controller: _baseUrlCtl,
          enabled: canManage,
          decoration: InputDecoration(labelText: t.basalamSettingsApiBaseUrl),
        ),
        TextField(
          controller: _defaultVendorIdCtl,
          enabled: canManage,
          keyboardType: TextInputType.number,
          decoration:
              InputDecoration(labelText: t.basalamSettingsDefaultVendorId),
        ),
        TextField(
          controller: _defaultCategoryIdCtl,
          enabled: canManage,
          keyboardType: TextInputType.number,
          decoration:
              InputDecoration(labelText: t.basalamSettingsDefaultCategoryId),
        ),
        TextField(
          controller: _defaultBasalamStockCtl,
          enabled: canManage,
          keyboardType: TextInputType.number,
          decoration:
              InputDecoration(labelText: t.basalamSettingsDefaultPublishStock),
        ),
        DropdownButtonFormField<String>(
          value: _basalamMonetaryUnit,
          onChanged: canManage
              ? (v) => setState(() => _basalamMonetaryUnit = v ?? _basalamMonetaryUnit)
              : null,
          decoration: InputDecoration(
            labelText: t.basalamSettingsMonetaryUnit,
            helperText: t.basalamSettingsMonetaryUnitHelper,
          ),
          items: [
            DropdownMenuItem(
              value: 'rial',
              child: Text(t.basalamSettingsMonetaryUnitRial),
            ),
            DropdownMenuItem(
              value: 'toman',
              child: Text(t.basalamSettingsMonetaryUnitToman),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: _webhookEnabled,
          onChanged: canManage
              ? (v) => setState(() => _webhookEnabled = v)
              : null,
          title: Text(t.basalamSettingsEnableWebhook),
        ),
        TextField(
          controller: _webhookSecretCtl,
          enabled: canManage,
          decoration: InputDecoration(labelText: t.basalamSettingsWebhookSecret),
        ),
        SwitchListTile(
          value: _chatEnabled,
          onChanged:
              canManage ? (v) => setState(() => _chatEnabled = v) : null,
          title: Text(t.basalamSettingsEnableChat),
        ),
        SwitchListTile(
          value: _orderSyncEnabled,
          onChanged:
              canManage ? (v) => setState(() => _orderSyncEnabled = v) : null,
          title: Text(t.basalamSettingsEnableOrderSync),
        ),
        SwitchListTile(
          value: _productSyncEnabled,
          onChanged:
              canManage ? (v) => setState(() => _productSyncEnabled = v) : null,
          title: Text(t.basalamSettingsEnableProductSync),
        ),
        SwitchListTile(
          value: _createInvoiceOnSync,
          onChanged:
              canManage ? (v) => setState(() => _createInvoiceOnSync = v) : null,
          title: Text(t.basalamSettingsCreateInvoiceOnSync),
        ),
        DropdownButtonFormField<String>(
          value: _invoiceTypeOnSync,
          onChanged: canManage
              ? (v) => setState(() => _invoiceTypeOnSync = v ?? _invoiceTypeOnSync)
              : null,
          decoration:
              InputDecoration(labelText: t.basalamSettingsSyncInvoiceType),
          items: [
            DropdownMenuItem(
              value: 'invoice_sales',
              child: Text(t.basalamSyncInvoiceTypeSales),
            ),
            DropdownMenuItem(
              value: 'invoice_sales_return',
              child: Text(t.basalamSyncInvoiceTypeSalesReturn),
            ),
          ],
        ),
        DropdownButtonFormField<String>(
          value: _personMode,
          onChanged: canManage
              ? (v) => setState(() => _personMode = v ?? _personMode)
              : null,
          decoration:
              InputDecoration(labelText: t.basalamSettingsPersonMatchMode),
          items: [
            DropdownMenuItem(
              value: 'match_only',
              child: Text(t.basalamModeMatchOnly),
            ),
            DropdownMenuItem(
              value: 'create_only',
              child: Text(t.basalamModeCreateOnly),
            ),
            DropdownMenuItem(
              value: 'match_or_create',
              child: Text(t.basalamModeMatchOrCreate),
            ),
            DropdownMenuItem(
              value: 'manual_review',
              child: Text(t.basalamModeManualReview),
            ),
          ],
        ),
        DropdownButtonFormField<String>(
          value: _productMode,
          onChanged: canManage
              ? (v) => setState(() => _productMode = v ?? _productMode)
              : null,
          decoration:
              InputDecoration(labelText: t.basalamSettingsProductMatchMode),
          items: [
            DropdownMenuItem(
              value: 'match_only',
              child: Text(t.basalamModeMatchOnly),
            ),
            DropdownMenuItem(
              value: 'create_only',
              child: Text(t.basalamModeCreateOnly),
            ),
            DropdownMenuItem(
              value: 'match_or_create',
              child: Text(t.basalamModeMatchOrCreate),
            ),
            DropdownMenuItem(
              value: 'manual_review',
              child: Text(t.basalamModeManualReview),
            ),
          ],
        ),
        DropdownButtonFormField<String>(
          value: _paymentMode,
          onChanged: canManage
              ? (v) => setState(() => _paymentMode = v ?? _paymentMode)
              : null,
          decoration: InputDecoration(labelText: t.basalamSettingsPaymentMode),
          items: [
            DropdownMenuItem(
              value: 'manual_review',
              child: Text(t.basalamPaymentModeManualReview),
            ),
            DropdownMenuItem(
              value: 'auto_bank',
              child: Text(t.basalamPaymentModeAutoBank),
            ),
            DropdownMenuItem(
              value: 'auto_cash',
              child: Text(t.basalamPaymentModeAutoCash),
            ),
          ],
        ),
        SwitchListTile(
          value: _paymentReconcileBlockOverpayment,
          onChanged: canManage
              ? (v) => setState(() => _paymentReconcileBlockOverpayment = v)
              : null,
          title: Text(t.basalamSettingsBlockOverpayment),
          subtitle: Text(t.basalamSettingsBlockOverpaymentSubtitle),
        ),
        TextField(
          controller: _paymentReconcileToleranceCtl,
          enabled: canManage,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration:
              InputDecoration(labelText: t.basalamSettingsInvoiceToleranceIrr),
        ),
        DropdownButtonFormField<String>(
          value: _priceConflictStrategy,
          onChanged: canManage
              ? (v) => setState(
                    () => _priceConflictStrategy = v ?? _priceConflictStrategy,
                  )
              : null,
          decoration:
              InputDecoration(labelText: t.basalamSettingsPriceConflictStrategy),
          items: [
            DropdownMenuItem(
              value: 'local_wins',
              child: Text(t.basalamStrategyLocalWins),
            ),
            DropdownMenuItem(
              value: 'remote_wins',
              child: Text(t.basalamStrategyRemoteWins),
            ),
            DropdownMenuItem(
              value: 'manual_review',
              child: Text(t.basalamModeManualReview),
            ),
          ],
        ),
        DropdownButtonFormField<String>(
          value: _stockConflictStrategy,
          onChanged: canManage
              ? (v) => setState(
                    () => _stockConflictStrategy = v ?? _stockConflictStrategy,
                  )
              : null,
          decoration:
              InputDecoration(labelText: t.basalamSettingsStockConflictStrategy),
          items: [
            DropdownMenuItem(
              value: 'local_wins',
              child: Text(t.basalamStrategyLocalWins),
            ),
            DropdownMenuItem(
              value: 'remote_wins',
              child: Text(t.basalamStrategyRemoteWins),
            ),
            DropdownMenuItem(
              value: 'manual_review',
              child: Text(t.basalamModeManualReview),
            ),
          ],
        ),
        DropdownButtonFormField<String>(
          value: _variantStrategy,
          onChanged: canManage
              ? (v) =>
                  setState(() => _variantStrategy = v ?? _variantStrategy)
              : null,
          decoration:
              InputDecoration(labelText: t.basalamSettingsVariantStrategy),
          items: [
            DropdownMenuItem(
              value: 'manual_review',
              child: Text(t.basalamModeManualReview),
            ),
            DropdownMenuItem(
              value: 'local_wins',
              child: Text(t.basalamStrategyLocalWins),
            ),
            DropdownMenuItem(
              value: 'remote_wins',
              child: Text(t.basalamStrategyRemoteWins),
            ),
          ],
        ),
        TextField(
          controller: _defaultTagCtl,
          enabled: canManage,
          decoration:
              InputDecoration(labelText: t.basalamSettingsDefaultOrderTag),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: canManage && !_saving ? _save : null,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: Text(t.basalamSettingsSave),
        ),
        const Divider(height: 28),
        Text(
          t.basalamSettingsLatestWebhook,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text('${t.basalamSettingsWebhookEventType}: ${_lastWebhookEventType ?? '-'}'),
        Text('${t.basalamSettingsWebhookEventTime}: ${_lastWebhookEventAt ?? '-'}'),
      ],
    );
  }
}
