import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/invoice/warehouse_combobox_widget.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/data_table_utils.dart';

class PendingDocumentsReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  
  const PendingDocumentsReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<PendingDocumentsReportPage> createState() => _PendingDocumentsReportPageState();
}

class _PendingDocumentsReportPageState extends State<PendingDocumentsReportPage> {
  int? _selectedWarehouseId;
  
  @override
  void initState() {
    super.initState();
  }

  void _refreshData() {
    if (mounted) {
      setState(() {});
    }
  }

  Map<String, dynamic> _additionalParams() {
    return {
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
      endpoint: '/api/v1/warehouse-reports/businesses/${widget.businessId}/pending-documents',
      businessId: widget.businessId,
      reportModuleKey: 'pending_documents',
      reportSubtype: 'list',
      title: 'گزارش حواله‌های در انتظار تایید',
      showRowNumbers: true,
      enableRowSelection: false,
      showColumnSearch: false,
      showActiveFilters: true,
      showClearFiltersButton: false,
      showExportButtons: true,
      excelEndpoint: '/api/v1/warehouse-reports/businesses/${widget.businessId}/pending-documents/export/excel',
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
        NumberColumn(
          'items_count',
          'تعداد اقلام',
          formatter: (row) => _formatNumber((row as Map<String, dynamic>)['items_count']),
        ),
        NumberColumn(
          'days_pending',
          'روز انتظار',
          formatter: (row) => _formatNumber((row as Map<String, dynamic>)['days_pending']),
        ),
      ],
      defaultPageSize: 50,
      defaultSortBy: 'days_pending',
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
        title: const Text('گزارش حواله‌های در انتظار تایید'),
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

