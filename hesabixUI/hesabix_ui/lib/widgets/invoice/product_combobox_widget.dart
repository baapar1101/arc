import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart' as dio;
import '../../services/product_service.dart';
import '../../services/warehouse_service.dart';
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
  final WarehouseService _warehouseService = WarehouseService();
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _initializeSelectedProduct();
    _loadRecent();
  }

  @override
  void didUpdateWidget(ProductComboboxWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedProduct?['id'] != widget.selectedProduct?['id']) {
      _initializeSelectedProduct();
    }
  }

  Future<void> _initializeSelectedProduct() async {
    if (widget.selectedProduct == null) {
      _searchCtrl.text = '';
      return;
    }

    final productId = widget.selectedProduct!['id'] as int?;
    final hasCode = widget.selectedProduct!['code'] != null;
    final hasName = widget.selectedProduct!['name'] != null;

    // اگر اطلاعات کامل (code و name) موجود است، از آن استفاده می‌کنیم
    if (hasCode || hasName) {
      final code = widget.selectedProduct!['code']?.toString() ?? '';
      final name = widget.selectedProduct!['name']?.toString() ?? '';
      _searchCtrl.text = code.isNotEmpty ? '$code - $name' : name;
      return;
    }

    // اگر فقط id موجود است، باید اطلاعات کامل را از API دریافت کنیم
    if (productId != null) {
      try {
        final product = await _service.getProduct(
          businessId: widget.businessId,
          productId: productId,
        );
        if (mounted && product.isNotEmpty) {
          final code = product['code']?.toString() ?? '';
          final name = product['name']?.toString() ?? '';
          _searchCtrl.text = code.isNotEmpty ? '$code - $name' : name;
          // اضافه کردن به لیست items اگر وجود نداشته باشد
          if (mounted) {
            final existsInList = _items.any((item) => (item['id'] as num?)?.toInt() == productId);
            if (!existsInList) {
              setState(() {
                _items = [product, ..._items];
              });
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading product info: $e');
        // در صورت خطا، حداقل id را نمایش می‌دهیم
        if (mounted) {
          _searchCtrl.text = 'کالا #$productId';
        }
      }
    } else {
      _searchCtrl.text = '';
    }
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

  Future<void> _searchByBarcode(BuildContext bottomSheetContext, VoidCallback refreshBottomSheet) async {
    final barcodeController = TextEditingController();
    
    await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('جستجو با بارکد/سریال'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: barcodeController,
              decoration: const InputDecoration(
                labelText: 'بارکد یا سریال نامبر',
                hintText: 'بارکد یا سریال را وارد کنید',
                prefixIcon: Icon(Icons.qr_code_scanner),
              ),
              autofocus: true,
              onSubmitted: (value) async {
                if (value.trim().isNotEmpty) {
                  await _performBarcodeSearch(value.trim(), context, refreshBottomSheet);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () async {
              if (barcodeController.text.trim().isNotEmpty) {
                await _performBarcodeSearch(barcodeController.text.trim(), context, refreshBottomSheet);
              }
            },
            child: const Text('جستجو'),
          ),
        ],
      ),
    );
  }

  Future<void> _performBarcodeSearch(String code, BuildContext dialogContext, VoidCallback refreshBottomSheet) async {
    try {
      final instanceData = await _warehouseService.searchInstanceByCode(
        businessId: widget.businessId,
        code: code,
      );
      
      // بررسی اینکه آیا چند نتیجه برگردانده شده یا نه
      final multipleResults = instanceData['multiple_results'] == true;
      final items = instanceData['items'] as List?;
      
      Map<String, dynamic>? selectedInstance;
      
      if (multipleResults && items != null && items.isNotEmpty) {
        // اگر چند نتیجه پیدا شد، دیالوگ انتخاب نمایش بده
        if (!dialogContext.mounted) return;
        selectedInstance = await showDialog<Map<String, dynamic>>(
          context: dialogContext,
          builder: (context) => _InstanceSelectionDialog(
            instances: items,
            searchCode: code,
          ),
        );
        
        if (selectedInstance == null) {
          return; // کاربر انصراف داد
        }
      } else {
        // اگر یک نتیجه یا نتیجه مستقیم برگردانده شد
        selectedInstance = instanceData;
      }
      
      final productId = selectedInstance['product_id'] as int?;
      if (productId == null) {
        if (dialogContext.mounted) {
          ScaffoldMessenger.of(dialogContext).showSnackBar(
            const SnackBar(content: Text('کالای یونیکی با این بارکد/سریال یافت نشد')),
          );
        }
        return;
      }
      
      // دریافت اطلاعات کالا
      final product = await _service.getProduct(
        businessId: widget.businessId,
        productId: productId,
      );
      
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
        
        // به‌روزرسانی لیست: اضافه کردن محصول انتخاب شده به لیست یا refresh لیست
        if (mounted) {
          // بررسی اینکه آیا محصول در لیست وجود دارد یا نه
          final existsInList = _items.any((item) => (item['id'] as num?)?.toInt() == productId);
          if (!existsInList) {
            // اگر در لیست نیست، به ابتدای لیست اضافه کن
            setState(() {
              _items = [product, ..._items];
            });
          } else {
            // اگر در لیست است، لیست را refresh کن تا محصول در ابتدا قرار بگیرد
            await _loadRecent();
          }
        }
        
        // انتخاب محصول
        _select(product);
        
        // به‌روزرسانی لیست در bottom sheet
        refreshBottomSheet();
        
        // بستن bottom sheet اگر باز است
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }
    } on dio.DioException catch (e) {
      String errorMessage = 'خطا در جستجو';
      if (e.response != null) {
        final data = e.response?.data;
        if (data is Map<String, dynamic>) {
          final error = data['error'];
          if (error is Map<String, dynamic>) {
            final code = error['code'] as String?;
            final message = error['message'] as String?;
            if (code == 'NOT_FOUND' || message?.contains('not found') == true) {
              errorMessage = 'کالای یونیکی با این بارکد/سریال یافت نشد';
            } else if (message != null) {
              errorMessage = message;
            }
          }
        }
      }
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } catch (e) {
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(content: Text('خطا در جستجو: $e')),
        );
      }
    }
  }

  void _openPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return StatefulBuilder(
          builder: (bottomSheetContext, setBottomSheetState) {
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
                        // دکمه جستجو با بارکد
                        IconButton(
                          onPressed: () async {
                            await _searchByBarcode(bottomSheetContext, () {
                              if (mounted) {
                                setBottomSheetState(() {});
                              }
                            });
                          },
                          icon: const Icon(Icons.qr_code_scanner),
                          tooltip: 'جستجو با بارکد/سریال',
                          color: theme.colorScheme.primary,
                        ),
                        if (widget.authStore != null)
                          IconButton(
                            onPressed: () => _addNewProduct(bottomSheetContext),
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
                      onChanged: (value) {
                        _onQueryChanged(value);
                        // به‌روزرسانی لیست در bottom sheet
                        setBottomSheetState(() {});
                      },
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

/// Dialog برای انتخاب instance از بین چند نتیجه
class _InstanceSelectionDialog extends StatelessWidget {
  final List<dynamic> instances;
  final String searchCode;

  const _InstanceSelectionDialog({
    required this.instances,
    required this.searchCode,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // هدر
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, color: cs.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'چند نتیجه پیدا شد',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'برای "$searchCode"',
                          style: TextStyle(
                            fontSize: 14,
                            color: cs.onPrimaryContainer.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: cs.onPrimaryContainer),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // لیست نتایج
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: instances.length,
                itemBuilder: (context, index) {
                  final instance = Map<String, dynamic>.from(instances[index] as Map);
                  final serialNumber = instance['serial_number']?.toString() ?? '-';
                  final barcode = instance['barcode']?.toString() ?? '-';
                  final productName = instance['product_name']?.toString() ?? 'نامشخص';
                  final warehouseName = instance['warehouse_name']?.toString();
                  
                  return ListTile(
                    leading: const Icon(Icons.inventory_2),
                    title: Text(productName),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (serialNumber != '-') 
                          Text('سریال: $serialNumber'),
                        if (barcode != '-') 
                          Text('بارکد: $barcode'),
                        if (warehouseName != null)
                          Text('انبار: $warehouseName'),
                      ],
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.of(context).pop(instance);
                    },
                  );
                },
              ),
            ),
            // دکمه انصراف
            Container(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('انصراف'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


