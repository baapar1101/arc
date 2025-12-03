import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/invoice/warehouse_combobox_widget.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/data_table_utils.dart';

class InterWarehouseTransfersReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  
  const InterWarehouseTransfersReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<InterWarehouseTransfersReportPage> createState() => _InterWarehouseTransfersReportPageState();
}

class _InterWarehouseTransfersReportPageState extends State<InterWarehouseTransfersReportPage> {
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedWarehouseFromId;
  int? _selectedWarehouseToId;
  
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
      if (_selectedWarehouseFromId != null) 'warehouse_from_ids': [_selectedWarehouseFromId],
      if (_selectedWarehouseToId != null) 'warehouse_to_ids': [_selectedWarehouseToId],
    };
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/warehouse-reports/businesses/${widget.businessId}/inter-warehouse-transfers',
      businessId: widget.businessId,
      reportModuleKey: 'inter_warehouse_transfers',
      reportSubtype: 'list',
      title: 'گزارش انتقالات بین انبارها',
      showRowNumbers: true,
      enableRowSelection: false,
      showColumnSearch: false,
      showActiveFilters: true,
      showClearFiltersButton: false,
      showExportButtons: true,
      excelEndpoint: '/api/v1/warehouse-reports/businesses/${widget.businessId}/inter-warehouse-transfers/export/excel',
      additionalParams: _additionalParams(),
      columns: [
        TextColumn(
          'code',
          'کد حواله',
          width: ColumnWidth.medium,
          formatter: (row) => (row as Map<String, dynamic>)['code']?.toString() ?? '',
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
          'warehouse_from_name',
          'انبار مبدا',
          width: ColumnWidth.medium,
          formatter: (row) => (row as Map<String, dynamic>)['warehouse_from_name']?.toString() ?? '-',
        ),
        TextColumn(
          'warehouse_to_name',
          'انبار مقصد',
          width: ColumnWidth.medium,
          formatter: (row) => (row as Map<String, dynamic>)['warehouse_to_name']?.toString() ?? '-',
        ),
        NumberColumn(
          'items_count',
          'تعداد اقلام',
          formatter: (row) => _formatNumber((row as Map<String, dynamic>)['items_count']),
        ),
        NumberColumn(
          'total_quantity',
          'مقدار کل',
          formatter: (row) => _formatNumber((row as Map<String, dynamic>)['total_quantity']),
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
        title: const Text('گزارش انتقالات بین انبارها'),
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
                      selectedWarehouseId: _selectedWarehouseFromId,
                      onChanged: (id) {
                        setState(() {
                          _selectedWarehouseFromId = id;
                        });
                        _refreshData();
                      },
                      label: 'انبار مبدا',
                      hintText: 'همه انبارها',
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: WarehouseComboboxWidget(
                      businessId: widget.businessId,
                      selectedWarehouseId: _selectedWarehouseToId,
                      onChanged: (id) {
                        setState(() {
                          _selectedWarehouseToId = id;
                        });
                        _refreshData();
                      },
                      label: 'انبار مقصد',
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
                    _selectedWarehouseFromId,
                    _selectedWarehouseToId,
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

