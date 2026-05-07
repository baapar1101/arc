import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/product_service.dart';
import '../../services/category_service.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../widgets/product/product_form_dialog.dart';
import '../../widgets/product/category_tree_widget.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;

/// متن خلاصه‌ی نمایشی کالا (کد - نام یا فقط نام)
String _pickerProductDisplayLine(Map<String, dynamic>? p) {
  if (p == null) return '';
  final code = p['code']?.toString() ?? '';
  final name = p['name']?.toString() ?? '';
  if (code.isNotEmpty && name.isNotEmpty) return '$code - $name';
  return name.isNotEmpty ? name : code;
}

String _pickerFormatMoney(dynamic v) {
  return formatWithThousands(v, decimalPlaces: 2);
}

String _pickerFormatQty(dynamic v) {
  return formatWithThousands(v, decimalPlaces: 3);
}

class _ProductSearchSuggestionTile extends StatelessWidget {
  const _ProductSearchSuggestionTile({
    required this.item,
    required this.onTap,
    this.dense = false,
    this.highlighted = false,
  });

  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final bool dense;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = _pickerProductDisplayLine(item);
    final itemType = item['item_type']?.toString() ?? '';
    final purchaseStr = item['base_purchase_price'] == null
        ? '—'
        : _pickerFormatMoney(item['base_purchase_price']);
    final salesStr = item['base_sales_price'] == null
        ? '—'
        : _pickerFormatMoney(item['base_sales_price']);
    final trackInventory = item['track_inventory'] == true;
    final String metricsLine;
    if (!trackInventory) {
      metricsLine = 'خرید $purchaseStr · فروش $salesStr · بدون موجودی انباردیاری';
    } else {
      final wh = item['inventory_stock_warehouse'];
      final acc = item['inventory_stock_accounting'];
      final hasLoaded = wh != null || acc != null;
      final stockPart = !hasLoaded
          ? 'موجودی: —'
          : 'موجودی انبار ${_pickerFormatQty(wh ?? acc ?? 0)} · حساب ${_pickerFormatQty(acc ?? wh ?? 0)}';
      metricsLine = 'خرید $purchaseStr · فروش $salesStr · $stockPart';
    }

    final padH = dense ? 10.0 : 14.0;
    final padV = dense ? 8.0 : 10.0;

    return Material(
      color: highlighted ? cs.primary.withValues(alpha: 0.08) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        hoverColor: cs.primary.withValues(alpha: 0.06),
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: padH + 36,
            end: padH,
            top: padV,
            bottom: padV,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              PositionedDirectional(
                start: -30,
                top: dense ? 1 : 2,
                child: Icon(Icons.inventory_2_outlined, size: dense ? 18 : 20, color: cs.primary),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.25),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                  if (itemType.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      itemType,
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    metricsLine,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _buildProductSuggestionsScrollArea({
  required BuildContext context,
  required _ProductPickerState state,
  required ScrollController scrollController,
  required void Function(Map<String, dynamic> product) onProductSelected,
  int highlightedIndex = -1,
  bool dense = false,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;

  if (state.isLoading && state.items.isEmpty) {
    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SizedBox(width: dense ? 24 : 32, height: dense ? 24 : 32, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
    );
  }

  if (!state.isLoading && state.items.isEmpty) {
    return SizedBox.expand(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inventory_2_outlined, size: dense ? 40 : 48, color: colorScheme.onSurface.withValues(alpha: 0.45)),
              const SizedBox(height: 12),
              Text(
                'کالایی یافت نشد',
                style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface.withValues(alpha: 0.72)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (state.isLoading) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: ListView.separated(
          controller: scrollController,
          padding: EdgeInsets.symmetric(vertical: dense ? 4 : 6),
          itemCount: state.items.length +
              ((state.isLoadingMore || (state.isLoading && state.items.isNotEmpty)) ? 1 : 0),
          separatorBuilder: (separatorContext, separatorIndex) {
            if (separatorIndex >= state.items.length - 1) return const SizedBox.shrink();
            return Divider(height: 1, color: colorScheme.outline.withValues(alpha: 0.12));
          },
          itemBuilder: (context, index) {
            if (index == state.items.length &&
                (state.isLoadingMore || (state.isLoading && state.items.isNotEmpty))) {
              return const Padding(
                padding: EdgeInsets.all(14),
                child: Center(
                  child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              );
            }
            if (index >= state.items.length) return const SizedBox.shrink();
            final it = state.items[index];
            return _ProductSearchSuggestionTile(
              item: it,
              dense: dense,
              highlighted: index == highlightedIndex,
              onTap: () => onProductSelected(it),
            );
          },
        ),
      ),
    ],
  );
}

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
  final ScrollController _overlayScrollController = ScrollController();
  final FocusNode _fieldFocus = FocusNode();
  final LayerLink _layerLink = LayerLink();
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
  OverlayEntry? _desktopOverlayEntry;
  double _desktopFieldWidth = 0;
  bool _suppressFieldNotifications = false;
  int _highlightedIndex = -1;

  // دسته‌بندی‌ها
  List<CategoryNode> _categoryTree = [];
  bool _loadingCategories = false;
  int? _selectedCategoryId;

  double _desktopOverlayHeight(_ProductPickerState state) {
    if (state.isLoading && state.items.isEmpty) return 120;
    if (!state.isLoading && state.items.isEmpty) return 100;
    final extraRow = (state.isLoadingMore || (state.isLoading && state.items.isNotEmpty)) ? 1 : 0;
    final rows = state.items.length + extraRow;
    const rowHeight = 84.0;
    final raw = (rows * rowHeight) + (state.isLoading ? 6 : 0) + 8;
    return raw.clamp(100.0, 360.0);
  }

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
    _fieldFocus.addListener(_onDesktopFocusChanged);
    _scrollController.addListener(_onPickerListScroll);
    _overlayScrollController.addListener(_onOverlayListScroll);
    _initializeSelectedProduct();
    _loadCategories();
    _loadRecent();
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
      _setFieldQuiet('');
      return;
    }

    final productId = widget.selectedProduct!['id'] as int?;
    final hasCode = widget.selectedProduct!['code'] != null;
    final hasName = widget.selectedProduct!['name'] != null;

    debugPrint('[ProductCombobox] productId: $productId, hasCode: $hasCode, hasName: $hasName');

    if (hasCode || hasName) {
      final displayText = _pickerProductDisplayLine(Map<String, dynamic>.from(widget.selectedProduct!));
      debugPrint('[ProductCombobox] Setting _searchCtrl.text to: "$displayText"');
      _setFieldQuiet(displayText);
      if (mounted) setState(() {});
      return;
    }

    if (productId != null) {
      try {
        final product = await _service.getProduct(
          businessId: widget.businessId,
          productId: productId,
        );
        if (mounted && product.isNotEmpty) {
          _setFieldQuiet(_pickerProductDisplayLine(product));
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
        if (mounted) {
          _setFieldQuiet('کالا #$productId');
        }
      }
    } else {
      _setFieldQuiet('');
    }
  }

  void _setFieldQuiet(String text) {
    _suppressFieldNotifications = true;
    _searchCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _suppressFieldNotifications = false;
  }

  void _onDesktopFocusChanged() {
    if (!mounted) return;
    if (ResponsiveHelper.isMobile(context)) return;
    if (_fieldFocus.hasFocus) {
      _showDesktopOverlay();
      if (_searchCtrl.text.trim().isEmpty) {
        unawaited(_loadRecent());
      }
    } else {
      Future.delayed(const Duration(milliseconds: 180), () {
        if (!mounted || _fieldFocus.hasFocus) return;
        _removeDesktopOverlay();
      });
    }
  }

  void _removeDesktopOverlay() {
    _desktopOverlayEntry?.remove();
    _desktopOverlayEntry = null;
    _highlightedIndex = -1;
  }

  void _showDesktopOverlay() {
    if (!mounted || ResponsiveHelper.isMobile(context)) return;
    if (_desktopOverlayEntry != null) {
      _desktopOverlayEntry!.markNeedsBuild();
      return;
    }
    final overlayHost = Overlay.maybeOf(context);
    final overlayResolved = overlayHost ?? Overlay.of(context);
    _desktopOverlayEntry = OverlayEntry(
      builder: (ctx) => _buildDesktopOverlayStack(ctx),
    );
    overlayResolved.insert(_desktopOverlayEntry!);
  }

  Widget _buildDesktopOverlayStack(BuildContext overlayContext) {
    final width = math.max(_desktopFieldWidth, 280.0);
    final cs = Theme.of(overlayContext).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (_) {
              _fieldFocus.unfocus();
              _removeDesktopOverlay();
            },
          ),
        ),
        CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          followerAnchor: Alignment.topCenter,
          targetAnchor: Alignment.bottomCenter,
          offset: const Offset(0, 6),
          child: ValueListenableBuilder<_ProductPickerState>(
            valueListenable: _pickerStateNotifier,
            builder: (context, state, _) {
              final overlayHeight = _desktopOverlayHeight(state);
              return Material(
                elevation: 14,
                surfaceTintColor: cs.surfaceTint,
                color: cs.surfaceContainerHigh,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                clipBehavior: Clip.antiAlias,
                shadowColor: Colors.black.withValues(alpha: 0.22),
                child: SizedBox(
                  width: width,
                  height: overlayHeight,
                  child: _buildProductSuggestionsScrollArea(
                    context: context,
                    state: state,
                    scrollController: _overlayScrollController,
                    onProductSelected: (p) {
                      _select(p);
                      _removeDesktopOverlay();
                    },
                    highlightedIndex: _highlightedIndex,
                    dense: true,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _onDesktopFieldChanged(String value) {
    if (_suppressFieldNotifications) return;
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      if (widget.selectedProduct != null) {
        widget.onChanged(null);
      }
    } else {
      final sel = widget.selectedProduct;
      if (sel != null && trimmed != _pickerProductDisplayLine(Map<String, dynamic>.from(sel)).trim()) {
        widget.onChanged(null);
      }
    }
    _onQueryChanged(value);
    if (_fieldFocus.hasFocus && !ResponsiveHelper.isMobile(context) && _desktopOverlayEntry == null) {
      _showDesktopOverlay();
    }
  }

  void _moveHighlightedSelection(int delta) {
    if (_items.isEmpty) return;
    var nextIndex = _highlightedIndex;
    if (nextIndex < 0 || nextIndex >= _items.length) {
      nextIndex = delta > 0 ? 0 : _items.length - 1;
    } else {
      nextIndex = (nextIndex + delta).clamp(0, _items.length - 1);
    }
    if (nextIndex == _highlightedIndex) return;
    setState(() {
      _highlightedIndex = nextIndex;
    });
    _desktopOverlayEntry?.markNeedsBuild();
    _ensureHighlightedItemVisible();
  }

  void _ensureHighlightedItemVisible() {
    if (_highlightedIndex < 0 || !_overlayScrollController.hasClients) return;
    const itemExtent = 78.0;
    final targetOffset = _highlightedIndex * itemExtent;
    final pos = _overlayScrollController.position;
    final viewportEnd = pos.pixels + pos.viewportDimension - itemExtent;
    if (targetOffset < pos.pixels) {
      _overlayScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    } else if (targetOffset > viewportEnd) {
      _overlayScrollController.animateTo(
        targetOffset - pos.viewportDimension + itemExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    }
  }

  void _selectHighlightedOrFirst() {
    if (_items.isEmpty) return;
    final idx = (_highlightedIndex >= 0 && _highlightedIndex < _items.length) ? _highlightedIndex : 0;
    _select(_items[idx]);
    _removeDesktopOverlay();
    _fieldFocus.unfocus();
  }

  KeyEventResult _onDesktopFieldKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (ResponsiveHelper.isMobile(context) || _desktopOverlayEntry == null) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveHighlightedSelection(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveHighlightedSelection(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _selectHighlightedOrFirst();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeDesktopOverlay();
    _fieldFocus.removeListener(_onDesktopFocusChanged);
    _fieldFocus.dispose();
    _scrollController.removeListener(_onPickerListScroll);
    _scrollController.dispose();
    _overlayScrollController.removeListener(_onOverlayListScroll);
    _overlayScrollController.dispose();
    _pickerStateNotifier.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _syncPickerState() {
    if (_items.isEmpty) {
      _highlightedIndex = -1;
    } else if (_highlightedIndex >= _items.length) {
      _highlightedIndex = _items.length - 1;
    } else if (_fieldFocus.hasFocus &&
        !ResponsiveHelper.isMobile(context) &&
        _desktopOverlayEntry != null &&
        _highlightedIndex < 0) {
      _highlightedIndex = 0;
    }
    _pickerStateNotifier.value = _ProductPickerState(
      items: _items,
      isLoading: _loading,
      isLoadingMore: _loadingMore,
      hasMore: _hasMore,
    );
  }

  void _onPickerListScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (_hasMore && !_loadingMore && !_loading) {
        _loadMore();
      }
    }
  }

  void _onOverlayListScroll() {
    if (!_overlayScrollController.hasClients) return;
    final pos = _overlayScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 160) {
      if (_hasMore && !_loadingMore && !_loading) {
        _loadMore();
      }
    }
  }

  Future<void> _loadRecent() async {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    if (_overlayScrollController.hasClients) {
      _overlayScrollController.jumpTo(0);
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
        includeInventory: true,
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
    if (_overlayScrollController.hasClients) {
      _overlayScrollController.jumpTo(0);
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
        includeInventory: true,
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
        includeInventory: true,
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
      _suppressFieldNotifications = true;
      _searchCtrl.clear();
      _suppressFieldNotifications = false;
      widget.onChanged(null);
      if (mounted) setState(() {});
      return;
    }
    final displayText = _pickerProductDisplayLine(item);
    debugPrint('[ProductCombobox] Setting _searchCtrl.text to: "$displayText"');
    debugPrint('[ProductCombobox] Calling widget.onChanged with item: $item');
    _setFieldQuiet(displayText);
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
    _removeDesktopOverlay();
    FocusManager.instance.primaryFocus?.unfocus();
    final isMobile = ResponsiveHelper.isMobile(context);

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
            isMobile: isMobile,
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
    final isMobileUi = ResponsiveHelper.isMobile(context);

    String displayTooltip;
    if (_searchCtrl.text.isNotEmpty) {
      displayTooltip = _searchCtrl.text;
    } else if (widget.selectedProduct != null) {
      displayTooltip = _pickerProductDisplayLine(Map<String, dynamic>.from(widget.selectedProduct!));
      if (displayTooltip.isEmpty) displayTooltip = widget.hintText;
    } else {
      displayTooltip = widget.hintText;
    }

    if (isMobileUi) {
      return InkWell(
        onTap: _openPicker,
        child: Tooltip(
          message: displayTooltip,
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
                    displayTooltip,
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

    return CompositedTransformTarget(
      link: _layerLink,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          if ((_desktopFieldWidth - w).abs() > 0.5) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if ((_desktopFieldWidth - w).abs() > 0.5) {
                setState(() => _desktopFieldWidth = w);
                _desktopOverlayEntry?.markNeedsBuild();
              }
            });
          }

          return Tooltip(
            message: displayTooltip.length > 120 ? '${displayTooltip.substring(0, 120)}…' : displayTooltip,
            waitDuration: const Duration(milliseconds: 600),
            child: Focus(
              onKeyEvent: _onDesktopFieldKeyEvent,
              child: TextField(
                controller: _searchCtrl,
                focusNode: _fieldFocus,
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  fontSize: 13.5,
                ),
                minLines: 1,
                maxLines: 1,
                decoration: InputDecoration(
                  isDense: false,
                  hintText: widget.hintText,
                  labelText: widget.label,
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  prefixIcon: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: Icon(Icons.inventory_2_outlined, color: colorScheme.primary, size: 20),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  suffixIconConstraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_loading)
                        const Padding(
                          padding: EdgeInsetsDirectional.only(end: 6),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'انتخاب پیشرفته (دسته‌ها و افزودن)',
                        icon: Icon(Icons.manage_search_rounded, color: colorScheme.primary),
                        onPressed: () => _openPicker(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                      ),
                    ],
                  ),
                ),
                onTap: () {
                  final allowOverlay = !ResponsiveHelper.isMobile(context);
                  Future.microtask(() {
                    if (!mounted) return;
                    if (!_fieldFocus.hasFocus) _fieldFocus.requestFocus();
                    if (!allowOverlay) return;
                    _showDesktopOverlay();
                    if (_searchCtrl.text.trim().isEmpty) {
                      unawaited(_loadRecent());
                    }
                  });
                },
                onChanged: _onDesktopFieldChanged,
              ),
            ),
          );
        },
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
                          : colorScheme.onSurface.withValues(alpha: 0.6),
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
                  return _buildProductSuggestionsScrollArea(
                    context: context,
                    state: state,
                    scrollController: widget.scrollController,
                    onProductSelected: widget.onProductSelected,
                    highlightedIndex: -1,
                    dense: false,
                  );
                },
              ),
            ),
          ],
        ),
      ),
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
      child: SizedBox(
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
                  bottom: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2)),
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
                        right: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2)),
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
                              bottom: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2)),
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
                        return _buildProductSuggestionsScrollArea(
                          context: context,
                          state: state,
                          scrollController: scrollController,
                          onProductSelected: onProductSelected,
                          highlightedIndex: -1,
                          dense: false,
                        );
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
}


