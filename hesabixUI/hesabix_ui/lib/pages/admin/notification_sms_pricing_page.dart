import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/api_client.dart';
import '../../services/admin_system_settings_service.dart';
import '../../services/system_settings_service.dart';
import '../../services/currency_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/number_normalizer.dart';

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
              'خطا در بارگذاری تنظیمات: ${ErrorExtractor.forContext(e, context)}',
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
        throw Exception('قیمت پیش‌فرض باید بزرگتر از صفر باشد');
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
        SnackBarHelper.show(context, message: 'تنظیمات قیمت‌گذاری با موفقیت ذخیره شد');
        _load(); // Reload to get updated values
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
        context,
        message:
            'خطا در ذخیره تنظیمات: ${ErrorExtractor.forContext(e, context)}',
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
    final t = AppLocalizations.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('قیمت‌گذاری پیامک ناتیفیکیشن')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('قیمت‌گذاری پیامک ناتیفیکیشن')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _load,
                child: const Text('تلاش مجدد'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('قیمت‌گذاری پیامک ناتیفیکیشن'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'قیمت پیش‌فرض',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'این قیمت برای تمام پیامک‌های ناتیفیکیشن استفاده می‌شود مگر اینکه قیمت خاصی برای event type تعریف شده باشد.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _pricePerSmsController,
                      decoration: InputDecoration(
                        labelText: 'قیمت هر پیامک (${_walletCurrencyTitle ?? 'تومان'})',
                        hintText: 'مثلاً 500',
                        prefixIcon: const Icon(Icons.attach_money),
                        suffixText: _walletCurrencyTitle ?? 'تومان',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'قیمت پیش‌فرض الزامی است';
                        }
                        final price = double.tryParse(value.trim());
                        if (price == null || price <= 0) {
                          return 'قیمت باید بزرگتر از صفر باشد';
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
                      'قیمت‌های خاص برای Event Types',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'می‌توانید برای هر نوع رویداد قیمت خاصی تعریف کنید. در غیر این صورت از قیمت پیش‌فرض استفاده می‌شود.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_eventTypes.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'در حال بارگذاری انواع رویدادها...',
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
                              hintText: 'خالی = استفاده از قیمت پیش‌فرض',
                              prefixIcon: const Icon(Icons.event),
                              suffixText: _walletCurrencyTitle ?? 'تومان',
                              helperText: 'کد: $code',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                            ],
                            validator: (value) {
                              if (value != null && value.trim().isNotEmpty) {
                                final price = double.tryParse(value.trim());
                                if (price == null || price <= 0) {
                                  return 'قیمت باید بزرگتر از صفر باشد';
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
                    : const Text('ذخیره تنظیمات'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

