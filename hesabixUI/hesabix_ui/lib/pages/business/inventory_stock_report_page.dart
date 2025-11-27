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
import 'package:hesabix_ui/widgets/data_table/helpers/data_table_utils.dart';
import 'package:hesabix_ui/widgets/invoice/product_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/warehouse_combobox_widget.dart';
import 'package:hesabix_ui/widgets/category/category_picker_field.dart';

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
  
  // Boolean filters
  bool _includeZero = false;
  bool _onlyNegativeStock = false;
  bool _onlyWithoutMovements = false;
  bool? _trackInventory; // null = همه، true = فقط با کنترل، false = فقط بدون کنترل
  
  // Data
  List<Map<String, dynamic>> _fiscalYears = [];
  List<Map<String, dynamic>> _categories = [];

  @override
  void initState() {
    super.initState();
    _asOfDate = DateTime.now();
    _loadFiscalYears();
    _loadCategories();
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

  void _refreshData() {
    if (mounted) {
      setState(() {});
    }
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
      showActiveFilters: true,
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
            if (qty < 0) {
              textColor = Colors.red;
            } else if (qty > 0) {
              textColor = Colors.green.shade700;
            } else {
              textColor = Colors.grey;
            }
            return Text(
              _formatNumber(qty),
              style: TextStyle(
                color: textColor,
                fontWeight: qty < 0 ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
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
      _includeZero = false;
      _onlyNegativeStock = false;
      _onlyWithoutMovements = false;
      _trackInventory = null;
    });
    _refreshData();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(t.reportsInventoryStockTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Filters
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Main filters
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 160,
                          child: DateInputField(
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
                        ),
                        SizedBox(
                          width: 180,
                          child: DropdownButtonFormField<int>(
                            value: _selectedFiscalYearId,
                            decoration: InputDecoration(
                              labelText: 'سال مالی',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              isDense: true,
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
                        ),
                        SizedBox(
                          width: 200,
                          child: ProductComboboxWidget(
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
                        ),
                        SizedBox(
                          width: 180,
                          child: WarehouseComboboxWidget(
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
                        ),
                        SizedBox(
                          width: 200,
                          child: CategoryPickerField(
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
                        ),
                        SizedBox(
                          width: 180,
                          child: TextField(
                            decoration: InputDecoration(
                              labelText: 'جستجو',
                              hintText: 'کد/نام محصول',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              isDense: true,
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () {
                                        setState(() {
                                          _searchQuery = '';
                                        });
                                        _refreshData();
                                      },
                                    )
                                  : null,
                            ),
                            style: const TextStyle(fontSize: 13),
                            onChanged: (value) {
                              setState(() {
                                _searchQuery = value;
                              });
                            },
                            onSubmitted: (_) {
                              _refreshData();
                            },
                          ),
                        ),
                        SizedBox(
                          width: 160,
                          child: DropdownButtonFormField<bool?>(
                            value: _trackInventory,
                            decoration: InputDecoration(
                              labelText: 'کنترل موجودی',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    
                    // Row 2: Checkboxes and Clear button
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: _includeZero,
                              onChanged: (value) {
                                setState(() {
                                  _includeZero = value ?? false;
                                });
                                _refreshData();
                              },
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            const Text('نمایش موجودی صفر', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: _onlyNegativeStock,
                              onChanged: (value) {
                                setState(() {
                                  _onlyNegativeStock = value ?? false;
                                });
                                _refreshData();
                              },
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            const Text('فقط موجودی منفی', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: _onlyWithoutMovements,
                              onChanged: (value) {
                                setState(() {
                                  _onlyWithoutMovements = value ?? false;
                                });
                                _refreshData();
                              },
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            const Text('فاقد حواله', style: TextStyle(fontSize: 13)),
                          ],
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
            ),
            
            // Data Table
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

