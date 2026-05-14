import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/services/list_filter_preferences_service.dart';
import 'package:hesabix_ui/widgets/invoice/warehouse_combobox_widget.dart';
import 'package:hesabix_ui/widgets/category/category_picker_field.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/data_table_utils.dart';
import 'package:hesabix_ui/services/category_service.dart';
import 'package:hesabix_ui/core/api_client.dart';

class InventoryTurnoverReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  
  const InventoryTurnoverReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<InventoryTurnoverReportPage> createState() => _InventoryTurnoverReportPageState();
}

class _InventoryTurnoverReportPageState extends State<InventoryTurnoverReportPage> {
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedWarehouseId;
  int? _selectedCategoryId;
  List<Map<String, dynamic>> _categories = [];
  
  @override
  void initState() {
    super.initState();
    _fromDate = DateTime.now().subtract(const Duration(days: 365));
    _toDate = DateTime.now();
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
      if (_fromDate != null) 'date_from': _fromDate!.toIso8601String().split('T').first,
      if (_toDate != null) 'date_to': _toDate!.toIso8601String().split('T').first,
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
      endpoint: '/api/v1/warehouse-reports/businesses/${widget.businessId}/inventory-turnover',
      businessId: widget.businessId,
      persistTableFiltersPageId: ListFilterPageIds.inventoryTurnoverReportTable,
      reportModuleKey: 'inventory_turnover',
      reportSubtype: 'list',
      title: 'گزارش گردش موجودی',
      showRowNumbers: true,
      enableRowSelection: false,
      showColumnSearch: false,
      showActiveFilters: true,
      showClearFiltersButton: false,
      showExportButtons: true,
      excelEndpoint: '/api/v1/warehouse-reports/businesses/${widget.businessId}/inventory-turnover/export/excel',
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
          'average_stock',
          'موجودی متوسط',
          formatter: (row) => _formatNumber((row as Map<String, dynamic>)['average_stock']),
        ),
        NumberColumn(
          'total_out',
          'کل خروج',
          formatter: (row) => _formatNumber((row as Map<String, dynamic>)['total_out']),
        ),
        NumberColumn(
          'turnover_rate',
          'نرخ گردش',
          formatter: (row) {
            final rate = (row as Map<String, dynamic>)['turnover_rate'];
            if (rate == null) return '0';
            final n = rate is num ? rate.toDouble() : double.tryParse(rate.toString()) ?? 0.0;
            return DataTableUtils.formatNumber(n, decimalPlaces: 2);
          },
        ),
        TextColumn(
          'unit',
          'واحد',
          width: ColumnWidth.small,
          formatter: (row) => (row as Map<String, dynamic>)['unit']?.toString() ?? '',
        ),
      ],
      defaultPageSize: 50,
      defaultSortBy: 'turnover_rate',
      defaultSortDesc: true,
      expandBodyHeightToFitRows: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('گزارش گردش موجودی'),
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
                    width: 160,
                    child: DateInputField(
                      labelText: 'از تاریخ',
                      value: _fromDate,
                      calendarController: widget.calendarController,
                      onChanged: (date) {
                        setState(() {
                          _fromDate = date;
                        });
                        _refreshData();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: DateInputField(
                      labelText: 'تا تاریخ',
                      value: _toDate,
                      calendarController: widget.calendarController,
                      onChanged: (date) {
                        setState(() {
                          _toDate = date;
                        });
                        _refreshData();
                      },
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
                    _fromDate?.toIso8601String(),
                    _toDate?.toIso8601String(),
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

