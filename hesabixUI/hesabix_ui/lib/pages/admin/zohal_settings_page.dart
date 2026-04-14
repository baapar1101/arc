import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/api_client.dart';
import '../../services/zohal_service.dart';
import '../../services/system_settings_service.dart';
import '../../services/currency_service.dart';
import '../../utils/snackbar_helper.dart';

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
      setState(() => _error = '$e');
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
        final t = AppLocalizations.of(context);
        SnackBarHelper.show(context, message: 'تنظیمات با موفقیت ذخیره شد');
        _load(); // Reload to get updated values
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'خطا در ذخیره تنظیمات: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('تنظیمات سرویس زحل'),
        actions: [
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _load,
              tooltip: 'بارگذاری مجدد',
            ),
        ],
      ),
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
                        label: const Text('تلاش مجدد'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
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
                                      'کلید API',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _apiKeyController,
                                  decoration: const InputDecoration(
                                    labelText: 'کلید API زحل',
                                    hintText: 'کلید API خود را وارد کنید',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.vpn_key),
                                  ),
                                  obscureText: true,
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'کلید API الزامی است';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'کلید API را از پنل زحل دریافت کنید',
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
                                      'آدرس پایه API',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _baseUrlController,
                                  decoration: const InputDecoration(
                                    labelText: 'آدرس پایه API',
                                    hintText: 'https://service.zohal.io/api/v0',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.http),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'آدرس پایه API الزامی است';
                                    }
                                    final uri = Uri.tryParse(value.trim());
                                    if (uri == null || !uri.hasAbsolutePath) {
                                      return 'آدرس معتبر نیست';
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
                                      'آستانه موجودی کم',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _lowBalanceThresholdController,
                                  decoration: InputDecoration(
                                    labelText: 'آستانه موجودی کم (${_walletCurrencyTitle ?? 'تومان'})',
                                    hintText: '10000',
                                    border: const OutlineInputBorder(),
                                    prefixIcon: const Icon(Icons.account_balance_wallet),
                                  ),
                                  keyboardType: TextInputType.number,
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'آستانه موجودی الزامی است';
                                    }
                                    final num = double.tryParse(value.trim());
                                    if (num == null || num < 0) {
                                      return 'مقدار معتبر وارد کنید';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'اگر موجودی کیف پول کمتر از این مقدار (${_walletCurrencyTitle ?? 'تومان'}) باشد، به کاربر اخطار نمایش داده می‌شود',
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
                          label: Text(_saving ? 'در حال ذخیره...' : 'ذخیره تنظیمات'),
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

