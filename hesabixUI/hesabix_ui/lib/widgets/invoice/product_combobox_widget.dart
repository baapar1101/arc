import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart' as dio;
import '../../services/product_service.dart';
import '../../services/warehouse_service.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../widgets/product/product_form_dialog.dart';
import '../../utils/snackbar_helper.dart';


class _ProductPickerState {
  final List<Map<String, dynamic>> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;

  const _ProductPickerState({
    required this.items,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasMore,
  });

  _ProductPickerState copyWith({
    List<Map<String, dynamic>>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
  }) {
    return _ProductPickerState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

class ProductComboboxWidget extends StatefulWidget {
  final int businessId;
  final Map<String, dynamic>? selectedProduct;
  final ValueChanged<Map<String, dynamic>?> onChanged;
  final String label;
  final String hintText;
  final AuthStore? authStore;
  final ValueChanged<List<Map<String, dynamic>>>? onProductsLoaded;

  const ProductComboboxWidget({
    super.key,
    required this.businessId,
    required this.onChanged,
    this.selectedProduct,
    this.label = 'کالا/خدمت',
    this.hintText = 'جست‌وجو و انتخاب کالا/خدمت',
    this.authStore,
    this.onProductsLoaded,
  });

  @override
  State<ProductComboboxWidget> createState() => _ProductComboboxWidgetState();
}

class _ProductComboboxWidgetState extends State<ProductComboboxWidget> {
  final ProductService _service = ProductService(apiClient: ApiClient());
  final WarehouseService _warehouseService = WarehouseService();
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  bool _loading = false;
  bool _loadingMore = false;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];
  bool _isFirstLoad = true;
  bool _hasMore = false;
  int _currentSkip = 0;
  String? _currentSearchQuery;
  static const int _pageSize = 20;
  late final ValueNotifier<_ProductPickerState> _pickerStateNotifier;

  @override
  void initState() {
    super.initState();
    _pickerStateNotifier = ValueNotifier<_ProductPickerState>(
      const _ProductPickerState(
        items: <Map<String, dynamic>>[],
        isLoading: false,
        isLoadingMore: false,
        hasMore: false,
      ),
    );
    _initializeSelectedProduct();
    _loadRecent();
    _scrollController.addListener(_onScroll);
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
              _syncPickerState();
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
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _pickerStateNotifier.dispose();
    super.dispose();
  }

  void _syncPickerState() {
    _pickerStateNotifier.value = _ProductPickerState(
      items: _items,
      isLoading: _loading,
      isLoadingMore: _loadingMore,
      hasMore: _hasMore,
    );
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      // وقتی به 200 پیکسل مانده به پایین رسیدیم، صفحه بعدی را بارگذاری کن
      if (_hasMore && !_loadingMore && !_loading) {
        _loadMore();
      }
    }
  }

  Future<void> _loadRecent() async {
    // Reset scroll position when loading recent
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    setState(() {
      _loading = true;
      _currentSkip = 0;
      _currentSearchQuery = null;
      _hasMore = false;
    });
    _syncPickerState();
    try {
      final items = await _service.searchProducts(
        businessId: widget.businessId,
        searchQuery: null,
        limit: _pageSize,
        skip: 0,
        searchFields: const ['code', 'name'],
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _hasMore = items.length >= _pageSize;
        _currentSkip = items.length;
      });
      _syncPickerState();
      // فراخوانی callback فقط در بار اول
      if (_isFirstLoad && widget.onProductsLoaded != null) {
        _isFirstLoad = false;
        widget.onProductsLoaded?.call(items);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = const <Map<String, dynamic>>[];
        _hasMore = false;
        _currentSkip = 0;
      });
      _syncPickerState();
      // فراخوانی callback با لیست خالی در صورت خطا (فقط در بار اول)
      if (_isFirstLoad && widget.onProductsLoaded != null) {
        _isFirstLoad = false;
        widget.onProductsLoaded?.call(const <Map<String, dynamic>>[]);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _syncPickerState();
      }
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
    // Reset scroll position when starting a new search
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    setState(() {
      _loading = true;
      _currentSkip = 0;
      _currentSearchQuery = q;
      _hasMore = false;
    });
    _syncPickerState();
    try {
      final items = await _service.searchProducts(
        businessId: widget.businessId,
        searchQuery: q,
        limit: _pageSize,
        skip: 0,
        searchFields: const ['code', 'name'],
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _hasMore = items.length >= _pageSize;
        _currentSkip = items.length;
      });
      _syncPickerState();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = const <Map<String, dynamic>>[];
        _hasMore = false;
        _currentSkip = 0;
      });
      _syncPickerState();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _syncPickerState();
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    
    setState(() => _loadingMore = true);
    _syncPickerState();
    try {
      final items = await _service.searchProducts(
        businessId: widget.businessId,
        searchQuery: _currentSearchQuery,
        limit: _pageSize,
        skip: _currentSkip,
        searchFields: const ['code', 'name'],
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...items];
        _hasMore = items.length >= _pageSize;
        _currentSkip = _items.length;
      });
      _syncPickerState();
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasMore = false);
      _syncPickerState();
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
        _syncPickerState();
      }
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

  Future<void> _searchByBarcode(BuildContext bottomSheetContext) async {
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
                  await _performBarcodeSearch(value.trim(), context, bottomSheetContext);
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
                await _performBarcodeSearch(barcodeController.text.trim(), context, bottomSheetContext);
              }
            },
            child: const Text('جستجو'),
          ),
        ],
      ),
    );
  }

  Future<void> _performBarcodeSearch(String code, BuildContext dialogContext, BuildContext bottomSheetContext) async {
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
          SnackBarHelper.show(dialogContext, message: 'کالای یونیکی با این بارکد/سریال یافت نشد');
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
            _syncPickerState();
          } else {
            // اگر در لیست است، لیست را refresh کن تا محصول در ابتدا قرار بگیرد
            await _loadRecent();
          }
        }
        
        // انتخاب محصول
        _select(product);

        // بستن bottom sheet (بعد از انتخاب موفق)
        if (bottomSheetContext.mounted && Navigator.canPop(bottomSheetContext)) {
          Navigator.pop(bottomSheetContext);
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
        SnackBarHelper.show(dialogContext, message: errorMessage);
      }
    } catch (e) {
      if (dialogContext.mounted) {
        SnackBarHelper.show(dialogContext, message: 'خطا در جستجو: $e');
      }
    }
  }

  void _openPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return _ProductPickerBottomSheet(
          label: widget.label,
          hintText: widget.hintText,
          pickerStateNotifier: _pickerStateNotifier,
          scrollController: _scrollController,
          searchController: _searchCtrl,
          canAddNewProduct: widget.authStore != null,
          onClose: () => Navigator.pop(ctx),
          onAddNewProduct: widget.authStore != null ? (bottomSheetContext) => _addNewProduct(bottomSheetContext) : null,
          onSearchByBarcode: (bottomSheetContext) => _searchByBarcode(bottomSheetContext),
          onQueryChanged: _onQueryChanged,
          onProductSelected: (product) {
            _select(product);
            Navigator.pop(ctx);
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
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

class _ProductPickerBottomSheet extends StatefulWidget {
  final String label;
  final String hintText;
  final ValueNotifier<_ProductPickerState> pickerStateNotifier;
  final ScrollController scrollController;
  final TextEditingController searchController;
  final bool canAddNewProduct;
  final VoidCallback onClose;
  final void Function(BuildContext bottomSheetContext)? onAddNewProduct;
  final Future<void> Function(BuildContext bottomSheetContext) onSearchByBarcode;
  final void Function(String query) onQueryChanged;
  final void Function(Map<String, dynamic> product) onProductSelected;

  const _ProductPickerBottomSheet({
    required this.label,
    required this.hintText,
    required this.pickerStateNotifier,
    required this.scrollController,
    required this.searchController,
    required this.canAddNewProduct,
    required this.onClose,
    required this.onAddNewProduct,
    required this.onSearchByBarcode,
    required this.onQueryChanged,
    required this.onProductSelected,
  });

  @override
  State<_ProductPickerBottomSheet> createState() => _ProductPickerBottomSheetState();
}

class _ProductPickerBottomSheetState extends State<_ProductPickerBottomSheet> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ValueListenableBuilder<_ProductPickerState>(
          valueListenable: widget.pickerStateNotifier,
          builder: (context, state, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      widget.label,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () async => widget.onSearchByBarcode(context),
                      icon: const Icon(Icons.qr_code_scanner),
                      tooltip: 'جستجو با بارکد/سریال',
                      color: colorScheme.primary,
                    ),
                    if (widget.canAddNewProduct && widget.onAddNewProduct != null)
                      IconButton(
                        onPressed: () => widget.onAddNewProduct!(context),
                        icon: const Icon(Icons.add),
                        tooltip: 'افزودن کالا/خدمت جدید',
                        color: colorScheme.primary,
                      ),
                    IconButton(onPressed: widget.onClose, icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: widget.searchController,
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    suffixIcon: state.isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                  onChanged: widget.onQueryChanged,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _buildList(theme, state),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildList(ThemeData theme, _ProductPickerState state) {
    final colorScheme = theme.colorScheme;

    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!state.isLoading && state.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 48,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'کالایی یافت نشد',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (state.isLoading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView.separated(
            controller: widget.scrollController,
            itemCount: state.items.length + ((state.isLoadingMore || (state.isLoading && state.items.isNotEmpty)) ? 1 : 0),
            separatorBuilder: (separatorContext, separatorIndex) {
              if (separatorIndex >= state.items.length - 1) return const SizedBox.shrink();
              return const Divider(height: 1);
            },
            itemBuilder: (context, index) {
              // فوتر لودینگ: هم برای صفحه بعد (load more) و هم برای واکشی نتیجه جدید (refresh search)
              if (index == state.items.length && (state.isLoadingMore || (state.isLoading && state.items.isNotEmpty))) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              // گارد ایمن: در صورت تغییر همزمان طول لیست هنگام rebuild، از RangeError جلوگیری کن
              if (index >= state.items.length) {
                return const SizedBox.shrink();
              }
              final it = state.items[index];
              final code = it['code']?.toString() ?? '';
              final name = it['name']?.toString() ?? '';
              final itemType = it['item_type']?.toString() ?? '';
              return ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(code.isNotEmpty ? '$code - $name' : name),
                subtitle: itemType.isNotEmpty ? Text(itemType) : null,
                onTap: () => widget.onProductSelected(it),
              );
            },
          ),
        ),
      ],
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


