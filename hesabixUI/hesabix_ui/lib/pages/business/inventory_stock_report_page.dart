import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/services/category_service.dart';
import 'package:hesabix_ui/services/product_service.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/data_table_utils.dart';
import 'package:hesabix_ui/widgets/invoice/product_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/warehouse_combobox_widget.dart';
import 'package:hesabix_ui/widgets/category/category_picker_field.dart';
import 'package:hesabix_ui/core/date_utils.dart';

class InventoryStockReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  
  const InventoryStockReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<InventoryStockReportPage> createState() => _InventoryStockReportPageState();
}

class _InventoryStockReportPageState extends State<InventoryStockReportPage> {
  // Filters
  DateTime? _asOfDate;
  int? _selectedFiscalYearId;
  int? _selectedWarehouseId;
  int? _selectedCategoryId;
  Map<String, dynamic>? _selectedProduct;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  
  // Boolean filters
  bool _includeZero = false;
  bool _onlyNegativeStock = false;
  bool _onlyWithoutMovements = false;
  bool? _trackInventory; // null = همه، true = فقط با کنترل، false = فقط بدون کنترل
  
  // Data
  List<Map<String, dynamic>> _fiscalYears = [];
  List<Map<String, dynamic>> _categories = [];
  
  // UI State
  bool _filtersExpanded = false; // برای ExpansionTile در دسکتاپ
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  // Summary data
  Map<String, dynamic>? _summaryData;
  final ProductService _productService = ProductService(apiClient: ApiClient());

  @override
  void initState() {
    super.initState();
    _asOfDate = DateTime.now();
    _loadFiscalYears();
    _loadCategories();
    _loadSummaryData(); // بارگذاری summary data
    
    // برای نمایش مقدار اولیه در search field
    _searchController.text = _searchQuery;
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadFiscalYears() async {
    try {
      final svc = BusinessDashboardService(ApiClient());
      final items = await svc.listFiscalYears(widget.businessId);
      if (!mounted) return;
      setState(() {
        _fiscalYears = items;
        final current = items.firstWhere(
          (e) => (e['is_current'] == true),
          orElse: () => const <String, dynamic>{},
        );
        final id = current['id'];
        if (id is int) {
          _selectedFiscalYearId = id;
        }
      });
    } catch (_) {
      // ignore errors
    }
  }

  Future<void> _loadCategories() async {
    try {
      final svc = CategoryService(ApiClient());
      final items = await svc.getTree(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _categories = items;
      });
    } catch (_) {
      // ignore errors
    }
  }
  
  Future<void> _loadSummaryData() async {
    try {
      final api = ApiClient();
      final response = await api.post<Map<String, dynamic>>(
        '/api/v1/products/businesses/${widget.businessId}/reports/inventory-stock',
        data: {
          ..._additionalParams(),
          'take': 1, // فقط برای گرفتن summary
          'skip': 0,
        },
      );
      
      if (!mounted) return;
      if (response.data != null && response.data!['data'] != null) {
        final data = response.data!['data'] as Map<String, dynamic>;
        final summary = data['summary'] as Map<String, dynamic>?;
        if (summary != null) {
          setState(() {
            _summaryData = summary;
          });
        }
      }
    } catch (_) {
      // ignore errors
    }
  }

  void _refreshData() {
    if (mounted) {
      setState(() {});
      _loadSummaryData(); // بارگذاری summary data
    }
  }
  
  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
    });
    
    // Cancel previous timer
    _searchDebounce?.cancel();
    
    // Create new timer
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _refreshData();
    });
  }

  // تابع برای جمع‌آوری تمام ID های زیرشاخه‌های یک دسته‌بندی
  List<int> _getAllCategoryIds(int categoryId, List<Map<String, dynamic>> categories) {
    final result = <int>[categoryId];
    
    void findChildren(int parentId, List<Map<String, dynamic>> tree) {
      for (final cat in tree) {
        final id = cat['id'] as int?;
        
        if (id != null) {
          final parentIdFromTree = cat['parent_id'] as int?;
          if (parentIdFromTree == parentId) {
            result.add(id);
            final children = cat['children'] as List<dynamic>?;
            if (children != null && children.isNotEmpty) {
              findChildren(id, children.cast<Map<String, dynamic>>());
            }
          }
          
          final children = cat['children'] as List<dynamic>?;
          if (children != null && children.isNotEmpty) {
            findChildren(parentId, children.cast<Map<String, dynamic>>());
          }
        }
      }
    }
    
    findChildren(categoryId, categories);
    return result;
  }
  
  // تابع برای تبدیل tree به لیست flat برای dropdown
  List<Map<String, dynamic>> _flattenCategoriesTree(List<Map<String, dynamic>> tree, {int level = 0}) {
    final result = <Map<String, dynamic>>[];
    final prefix = '  ' * level; // دو space برای هر سطح
    
    for (final cat in tree) {
      final id = cat['id'] as int?;
      final label = (cat['label'] ?? cat['title'] ?? '').toString();
      
      if (id != null) {
        final displayLabel = level > 0 ? '$prefix$label' : label;
        result.add({
          'id': id,
          'label': label,
          'display_label': displayLabel, // برای نمایش در dropdown (با prefix برای زیرشاخه‌ها)
        });
        
        final children = (cat['children'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        if (children.isNotEmpty) {
          result.addAll(_flattenCategoriesTree(children, level: level + 1));
        }
      }
    }
    
    return result;
  }
  
  // تابع برای پیدا کردن نام دسته‌بندی بر اساس ID
  String? _getCategoryNameById(int? categoryId) {
    if (categoryId == null) return null;
    
    String? findName(List<Map<String, dynamic>> tree, int id) {
      for (final cat in tree) {
        final catId = (cat['id'] as num?)?.toInt();
        if (catId == id) {
          return (cat['label'] ?? cat['title'] ?? '').toString();
        }
        final children = (cat['children'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        final found = findName(children, id);
        if (found != null) return found;
      }
      return null;
    }
    
    return findName(_categories, categoryId);
  }

  Map<String, dynamic> _additionalParams() {
    List<int>? categoryIds;
    if (_selectedCategoryId != null) {
      categoryIds = _getAllCategoryIds(_selectedCategoryId!, _categories);
    }
    
    return {
      if (_asOfDate != null) 'as_of_date': _asOfDate!.toIso8601String().split('T').first,
      if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
      if (_selectedWarehouseId != null) 'warehouse_ids': [_selectedWarehouseId],
      if (categoryIds != null) 'category_ids': categoryIds,
      if (_selectedProduct != null) 'product_ids': [_selectedProduct!['id']],
      if (_searchQuery.isNotEmpty) 'search': _searchQuery,
      'include_zero': _includeZero,
      'only_negative_stock': _onlyNegativeStock,
      'only_without_movements': _onlyWithoutMovements,
      if (_trackInventory != null) 'track_inventory': _trackInventory,
    };
  }
  
  int _getActiveFiltersCount() {
    int count = 0;
    if (_asOfDate != null) count++;
    if (_selectedFiscalYearId != null) count++;
    if (_selectedWarehouseId != null) count++;
    if (_selectedCategoryId != null) count++;
    if (_selectedProduct != null) count++;
    if (_searchQuery.isNotEmpty) count++;
    if (_includeZero) count++;
    if (_onlyNegativeStock) count++;
    if (_onlyWithoutMovements) count++;
    if (_trackInventory != null) count++;
    return count;
  }
  
  List<Map<String, String>> _getActiveFiltersList() {
    final filters = <Map<String, String>>[];
    
    if (_asOfDate != null) {
      // فرمت تاریخ بر اساس تقویم انتخاب شده
      final isJalali = widget.calendarController.isJalali;
      final formattedDate = HesabixDateUtils.formatForDisplay(_asOfDate, isJalali);
      filters.add({
        'key': 'as_of_date',
        'label': 'تاریخ گزارش',
        'value': formattedDate,
      });
    }
    if (_selectedFiscalYearId != null) {
      final fy = _fiscalYears.firstWhere(
        (e) => e['id'] == _selectedFiscalYearId,
        orElse: () => {'title': ''},
      );
      filters.add({
        'key': 'fiscal_year_id',
        'label': 'سال مالی',
        'value': fy['title']?.toString() ?? '',
      });
    }
    if (_selectedWarehouseId != null) {
      // باید از widget استفاده شود، فعلا فقط label
      filters.add({
        'key': 'warehouse_id',
        'label': 'انبار',
        'value': 'انبار انتخاب شده',
      });
    }
    if (_selectedCategoryId != null) {
      final categoryName = _getCategoryNameById(_selectedCategoryId);
      filters.add({
        'key': 'category_id',
        'label': 'دسته‌بندی',
        'value': categoryName ?? '',
      });
    }
    if (_selectedProduct != null) {
      filters.add({
        'key': 'product_id',
        'label': 'محصول',
        'value': _selectedProduct!['name']?.toString() ?? '',
      });
    }
    if (_searchQuery.isNotEmpty) {
      filters.add({
        'key': 'search',
        'label': 'جستجو',
        'value': _searchQuery,
      });
    }
    if (_includeZero) {
      filters.add({
        'key': 'include_zero',
        'label': 'نمایش موجودی صفر',
        'value': '',
      });
    }
    if (_onlyNegativeStock) {
      filters.add({
        'key': 'only_negative_stock',
        'label': 'فقط موجودی منفی',
        'value': '',
      });
    }
    if (_onlyWithoutMovements) {
      filters.add({
        'key': 'only_without_movements',
        'label': 'فاقد حواله',
        'value': '',
      });
    }
    if (_trackInventory != null) {
      filters.add({
        'key': 'track_inventory',
        'label': 'کنترل موجودی',
        'value': _trackInventory == true ? 'با کنترل' : 'بدون کنترل',
      });
    }
    
    return filters;
  }
  
  void _removeFilter(String key) {
    setState(() {
      switch (key) {
        case 'as_of_date':
          _asOfDate = DateTime.now();
          break;
        case 'fiscal_year_id':
          _selectedFiscalYearId = null;
          break;
        case 'warehouse_id':
          _selectedWarehouseId = null;
          break;
        case 'category_id':
          _selectedCategoryId = null;
          break;
        case 'product_id':
          _selectedProduct = null;
          break;
        case 'search':
          _searchQuery = '';
          _searchController.clear();
          break;
        case 'include_zero':
          _includeZero = false;
          break;
        case 'only_negative_stock':
          _onlyNegativeStock = false;
          break;
        case 'only_without_movements':
          _onlyWithoutMovements = false;
          break;
        case 'track_inventory':
          _trackInventory = null;
          break;
      }
    });
    _refreshData();
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/products/businesses/${widget.businessId}/reports/inventory-stock',
      businessId: widget.businessId,
      reportModuleKey: 'inventory_stock',
      reportSubtype: 'list',
      title: t.reportsInventoryStockTitle,
      showRowNumbers: true,
      enableRowSelection: false,
      showColumnSearch: false,
      showActiveFilters: false, // چون خودمان نمایش می‌دهیم
      showClearFiltersButton: false,
      showExportButtons: true,
      excelEndpoint: '/api/v1/products/businesses/${widget.businessId}/reports/inventory-stock/export/excel',
      pdfEndpoint: '/api/v1/products/businesses/${widget.businessId}/reports/inventory-stock/export/pdf',
      additionalParams: _additionalParams(),
      columns: [
        TextColumn(
          'product_code',
          'کد محصول',
          width: ColumnWidth.small,
          formatter: (row) => (row as Map<String, dynamic>)['product_code']?.toString() ?? '',
        ),
        TextColumn(
          'product_name',
          'نام محصول',
          width: ColumnWidth.large,
          formatter: (row) => (row as Map<String, dynamic>)['product_name']?.toString() ?? '',
        ),
        TextColumn(
          'category_name',
          'دسته‌بندی',
          width: ColumnWidth.medium,
          formatter: (row) => (row as Map<String, dynamic>)['category_name']?.toString() ?? '-',
        ),
        TextColumn(
          'warehouse_code',
          'کد انبار',
          width: ColumnWidth.small,
          formatter: (row) => (row as Map<String, dynamic>)['warehouse_code']?.toString() ?? '-',
        ),
        TextColumn(
          'warehouse_name',
          'نام انبار',
          width: ColumnWidth.medium,
          formatter: (row) => (row as Map<String, dynamic>)['warehouse_name']?.toString() ?? '-',
        ),
        CustomColumn(
          'quantity',
          'موجودی',
          width: ColumnWidth.medium,
          sortable: true,
          searchable: false,
          builder: (row, index) {
            final m = row as Map<String, dynamic>;
            final qty = (m['quantity'] as num?)?.toDouble() ?? 0.0;
            Color textColor;
            IconData? iconData;
            
            if (qty < 0) {
              textColor = Colors.red.shade700;
              iconData = Icons.warning;
            } else if (qty == 0) {
              textColor = Colors.orange.shade700;
              iconData = Icons.remove_circle_outline;
            } else {
              textColor = Colors.green.shade700;
              iconData = Icons.check_circle_outline;
            }
            
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (iconData != null)
                  Icon(
                    iconData,
                    size: 16,
                    color: textColor,
                  ),
                const SizedBox(width: 4),
                Text(
              _formatNumber(qty),
              style: TextStyle(
                color: textColor,
                fontWeight: qty < 0 ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
                ),
              ],
            );
          },
        ),
        TextColumn(
          'unit',
          'واحد',
          width: ColumnWidth.small,
          formatter: (row) => (row as Map<String, dynamic>)['unit']?.toString() ?? '',
        ),
        CustomColumn(
          'track_inventory',
          'کنترل موجودی',
          width: ColumnWidth.small,
          sortable: false,
          searchable: false,
          builder: (row, index) {
            final m = row as Map<String, dynamic>;
            final trackInventory = m['track_inventory'] == true;
            return Center(
              child: Icon(
                trackInventory ? Icons.check_circle : Icons.cancel,
                color: trackInventory ? Colors.green : Colors.grey,
                size: 20,
              ),
            );
          },
        ),
      ],
      defaultPageSize: 50,
      defaultSortBy: 'product_code',
      defaultSortDesc: false,
      expandBodyHeightToFitRows: true,
    );
  }

  void _clearFilters() {
    setState(() {
      _asOfDate = DateTime.now();
      _selectedFiscalYearId = null;
      _selectedWarehouseId = null;
      _selectedCategoryId = null;
      _selectedProduct = null;
      _searchQuery = '';
      _searchController.clear();
      _includeZero = false;
      _onlyNegativeStock = false;
      _onlyWithoutMovements = false;
      _trackInventory = null;
    });
    _refreshData();
  }

  Widget _buildFiltersContent({required bool isMobile}) {
    if (isMobile) {
      return _buildMobileFilters();
    } else {
      return _buildDesktopFilters();
    }
  }
  
  String _productDisplayText(Map<String, dynamic>? product) {
    if (product == null) return '';
    final code = product['code']?.toString() ?? '';
    final name = product['name']?.toString() ?? '';
    if (code.isEmpty && name.isEmpty) return '';
    if (code.isEmpty) return name;
    if (name.isEmpty) return code;
    return '$code - $name';
  }

  Future<Map<String, dynamic>?> _showProductPickerDialog() async {
    return showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) {
        final searchController = TextEditingController();
        Timer? debounce;
        bool loading = true;
        bool loadingMore = false;
        bool hasMore = false;
        int skip = 0;
        const int limit = 20;
        List<Map<String, dynamic>> items = const <Map<String, dynamic>>[];

        Future<void> load({required bool reset}) async {
          if (reset) {
            skip = 0;
            hasMore = false;
            loading = true;
          } else {
            loadingMore = true;
          }

          // State is driven by StatefulBuilder below; we update variables then call setState there
          try {
            final q = searchController.text.trim();
            final result = await _productService.searchProducts(
              businessId: widget.businessId,
              searchQuery: q.isEmpty ? null : q,
              limit: limit,
              skip: skip,
              searchFields: const ['code', 'name'],
            );
            if (reset) {
              items = result;
            } else {
              items = [...items, ...result];
            }
            hasMore = result.length == limit;
            if (hasMore) {
              skip += limit;
            }
          } catch (_) {
            // ignore
          } finally {
            loading = false;
            loadingMore = false;
          }
        }

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> loadAndUpdate({required bool reset}) async {
              await load(reset: reset);
              if (ctx.mounted) {
                setStateDialog(() {});
              }
            }

            // initial load once
            if (loading && items.isEmpty) {
              // kick off async load
              Future.microtask(() => loadAndUpdate(reset: true));
            }

            return Dialog(
              child: SizedBox(
                width: 680,
                height: 560,
                child: Column(
                  children: [
                    AppBar(
                      title: const Text('انتخاب محصول'),
                      leading: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          debounce?.cancel();
                          Navigator.of(ctx).pop();
                        },
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            debounce?.cancel();
                            Navigator.of(ctx).pop(null);
                          },
                          child: const Text('پاک کردن'),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          hintText: 'جستجو: کد یا نام محصول',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          isDense: true,
                        ),
                        onChanged: (_) {
                          debounce?.cancel();
                          debounce = Timer(
                            const Duration(milliseconds: 300),
                            () => loadAndUpdate(reset: true),
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: loading && items.isEmpty
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.separated(
                              itemCount: items.length + (hasMore ? 1 : 0),
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                if (index >= items.length) {
                                  return Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: loadingMore
                                        ? const Center(child: CircularProgressIndicator())
                                        : OutlinedButton.icon(
                                            onPressed: () => loadAndUpdate(reset: false),
                                            icon: const Icon(Icons.expand_more),
                                            label: const Text('نمایش بیشتر'),
                                          ),
                                  );
                                }

                                final p = items[index];
                                final title = (p['name'] ?? '').toString();
                                final code = (p['code'] ?? '').toString();
                                final subtitle = code.isNotEmpty ? 'کد: $code' : null;
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    title.isNotEmpty ? title : _productDisplayText(p),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: subtitle == null
                                      ? null
                                      : Text(
                                          subtitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                  onTap: () {
                                    debounce?.cancel();
                                    Navigator.of(ctx).pop(p);
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

  Widget _buildSimpleProductField() {
    final theme = Theme.of(context);
    final displayText = _productDisplayText(_selectedProduct);
    final hasValue = displayText.trim().isNotEmpty;

    // فیلد ظاهراً مثل DateInputField (InputDecoration + isDense + contentPadding)
    // نکته: این ویجت داخل GridView قرار می‌گیرد و سلول Grid ممکن است بلندتر از خود فیلد باشد.
    // اگر InkWell کل سلول را بگیرد، hover/splash روی فضای خالی زیر فیلد هم دیده می‌شود.
    // بنابراین InkWell را فقط روی خود فیلد (ارتفاع 56) قرار می‌دهیم.
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: 56,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              final picked = await _showProductPickerDialog();
              if (!mounted) return;
              setState(() {
                _selectedProduct = picked;
              });
              _refreshData();
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'محصول',
                hintText: 'همه محصولات',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_selectedProduct != null)
                      IconButton(
                        tooltip: 'پاک کردن',
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          setState(() {
                            _selectedProduct = null;
                          });
                          _refreshData();
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    const Icon(Icons.expand_more, size: 20),
                  ],
                ),
              ),
              child: Text(
                hasValue ? displayText : 'همه محصولات',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  color: hasValue ? null : theme.hintColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildMobileFilters() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
                  children: [
        // تاریخ گزارش
        DateInputField(
                            labelText: 'تاریخ گزارش',
                            value: _asOfDate,
                            calendarController: widget.calendarController,
                            onChanged: (date) {
                              setState(() {
                                _asOfDate = date;
                              });
                              _refreshData();
                            },
                          ),
        const SizedBox(height: 16),
        
        // سال مالی
        DropdownButtonFormField<int>(
                            value: _selectedFiscalYearId,
                            decoration: InputDecoration(
                              labelText: 'سال مالی',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            items: [
                              const DropdownMenuItem<int>(
                                value: null,
              child: Text('همه'),
                              ),
                              ..._fiscalYears.map((fy) {
                                final id = fy['id'] as int?;
                                final title = (fy['title'] ?? '').toString();
                                return DropdownMenuItem<int>(
                                  value: id,
                child: Text(title),
                                );
                              }),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedFiscalYearId = value;
                              });
                              _refreshData();
                            },
                          ),
        const SizedBox(height: 16),
        
        // محصول
        ProductComboboxWidget(
                            businessId: widget.businessId,
                            selectedProduct: _selectedProduct,
                            onChanged: (product) {
                              setState(() {
                                _selectedProduct = product;
                              });
                              _refreshData();
                            },
                            label: 'محصول',
                            hintText: 'همه محصولات',
                          ),
        const SizedBox(height: 16),
        
        // انبار
        WarehouseComboboxWidget(
                            businessId: widget.businessId,
                            selectedWarehouseId: _selectedWarehouseId,
                            onChanged: (id) {
                              setState(() {
                                _selectedWarehouseId = id;
                              });
                              _refreshData();
                            },
                            label: 'انبار',
                            hintText: 'همه انبارها',
                          ),
        const SizedBox(height: 16),
        
        // دسته‌بندی
        CategoryPickerField(
                            businessId: widget.businessId,
                            categoriesTree: _categories,
                            initialValue: _selectedCategoryId,
                            onChanged: (categoryId) {
                              setState(() {
                                _selectedCategoryId = categoryId;
                              });
                              _refreshData();
                            },
                            label: 'دسته‌بندی',
                          ),
        const SizedBox(height: 16),
        
        // جستجو
        TextField(
          controller: _searchController,
                            decoration: InputDecoration(
                              labelText: 'جستجو',
                              hintText: 'کد/نام محصول',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                    icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        setState(() {
                                          _searchQuery = '';
                        _searchController.clear();
                                        });
                                        _refreshData();
                                      },
                                    )
                                  : null,
                            ),
          onChanged: _onSearchChanged,
          onSubmitted: (_) {
            _refreshData();
          },
        ),
        const SizedBox(height: 16),
        
        // کنترل موجودی
        DropdownButtonFormField<bool?>(
          value: _trackInventory,
          decoration: InputDecoration(
            labelText: 'کنترل موجودی',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          items: const [
            DropdownMenuItem<bool?>(
              value: null,
              child: Text('همه'),
            ),
            DropdownMenuItem<bool?>(
              value: true,
              child: Text('با کنترل'),
            ),
            DropdownMenuItem<bool?>(
              value: false,
              child: Text('بدون کنترل'),
            ),
          ],
          onChanged: (value) {
            setState(() {
              _trackInventory = value;
            });
            _refreshData();
          },
        ),
        const SizedBox(height: 24),
        
        // چک‌باکس‌ها
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
        child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                Text(
                  'فیلترهای موجودی',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      selected: _includeZero,
                      label: const Text('نمایش موجودی صفر'),
                      onSelected: (selected) {
                        setState(() {
                          _includeZero = selected;
                        });
                        _refreshData();
                      },
                    ),
                    FilterChip(
                      selected: _onlyNegativeStock,
                      label: const Text('فقط موجودی منفی'),
                      onSelected: (selected) {
                        setState(() {
                          _onlyNegativeStock = selected;
                        });
                        _refreshData();
                      },
                    ),
                    FilterChip(
                      selected: _onlyWithoutMovements,
                      label: const Text('فاقد حواله'),
                      onSelected: (selected) {
                        setState(() {
                          _onlyWithoutMovements = selected;
                        });
                        _refreshData();
                      },
                  ),
                ],
              ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        
        // دکمه‌های عملیات
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.clear_all),
                label: const Text('پاک کردن همه'),
                onPressed: _clearFilters,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('اعمال فیلتر'),
                onPressed: () {
                  Navigator.of(context).pop(); // بستن Drawer
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
  
  Widget _buildDesktopFilters() {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            // Grid of filters
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth > 1200 ? 4 : 
                                      constraints.maxWidth > 800 ? 3 : 2;
                return GridView.count(
                  crossAxisCount: crossAxisCount,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 3.5,
                      children: [
                    DateInputField(
                            labelText: 'تاریخ گزارش',
                            value: _asOfDate,
                            calendarController: widget.calendarController,
                            isDense: true,
                            onChanged: (date) {
                              setState(() {
                                _asOfDate = date;
                              });
                              _refreshData();
                            },
                          ),
                    DropdownButtonFormField<int>(
                            value: _selectedFiscalYearId,
                            decoration: InputDecoration(
                              labelText: 'سال مالی',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                            ),
                            items: [
                              const DropdownMenuItem<int>(
                                value: null,
                                child: Text('همه', style: TextStyle(fontSize: 13)),
                              ),
                              ..._fiscalYears.map((fy) {
                                final id = fy['id'] as int?;
                                final title = (fy['title'] ?? '').toString();
                                return DropdownMenuItem<int>(
                                  value: id,
                                  child: Text(
                                    title,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                            style: const TextStyle(fontSize: 13),
                                  ),
                                );
                              }),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedFiscalYearId = value;
                              });
                              _refreshData();
                            },
                          ),
                    _buildSimpleProductField(),
                    WarehouseComboboxWidget(
                            businessId: widget.businessId,
                            selectedWarehouseId: _selectedWarehouseId,
                            onChanged: (id) {
                              setState(() {
                                _selectedWarehouseId = id;
                              });
                              _refreshData();
                            },
                            label: 'انبار',
                            hintText: 'همه انبارها',
                            height: 56,
                          ),
                    DropdownButtonFormField<int>(
                      value: _selectedCategoryId,
                      decoration: InputDecoration(
                        labelText: 'دسته‌بندی',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      ),
                      items: [
                        const DropdownMenuItem<int>(
                          value: null,
                          child: Text('همه', style: TextStyle(fontSize: 13)),
                        ),
                        ..._flattenCategoriesTree(_categories).map((cat) {
                          final id = cat['id'] as int;
                          final displayLabel = cat['display_label'] as String;
                          return DropdownMenuItem<int>(
                            value: id,
                            child: Text(
                              displayLabel,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }),
                      ],
                      onChanged: (value) {
                              setState(() {
                          _selectedCategoryId = value;
                              });
                              _refreshData();
                            },
                    ),
                    TextField(
                      controller: _searchController,
                            decoration: InputDecoration(
                              labelText: 'جستجو',
                              hintText: 'کد/نام محصول',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () {
                                        setState(() {
                                          _searchQuery = '';
                                    _searchController.clear();
                                        });
                                        _refreshData();
                                      },
                                    )
                                  : null,
                            ),
                            style: const TextStyle(fontSize: 13),
                      onChanged: _onSearchChanged,
                            onSubmitted: (_) {
                              _refreshData();
                            },
                          ),
                    DropdownButtonFormField<bool?>(
                            value: _trackInventory,
                            decoration: InputDecoration(
                              labelText: 'کنترل موجودی',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem<bool?>(
                                value: null,
                                child: Text('همه', style: TextStyle(fontSize: 13)),
                              ),
                              DropdownMenuItem<bool?>(
                                value: true,
                                child: Text('با کنترل', style: TextStyle(fontSize: 13)),
                              ),
                              DropdownMenuItem<bool?>(
                                value: false,
                                child: Text('بدون کنترل', style: TextStyle(fontSize: 13)),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _trackInventory = value;
                              });
                              _refreshData();
                            },
                        ),
                      ],
                );
              },
                    ),
            const SizedBox(height: 12),
                    
            // Checkboxes row
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                FilterChip(
                  selected: _includeZero,
                  label: const Text('نمایش موجودی صفر'),
                  onSelected: (selected) {
                                setState(() {
                      _includeZero = selected;
                                });
                                _refreshData();
                              },
                ),
                FilterChip(
                  selected: _onlyNegativeStock,
                  label: const Text('فقط موجودی منفی'),
                  onSelected: (selected) {
                                setState(() {
                      _onlyNegativeStock = selected;
                                });
                                _refreshData();
                              },
                ),
                FilterChip(
                  selected: _onlyWithoutMovements,
                  label: const Text('فاقد حواله'),
                  onSelected: (selected) {
                                setState(() {
                      _onlyWithoutMovements = selected;
                                });
                                _refreshData();
                              },
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.clear_all, size: 16),
                          label: const Text('پاک کردن', style: TextStyle(fontSize: 13)),
                          onPressed: _clearFilters,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
    );
  }
  
  Widget _buildActiveFiltersChips({required bool isMobile}) {
    final activeFilters = _getActiveFiltersList();
    if (activeFilters.isEmpty) return const SizedBox.shrink();
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 16,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: activeFilters.map((filter) {
            return Chip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${filter['label']}${filter['value']!.isNotEmpty ? ': ${filter['value']}' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => _removeFilter(filter['key']!),
                    child: const Icon(
                      Icons.close,
                      size: 16,
                    ),
                  ),
                ],
              ),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              deleteIcon: const SizedBox.shrink(),
            );
          }).toList(),
        ),
      ),
    );
  }
  
  Widget _buildSummaryCards({required bool isMobile}) {
    final summary = _summaryData;
    
    // Extract summary values
    final totalProducts = summary?['total_products'] ?? 0;
    final totalWithStock = summary?['total_with_stock'] ?? 0;
    final totalNegativeStock = summary?['total_negative_stock'] ?? 0;
    final totalZeroStock = summary?['total_zero_stock'] ?? 0;
    
    return Container(
      padding: EdgeInsets.all(isMobile ? 8 : 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = isMobile ? 2 : 4;
          return GridView.count(
            crossAxisCount: crossAxisCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: isMobile ? 1.5 : 2.5,
            children: [
              _buildSummaryCard(
                title: 'کل محصولات',
                value: _formatNumber(totalProducts),
                icon: Icons.inventory_2,
                color: Colors.blue,
              ),
              _buildSummaryCard(
                title: 'با موجودی',
                value: _formatNumber(totalWithStock),
                icon: Icons.check_circle,
                color: Colors.green,
              ),
              _buildSummaryCard(
                title: 'موجودی منفی',
                value: _formatNumber(totalNegativeStock),
                icon: Icons.warning,
                color: Colors.red,
              ),
              _buildSummaryCard(
                title: 'موجودی صفر',
                value: _formatNumber(totalZeroStock),
                icon: Icons.remove_circle,
                color: Colors.orange,
              ),
            ],
          );
        },
      ),
    );
  }
  
  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final isMobile = mediaQuery.size.width < 600;
    final isTablet = mediaQuery.size.width >= 600 && mediaQuery.size.width < 1200;
    
    final activeFiltersCount = _getActiveFiltersCount();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(t.reportsInventoryStockTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (isMobile)
            IconButton(
              icon: Stack(
                children: [
                  const Icon(Icons.filter_list),
                  if (activeFiltersCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '$activeFiltersCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              onPressed: () {
                _scaffoldKey.currentState?.openEndDrawer();
              },
            ),
        ],
      ),
      endDrawer: isMobile
          ? Drawer(
              child: Column(
                children: [
                  DrawerHeader(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.filter_list, size: 32),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'فیلترها',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (activeFiltersCount > 0)
                                Text(
                                  '$activeFiltersCount فیلتر فعال',
                                  style: theme.textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _buildMobileFilters(),
                  ),
                ],
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Filters - Desktop
            if (!isMobile)
              ExpansionTile(
                initiallyExpanded: _filtersExpanded,
                onExpansionChanged: (expanded) {
                  setState(() {
                    _filtersExpanded = expanded;
                  });
                },
                leading: const Icon(Icons.filter_list),
                title: Text('فیلترها'),
                subtitle: activeFiltersCount > 0
                    ? Text('$activeFiltersCount فیلتر فعال')
                    : null,
                trailing: activeFiltersCount > 0
                    ? IconButton(
                        icon: const Icon(Icons.clear_all, size: 20),
                        tooltip: 'پاک کردن همه',
                        onPressed: _clearFilters,
                      )
                    : null,
                children: [
                  _buildDesktopFilters(),
                ],
              ),
            
            // Active Filters Chips
            _buildActiveFiltersChips(isMobile: isMobile),
            
            // Summary Cards
            _buildSummaryCards(isMobile: isMobile),
            
            // Data Table - با اسکرول عمودی
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(isMobile ? 4.0 : 8.0),
                child: DataTableWidget<Map<String, dynamic>>(
                  key: ValueKey({
                    _selectedFiscalYearId,
                    _selectedWarehouseId,
                    _selectedCategoryId,
                    _selectedProduct?['id'],
                    _searchQuery,
                    _asOfDate?.toIso8601String(),
                    _includeZero,
                    _onlyNegativeStock,
                    _onlyWithoutMovements,
                    _trackInventory,
                  }.toString()),
                  config: _buildTableConfig(t),
                  fromJson: (json) => Map<String, dynamic>.from(json as Map),
                  calendarController: widget.calendarController,
                  onRefresh: () {
                    // می‌توانیم summary data را از response بگیریم
                    // فعلا placeholder است
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
