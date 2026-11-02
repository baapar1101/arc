import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/hesabix_back.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/list_filter_preferences_service.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/data_table_utils.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/invoice/warehouse_combobox_widget.dart';

class ExpiryStockReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;

  const ExpiryStockReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<ExpiryStockReportPage> createState() => _ExpiryStockReportPageState();
}

class _ExpiryStockReportPageState extends State<ExpiryStockReportPage> {
  DateTime? _asOfDate;
  int? _selectedWarehouseId;
  String? _status;

  @override
  void initState() {
    super.initState();
    _asOfDate = null;
  }

  Map<String, dynamic> _additionalParams() {
    return {
      if (_asOfDate != null) 'as_of_date': _asOfDate!.toIso8601String().split('T').first,
      if (_selectedWarehouseId != null) 'warehouse_ids': [_selectedWarehouseId],
      if (_status != null) 'statuses': [_status],
    };
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  String _statusLabel(AppLocalizations t, dynamic raw) {
    switch (raw?.toString()) {
      case 'sellable':
        return t.expiryStatusSellable;
      case 'near_expiry':
        return t.expiryStatusNearExpiry;
      case 'blocked':
        return t.expiryStatusBlocked;
      case 'expired':
        return t.expiryStatusExpired;
      case 'undated':
        return t.expiryStatusUndated;
      default:
        return raw?.toString() ?? '-';
    }
  }

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/warehouse-reports/businesses/${widget.businessId}/expiry-stock',
      businessId: widget.businessId,
      persistTableFiltersPageId: ListFilterPageIds.expiryStockReportTable,
      reportModuleKey: 'expiry_stock',
      reportSubtype: 'list',
      title: t.reportsExpiryStockTitle,
      showRowNumbers: true,
      enableRowSelection: false,
      showColumnSearch: false,
      showActiveFilters: true,
      showClearFiltersButton: false,
      showExportButtons: true,
      excelEndpoint: '/api/v1/warehouse-reports/businesses/${widget.businessId}/expiry-stock/export/excel',
      additionalParams: _additionalParams(),
      columns: [
        TextColumn(
          'product_code',
          'کد کالا',
          width: ColumnWidth.small,
          formatter: (row) => (row as Map<String, dynamic>)['product_code']?.toString() ?? '',
        ),
        TextColumn(
          'product_name',
          'نام کالا',
          width: ColumnWidth.large,
          formatter: (row) => (row as Map<String, dynamic>)['product_name']?.toString() ?? '',
        ),
        TextColumn(
          'lot_code',
          t.expiryColLotSerial,
          width: ColumnWidth.small,
          formatter: (row) {
            final m = row as Map<String, dynamic>;
            final serial = m['serial_number']?.toString();
            if (serial != null && serial.isNotEmpty) return serial;
            return m['lot_code']?.toString() ?? '-';
          },
        ),
        TextColumn(
          'manufacturing_date',
          t.expiryColManufacturing,
          width: ColumnWidth.medium,
          formatter: (row) => (row as Map<String, dynamic>)['manufacturing_date']?.toString() ?? '-',
        ),
        TextColumn(
          'expiry_date',
          t.expiryColExpiry,
          width: ColumnWidth.medium,
          formatter: (row) => (row as Map<String, dynamic>)['expiry_date']?.toString() ?? '-',
        ),
        TextColumn(
          'status',
          t.status,
          width: ColumnWidth.medium,
          formatter: (row) => _statusLabel(t, (row as Map<String, dynamic>)['status']),
        ),
        NumberColumn(
          'quantity_main',
          'مقدار اصلی',
          formatter: (row) => _formatNumber((row as Map<String, dynamic>)['quantity_main']),
        ),
        NumberColumn(
          'quantity_secondary',
          'مقدار فرعی',
          formatter: (row) => _formatNumber((row as Map<String, dynamic>)['quantity_secondary']),
        ),
        NumberColumn(
          'remaining_days',
          t.expiryColRemainingDays,
          formatter: (row) {
            final v = (row as Map<String, dynamic>)['remaining_days'];
            return v == null ? '-' : v.toString();
          },
        ),
        TextColumn(
          'warehouse_name',
          t.warehouse,
          width: ColumnWidth.medium,
          formatter: (row) => (row as Map<String, dynamic>)['warehouse_name']?.toString() ?? '-',
        ),
      ],
      defaultPageSize: 50,
      defaultSortBy: 'expiry_date',
      defaultSortDesc: false,
      expandBodyHeightToFitRows: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(t.reportsExpiryStockTitle),
        leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 160,
                    child: DateInputField(
                      labelText: t.expiryReportAsOf,
                      value: _asOfDate,
                      calendarController: widget.calendarController,
                      onChanged: (date) {
                        setState(() => _asOfDate = date);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: WarehouseComboboxWidget(
                      businessId: widget.businessId,
                      selectedWarehouseId: _selectedWarehouseId,
                      onChanged: (id) {
                        setState(() => _selectedWarehouseId = id);
                      },
                      label: t.warehouse,
                      hintText: t.expiryReportAllStatuses,
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String?>(
                      value: _status,
                      decoration: InputDecoration(labelText: t.status),
                      items: [
                        DropdownMenuItem(value: null, child: Text(t.expiryReportAllStatuses)),
                        DropdownMenuItem(value: 'sellable', child: Text(t.expiryStatusSellable)),
                        DropdownMenuItem(value: 'near_expiry', child: Text(t.expiryStatusNearExpiry)),
                        DropdownMenuItem(value: 'blocked', child: Text(t.expiryStatusBlocked)),
                        DropdownMenuItem(value: 'expired', child: Text(t.expiryStatusExpired)),
                        DropdownMenuItem(value: 'undated', child: Text(t.expiryStatusUndated)),
                      ],
                      onChanged: (v) => setState(() => _status = v),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: DataTableWidget<Map<String, dynamic>>(
                  key: ValueKey({
                    _asOfDate?.toIso8601String(),
                    _selectedWarehouseId,
                    _status,
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
