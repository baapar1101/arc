import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/product_service.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../widgets/product/product_form_dialog.dart';

class ProductComboboxWidget extends StatefulWidget {
  final int businessId;
  final Map<String, dynamic>? selectedProduct;
  final ValueChanged<Map<String, dynamic>?> onChanged;
  final String label;
  final String hintText;
  final AuthStore? authStore;

  const ProductComboboxWidget({
    super.key,
    required this.businessId,
    required this.onChanged,
    this.selectedProduct,
    this.label = 'کالا/خدمت',
    this.hintText = 'جست‌وجو و انتخاب کالا/خدمت',
    this.authStore,
  });

  @override
  State<ProductComboboxWidget> createState() => _ProductComboboxWidgetState();
}

class _ProductComboboxWidgetState extends State<ProductComboboxWidget> {
  final ProductService _service = ProductService(apiClient: ApiClient());
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = widget.selectedProduct != null
        ? ('${widget.selectedProduct!['code']?.toString() ?? ''} - ${widget.selectedProduct!['name']?.toString() ?? ''}')
        : '';
    _loadRecent();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    setState(() => _loading = true);
    try {
      final items = await _service.searchProducts(
        businessId: widget.businessId,
        searchQuery: null,
        limit: 10,
        searchFields: const ['code', 'name'],
      );
      if (!mounted) return;
      setState(() => _items = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _items = const <Map<String, dynamic>>[]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _performSearch(q.trim()));
  }

  Future<void> _performSearch(String q) async {
    if (q.isEmpty) {
      await _loadRecent();
      return;
    }
    setState(() => _loading = true);
    try {
      final items = await _service.searchProducts(
        businessId: widget.businessId,
        searchQuery: q,
        limit: 20,
        searchFields: const ['code', 'name'],
      );
      if (!mounted) return;
      setState(() => _items = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _items = const <Map<String, dynamic>>[]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(Map<String, dynamic>? item) {
    if (item == null) {
      _searchCtrl.clear();
      widget.onChanged(null);
      return;
    }
    final code = item['code']?.toString() ?? '';
    final name = item['name']?.toString() ?? '';
    _searchCtrl.text = code.isNotEmpty ? '$code - $name' : name;
    widget.onChanged(item);
  }

  Future<void> _addNewProduct(BuildContext bottomSheetContext) async {
    final authStore = widget.authStore;
    if (authStore == null) {
      // اگر AuthStore ارائه نشده باشد، نمی‌توانیم کالای جدید اضافه کنیم
      return;
    }

    // بستن bottom sheet قبل از باز کردن dialog
    Navigator.pop(bottomSheetContext);

    final result = await showDialog<dynamic>(
      context: context,
      builder: (context) => ProductFormDialog(
        businessId: widget.businessId,
        authStore: authStore,
        onSuccess: () {},
      ),
    );
    
    if (result != null && result != false && mounted) {
      int? newProductId;
      if (result is int) {
        newProductId = result;
      } else if (result == true) {
        // اگر true برگردانده شد، از روش fallback استفاده می‌کنیم
      }
      
      // اگر ID کالای جدید را داریم، مستقیماً آن را جستجو و انتخاب کنیم
      if (newProductId != null) {
        try {
          final product = await _service.getProduct(
            businessId: widget.businessId,
            productId: newProductId,
          );
          if (product.isNotEmpty && mounted) {
            _select(product);
            return;
          }
        } catch (_) {
          // اگر خطا رخ داد، به روش قبلی برمی‌گردیم
        }
      }
      
      // Refresh لیست و پیدا کردن کالای جدید
      await _loadRecent();
      
      // پیدا کردن کالای جدید (احتمالاً آخرین آیتم در لیست یا آیتمی با بیشترین ID)
      if (_items.isNotEmpty) {
        // مرتب‌سازی بر اساس ID (بزرگترین = جدیدترین)
        final sortedItems = List<Map<String, dynamic>>.from(_items);
        sortedItems.sort((a, b) {
          final idA = (a['id'] as num?)?.toInt() ?? 0;
          final idB = (b['id'] as num?)?.toInt() ?? 0;
          return idB.compareTo(idA);
        });
        _select(sortedItems.first);
      }
    }
  }

  void _openPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(widget.label, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (widget.authStore != null)
                      IconButton(
                        onPressed: () => _addNewProduct(ctx),
                        icon: const Icon(Icons.add),
                        tooltip: 'افزودن کالا/خدمت جدید',
                        color: theme.colorScheme.primary,
                      ),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: _onQueryChanged,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (separatorContext, separatorIndex) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final it = _items[index];
                            final code = it['code']?.toString() ?? '';
                            final name = it['name']?.toString() ?? '';
                            final itemType = it['item_type']?.toString() ?? '';
                            return ListTile(
                              leading: const Icon(Icons.inventory_2_outlined),
                              title: Text(code.isNotEmpty ? '$code - $name' : name),
                              subtitle: itemType.isNotEmpty ? Text(itemType) : null,
                              onTap: () {
                                _select(it);
                                Navigator.pop(ctx);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final display = widget.selectedProduct != null
        ? (((widget.selectedProduct!['code']?.toString() ?? '').isNotEmpty)
            ? '${widget.selectedProduct!['code']} - ${widget.selectedProduct!['name']}'
            : (widget.selectedProduct!['name']?.toString() ?? ''))
        : widget.hintText;

    return InkWell(
      onTap: _openPicker,
      child: Tooltip(
        message: display,
        waitDuration: const Duration(milliseconds: 600),
        preferBelow: true,
        child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(8),
          color: colorScheme.surface,
        ),
        child: Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: colorScheme.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                display,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500, fontSize: 13.5),
              ),
            ),
            Icon(Icons.arrow_drop_down, color: colorScheme.onSurface.withValues(alpha: 0.6), size: 20),
          ],
        ),
        ),
      ),
    );
  }
}


