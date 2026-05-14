import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/services/list_filter_preferences_service.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import 'package:hesabix_ui/utils/number_formatters.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';
import 'package:hesabix_ui/core/date_utils.dart';

class DebtorsReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  
  const DebtorsReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<DebtorsReportPage> createState() => _DebtorsReportPageState();
}

class _DebtorsReportPageState extends State<DebtorsReportPage> {
  final TextEditingController _minBalanceController = TextEditingController();
  
  // Filters
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedFiscalYearId;
  int? _selectedCurrencyId;
  double? _minBalance;
  
  // Fiscal years and currencies
  List<Map<String, dynamic>> _fiscalYears = [];
  List<Map<String, dynamic>> _currencies = [];

  @override
  void initState() {
    super.initState();
    _loadFiscalYears();
    _loadCurrencies();
  }

  @override
  void dispose() {
    _minBalanceController.dispose();
    super.dispose();
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
    // با تغییر key در DataTableWidget، خودکار rebuild می‌شود و config جدید با additionalParams جدید استفاده می‌شود
    // نیازی به فراخوانی refresh نیست چون rebuild خودکار باعث fetch می‌شود
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
      if (_minBalance != null) 'min_balance': _minBalance,
    };
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return formatWithThousands(n, decimalPlaces: 2);
  }

  String _formatDate(dynamic value) {
    if (value == null) return '';
    
    // استفاده از helper موجود
    return HesabixDateUtils.formatForDisplay(
      value is DateTime ? value : (value is String ? DateTime.tryParse(value) : null),
      widget.calendarController.isJalali,
    );
  }

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/persons/businesses/${widget.businessId}/reports/debtors',
      businessId: widget.businessId,
      persistTableFiltersPageId: ListFilterPageIds.debtorsReportTable,
      reportModuleKey: 'debtors',
      reportSubtype: 'list',
      title: t.reportsDebtorsTitle,
      showRowNumbers: true,
      columns: [
        TextColumn(
          'code',
          t.code,
          formatter: (item) => (item as Map<String, dynamic>)['code']?.toString() ?? '',
        ),
        TextColumn(
          'display_name',
          'نام',
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            return m['display_name']?.toString() ?? 
                   m['alias_name']?.toString() ?? 
                   '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
          },
        ),
        NumberColumn(
          'balance',
          t.openingBalance,
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['balance']),
        ),
        NumberColumn(
          'total_debit',
          t.debit,
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['total_debit']),
        ),
        NumberColumn(
          'total_credit',
          t.credit,
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['total_credit']),
        ),
        DateColumn(
          'last_transaction_date',
          'تاریخ آخرین تراکنش',
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            // استفاده از فیلد فرمت شده یا raw
            final formatted = m['last_transaction_date_formatted'] ?? m['last_transaction_date_raw'] ?? m['last_transaction_date'];
            return _formatDate(formatted);
          },
        ),
        CustomColumn(
          'status',
          t.status,
          builder: (item, _) {
            final m = item as Map<String, dynamic>;
            final status = m['status']?.toString() ?? '';
            final balance = m['balance'];
            double b = 0.0;
            if (balance is num) {
              b = balance.toDouble();
            } else if (balance != null) {
              b = double.tryParse(balance.toString()) ?? 0.0;
            }
            
            Color? color;
            if (b < 0) {
              color = Colors.red[700];
            } else if (b == 0) {
              color = Colors.grey;
            } else {
              color = Colors.green[700];
            }
            
            return Text(
              status,
              style: TextStyle(color: color, fontWeight: FontWeight.w500),
            );
          },
        ),
      ],
      searchFields: const ['code', 'alias_name', 'first_name', 'last_name', 'company_name'],
      defaultPageSize: 20,
      additionalParams: _additionalParams(),
      showExportButtons: true,
      excelEndpoint: '/api/v1/persons/businesses/${widget.businessId}/reports/debtors/export/excel',
      pdfEndpoint: '/api/v1/persons/businesses/${widget.businessId}/reports/debtors/export/pdf',
      getExportParams: () => _additionalParams(),
      rowColorBuilder: (item, index) {
        try {
          final m = item as Map<String, dynamic>;
          final balance = m['balance'];
          final b = balance is num ? balance.toDouble() : double.tryParse(balance?.toString() ?? '0') ?? 0.0;
          if (b < 0) {
            return Colors.red.withValues(alpha: 0.05);
          }
        } catch (_) {}
        return null;
      },
      footerTotals: {
        'balance': t.total,
        'total_debit': t.totalsDebit,
        'total_credit': t.totalsCredit,
      },
      expandBodyHeightToFitRows: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(t.reportsDebtorsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t.refresh,
            onPressed: _refreshData,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters
          Card(
            margin: const EdgeInsets.all(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<int>(
                      value: _selectedFiscalYearId,
                      decoration: InputDecoration(
                        labelText: t.fiscalYear,
                        border: const OutlineInputBorder(),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      ),
                      items: _fiscalYears.map<DropdownMenuItem<int>>((fy) {
                        final id = fy['id'] as int?;
                        final title = (fy['title'] ?? '').toString();
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text(
                            title.isNotEmpty ? title : 'FY ${id ?? ''}',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedFiscalYearId = val;
                        });
                        _refreshData();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<int>(
                      value: _selectedCurrencyId,
                      decoration: InputDecoration(
                        labelText: t.currency,
                        border: const OutlineInputBorder(),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      ),
                      items: _currencies.map<DropdownMenuItem<int>>((c) {
                        final id = c['id'] as int?;
                        final code = (c['code'] ?? '').toString();
                        final title = (c['title'] ?? code).toString();
                        final isDefault = c['is_default'] == true;
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text(
                            isDefault ? '$title (پیش‌فرض)' : title,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        );
                      }).toList(),
                      menuMaxHeight: 300,
                      onChanged: (val) {
                        setState(() {
                          _selectedCurrencyId = val;
                        });
                        _refreshData();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: DateInputField(
                      labelText: t.dateFrom,
                      value: _fromDate,
                      onChanged: (d) {
                        setState(() => _fromDate = d);
                        _refreshData();
                      },
                      calendarController: widget.calendarController,
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: DateInputField(
                      labelText: t.dateTo,
                      value: _toDate,
                      onChanged: (d) {
                        setState(() => _toDate = d);
                        _refreshData();
                      },
                      calendarController: widget.calendarController,
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: TextFormField(
                      controller: _minBalanceController,
                      decoration: InputDecoration(
                        labelText: 'حداقل بدهی',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        hintText: '1,000,000',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        const EnglishDigitsFormatter(),
                        FilteringTextInputFormatter.allow(RegExp(r'[\d,]')),
                        const ThousandsSeparatorInputFormatter(allowDecimal: false),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _minBalance = parseFormattedNumber(value)?.toDouble();
                        });
                        _refreshData();
                      },
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _fromDate = null;
                        _toDate = null;
                        _minBalance = null;
                        _minBalanceController.clear();
                      });
                      _refreshData();
                    },
                    icon: const Icon(Icons.clear),
                    label: Text(t.clear),
                  ),
                ],
              ),
            ),
          ),
          // Table
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: DataTableWidget<Map<String, dynamic>>(
                key: ValueKey({
                  _selectedFiscalYearId,
                  _selectedCurrencyId,
                  _fromDate?.toIso8601String(),
                  _toDate?.toIso8601String(),
                  _minBalance,
                }.toString()), // key بر اساس فیلترها برای rebuild خودکار
                config: _buildTableConfig(t),
                fromJson: (json) => Map<String, dynamic>.from(json as Map),
                calendarController: widget.calendarController,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
