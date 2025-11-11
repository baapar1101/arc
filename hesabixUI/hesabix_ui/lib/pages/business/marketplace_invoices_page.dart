import 'package:flutter/material.dart';
import '../../core/auth_store.dart';
import '../../services/marketplace_service.dart';

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
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canView = widget.authStore.hasBusinessPermission('marketplace', 'invoices') ||
        widget.authStore.hasBusinessPermission('marketplace', 'view');
    if (!canView) {
      return Scaffold(
        appBar: AppBar(title: const Text('صورتحساب‌های بازار افزونه')),
        body: Center(child: Text('دسترسی مشاهده صورتحساب‌های بازار را ندارید', style: theme.textTheme.titleMedium)),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('صورتحساب‌های بازار افزونه'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final it = _items[index];
                return ListTile(
                  leading: const Icon(Icons.receipt_long),
                  title: Text(it['code'] ?? '-'),
                  subtitle: Text('مبلغ: ${it['total']} | وضعیت: ${it['status']}'),
                  trailing: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (it['issued_at'] != null) Text('صدور: ${it['issued_at']}'),
                      if (it['paid_at'] != null) Text('پرداخت: ${it['paid_at']}'),
                    ],
                  ),
                );
              },
            ),
    );
  }
}


