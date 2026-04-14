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

class TrialBalanceReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  
  const TrialBalanceReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<TrialBalanceReportPage> createState() => _TrialBalanceReportPageState();
}

class _TrialBalanceReportPageState extends State<TrialBalanceReportPage> {
  // Filters
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedFiscalYearId;
  int? _selectedCurrencyId;
  String? _selectedAccountType;
  bool _includeZeroBalance = false;
  
  // Data
  List<Map<String, dynamic>> _fiscalYears = [];
  List<Map<String, dynamic>> _currencies = [];
  
  // Account types for filtering
  final List<String> _accountTypes = [
    'bank',
    'cash_register',
    'petty_cash',
    'check',
    'person',
    'product',
    'service',
    'accounting_document',
  ];
  
  String _localizedAccountType(AppLocalizations t, String? value) {
    if (value == null || value.isEmpty) return '-';
    final ln = t.localeName;
    if (ln.startsWith('fa')) {
      switch (value) {
        case 'bank':
          return t.accountTypeBank;
        case 'cash_register':
          return t.accountTypeCashRegister;
        case 'petty_cash':
          return t.accountTypePettyCash;
        case 'check':
          return t.accountTypeCheck;
        case 'person':
          return t.accountTypePerson;
        case 'product':
          return t.accountTypeProduct;
        case 'service':
          return t.accountTypeService;
        case 'accounting_document':
          return t.accountTypeAccountingDocument;
        default:
          return value;
      }
    }
    // English and other locales: humanize
    String humanize(String v) {
      return v
          .split('_')
          .map((p) => p.isEmpty ? p : (p[0].toUpperCase() + p.substring(1)))
          .join(' ');
    }
    switch (value) {
      case 'bank':
        return t.accountTypeBank;
      case 'cash_register':
        return t.accountTypeCashRegister;
      case 'petty_cash':
        return t.accountTypePettyCash;
      case 'check':
        return t.accountTypeCheck;
      case 'person':
        return t.accountTypePerson;
      case 'product':
        return t.accountTypeProduct;
      case 'service':
        return t.accountTypeService;
      case 'accounting_document':
        return t.accountTypeAccountingDocument;
      default:
        return humanize(value);
    }
  }

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
      if (_selectedAccountType != null) 'account_type': _selectedAccountType,
      'include_zero_balance': _includeZeroBalance,
    };
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/businesses/${widget.businessId}/reports/trial-balance',
      businessId: widget.businessId,
      reportModuleKey: 'trial_balance',
      reportSubtype: 'list',
      title: t.reportsTrialBalanceTitle,
      showRowNumbers: true,
      columns: [
        TextColumn(
          'account_code',
          'کد حساب',
          formatter: (item) => (item as Map<String, dynamic>)['account_code']?.toString() ?? '',
        ),
        TextColumn(
          'account_name',
          'نام حساب',
          formatter: (item) => (item as Map<String, dynamic>)['account_name']?.toString() ?? '',
        ),
        TextColumn(
          'account_type',
          'نوع حساب',
          formatter: (item) {
            final type = (item as Map<String, dynamic>)['account_type']?.toString() ?? '';
            return _localizedAccountType(t, type);
          },
        ),
        NumberColumn(
          'opening_debit',
          'مانده ابتدای دوره (بدهکار)',
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['opening_debit']),
        ),
        NumberColumn(
          'opening_credit',
          'مانده ابتدای دوره (بستانکار)',
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['opening_credit']),
        ),
        NumberColumn(
          'period_debit',
          'جمع بدهکار دوره',
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['period_debit']),
        ),
        NumberColumn(
          'period_credit',
          'جمع بستانکار دوره',
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['period_credit']),
        ),
        NumberColumn(
          'closing_debit',
          'مانده انتهای دوره (بدهکار)',
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['closing_debit']),
        ),
        NumberColumn(
          'closing_credit',
          'مانده انتهای دوره (بستانکار)',
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['closing_credit']),
        ),
      ],
      searchFields: const ['account_code', 'account_name'],
      defaultPageSize: 50,
      additionalParams: _additionalParams(),
      showExportButtons: true,
      excelEndpoint: '/api/v1/businesses/${widget.businessId}/reports/trial-balance/export/excel',
      pdfEndpoint: '/api/v1/businesses/${widget.businessId}/reports/trial-balance/export/pdf',
      getExportParams: () => _additionalParams(),
      footerTotals: {
        'opening_debit': 'جمع مانده ابتدای دوره (بدهکار)',
        'opening_credit': 'جمع مانده ابتدای دوره (بستانکار)',
        'period_debit': 'جمع بدهکار دوره',
        'period_credit': 'جمع بستانکار دوره',
        'closing_debit': 'جمع مانده انتهای دوره (بدهکار)',
        'closing_credit': 'جمع مانده انتهای دوره (بستانکار)',
      },
      defaultSortBy: 'account_code',
      defaultSortDesc: false,
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
        title: Text(t.reportsTrialBalanceTitle),
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
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      ),
                      items: _fiscalYears.map((fy) {
                        return DropdownMenuItem<int>(
                          value: fy['id'] as int?,
                          child: Text(
                            fy['title']?.toString() ?? '',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedFiscalYearId = value;
                        });
                        _refreshData();
                      },
                    ),
                  ),
                  
                  // Date From
                  SizedBox(
                    width: 180,
                    child: DateInputField(
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
                  
                  // Date To
                  SizedBox(
                    width: 180,
                    child: DateInputField(
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
                  
                  // Currency
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<int>(
                      value: _selectedCurrencyId,
                      decoration: InputDecoration(
                        labelText: 'ارز',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      ),
                      items: [
                        const DropdownMenuItem<int>(
                          value: null,
                          child: Text('همه ارزها'),
                        ),
                        ..._currencies.map<DropdownMenuItem<int>>((c) {
                          final id = c['id'] as int?;
                          final code = (c['code'] ?? '').toString();
                          final name = (c['name'] ?? '').toString();
                          final displayName = code.isNotEmpty ? '$code - $name' : name;
                          return DropdownMenuItem<int>(
                            key: ValueKey('currency_$id'),
                            value: id,
                            child: Text(
                              displayName,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          );
                        }).toList(),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedCurrencyId = val;
                        });
                        _refreshData();
                      },
                    ),
                  ),
                  
                  // Account Type
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String>(
                      value: _selectedAccountType,
                      decoration: InputDecoration(
                        labelText: 'نوع حساب',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('همه انواع'),
                        ),
                        ..._accountTypes.map((type) {
                          final t = AppLocalizations.of(context);
                          return DropdownMenuItem<String>(
                            value: type,
                            child: Text(_localizedAccountType(t, type)),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedAccountType = value;
                        });
                        _refreshData();
                      },
                    ),
                  ),
                  
                  // Include Zero Balance
                  SizedBox(
                    width: 200,
                    child: CheckboxListTile(
                      title: const Text('نمایش حساب‌های با مانده صفر'),
                      value: _includeZeroBalance,
                      onChanged: (value) {
                        setState(() {
                          _includeZeroBalance = value ?? false;
                        });
                        _refreshData();
                      },
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Data Table
          Expanded(
            child: DataTableWidget<Map<String, dynamic>>(
              key: ValueKey(
                'trial_balance_${_selectedFiscalYearId}_${_selectedCurrencyId}_${_selectedAccountType}_${_includeZeroBalance}_${_fromDate?.toIso8601String()}_${_toDate?.toIso8601String()}',
              ),
              config: _buildTableConfig(t),
              fromJson: (json) => Map<String, dynamic>.from(json),
              calendarController: widget.calendarController,
            ),
          ),
        ],
      ),
    );
  }
}

