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
import 'package:shamsi_date/shamsi_date.dart';

class MonthlySalesReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  
  const MonthlySalesReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<MonthlySalesReportPage> createState() => _MonthlySalesReportPageState();
}

class _MonthlySalesReportPageState extends State<MonthlySalesReportPage> {
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

  String _formatMonth(dynamic value) {
    if (value == null) return '';
    final monthKey = value.toString();
    if (monthKey.length == 7 && monthKey.contains('-')) {
      // Format: YYYY-MM
      final parts = monthKey.split('-');
      if (parts.length == 2) {
        final year = parts[0];
        final month = parts[1];
        // Display month name based on calendar
        if (widget.calendarController.isJalali) {
          // Persian month names
          final monthNames = [
            '', 'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
            'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'
          ];
          try {
            final monthNum = int.parse(month);
            if (monthNum >= 1 && monthNum <= 12) {
              return '${monthNames[monthNum]} $year';
            }
          } catch (_) {}
        } else {
          // Gregorian month names
          final monthNames = [
            '', 'January', 'February', 'March', 'April', 'May', 'June',
            'July', 'August', 'September', 'October', 'November', 'December'
          ];
          try {
            final monthNum = int.parse(month);
            if (monthNum >= 1 && monthNum <= 12) {
              return '${monthNames[monthNum]} $year';
            }
          } catch (_) {}
        }
        return '$year/$month';
      }
    }
    return monthKey;
  }

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/businesses/${widget.businessId}/reports/monthly-sales',
      businessId: widget.businessId,
      reportModuleKey: 'monthly_sales',
      reportSubtype: 'list',
      title: t.reportsMonthlySalesTitle,
      showRowNumbers: true,
      enableRowSelection: false,
      showColumnSearch: false,
      showActiveFilters: true,
      showClearFiltersButton: false,
      showExportButtons: true,
      excelEndpoint: '/api/v1/businesses/${widget.businessId}/reports/monthly-sales/export/excel',
      pdfEndpoint: '/api/v1/businesses/${widget.businessId}/reports/monthly-sales/export/pdf',
      additionalParams: _additionalParams(),
      columns: [
        TextColumn(
          'month_key',
          'ماه',
          width: ColumnWidth.medium,
          formatter: (row) {
            // اول سعی می‌کنیم از month_key استفاده کنیم
            final monthKey = row['month_key'];
            if (monthKey != null && monthKey.toString().isNotEmpty) {
              return _formatMonth(monthKey.toString());
            }
            // اگر month_key نبود، از date استفاده می‌کنیم
            final dateValue = row['date'];
            if (dateValue != null) {
              try {
                DateTime? dt;
                if (dateValue is DateTime) {
                  dt = dateValue;
                } else if (dateValue is String) {
                  dt = DateTime.tryParse(dateValue);
                }
                
                if (dt != null) {
                  // فرمت ماهانه بر اساس تقویم
                  if (widget.calendarController.isJalali) {
                    // تبدیل به شمسی
                    final local = dt.toLocal();
                    try {
                      final jalali = Jalali.fromDateTime(local);
                      final monthNames = [
                        '', 'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
                        'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'
                      ];
                      if (jalali.month >= 1 && jalali.month <= 12) {
                        return '${monthNames[jalali.month]} ${jalali.year}';
                      }
                    } catch (_) {
                      // Fallback: نمایش تاریخ
                      return HesabixDateUtils.formatForDisplay(dt, true);
                    }
                  } else {
                    // میلادی
                    final monthNames = [
                      '', 'January', 'February', 'March', 'April', 'May', 'June',
                      'July', 'August', 'September', 'October', 'November', 'December'
                    ];
                    final local = dt.toLocal();
                    final month = local.month;
                    final year = local.year;
                    if (month >= 1 && month <= 12) {
                      return '${monthNames[month]} $year';
                    }
                  }
                }
              } catch (_) {}
            }
            // Fallback: از year و month استفاده کنیم
            final year = row['year'];
            final month = row['month'];
            if (year != null && month != null) {
              return _formatMonth('$year-${month.toString().padLeft(2, '0')}');
            }
            return '-';
          },
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
      defaultSortBy: 'month_key',
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
        title: Text(t.reportsMonthlySalesTitle),
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
            SingleChildScrollView(
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

