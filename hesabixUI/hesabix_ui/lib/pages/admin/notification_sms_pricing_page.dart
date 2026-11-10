import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api_client.dart';
import '../../services/admin_system_settings_service.dart';
import '../../services/system_settings_service.dart';
import '../../services/currency_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/number_normalizer.dart';
import 'admin_compact_scaffold.dart';
import '../../theme/tokens/extensions.dart';

class NotificationSmsPricingPage extends StatefulWidget {
  const NotificationSmsPricingPage({super.key});

  @override
  State<NotificationSmsPricingPage> createState() => _NotificationSmsPricingPageState();
}

class _NotificationSmsPricingPageState extends State<NotificationSmsPricingPage> {
  final _formKey = GlobalKey<FormState>();
  late final AdminSystemSettingsService _adminService;
  late final SystemSettingsService _systemSettingsService;
  late final CurrencyService _currencyService;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _walletCurrencyCode;
  String? _walletCurrencyTitle;

  final _pricePerSmsController = TextEditingController();
  final Map<String, TextEditingController> _eventTypePriceControllers = {};
  final List<Map<String, dynamic>> _eventTypes = [];
  final List<String> _eventTypeKeys = [];

  @override
  void initState() {
    super.initState();
    final api = ApiClient();
    _adminService = AdminSystemSettingsService(api);
    _systemSettingsService = SystemSettingsService(api);
    _currencyService = CurrencyService(api);
    _load();
  }

  @override
  void dispose() {
    _pricePerSmsController.dispose();
    for (var controller in _eventTypePriceControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // دریافت تنظیمات قیمت‌گذاری
      final pricing = await _adminService.getNotificationSmsPricing();
      
      // دریافت ارز کیف پول
      final walletSettings = await _systemSettingsService.getWalletSettings();
      final currencies = await _currencyService.listCurrencies();
      
      final walletCurrencyCode = (walletSettings['wallet_base_currency_code'] ?? 'IRR').toString();
      final walletCurrency = currencies.firstWhere(
        (c) => (c['code'] ?? '').toString() == walletCurrencyCode,
        orElse: () => {'code': 'IRR', 'title': 'تومان'},
      );

      // دریافت لیست event types
      try {
        final api = ApiClient();
        final eventTypesRes = await api.get<Map<String, dynamic>>(
          '/api/v1/business-notifications/event-types',
        );
        final eventTypesData = eventTypesRes.data?['data'] as Map<String, dynamic>?;
        final eventTypesList = eventTypesData?['items'] as List? ?? [];
        
        setState(() {
          _eventTypes.clear();
          _eventTypeKeys.clear();
          for (var et in eventTypesList) {
            final etMap = et as Map<String, dynamic>;
            final code = etMap['code']?.toString();
            if (code != null) {
              _eventTypes.add(etMap);
              _eventTypeKeys.add(code);
            }
          }
        });
      } catch (e) {
        // اگر event types را نتوانستیم دریافت کنیم، ادامه می‌دهیم
        debugPrint('خطا در دریافت event types: $e');
      }

      // بارگذاری قیمت‌ها
      final pricePerSms = pricing['price_per_sms'] as num? ?? 500.0;
      final eventTypePrices = pricing['event_type_prices'] as Map<String, dynamic>? ?? {};

      setState(() {
        _pricePerSmsController.text = pricePerSms.toString();
        _walletCurrencyCode = walletCurrencyCode;
        _walletCurrencyTitle = (walletCurrency['title'] ?? 'تومان').toString();
        
        // ایجاد controller برای هر event type
        for (var key in _eventTypeKeys) {
          final price = eventTypePrices[key] as num?;
          if (!_eventTypePriceControllers.containsKey(key)) {
            _eventTypePriceControllers[key] = TextEditingController();
          }
          _eventTypePriceControllers[key]!.text = price?.toString() ?? '';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              '${adminTx(context, 'بارگذاری ناموفق', 'Could not load settings')}: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      final pricePerSms = double.tryParse(_pricePerSmsController.text.trim());
      if (pricePerSms == null || pricePerSms <= 0) {
        throw Exception(adminTx(context, 'قیمت پیش‌فرض باید بیشتر از صفر باشد', 'Default price must be greater than zero'));
      }

      final eventTypePrices = <String, double>{};
      for (var entry in _eventTypePriceControllers.entries) {
        final key = entry.key;
        final controller = entry.value;
        final priceText = controller.text.trim();
        if (priceText.isNotEmpty) {
          final price = double.tryParse(priceText);
          if (price != null && price > 0) {
            eventTypePrices[key] = price;
          }
        }
      }

      await _adminService.setNotificationSmsPricing(
        pricePerSms: pricePerSms,
        eventTypePrices: eventTypePrices.isEmpty ? null : eventTypePrices,
      );

      if (mounted) {
        SnackBarHelper.show(context, message: adminTx(context, 'قیمت‌گذاری ذخیره شد', 'Pricing saved'));
        _load(); // Reload to get updated values
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
        context,
        message:
            '${adminTx(context, 'خطا در ذخیره تنظیمات', 'Could not save settings')}: ${ErrorExtractor.forContext(e, context)}',
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
      title: adminTx(context, 'قیمت پیامک اعلان', 'Notification SMS pricing'),
      subtitle: adminTx(context, 'نرخ ارسال پیامک اعلان‌های سیستم', 'Rate for system notification SMS'),
      actions: [
        IconButton(
          tooltip: adminTx(context, 'ذخیره', 'Save'),
          onPressed: (_loading || _saving || _error != null) ? null : _save,
          icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined, size: 20),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: Text(adminTx(context, 'تلاش مجدد', 'Retry'))),
                    ],
                  ),
                )
              : Form(
        key: _formKey,
        child: ListView(
          padding: context.settingsHub.pagePadding,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      adminTx(context, 'قیمت پیش‌فرض', 'Default price'),
                      style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      adminTx(context, 'برای همهٔ پیامک‌ها، مگر اینکه رویداد قیمت جدا داشته باشد.', 'Used for every SMS unless an event has its own price.'),
                      style: context.settingsHub.cardSubtitleStyle(theme.textTheme, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pricePerSmsController,
                      decoration: InputDecoration(
                        labelText: adminTx(context, 'قیمت هر پیامک', 'Price per SMS') + ' (${_walletCurrencyTitle ?? adminTx(context, 'تومان', 'IRR')})',
                        hintText: '500',
                        isDense: true,
                        prefixIcon: const Icon(Icons.attach_money, size: 18),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return adminTx(context, 'قیمت پیش‌فرض الزامی است', 'Default price is required');
                        }
                        final price = double.tryParse(value.trim());
                        if (price == null || price <= 0) {
                          return adminTx(context, 'قیمت باید بیشتر از صفر باشد', 'Price must be greater than zero');
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
                    Text(
                      adminTx(context, 'قیمت رویدادها', 'Event prices'),
                      style: context.settingsHub.cardTitleStyle(theme.textTheme, color: theme.colorScheme.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      adminTx(context, 'خالی یعنی همان قیمت پیش‌فرض.', 'Empty uses the default price.'),
                      style: context.settingsHub.cardSubtitleStyle(theme.textTheme, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    if (_eventTypes.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          adminTx(context, 'در حال بارگذاری رویدادها...', 'Loading events...'),
                          style: theme.textTheme.bodySmall,
                        ),
                      )
                    else
                      ..._eventTypes.map((eventType) {
                        final code = eventType['code']?.toString() ?? '';
                        final name = eventType['name']?.toString() ?? code;
                        final controller = _eventTypePriceControllers[code] ??= TextEditingController();
                        
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: TextFormField(
                            controller: controller,
                            decoration: InputDecoration(
                              labelText: name,
                              hintText: adminTx(context, 'خالی = قیمت پیش‌فرض', 'Empty = default price'),
                              prefixIcon: const Icon(Icons.event, size: 18),
                              isDense: true,
                              helperText: code,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                            ],
                            validator: (value) {
                              if (value != null && value.trim().isNotEmpty) {
                                final price = double.tryParse(value.trim());
                                if (price == null || price <= 0) {
                                  return adminTx(context, 'قیمت باید بیشتر از صفر باشد', 'Price must be greater than zero');
                                }
                              }
                              return null;
                            },
                          ),
                        );
                      }).toList(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(adminTx(context, 'ذخیره تنظیمات', 'Save settings')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

