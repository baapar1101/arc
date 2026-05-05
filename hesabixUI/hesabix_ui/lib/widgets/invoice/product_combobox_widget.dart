import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/product_service.dart';
import '../../services/category_service.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../widgets/product/product_form_dialog.dart';
import '../../widgets/product/category_tree_widget.dart';
import '../../utils/error_extractor.dart';
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
  final CategoryService _categoryService = CategoryService(ApiClient());
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
  
  // دسته‌بندی‌ها
  List<CategoryNode> _categoryTree = [];
  bool _loadingCategories = false;
  int? _selectedCategoryId;
  static const double _mobileBreakpoint = 700.0;

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
    _loadCategories();
    _loadRecent();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadCategories() async {
    if (_loadingCategories) return;
    setState(() {
      _loadingCategories = true;
    });
    try {
      final categories = await _categoryService.getCategoriesTree(businessId: widget.businessId);
      if (mounted) {
        setState(() {
          _categoryTree = categories.map((e) => CategoryNode.fromMap(e)).toList();
          _loadingCategories = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading categories: $e');
      if (mounted) {
        setState(() {
          _loadingCategories = false;
        });
      }
    }
  }

  List<int> _getCategoryIdsForFilter(int? categoryId) {
    if (categoryId == null) return [];
    
    // پیدا کردن node مربوط به دسته انتخاب شده
    final node = findCategoryNode(_categoryTree, categoryId);
    if (node == null) return [categoryId];
    
    // جمع‌آوری تمام IDهای زیردسته‌ها
    return getAllCategoryIds(node);
  }

  @override
  void didUpdateWidget(ProductComboboxWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    debugPrint('[ProductCombobox] didUpdateWidget called');
    debugPrint('[ProductCombobox] oldProduct: ${oldWidget.selectedProduct}');
    debugPrint('[ProductCombobox] newProduct: ${widget.selectedProduct}');
    debugPrint('[ProductCombobox] current _searchCtrl.text: "${_searchCtrl.text}"');
    
    // بررسی تغییر در id
    final oldId = oldWidget.selectedProduct?['id'];
    final newId = widget.selectedProduct?['id'];
    if (oldId != newId) {
      debugPrint('[ProductCombobox] ID changed: $oldId -> $newId, calling _initializeSelectedProduct');
      _initializeSelectedProduct();
      return;
    }
    
    // اگر id تغییر نکرده اما selectedProduct تغییر کرده (مثلاً name یا code به‌روز شده)
    // باید نمایش را به‌روزرسانی کنیم
    final oldProduct = oldWidget.selectedProduct;
    final newProduct = widget.selectedProduct;
    
    // بررسی تغییر در null بودن
    if (oldProduct == null && newProduct != null) {
      debugPrint('[ProductCombobox] Product changed from null to not null, calling _initializeSelectedProduct');
      _initializeSelectedProduct();
      return;
    }
    if (oldProduct != null && newProduct == null) {
      debugPrint('[ProductCombobox] Product changed from not null to null, calling _initializeSelectedProduct');
      _initializeSelectedProduct();
      return;
    }
    
    // اگر هر دو null یا هر دو not null هستند، مقایسه فیلدها
    if (oldProduct != null && newProduct != null) {
      final oldCode = oldProduct['code']?.toString();
      final newCode = newProduct['code']?.toString();
      final oldName = oldProduct['name']?.toString();
      final newName = newProduct['name']?.toString();
      
      debugPrint('[ProductCombobox] Comparing fields - oldCode: "$oldCode", newCode: "$newCode", oldName: "$oldName", newName: "$newName"');
      
      if (oldCode != newCode || oldName != newName) {
        debugPrint('[ProductCombobox] Code or name changed, calling _initializeSelectedProduct');
        _initializeSelectedProduct();
      } else {
        debugPrint('[ProductCombobox] No changes detected, skipping _initializeSelectedProduct');
      }
    }
  }

  Future<void> _initializeSelectedProduct() async {
    debugPrint('[ProductCombobox] _initializeSelectedProduct called');
    if (widget.selectedProduct == null) {
      debugPrint('[ProductCombobox] selectedProduct is null, clearing _searchCtrl');
      _searchCtrl.text = '';
      return;
    }

    final productId = widget.selectedProduct!['id'] as int?;
    final hasCode = widget.selectedProduct!['code'] != null;
    final hasName = widget.selectedProduct!['name'] != null;
    
    debugPrint('[ProductCombobox] productId: $productId, hasCode: $hasCode, hasName: $hasName');

    // اگر اطلاعات کامل (code و name) موجود است، از آن استفاده می‌کنیم
    if (hasCode || hasName) {
      final code = widget.selectedProduct!['code']?.toString() ?? '';
      final name = widget.selectedProduct!['name']?.toString() ?? '';
      final displayText = code.isNotEmpty ? '$code - $name' : name;
      debugPrint('[ProductCombobox] Setting _searchCtrl.text to: "$displayText"');
      _searchCtrl.text = displayText;
      if (mounted) setState(() {}); // به‌روزرسانی UI
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
      final categoryIds = _getCategoryIdsForFilter(_selectedCategoryId);
      final items = await _service.searchProducts(
        businessId: widget.businessId,
        searchQuery: null,
        limit: _pageSize,
        skip: 0,
        searchFields: const ['code', 'name', 'barcode'],
        categoryIds: categoryIds.isNotEmpty ? categoryIds : null,
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
      final categoryIds = _getCategoryIdsForFilter(_selectedCategoryId);
      final items = await _service.searchProducts(
        businessId: widget.businessId,
        searchQuery: q,
        limit: _pageSize,
        skip: 0,
        searchFields: const ['code', 'name', 'barcode'],
        categoryIds: categoryIds.isNotEmpty ? categoryIds : null,
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
      final categoryIds = _getCategoryIdsForFilter(_selectedCategoryId);
      final items = await _service.searchProducts(
        businessId: widget.businessId,
        searchQuery: _currentSearchQuery,
        limit: _pageSize,
        skip: _currentSkip,
        searchFields: const ['code', 'name', 'barcode'],
        categoryIds: categoryIds.isNotEmpty ? categoryIds : null,
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
    debugPrint('[ProductCombobox] _select called with item: $item');
    if (item == null) {
      debugPrint('[ProductCombobox] Item is null, clearing selection');
      _searchCtrl.clear();
      widget.onChanged(null);
      if (mounted) setState(() {}); // به‌روزرسانی UI
      return;
    }
    final code = item['code']?.toString() ?? '';
    final name = item['name']?.toString() ?? '';
    final displayText = code.isNotEmpty ? '$code - $name' : name;
    debugPrint('[ProductCombobox] Setting _searchCtrl.text to: "$displayText"');
    debugPrint('[ProductCombobox] Calling widget.onChanged with item: $item');
    _searchCtrl.text = displayText;
    widget.onChanged(item);
    debugPrint('[ProductCombobox] After onChanged, _searchCtrl.text is: "${_searchCtrl.text}"');
    if (mounted) {
      debugPrint('[ProductCombobox] Calling setState to update UI');
      setState(() {}); // به‌روزرسانی UI برای نمایش تغییرات
    }
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < _mobileBreakpoint;

    if (isMobile) {
      // موبایل: bottom sheet
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
            categoryTree: _categoryTree,
            selectedCategoryId: _selectedCategoryId,
            loadingCategories: _loadingCategories,
            onClose: () => Navigator.pop(ctx),
            onAddNewProduct: widget.authStore != null ? (bottomSheetContext) => _addNewProduct(bottomSheetContext) : null,
            onQueryChanged: _onQueryChanged,
            onCategorySelected: (categoryId) {
              setState(() {
                _selectedCategoryId = categoryId;
              });
              _loadRecent();
            },
            onProductSelected: (product) {
              _select(product);
              Navigator.pop(ctx);
            },
            isMobile: true,
          );
        },
      );
    } else {
      // دسکتاپ: Dialog با split view
      showDialog(
        context: context,
        builder: (ctx) {
          return _ProductPickerDialog(
            label: widget.label,
            hintText: widget.hintText,
            pickerStateNotifier: _pickerStateNotifier,
            scrollController: _scrollController,
            searchController: _searchCtrl,
            canAddNewProduct: widget.authStore != null,
            categoryTree: _categoryTree,
            selectedCategoryId: _selectedCategoryId,
            loadingCategories: _loadingCategories,
            onClose: () => Navigator.pop(ctx),
            onAddNewProduct: widget.authStore != null ? (dialogContext) => _addNewProduct(dialogContext) : null,
            onQueryChanged: _onQueryChanged,
            onCategorySelected: (categoryId) {
              setState(() {
                _selectedCategoryId = categoryId;
              });
              _loadRecent();
            },
            onProductSelected: (product) {
              _select(product);
              Navigator.pop(ctx);
            },
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // استفاده از _searchCtrl.text برای نمایش، چون همیشه به‌روز است
    // اما اگر خالی باشد، از widget.selectedProduct استفاده می‌کنیم
    String display;
    if (_searchCtrl.text.isNotEmpty) {
      display = _searchCtrl.text;
      debugPrint('[ProductCombobox] build: Using _searchCtrl.text: "$display"');
    } else if (widget.selectedProduct != null) {
      final code = widget.selectedProduct!['code']?.toString() ?? '';
      final name = widget.selectedProduct!['name']?.toString() ?? '';
      display = code.isNotEmpty ? '$code - $name' : (name.isNotEmpty ? name : widget.hintText);
      debugPrint('[ProductCombobox] build: Using widget.selectedProduct - code: "$code", name: "$name", display: "$display"');
    } else {
      display = widget.hintText;
      debugPrint('[ProductCombobox] build: No product selected, using hintText: "$display"');
    }

    return InkWell(
      onTap: _openPicker,
      child: Tooltip(
        message: display,
        waitDuration: const Duration(milliseconds: 600),
        preferBelow: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outline.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(8),
            color: colorScheme.surface,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.inventory_2_outlined, color: colorScheme.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500, 
                    fontSize: 13.5,
                  ),
                ),
              ),
              const SizedBox(width: 4),
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
  final List<CategoryNode> categoryTree;
  final int? selectedCategoryId;
  final bool loadingCategories;
  final VoidCallback onClose;
  final void Function(BuildContext bottomSheetContext)? onAddNewProduct;
  final void Function(String query) onQueryChanged;
  final void Function(int? categoryId) onCategorySelected;
  final void Function(Map<String, dynamic> product) onProductSelected;
  final bool isMobile;

  const _ProductPickerBottomSheet({
    required this.label,
    required this.hintText,
    required this.pickerStateNotifier,
    required this.scrollController,
    required this.searchController,
    required this.canAddNewProduct,
    required this.categoryTree,
    this.selectedCategoryId,
    this.loadingCategories = false,
    required this.onClose,
    required this.onAddNewProduct,
    required this.onQueryChanged,
    required this.onCategorySelected,
    required this.onProductSelected,
    this.isMobile = true,
  });

  @override
  State<_ProductPickerBottomSheet> createState() => _ProductPickerBottomSheetState();
}

class _ProductPickerBottomSheetState extends State<_ProductPickerBottomSheet> {
  final FocusNode _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  String _getCategoryLabel(int categoryId) {
    final node = findCategoryNode(widget.categoryTree, categoryId);
    return node?.label ?? 'دسته‌بندی';
  }

  void _showCategoryFilter(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    'انتخاب دسته‌بندی',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 400,
                child: widget.loadingCategories
                    ? const Center(child: CircularProgressIndicator())
                    : CategoryTreeWidget(
                        categories: widget.categoryTree,
                        selectedCategoryId: widget.selectedCategoryId,
                        onCategorySelected: (categoryId) {
                          widget.onCategorySelected(categoryId);
                          Navigator.pop(ctx);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  widget.label,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
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
            if (widget.isMobile && widget.selectedCategoryId != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Chip(
                        label: Text(_getCategoryLabel(widget.selectedCategoryId!)),
                        onDeleted: () => widget.onCategorySelected(null),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        avatar: const Icon(Icons.category, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.isMobile)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: IconButton(
                      onPressed: () => _showCategoryFilter(context),
                      icon: Icon(
                        widget.selectedCategoryId != null
                            ? Icons.filter_alt
                            : Icons.filter_alt_outlined,
                      ),
                      tooltip: 'فیلتر دسته‌بندی',
                      color: widget.selectedCategoryId != null
                          ? colorScheme.primary
                          : colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                Expanded(
                  child: TextField(
                    controller: widget.searchController,
                    focusNode: _searchFocus,
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: widget.onQueryChanged,
                  ),
                ),
                SizedBox(
                  width: 40,
                  height: kMinInteractiveDimension,
                  child: ValueListenableBuilder<_ProductPickerState>(
                    valueListenable: widget.pickerStateNotifier,
                    builder: (context, state, _) {
                      if (!state.isLoading) {
                        return const SizedBox.shrink();
                      }
                      return const Padding(
                        padding: EdgeInsetsDirectional.only(start: 8, top: 12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ValueListenableBuilder<_ProductPickerState>(
                valueListenable: widget.pickerStateNotifier,
                builder: (context, state, _) {
                  return _buildList(theme, state);
                },
              ),
            ),
          ],
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

/// Dialog برای انتخاب محصول در دسکتاپ با split view (درخت دسته‌بندی + لیست محصولات)
class _ProductPickerDialog extends StatelessWidget {
  final String label;
  final String hintText;
  final ValueNotifier<_ProductPickerState> pickerStateNotifier;
  final ScrollController scrollController;
  final TextEditingController searchController;
  final bool canAddNewProduct;
  final List<CategoryNode> categoryTree;
  final int? selectedCategoryId;
  final bool loadingCategories;
  final VoidCallback onClose;
  final void Function(BuildContext dialogContext)? onAddNewProduct;
  final void Function(String query) onQueryChanged;
  final void Function(int? categoryId) onCategorySelected;
  final void Function(Map<String, dynamic> product) onProductSelected;

  const _ProductPickerDialog({
    required this.label,
    required this.hintText,
    required this.pickerStateNotifier,
    required this.scrollController,
    required this.searchController,
    required this.canAddNewProduct,
    required this.categoryTree,
    this.selectedCategoryId,
    this.loadingCategories = false,
    required this.onClose,
    required this.onAddNewProduct,
    required this.onQueryChanged,
    required this.onCategorySelected,
    required this.onProductSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      child: Container(
        width: 900,
        height: 600,
        child: Column(
          children: [
            // هدر
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                border: Border(
                  bottom: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    label,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (canAddNewProduct && onAddNewProduct != null)
                    IconButton(
                      onPressed: () => onAddNewProduct!(context),
                      icon: const Icon(Icons.add),
                      tooltip: 'افزودن کالا/خدمت جدید',
                      color: colorScheme.primary,
                    ),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            // فیلد جستجو
            Container(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  hintText: hintText,
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: onQueryChanged,
              ),
            ),
            // Split view: درخت دسته‌بندی + لیست محصولات
            Expanded(
              child: Row(
                children: [
                  // پنل سمت چپ: درخت دسته‌بندی
                  Container(
                    width: 280,
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            border: Border(
                              bottom: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.category, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'دسته‌بندی‌ها',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: loadingCategories
                              ? const Center(child: CircularProgressIndicator())
                              : CategoryTreeWidget(
                                  categories: categoryTree,
                                  selectedCategoryId: selectedCategoryId,
                                  onCategorySelected: onCategorySelected,
                                ),
                        ),
                      ],
                    ),
                  ),
                  // پنل راست: لیست محصولات
                  Expanded(
                    child: ValueListenableBuilder<_ProductPickerState>(
                      valueListenable: pickerStateNotifier,
                      builder: (context, state, _) {
                        return _buildProductList(theme, colorScheme, state);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductList(ThemeData theme, ColorScheme colorScheme, _ProductPickerState state) {
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
              color: colorScheme.onSurface.withOpacity(0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'کالایی یافت نشد',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.75),
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
            controller: scrollController,
            itemCount: state.items.length +
                ((state.isLoadingMore || (state.isLoading && state.items.isNotEmpty)) ? 1 : 0),
            separatorBuilder: (separatorContext, separatorIndex) {
              if (separatorIndex >= state.items.length - 1) return const SizedBox.shrink();
              return const Divider(height: 1);
            },
            itemBuilder: (context, index) {
              if (index == state.items.length &&
                  (state.isLoadingMore || (state.isLoading && state.items.isNotEmpty))) {
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
                onTap: () => onProductSelected(it),
              );
            },
          ),
        ),
      ],
    );
  }
}


