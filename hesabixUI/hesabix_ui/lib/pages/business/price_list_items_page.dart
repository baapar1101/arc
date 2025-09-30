import 'package:flutter/material.dart';
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
            tooltip: 'افزودن قیمت',
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
                return ListTile(
                  title: Text('کالا ${it['product_id']} - ${it['tier_name']}'),
                  subtitle: Text('حداقل ${it['min_qty']} - قیمت ${it['price']}'),
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

    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item == null ? 'افزودن قیمت' : 'ویرایش قیمت'),
        content: SizedBox(
          width: 520,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: productId?.toString(),
                  decoration: const InputDecoration(labelText: 'شناسه کالا'),
                  keyboardType: TextInputType.number,
                  validator: (v) => (int.tryParse(v ?? '') == null) ? 'نامعتبر' : null,
                  onChanged: (v) => productId = int.tryParse(v),
                ),
                TextFormField(
                  initialValue: tierName,
                  decoration: const InputDecoration(labelText: 'نام پله (مثلاً: تکی/عمده/همکار)'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'ضروری' : null,
                  onChanged: (v) => tierName = v,
                ),
                DropdownButtonFormField<int>(
                  value: unitId,
                  items: _fallbackUnits
                      .map((u) => DropdownMenuItem<int>(
                            value: u['id'] as int,
                            child: Text(u['title'] as String),
                          ))
                      .toList(),
                  onChanged: (v) => unitId = v,
                  decoration: const InputDecoration(labelText: 'واحد'),
                ),
                TextFormField(
                  initialValue: minQty.toString(),
                  decoration: const InputDecoration(labelText: 'حداقل تعداد'),
                  keyboardType: TextInputType.number,
                  validator: (v) => (num.tryParse(v ?? '') == null) ? 'نامعتبر' : null,
                  onChanged: (v) => minQty = num.tryParse(v) ?? 0,
                ),
                TextFormField(
                  initialValue: price.toString(),
                  decoration: const InputDecoration(labelText: 'قیمت'),
                  keyboardType: TextInputType.number,
                  validator: (v) => (num.tryParse(v ?? '') == null) ? 'نامعتبر' : null,
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
              final payload = {
                'product_id': productId,
                'tier_name': tierName,
                'unit_id': unitId,
                'min_qty': minQty,
                'price': price,
              }..removeWhere((k, v) => v == null);
              await _svc.upsertItem(
                businessId: widget.businessId,
                priceListId: widget.priceListId,
                payload: payload,
              );
              if (mounted) Navigator.of(ctx).pop(true);
              _load();
            },
            child: Text(AppLocalizations.of(ctx).save),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _fallbackUnits => [
        {'id': 1, 'title': 'عدد'},
        {'id': 2, 'title': 'کیلوگرم'},
        {'id': 3, 'title': 'لیتر'},
      ];
}


