import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/invoice/product_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/warehouse_combobox_widget.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/data_table_utils.dart';

class ProductMovementHistoryReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  
  const ProductMovementHistoryReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<ProductMovementHistoryReportPage> createState() => _ProductMovementHistoryReportPageState();
}

class _ProductMovementHistoryReportPageState extends State<ProductMovementHistoryReportPage> {
  DateTime? _fromDate;
  DateTime? _toDate;
  Map<String, dynamic>? _selectedProduct;
  int? _selectedWarehouseId;
  bool _hasProducts = true;
  
  @override
  void initState() {
    super.initState();
    _fromDate = DateTime.now().subtract(const Duration(days: 30));
    _toDate = DateTime.now();
  }
  
  void _onProductsLoaded(List<Map<String, dynamic>> products) {
    if (!mounted) return;
    
    setState(() {
      _hasProducts = products.isNotEmpty;
      
      // انتخاب خودکار اولین محصول اگر هیچ محصولی انتخاب نشده باشد
      if (_selectedProduct == null && products.isNotEmpty) {
        _selectedProduct = products.first;
      }
    });
  }

  void _refreshData() {
    if (mounted) {
      setState(() {});
    }
  }

  Map<String, dynamic> _additionalParams() {
    return {
      if (_selectedProduct != null) 'product_id': _selectedProduct!['id'],
      if (_fromDate != null) 'date_from': _fromDate!.toIso8601String().split('T').first,
      if (_toDate != null) 'date_to': _toDate!.toIso8601String().split('T').first,
      if (_selectedWarehouseId != null) 'warehouse_ids': [_selectedWarehouseId],
    };
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/warehouse-reports/businesses/${widget.businessId}/product-movement-history',
      businessId: widget.businessId,
      reportModuleKey: 'product_movement_history',
      reportSubtype: 'list',
      title: 'گزارش تاریخچه حرکات یک کالا',
      showRowNumbers: true,
      enableRowSelection: false,
      showColumnSearch: false,
      showActiveFilters: true,
      showClearFiltersButton: false,
      showExportButtons: true,
      excelEndpoint: '/api/v1/warehouse-reports/businesses/${widget.businessId}/product-movement-history/export/excel',
      additionalParams: _additionalParams(),
      columns: [
        TextColumn(
          'document_code',
          'کد حواله',
          width: ColumnWidth.medium,
          formatter: (row) => (row as Map<String, dynamic>)['document_code']?.toString() ?? '',
        ),
        TextColumn(
          'document_date',
          'تاریخ',
          width: ColumnWidth.medium,
          formatter: (row) {
            final date = (row as Map<String, dynamic>)['document_date'];
            if (date == null) return '-';
            return date.toString().split('T').first;
          },
        ),
        TextColumn(
          'doc_type',
          'نوع حواله',
          width: ColumnWidth.medium,
          formatter: (row) {
            final type = (row as Map<String, dynamic>)['doc_type']?.toString() ?? '';
            final typeNames = {
              'receipt': 'ورود',
              'issue': 'خروج',
              'transfer': 'انتقال',
              'adjustment': 'تعدیل',
              'production_in': 'ورود تولید',
              'production_out': 'خروج تولید',
            };
            return typeNames[type] ?? type;
          },
        ),
        TextColumn(
          'warehouse_name',
          'انبار',
          width: ColumnWidth.medium,
          formatter: (row) => (row as Map<String, dynamic>)['warehouse_name']?.toString() ?? '-',
        ),
        TextColumn(
          'movement',
          'نوع حرکت',
          width: ColumnWidth.small,
          formatter: (row) {
            final movement = (row as Map<String, dynamic>)['movement']?.toString() ?? '';
            return movement == 'in' ? 'ورود' : 'خروج';
          },
        ),
        NumberColumn(
          'quantity',
          'مقدار',
          formatter: (row) => _formatNumber((row as Map<String, dynamic>)['quantity']),
        ),
      ],
      defaultPageSize: 50,
      defaultSortBy: 'document_date',
      defaultSortDesc: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('گزارش تاریخچه حرکات یک کالا'),
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
                      onProductsLoaded: _onProductsLoaded,
                      label: 'محصول',
                      hintText: 'انتخاب محصول',
                    ),
                  ),
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
                ],
              ),
            ),
            
            // Data Table
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: !_hasProducts
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 64,
                              color: theme.colorScheme.outline.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'هیچ کالایی موجود نیست',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'لطفاً ابتدا کالایی به سیستم اضافه کنید',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      )
                    : DataTableWidget<Map<String, dynamic>>(
                        key: ValueKey({
                          _selectedProduct?['id'],
                          _fromDate?.toIso8601String(),
                          _toDate?.toIso8601String(),
                          _selectedWarehouseId,
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

