import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/auth_store.dart';
import '../../services/price_list_service.dart';
import '../../core/api_client.dart';

class PriceListItemsPage extends StatefulWidget {
  final int businessId;
  final int priceListId;
  final AuthStore authStore;
  final String? priceListName;

  const PriceListItemsPage({
    super.key,
    required this.businessId,
    required this.priceListId,
    required this.authStore,
    this.priceListName,
  });

  @override
  State<PriceListItemsPage> createState() => _PriceListItemsPageState();
}

class _PriceListItemsPageState extends State<PriceListItemsPage> {
  final _svc = PriceListService(apiClient: ApiClient());
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
      _items = await _svc.listItems(businessId: widget.businessId, priceListId: widget.priceListId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در بارگذاری: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.priceListName ?? t.priceLists),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _openEditor(),
            tooltip: t.addPrice,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final it = _items[i];
                final t = AppLocalizations.of(ctx);
                return ListTile(
                  title: Text('${t.products} ${it['product_id']} - ${it['tier_name']}'),
                  subtitle: Text('${t.minQty} ${it['min_qty']} - ${t.price} ${it['price']} - ${t.currency} ${it['currency_id'] ?? '-'}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _openEditor(item: it),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          final ok = await _svc.deleteItem(businessId: widget.businessId, itemId: it['id'] as int);
                          if (ok) _load();
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _openEditor({Map<String, dynamic>? item}) async {
    final formKey = GlobalKey<FormState>();
    int? productId = item?['product_id'] as int?;
    String tierName = (item?['tier_name'] as String?) ?? 'تکی';
    int? unitId = item?['unit_id'] as int?;
    num minQty = (item?['min_qty'] as num?) ?? 0;
    num price = (item?['price'] as num?) ?? 0;
    int? currencyId = item?['currency_id'] as int? ?? (_fallbackCurrencies.first['id'] as int);

    await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final t = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(item == null ? t.addPriceTitle : t.editPriceTitle),
          content: SizedBox(
            width: 520,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: productId?.toString(),
                    decoration: InputDecoration(labelText: t.productId),
                    keyboardType: TextInputType.number,
                    validator: (v) => (int.tryParse(v ?? '') == null) ? t.invalid : null,
                    onChanged: (v) => productId = int.tryParse(v),
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: currencyId,
                    items: _fallbackCurrencies
                        .map((c) => DropdownMenuItem<int>(
                              value: c['id'] as int,
                              child: Text('${c['title']} (${c['code']})'),
                            ))
                        .toList(),
                    onChanged: (v) => currencyId = v,
                    decoration: InputDecoration(labelText: t.currency),
                    validator: (v) => (v == null) ? t.required : null,
                  ),
                  TextFormField(
                    initialValue: tierName,
                    decoration: const InputDecoration(labelText: 'نام پله (مثلاً: تکی/عمده/همکار)'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? t.required : null,
                    onChanged: (v) => tierName = v,
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: unitId,
                    items: _fallbackUnits
                        .map((u) => DropdownMenuItem<int>(
                              value: u['id'] as int,
                              child: Text(u['title'] as String),
                            ))
                        .toList(),
                    onChanged: (v) => unitId = v,
                    decoration: InputDecoration(labelText: t.unit),
                  ),
                  TextFormField(
                    initialValue: minQty.toString(),
                    decoration: InputDecoration(labelText: t.minQty),
                    keyboardType: TextInputType.number,
                    validator: (v) => (num.tryParse(v ?? '') == null) ? t.invalid : null,
                    onChanged: (v) => minQty = num.tryParse(v) ?? 0,
                  ),
                  TextFormField(
                    initialValue: price.toString(),
                    decoration: InputDecoration(labelText: t.price),
                    keyboardType: TextInputType.number,
                    validator: (v) => (num.tryParse(v ?? '') == null) ? t.invalid : null,
                    onChanged: (v) => price = num.tryParse(v) ?? 0,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(AppLocalizations.of(ctx).cancel)),
            FilledButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                try {
                  final payload = {
                    'product_id': productId,
                    'tier_name': tierName,
                    'unit_id': unitId,
                    'min_qty': minQty,
                    'price': price,
                    'currency_id': currencyId,
                  }..removeWhere((k, v) => v == null);
                  await _svc.upsertItem(
                    businessId: widget.businessId,
                    priceListId: widget.priceListId,
                    payload: payload,
                  );
                  if (mounted) Navigator.of(ctx).pop(true);
                  _load();
                } catch (e) {
                  String message = t.operationFailed;
                  if (e is DioException) {
                    final data = e.response?.data;
                    final serverMsg = (data is Map && data['error'] is Map) ? (data['error']['message']?.toString()) : null;
                    message = serverMsg?.isNotEmpty == true ? serverMsg! : (e.message ?? message);
                  }
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message)),
                    );
                  }
                }
              },
              child: Text(AppLocalizations.of(ctx).save),
            ),
          ],
        );
      },
    );
  }

  List<Map<String, dynamic>> get _fallbackUnits => [
        {'id': 1, 'title': 'عدد'},
        {'id': 2, 'title': 'کیلوگرم'},
        {'id': 3, 'title': 'لیتر'},
      ];

  List<Map<String, dynamic>> get _fallbackCurrencies => [
        {'id': 1, 'title': 'تومان', 'code': 'IRR'},
        {'id': 2, 'title': 'دلار آمریکا', 'code': 'USD'},
      ];
}


