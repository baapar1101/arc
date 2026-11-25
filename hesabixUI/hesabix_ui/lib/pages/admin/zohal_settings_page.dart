import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../services/zohal_service.dart';
import '../../services/system_settings_service.dart';
import '../../services/currency_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import 'admin_compact_scaffold.dart';
import '../../theme/tokens/extensions.dart';

class ZohalSettingsPage extends StatefulWidget {
  const ZohalSettingsPage({super.key});

  @override
  State<ZohalSettingsPage> createState() => _ZohalSettingsPageState();
}

class _ZohalSettingsPageState extends State<ZohalSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late final ZohalService _zohalService;
  late final SystemSettingsService _systemSettingsService;
  late final CurrencyService _currencyService;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _walletCurrencyCode;
  String? _walletCurrencyTitle;

  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _lowBalanceThresholdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _zohalService = ZohalService(api);
    _systemSettingsService = SystemSettingsService(api);
    _currencyService = CurrencyService(api);
    _load();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _lowBalanceThresholdController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await _zohalService.getSettings();
      final walletSettings = await _systemSettingsService.getWalletSettings();
      final currencies = await _currencyService.listCurrencies();
      
      final walletCurrencyCode = (walletSettings['wallet_base_currency_code'] ?? 'IRR').toString();
      final walletCurrency = currencies.firstWhere(
        (c) => (c['code'] ?? '').toString() == walletCurrencyCode,
        orElse: () => {'code': 'IRR', 'title': 'تومان'},
      );
      
      setState(() {
        _apiKeyController.text = (settings['api_key'] ?? '').toString();
        _baseUrlController.text = (settings['base_url'] ?? 'https://service.zohal.io/api/v0').toString();
        _lowBalanceThresholdController.text = (settings['low_balance_threshold'] ?? 10000).toString();
        _walletCurrencyCode = walletCurrencyCode;
        _walletCurrencyTitle = (walletCurrency['title'] ?? 'تومان').toString();
      });
    } catch (e) {
      setState(() => _error = ErrorExtractor.forContext(e, context));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      await _zohalService.setSettings(
        apiKey: _apiKeyController.text.trim().isEmpty ? null : _apiKeyController.text.trim(),
        baseUrl: _baseUrlController.text.trim().isEmpty ? null : _baseUrlController.text.trim(),
        lowBalanceThreshold: double.tryParse(_lowBalanceThresholdController.text.trim()),
      );
      if (mounted) {
        SnackBarHelper.show(context, message: adminTx(context, 'ذخیره شد', 'Saved'));
        _load(); // Reload to get updated values
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: '${adminTx(context, 'ذخیره نشد', 'Could not save')}: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AdminCompactScaffold(
      title: adminTx(context, 'تنظیمات زحل', 'Zohal settings'),
      subtitle: adminTx(context, 'اتصال و کلید سرویس زحل', 'Zohal connection and key'),
      actions: [
        if (!_loading)
          IconButton(
            tooltip: adminTx(context, 'ذخیره', 'Save'),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined, size: 20),
          ),
        if (!_loading)
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _load,
            tooltip: adminTx(context, 'بارگذاری مجدد', 'Reload'),
          ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
                      const SizedBox(height: 16),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: Text(adminTx(context, 'تلاش مجدد', 'Retry')),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: context.settingsHub.pagePadding,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.key, color: theme.colorScheme.primary),
                                    const SizedBox(width: 8),
                                    Text(
                                      adminTx(context, 'کلید API', 'API key'),
                                      style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _apiKeyController,
                                  decoration: InputDecoration(
                                    labelText: adminTx(context, 'کلید API زحل', 'Zohal API key'),
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                    prefixIcon: const Icon(Icons.vpn_key),
                                  ),
                                  obscureText: true,
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return adminTx(context, 'کلید API الزامی است', 'API key is required');
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  adminTx(context, 'کلید را از پنل زحل بگیرید', 'Copy the key from the Zohal panel'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.link, color: theme.colorScheme.primary),
                                    const SizedBox(width: 8),
                                    Text(
                                      adminTx(context, 'آدرس پایه', 'Base URL'),
                                      style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _baseUrlController,
                                  decoration: InputDecoration(
                                    labelText: adminTx(context, 'آدرس پایه API', 'API base URL'),
                                    hintText: 'https://service.zohal.io/api/v0',
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                    prefixIcon: const Icon(Icons.http),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return adminTx(context, 'آدرس پایه الزامی است', 'Base URL is required');
                                    }
                                    final uri = Uri.tryParse(value.trim());
                                    if (uri == null || !uri.hasAbsolutePath) {
                                      return adminTx(context, 'آدرس معتبر نیست', 'Invalid URL');
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.warning_amber, color: theme.colorScheme.primary),
                                    const SizedBox(width: 8),
                                    Text(
                                      adminTx(context, 'آستانه موجودی کم', 'Low balance threshold'),
                                      style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _lowBalanceThresholdController,
                                  decoration: InputDecoration(
                                    labelText: adminTx(context, 'آستانه', 'Threshold') + ' (${_walletCurrencyTitle ?? adminTx(context, 'تومان', 'IRR')})',
                                    hintText: '10000',
                                    border: const OutlineInputBorder(),
                                    prefixIcon: const Icon(Icons.account_balance_wallet),
                                  ),
                                  keyboardType: TextInputType.number,
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return adminTx(context, 'آستانه الزامی است', 'Threshold is required');
                                    }
                                    final num = double.tryParse(value.trim());
                                    if (num == null || num < 0) {
                                      return adminTx(context, 'مقدار معتبر نیست', 'Invalid value');
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  adminTx(context, 'کمتر از این مبلغ به کاربر هشدار داده می‌شود', 'Users are warned when the wallet is below this amount'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save),
                          label: Text(_saving ? adminTx(context, 'در حال ذخیره', 'Saving') : adminTx(context, 'ذخیره', 'Save')),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

