import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/data_table_utils.dart';
import 'package:hesabix_ui/core/date_utils.dart';

class DailyPurchasesReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  
  const DailyPurchasesReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<DailyPurchasesReportPage> createState() => _DailyPurchasesReportPageState();
}

class _DailyPurchasesReportPageState extends State<DailyPurchasesReportPage> {
  // Filters
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedFiscalYearId;
  int? _selectedCurrencyId;
  
  // Data
  List<Map<String, dynamic>> _fiscalYears = [];
  List<Map<String, dynamic>> _currencies = [];

  @override
  void initState() {
    super.initState();
    _loadFiscalYears();
    _loadCurrencies();
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

  Future<void> _loadCurrencies() async {
    try {
      final svc = CurrencyService(ApiClient());
      final items = await svc.listBusinessCurrencies(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _currencies = items;
        // انتخاب ارز پیش‌فرض
        if (items.isNotEmpty) {
          final defaultCurrency = items.firstWhere(
            (c) => c['is_default'] == true,
            orElse: () => items.first,
          );
          _selectedCurrencyId = defaultCurrency['id'] as int?;
        }
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

  Map<String, dynamic> _additionalParams() {
    return {
      if (_fromDate != null) 'date_from': _fromDate!.toIso8601String().split('T').first,
      if (_toDate != null) 'date_to': _toDate!.toIso8601String().split('T').first,
      if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
      if (_selectedCurrencyId != null) 'currency_id': _selectedCurrencyId,
    };
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  String _formatDate(dynamic value) {
    if (value == null) return '';
    if (value is String) {
      try {
        final dt = DateTime.parse(value);
        return HesabixDateUtils.formatForDisplay(dt, widget.calendarController.isJalali);
      } catch (_) {
        return value;
      }
    }
    return HesabixDateUtils.formatForDisplay(
      value is DateTime ? value : null,
      widget.calendarController.isJalali,
    );
  }

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/businesses/${widget.businessId}/reports/daily-purchases',
      businessId: widget.businessId,
      reportModuleKey: 'daily_purchases',
      reportSubtype: 'list',
      title: t.reportsDailyPurchasesTitle,
      showRowNumbers: true,
      enableRowSelection: false,
      showColumnSearch: false,
      showActiveFilters: true,
      showClearFiltersButton: false,
      showExportButtons: true,
      additionalParams: _additionalParams(),
      columns: [
        DateColumn(
          'date',
          'تاریخ',
          width: ColumnWidth.medium,
          formatter: (row) => _formatDate(row['date']),
        ),
        NumberColumn(
          'invoice_count',
          'تعداد فاکتور',
          width: ColumnWidth.small,
          formatter: (row) => _formatNumber(row['invoice_count']),
        ),
        NumberColumn(
          'total_gross',
          'جمع کل',
          width: ColumnWidth.medium,
          formatter: (row) => _formatNumber(row['total_gross']),
        ),
        NumberColumn(
          'total_discount',
          'جمع تخفیف',
          width: ColumnWidth.medium,
          formatter: (row) => _formatNumber(row['total_discount']),
        ),
        NumberColumn(
          'total_tax',
          'جمع مالیات',
          width: ColumnWidth.medium,
          formatter: (row) => _formatNumber(row['total_tax']),
        ),
        NumberColumn(
          'total_net',
          'جمع خالص',
          width: ColumnWidth.medium,
          formatter: (row) => _formatNumber(row['total_net']),
        ),
      ],
      footerTotals: {
        'invoice_count': 'جمع تعداد',
        'total_gross': 'جمع کل',
        'total_discount': 'جمع تخفیف',
        'total_tax': 'جمع مالیات',
        'total_net': 'جمع خالص',
      },
      defaultPageSize: 50,
      defaultSortBy: 'date',
      defaultSortDesc: true,
      excelEndpoint: '/api/v1/businesses/${widget.businessId}/reports/daily-purchases/export/excel',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(t.reportsDailyPurchasesTitle),
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
              padding: const EdgeInsets.all(16),
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
                spacing: 16,
                runSpacing: 16,
                children: [
                  // Fiscal Year
                  SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<int>(
                      value: _selectedFiscalYearId,
                      decoration: InputDecoration(
                        labelText: 'سال مالی',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<int>(
                          value: null,
                          child: Text('همه سال‌های مالی'),
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
                  
                  // Currency
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<int>(
                      value: _selectedCurrencyId,
                      decoration: InputDecoration(
                        labelText: 'واحد پول',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<int>(
                          value: null,
                          child: Text('همه ارزها'),
                        ),
                        ..._currencies.map((curr) {
                          final id = curr['id'] as int?;
                          final code = (curr['code'] ?? '').toString();
                          final title = (curr['title'] ?? '').toString();
                          final displayName = code.isNotEmpty ? '$code - $title' : title;
                          return DropdownMenuItem<int>(
                            value: id,
                            child: Text(
                              displayName,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedCurrencyId = value;
                        });
                        _refreshData();
                      },
                    ),
                  ),
                  
                  // From Date
                  SizedBox(
                    width: 200,
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
                  
                  // To Date
                  SizedBox(
                    width: 200,
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
                ],
              ),
            ),
            
            // Data Table
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: DataTableWidget<Map<String, dynamic>>(
                  key: ValueKey({
                    _selectedFiscalYearId,
                    _selectedCurrencyId,
                    _fromDate?.toIso8601String(),
                    _toDate?.toIso8601String(),
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


