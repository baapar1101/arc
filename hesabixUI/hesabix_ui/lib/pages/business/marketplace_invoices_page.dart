import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/auth_store.dart';
import '../../services/marketplace_service.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;

class MarketplaceInvoicesPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  const MarketplaceInvoicesPage({super.key, required this.businessId, required this.authStore});

  @override
  State<MarketplaceInvoicesPage> createState() => _MarketplaceInvoicesPageState();
}

class _MarketplaceInvoicesPageState extends State<MarketplaceInvoicesPage> {
  final MarketplaceService _marketplace = MarketplaceService();
  bool _loading = true;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _marketplace.listInvoices(businessId: widget.businessId, page: 1, limit: 50);
      final items = (res['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      setState(() {
        _items = items;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final canView = widget.authStore.hasBusinessPermission('marketplace', 'invoices') ||
        widget.authStore.hasBusinessPermission('marketplace', 'view');
    if (!canView) {
      return Scaffold(
        appBar: AppBar(title: Text(t.pluginMarketplaceInvoicesLink)),
        body: Center(
          child: Text(t.pluginMarketplaceNoPermissionView, style: theme.textTheme.titleMedium),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(t.pluginMarketplaceInvoicesLink),
        actions: [
          IconButton(
            tooltip: t.pluginMarketplaceRefresh,
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 56, color: cs.outline),
                      const SizedBox(height: 12),
                      Text(t.pluginMarketplaceEmpty, style: theme.textTheme.titleMedium),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final it = _items[index];
                      final total = (it['total'] ?? 0).toDouble();
                      final currency = it['currency'] as Map<String, dynamic>?;
                      final currencySymbol = currency?['symbol']?.toString() ?? currency?['code']?.toString() ?? '';
                      final totalFormatted = formatWithThousands(total, decimalPlaces: 0);
                      final totalText = currencySymbol.isNotEmpty
                          ? '$totalFormatted $currencySymbol'
                          : totalFormatted;
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: cs.primaryContainer,
                            child: Icon(Icons.receipt_long, color: cs.onPrimaryContainer),
                          ),
                          title: Text(it['code'] ?? '-'),
                          subtitle: Text('${t.pluginMarketplaceConfirmPurchaseAmount}: $totalText · ${it['status']}'),
                          isThreeLine: it['issued_at'] != null || it['paid_at'] != null,
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
