import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/invoice/warehouse_combobox_widget.dart';
import 'package:hesabix_ui/widgets/category/category_picker_field.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/data_table_utils.dart';
import 'package:hesabix_ui/services/category_service.dart';
import 'package:hesabix_ui/core/api_client.dart';

class SlowMovingItemsReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  
  const SlowMovingItemsReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<SlowMovingItemsReportPage> createState() => _SlowMovingItemsReportPageState();
}

class _SlowMovingItemsReportPageState extends State<SlowMovingItemsReportPage> {
  int _daysWithoutMovement = 90;
  int? _selectedWarehouseId;
  int? _selectedCategoryId;
  List<Map<String, dynamic>> _categories = [];
  
  @override
  void initState() {
    super.initState();
    _loadCategories();
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
      'days_without_movement': _daysWithoutMovement,
      if (_selectedWarehouseId != null) 'warehouse_ids': [_selectedWarehouseId],
      if (categoryIds != null) 'category_ids': categoryIds,
    };
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/warehouse-reports/businesses/${widget.businessId}/slow-moving-items',
      businessId: widget.businessId,
      reportModuleKey: 'slow_moving_items',
      reportSubtype: 'list',
      title: 'گزارش کالاهای کم‌گردش',
      showRowNumbers: true,
      enableRowSelection: false,
      showColumnSearch: false,
      showActiveFilters: true,
      showClearFiltersButton: false,
      showExportButtons: true,
      excelEndpoint: '/api/v1/warehouse-reports/businesses/${widget.businessId}/slow-moving-items/export/excel',
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
        NumberColumn(
          'current_stock',
          'موجودی فعلی',
          formatter: (row) => _formatNumber((row as Map<String, dynamic>)['current_stock']),
        ),
        TextColumn(
          'unit',
          'واحد',
          width: ColumnWidth.small,
          formatter: (row) => (row as Map<String, dynamic>)['unit']?.toString() ?? '',
        ),
        NumberColumn(
          'days_without_movement',
          'روز بدون حرکت',
          formatter: (row) => _formatNumber((row as Map<String, dynamic>)['days_without_movement']),
        ),
      ],
      defaultPageSize: 50,
      defaultSortBy: 'product_code',
      defaultSortDesc: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('گزارش کالاهای کم‌گردش'),
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
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 180,
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: 'روز بدون حرکت',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 13),
                      onChanged: (value) {
                        final days = int.tryParse(value);
                        if (days != null && days > 0) {
                          setState(() {
                            _daysWithoutMovement = days;
                          });
                          _refreshData();
                        }
                      },
                      controller: TextEditingController(text: _daysWithoutMovement.toString()),
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
                ],
              ),
            ),
            
            // Data Table
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: DataTableWidget<Map<String, dynamic>>(
                  key: ValueKey({
                    _daysWithoutMovement,
                    _selectedWarehouseId,
                    _selectedCategoryId,
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

