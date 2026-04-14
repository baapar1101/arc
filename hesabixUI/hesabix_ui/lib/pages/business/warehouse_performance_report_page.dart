import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/invoice/warehouse_combobox_widget.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/data_table_utils.dart';

class WarehousePerformanceReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  
  const WarehousePerformanceReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<WarehousePerformanceReportPage> createState() => _WarehousePerformanceReportPageState();
}

class _WarehousePerformanceReportPageState extends State<WarehousePerformanceReportPage> {
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedWarehouseId;
  
  @override
  void initState() {
    super.initState();
    _fromDate = DateTime.now().subtract(const Duration(days: 30));
    _toDate = DateTime.now();
  }

  void _refreshData() {
    if (mounted) {
      setState(() {});
    }
  }

  Map<String, dynamic> _additionalParams() {
    return {
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
      endpoint: '/api/v1/warehouse-reports/businesses/${widget.businessId}/warehouse-performance',
      businessId: widget.businessId,
      reportModuleKey: 'warehouse_performance',
      reportSubtype: 'list',
      title: 'گزارش عملکرد انبارها',
      showRowNumbers: true,
      enableRowSelection: false,
      showColumnSearch: false,
      showActiveFilters: true,
      showClearFiltersButton: false,
      showExportButtons: true,
      excelEndpoint: '/api/v1/warehouse-reports/businesses/${widget.businessId}/warehouse-performance/export/excel',
      additionalParams: _additionalParams(),
      columns: [
        TextColumn(
          'warehouse_code',
          'کد انبار',
          width: ColumnWidth.small,
          formatter: (row) => (row as Map<String, dynamic>)['warehouse_code']?.toString() ?? '',
        ),
        TextColumn(
          'warehouse_name',
          'نام انبار',
          width: ColumnWidth.large,
          formatter: (row) => (row as Map<String, dynamic>)['warehouse_name']?.toString() ?? '',
        ),
        NumberColumn(
          'total_documents',
          'تعداد حواله‌ها',
          formatter: (row) => _formatNumber((row as Map<String, dynamic>)['total_documents']),
        ),
        NumberColumn(
          'total_items',
          'تعداد اقلام',
          formatter: (row) => _formatNumber((row as Map<String, dynamic>)['total_items']),
        ),
        NumberColumn(
          'total_quantity_in',
          'کل ورود',
          formatter: (row) => _formatNumber((row as Map<String, dynamic>)['total_quantity_in']),
        ),
        NumberColumn(
          'total_quantity_out',
          'کل خروج',
          formatter: (row) => _formatNumber((row as Map<String, dynamic>)['total_quantity_out']),
        ),
        NumberColumn(
          'net_quantity',
          'خالص',
          formatter: (row) => _formatNumber((row as Map<String, dynamic>)['net_quantity']),
        ),
      ],
      defaultPageSize: 50,
      defaultSortBy: 'warehouse_code',
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
        title: const Text('گزارش عملکرد انبارها'),
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

