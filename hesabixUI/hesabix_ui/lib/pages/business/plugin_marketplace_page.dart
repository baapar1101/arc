import 'package:flutter/material.dart';
import '../../core/auth_store.dart';
import '../../core/api_client.dart';
import '../../services/marketplace_service.dart';
import '../../services/wallet_service.dart';
import '../../utils/snackbar_helper.dart';

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
  List<Map<String, dynamic>> _plugins = const [];
  Map<String, dynamic>? _walletOverview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await _marketplace.listPlugins();
      final overview = await _wallet.getOverview(businessId: widget.businessId);
      setState(() {
        _plugins = items;
        _walletOverview = overview;
      });
    } finally {
      setState(() => _loading = false);
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
        final shortfall = res['shortfall'] ?? 0;
        _showSnack('موجودی کافی نیست. کسری: $shortfall');
      } else {
        _showSnack('نتیجه خرید: ${res['status']}');
      }
    } catch (e) {
      _showSnack('خطا در خرید: $e');
    }
  }

  Future<void> _confirmAndPurchase({
    required int pluginId,
    required int planId,
    required String pluginName,
    required String period,
    required double price,
  }) async {
    final available = (_walletOverview?['balances']?['available'] ?? 0).toString();
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
              Text('مبلغ: $price'),
              const SizedBox(height: 8),
              Text('موجودی کیف‌پول: $available'),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final canView = widget.authStore.hasBusinessPermission('marketplace', 'view');
    if (!canView) {
      return Center(
        child: Text('دسترسی مشاهده بازار افزونه‌ها را ندارید', style: theme.textTheme.titleMedium),
      );
    }
    final available = (_walletOverview?['balances']?['available'] ?? 0).toString();
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
                Text('موجودی قابل برداشت: $available'),
                const Spacer(),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: _plugins.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final p = _plugins[index];
                final plans = (p['plans'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.extension),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(p['name'] ?? '-', style: theme.textTheme.titleMedium),
                            ),
                          ],
                        ),
                        if ((p['description'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(p['description']),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: plans.map((pl) {
                            final label = '${pl['period']} - ${pl['price']}';
                            final canBuy = widget.authStore.hasBusinessPermission('marketplace', 'buy');
                            return ElevatedButton.icon(
                              onPressed: canBuy
                                  ? () => _confirmAndPurchase(
                                        pluginId: p['id'] as int,
                                        planId: pl['id'] as int,
                                        pluginName: (p['name'] ?? '-') as String,
                                        period: (pl['period'] ?? '-') as String,
                                        price: (pl['price'] ?? 0).toDouble(),
                                      )
                                  : null,
                              icon: const Icon(Icons.shopping_cart_checkout),
                              label: Text(label),
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


