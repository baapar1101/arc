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

class JournalLedgerReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  
  const JournalLedgerReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<JournalLedgerReportPage> createState() => _JournalLedgerReportPageState();
}

class _JournalLedgerReportPageState extends State<JournalLedgerReportPage> {
  // Filters
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedFiscalYearId;
  int? _selectedCurrencyId;
  String? _selectedDocumentType;
  bool _includeProforma = false;
  
  // Data
  List<Map<String, dynamic>> _fiscalYears = [];
  List<Map<String, dynamic>> _currencies = [];
  
  // Summary from API response
  Map<String, dynamic>? _summary;

  // Document types
  final Map<String, String> _documentTypes = {
    'invoice_sales': 'فاکتور فروش',
    'invoice_sales_return': 'برگشت از فروش',
    'invoice_purchase': 'فاکتور خرید',
    'invoice_purchase_return': 'برگشت از خرید',
    'invoice_production': 'فاکتور تولید',
    'invoice_direct_consumption': 'مصرف مستقیم',
    'invoice_waste': 'ضایعات',
    'receipt': 'دریافت',
    'payment': 'پرداخت',
    'transfer': 'انتقال',
    'expense_income': 'درآمد/هزینه',
    'opening_balance': 'تراز افتتاحیه',
    'manual_document': 'سند دستی',
    'check_endorse': 'پاسخگویی چک',
    'check_clear': 'وصول چک',
    'check_pay': 'پرداخت چک',
    'check_return': 'برگشت چک',
    'check_bounce': 'برگشت خوردن چک',
    'check_deposit': 'واریز به حساب',
    'check_delete': 'حذف چک',
  };

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

  Future<void> _fetchSummary() async {
    try {
      final api = ApiClient();
      final requestData = <String, dynamic>{
        'take': 1,
        'skip': 0,
        ..._additionalParams(),
      };
      
      final res = await api.post<Map<String, dynamic>>(
        '/api/v1/businesses/${widget.businessId}/reports/journal-ledger',
        data: requestData,
      );
      
      final body = res.data;
      if (body is Map<String, dynamic> && body['data'] is Map<String, dynamic>) {
        final data = body['data'] as Map<String, dynamic>;
        final summary = data['summary'] as Map<String, dynamic>?;
        if (summary != null && mounted) {
          setState(() {
            _summary = summary;
          });
        }
      }
    } catch (_) {
      // Ignore errors
    }
  }

  Map<String, dynamic> _additionalParams() {
    return {
      if (_fromDate != null) 'date_from': _fromDate!.toIso8601String().split('T').first,
      if (_toDate != null) 'date_to': _toDate!.toIso8601String().split('T').first,
      if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
      if (_selectedCurrencyId != null) 'currency_id': _selectedCurrencyId,
      if (_selectedDocumentType != null) 'document_type': _selectedDocumentType,
      'include_proforma': _includeProforma,
    };
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  String _formatAccount(dynamic code, dynamic name) {
    if (code == null && name == null) return '-';
    if (code == null) return name?.toString() ?? '-';
    if (name == null) return code.toString();
    return '${code} - ${name}';
  }

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/businesses/${widget.businessId}/reports/journal-ledger',
      businessId: widget.businessId,
      reportModuleKey: 'journal_ledger',
      reportSubtype: 'list',
      title: t.reportsJournalLedgerTitle,
      showRowNumbers: true,
      columns: [
        DateColumn(
          'document_date',
          'تاریخ سند',
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            final date = m['document_date'];
            if (date == null) return '';
            DateTime? dateObj;
            if (date is DateTime) {
              dateObj = date;
            } else if (date is String) {
              dateObj = DateTime.tryParse(date);
            }
            if (dateObj == null) return date.toString();
            return HesabixDateUtils.formatForDisplay(
              dateObj,
              widget.calendarController.isJalali,
            );
          },
        ),
        TextColumn(
          'document_type_name',
          'نوع سند',
          formatter: (item) => (item as Map<String, dynamic>)['document_type_name']?.toString() ?? '',
        ),
        TextColumn(
          'document_code',
          'شماره سند',
          formatter: (item) => (item as Map<String, dynamic>)['document_code']?.toString() ?? '',
        ),
        TextColumn(
          'description',
          'شرح',
          formatter: (item) => (item as Map<String, dynamic>)['description']?.toString() ?? '',
        ),
        TextColumn(
          'debit_account',
          t.debitAccount,
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            return _formatAccount(m['debit_account_code'], m['debit_account_name']);
          },
        ),
        NumberColumn(
          'debit_amount',
          'مبلغ بدهکار',
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['debit_amount']),
        ),
        TextColumn(
          'credit_account',
          t.creditAccount,
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            return _formatAccount(m['credit_account_code'], m['credit_account_name']);
          },
        ),
        NumberColumn(
          'credit_amount',
          'مبلغ بستانکار',
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['credit_amount']),
        ),
        TextColumn(
          'person_name',
          'طرف حساب',
          formatter: (item) => (item as Map<String, dynamic>)['person_name']?.toString() ?? '',
        ),
      ],
      searchFields: const ['document_code', 'description', 'debit_account_name', 'credit_account_name', 'person_name'],
      defaultPageSize: 50,
      additionalParams: _additionalParams(),
      showExportButtons: true,
      excelEndpoint: '/api/v1/businesses/${widget.businessId}/reports/journal-ledger/export/excel',
      getExportParams: () => _additionalParams(),
      footerTotals: {
        'debit_amount': 'جمع بدهکار',
        'credit_amount': 'جمع بستانکار',
      },
      defaultSortBy: 'document_date',
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
        title: Text(t.reportsJournalLedgerTitle),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
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
                      
                      // Document Type
                      SizedBox(
                        width: 200,
                        child: DropdownButtonFormField<String>(
                          value: _selectedDocumentType,
                          decoration: InputDecoration(
                            labelText: 'نوع سند',
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('همه انواع'),
                            ),
                            ..._documentTypes.entries.map((entry) {
                              return DropdownMenuItem<String>(
                                value: entry.key,
                                child: Text(entry.value),
                              );
                            }),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedDocumentType = value;
                            });
                            _refreshData();
                          },
                        ),
                      ),
                      
                      // Include Proforma
                      SizedBox(
                        width: 200,
                        child: CheckboxListTile(
                          title: const Text('شامل اسناد پیش‌نویس'),
                          value: _includeProforma,
                          onChanged: (value) {
                            setState(() {
                              _includeProforma = value ?? false;
                            });
                            _refreshData();
                          },
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Balance Validation Warning
          if (_summary != null && _summary!['balance_valid'] == false)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Card(
                color: cs.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: cs.onErrorContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'تراز برقرار نیست: تفاوت = ${_formatNumber(_summary!['balance_diff'])}',
                          style: TextStyle(
                            color: cs.onErrorContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          
          // Summary Cards
          if (_summary != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'جمع بدهکار',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatNumber(_summary!['total_debit']),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'جمع بستانکار',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatNumber(_summary!['total_credit']),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Card(
                      color: _summary!['balance_valid'] == true 
                          ? cs.primaryContainer 
                          : cs.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'وضعیت تراز',
                              style: TextStyle(
                                fontSize: 12,
                                color: (_summary!['balance_valid'] == true 
                                    ? cs.onPrimaryContainer 
                                    : cs.onErrorContainer).withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _summary!['balance_valid'] == true ? 'برقرار' : 'برقرار نیست',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _summary!['balance_valid'] == true 
                                    ? cs.onPrimaryContainer 
                                    : cs.onErrorContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          // Data Table
          Expanded(
            child: DataTableWidget<Map<String, dynamic>>(
              key: ValueKey(
                'journal_ledger_${_selectedFiscalYearId}_${_selectedCurrencyId}_${_selectedDocumentType}_${_includeProforma}_${_fromDate?.toIso8601String()}_${_toDate?.toIso8601String()}',
              ),
              config: _buildTableConfig(t),
              fromJson: (json) => Map<String, dynamic>.from(json),
              calendarController: widget.calendarController,
              onRefresh: _fetchSummary,
            ),
          ),
        ],
      ),
    );
  }
}

