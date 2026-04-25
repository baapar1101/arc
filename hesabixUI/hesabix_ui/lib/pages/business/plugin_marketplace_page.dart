import 'package:flutter/material.dart';
import '../../core/auth_store.dart';
import '../../core/api_client.dart';
import '../../services/marketplace_service.dart';
import '../../services/wallet_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;

class PluginMarketplacePage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  const PluginMarketplacePage({super.key, required this.businessId, required this.authStore});

  @override
  State<PluginMarketplacePage> createState() => _PluginMarketplacePageState();
}

class _PluginMarketplacePageState extends State<PluginMarketplacePage> {
  final MarketplaceService _marketplace = MarketplaceService();
  final WalletService _wallet = WalletService(ApiClient());
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _plugins = const [];
  Map<String, dynamic>? _walletOverview;
  List<Map<String, dynamic>> _businessPlugins = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _marketplace.listPlugins();
      final overview = await _wallet.getOverview(businessId: widget.businessId);
      // دریافت لیست افزونه‌های خریداری شده
      final businessPlugins = await _marketplace.listBusinessPlugins(businessId: widget.businessId);
      setState(() {
        _plugins = items;
        _walletOverview = overview;
        _businessPlugins = businessPlugins.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'خطا در بارگذاری: ${ErrorExtractor.forContext(e, context)}';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _startTrial(int pluginId) async {
    if (!widget.authStore.hasBusinessPermission('marketplace', 'buy')) {
      _showSnack('دسترسی شروع trial ندارید');
      return;
    }
    try {
      await _marketplace.startTrial(
        businessId: widget.businessId,
        pluginId: pluginId,
      );
      _showSnack('دوره trial با موفقیت شروع شد');
      await _load();
    } catch (e) {
      if (!mounted) return;
      String errorMessage = 'خطا در شروع trial';
      final raw = e.toString();
      if (raw.contains('TRIAL_ALREADY_USED')) {
        errorMessage = 'شما قبلاً از trial این افزونه استفاده کرده‌اید';
      } else if (raw.contains('TRIAL_NOT_ALLOWED')) {
        errorMessage = 'این افزونه trial ندارد';
      } else if (raw.contains('PLUGIN_ALREADY_ACTIVE')) {
        errorMessage = 'این افزونه قبلاً برای شما فعال شده است';
      } else {
        errorMessage =
            'خطا در شروع trial: ${ErrorExtractor.forContext(e, context)}';
      }
      _showSnack(errorMessage);
    }
  }

  Future<void> _purchase(int pluginId, int planId) async {
    if (!widget.authStore.hasBusinessPermission('marketplace', 'buy')) {
      _showSnack('دسترسی خرید ندارید');
      return;
    }
    try {
      final res = await _marketplace.purchase(
        businessId: widget.businessId,
        pluginId: pluginId,
        planId: planId,
      );
      if ((res['status'] ?? '') == 'paid') {
        _showSnack('خرید با موفقیت انجام شد');
        await _load();
      } else if ((res['status'] ?? '') == 'insufficient_funds') {
        final shortfall = (res['shortfall'] ?? 0).toDouble();
        final required = (res['required_amount'] ?? 0).toDouble();
        final available = (res['available_amount'] ?? 0).toDouble();
        _showSnack('موجودی کافی نیست. مبلغ مورد نیاز: ${formatWithThousands(required, decimalPlaces: 0)}، موجودی: ${formatWithThousands(available, decimalPlaces: 0)}، کسری: ${formatWithThousands(shortfall, decimalPlaces: 0)}');
      } else {
        _showSnack('نتیجه خرید: ${res['status']}');
      }
    } catch (e) {
      if (!mounted) return;
      String errorMessage = 'خطا در خرید افزونه';
      final raw = e.toString();
      if (raw.contains('PLUGIN_NOT_FOUND')) {
        errorMessage = 'افزونه یافت نشد یا غیرفعال است';
      } else if (raw.contains('PLAN_NOT_FOUND')) {
        errorMessage = 'پلن افزونه یافت نشد یا غیرفعال است';
      } else if (raw.contains('INVALID_QUANTITY')) {
        errorMessage = 'تعداد نامعتبر است';
      } else if (raw.contains('CURRENCY_NOT_FOUND')) {
        errorMessage = 'ارز پلن نامعتبر است';
      } else if (raw.contains('BUSINESS_NOT_FOUND')) {
        errorMessage = 'کسب‌وکار یافت نشد';
      } else {
        errorMessage =
            'خطا در خرید: ${ErrorExtractor.forContext(e, context)}';
      }
      _showSnack(errorMessage);
    }
  }

  Future<void> _confirmAndPurchase({
    required int pluginId,
    required int planId,
    required String pluginName,
    required String period,
    required double price,
    required String currencySymbol,
  }) async {
    final availableAmount = (_walletOverview?['available_balance'] ?? 0).toDouble();
    final available = formatWithThousands(availableAmount, decimalPlaces: 0);
    final walletCurrency = _getWalletCurrencySymbol();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('تایید خرید افزونه'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('افزونه: $pluginName'),
              Text('پلن: $period'),
              Text('مبلغ: ${_formatPrice(price, currencySymbol)}'),
              const SizedBox(height: 8),
              Text('موجودی کیف‌پول: $available $walletCurrency'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('تایید و پرداخت')),
          ],
        );
      },
    );
    if (confirmed == true) {
      await _purchase(pluginId, planId);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    SnackBarHelper.show(context, message: msg);
  }

  String _getCurrencySymbol(Map<String, dynamic>? plan) {
    if (plan == null) {
      // fallback به ارز پیش‌فرض کیف‌پول
      return _getWalletCurrencySymbol();
    }
    final currency = plan['currency'] as Map<String, dynamic>?;
    if (currency != null) {
      final symbol = currency['symbol']?.toString();
      if (symbol != null && symbol.isNotEmpty) {
        return symbol;
      }
      final code = currency['code']?.toString();
      if (code != null && code.isNotEmpty) {
        return code;
      }
    }
    // fallback به ارز پیش‌فرض کیف‌پول
    return _getWalletCurrencySymbol();
  }

  String _getWalletCurrencySymbol() {
    // استفاده از symbol ارز پیش‌فرض کیف‌پول
    final symbol = _walletOverview?['base_currency_symbol']?.toString();
    if (symbol != null && symbol.isNotEmpty) {
      return symbol;
    }
    // fallback به code در صورت نبودن symbol
    final code = _walletOverview?['base_currency_code']?.toString() ?? 'IRR';
    return code;
  }

  Map<String, dynamic>? _getBusinessPluginStatus(int pluginId) {
    try {
      return _businessPlugins.firstWhere(
        (bp) => (bp['plugin_id'] as num?)?.toInt() == pluginId,
        orElse: () => <String, dynamic>{},
      );
    } catch (_) {
      return null;
    }
  }

  String _formatPrice(double price, String symbol) {
    return '${formatWithThousands(price, decimalPlaces: 0)} $symbol';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('بازار افزونه‌ها')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    
    final canView = widget.authStore.hasBusinessPermission('marketplace', 'view');
    if (!canView) {
      return Scaffold(
        appBar: AppBar(title: const Text('بازار افزونه‌ها')),
        body: Center(
          child: Text('دسترسی مشاهده بازار افزونه‌ها را ندارید', style: theme.textTheme.titleMedium),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('بازار افزونه‌ها')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(_error!, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error)),
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

    final availableAmount = (_walletOverview?['available_balance'] ?? 0).toDouble();
    final available = formatWithThousands(availableAmount, decimalPlaces: 0);
    final walletCurrency = _getWalletCurrencySymbol();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('بازار افزونه‌ها'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.account_balance_wallet, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('موجودی قابل برداشت: $available $walletCurrency'),
                const Spacer(),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            ),
          ),
          Expanded(
            child: _plugins.isEmpty
                ? Center(
                    child: Text(
                      'هیچ افزونه‌ای در دسترس نیست',
                      style: theme.textTheme.bodyLarge,
                    ),
                  )
                : ListView.separated(
                    itemCount: _plugins.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final p = _plugins[index];
                      final plans = (p['plans'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
                      final pluginStatus = _getBusinessPluginStatus(p['id'] as int? ?? 0);
                      final isPurchased = pluginStatus != null && pluginStatus.isNotEmpty;
                      final isActive = pluginStatus?['is_active'] == true;
                      final isExpired = pluginStatus?['is_expired'] == true;
                      final isTrial = pluginStatus?['is_trial'] == true;
                      final trialRemainingDays = pluginStatus?['trial_remaining_days'] as int?;
                      final trialAllowed = p['trial_allowed'] == true;
                      final trialDays = p['trial_days'] as int?;
                      final hasUsedTrial = pluginStatus != null && 
                          (pluginStatus['is_trial'] == true || 
                           (pluginStatus['is_trial'] == false && pluginStatus['trial_started_at'] != null));
                      
                      // اگر افزونه پلن نداشته باشد، نمایش نده
                      if (plans.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  // نمایش آیکون افزونه یا آیکون پیش‌فرض
                                  if (p['icon_url'] != null && (p['icon_url'] as String).isNotEmpty)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        p['icon_url'] as String,
                                        width: 48,
                                        height: 48,
                                        errorBuilder: (_, __, ___) => Icon(
                                          Icons.extension,
                                          size: 48,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    )
                                  else
                                    Icon(Icons.extension, size: 48, color: theme.colorScheme.primary),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p['name'] ?? '-',
                                          style: theme.textTheme.titleMedium,
                                        ),
                                        if (p['category'] != null && (p['category'] as String).isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Chip(
                                            label: Text(
                                              p['category'] as String,
                                              style: theme.textTheme.labelSmall,
                                            ),
                                            padding: EdgeInsets.zero,
                                          ),
                                        ],
                                        if (isPurchased) ...[
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                isActive ? Icons.check_circle : Icons.cancel,
                                                size: 16,
                                                color: isActive ? Colors.green : Colors.red,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                isTrial
                                                    ? (trialRemainingDays != null && trialRemainingDays > 0
                                                        ? 'در حال تست (${trialRemainingDays} روز باقی مانده)'
                                                        : 'تست منقضی شده')
                                                    : isActive
                                                        ? 'فعال'
                                                        : isExpired
                                                            ? 'منقضی شده'
                                                            : 'غیرفعال',
                                                style: theme.textTheme.labelSmall?.copyWith(
                                                  color: isTrial 
                                                      ? (trialRemainingDays != null && trialRemainingDays > 0
                                                          ? Colors.orange
                                                          : Colors.red)
                                                      : isActive 
                                                          ? Colors.green 
                                                          : Colors.red,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                        if (trialAllowed && !isPurchased) ...[
                                          const SizedBox(height: 4),
                                          Chip(
                                            label: Text(
                                              'تست رایگان ${trialDays ?? 7} روزه',
                                              style: theme.textTheme.labelSmall?.copyWith(
                                                color: Colors.blue,
                                              ),
                                            ),
                                            avatar: const Icon(Icons.free_breakfast, size: 16, color: Colors.blue),
                                            padding: EdgeInsets.zero,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if ((p['description'] ?? '').toString().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  p['description'] as String,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                              const SizedBox(height: 12),
                              // دکمه شروع trial (اگر trial مجاز است و هنوز استفاده نشده)
                              if (trialAllowed && !isPurchased && !hasUsedTrial) ...[
                                OutlinedButton.icon(
                                  onPressed: widget.authStore.hasBusinessPermission('marketplace', 'buy')
                                      ? () => _startTrial(p['id'] as int)
                                      : null,
                                  icon: const Icon(Icons.free_breakfast),
                                  label: Text('شروع تست رایگان ${trialDays ?? 7} روزه'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.blue,
                                    side: const BorderSide(color: Colors.blue),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: plans.map((pl) {
                                  final period = pl['period'] ?? '-';
                                  final price = (pl['price'] ?? 0).toDouble();
                                  final currencySymbol = _getCurrencySymbol(pl);
                                  final label = '${period == 'monthly' ? 'ماهانه' : period == 'yearly' ? 'سالانه' : 'مادام‌العمر'} - ${_formatPrice(price, currencySymbol)}';
                                  final canBuy = widget.authStore.hasBusinessPermission('marketplace', 'buy');
                                  final isPlanPurchased = isPurchased && 
                                      (pluginStatus?['plan_id'] as num?)?.toInt() == (pl['id'] as num?)?.toInt();
                                  
                                  return ElevatedButton.icon(
                                    onPressed: canBuy && !isPlanPurchased
                                        ? () => _confirmAndPurchase(
                                              pluginId: p['id'] as int,
                                              planId: pl['id'] as int,
                                              pluginName: (p['name'] ?? '-') as String,
                                              period: period == 'monthly'
                                                  ? 'ماهانه'
                                                  : period == 'yearly'
                                                      ? 'سالانه'
                                                      : 'مادام‌العمر',
                                              price: price,
                                              currencySymbol: currencySymbol,
                                            )
                                        : null,
                                    icon: Icon(isPlanPurchased ? Icons.check_circle : Icons.shopping_cart_checkout),
                                    label: Text(isPlanPurchased ? 'خریداری شده' : label),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isPlanPurchased
                                          ? Colors.green.withOpacity(0.1)
                                          : null,
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
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
}



