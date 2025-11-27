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
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/models/person_model.dart';

class PeopleTransactionsReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  
  const PeopleTransactionsReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<PeopleTransactionsReportPage> createState() => _PeopleTransactionsReportPageState();
}

class _PeopleTransactionsReportPageState extends State<PeopleTransactionsReportPage> {
  // Filters
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedFiscalYearId;
  int? _selectedCurrencyId;
  Person? _selectedPerson;
  String? _selectedDocumentType;
  
  // Fiscal years and currencies
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
    // با تغییر key در DataTableWidget، خودکار rebuild می‌شود و config جدید با additionalParams جدید استفاده می‌شود
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
      if (_selectedPerson != null) 'person_ids': [_selectedPerson!.id],
      if (_selectedDocumentType != null) 'document_type': _selectedDocumentType,
    };
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
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
      endpoint: '/api/v1/persons/businesses/${widget.businessId}/reports/people-transactions',
      businessId: widget.businessId,
      reportModuleKey: 'people_transactions',
      reportSubtype: 'list',
      title: t.reportsPeopleTransactionsTitle,
      showRowNumbers: true,
      columns: [
        DateColumn(
          'document_date',
          'تاریخ سند',
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            final date = m['document_date'] ?? m['document_date_raw'] ?? m['document_date_formatted'];
            return _formatDate(date);
          },
        ),
        TextColumn(
          'document_code',
          'کد سند',
          formatter: (item) => (item as Map<String, dynamic>)['document_code']?.toString() ?? '',
        ),
        TextColumn(
          'person_name',
          'نام شخص',
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            return m['person_name']?.toString() ?? 
                   m['display_name']?.toString() ?? 
                   m['alias_name']?.toString() ?? 
                   '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
          },
        ),
        TextColumn(
          'document_type_name',
          'نوع سند',
          formatter: (item) => (item as Map<String, dynamic>)['document_type_name']?.toString() ?? '',
        ),
        NumberColumn(
          'debit',
          'بدهکار',
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['debit']),
        ),
        NumberColumn(
          'credit',
          'بستانکار',
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['credit']),
        ),
        NumberColumn(
          'running_balance',
          'تراز متحرک',
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['running_balance']),
        ),
        TextColumn(
          'description',
          'توضیحات',
          formatter: (item) => (item as Map<String, dynamic>)['description']?.toString() ?? '',
        ),
      ],
      searchFields: const ['document_code', 'person_name', 'description'],
      defaultPageSize: 20,
      additionalParams: _additionalParams(),
      showExportButtons: true,
      excelEndpoint: '/api/v1/persons/businesses/${widget.businessId}/reports/people-transactions/export/excel',
      pdfEndpoint: '/api/v1/persons/businesses/${widget.businessId}/reports/people-transactions/export/pdf',
      getExportParams: () => _additionalParams(),
      footerTotals: {
        'debit': 'جمع بدهکار',
        'credit': 'جمع بستانکار',
      },
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
        title: Text(t.reportsPeopleTransactionsTitle),
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
                  
                  // Date Range
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
                  
                  // Currency
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<int>(
                      value: _selectedCurrencyId,
                      decoration: InputDecoration(
                        labelText: 'واحد پول',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      ),
                      items: _currencies.map((curr) {
                        final code = curr['code']?.toString() ?? '';
                        final name = curr['name']?.toString() ?? '';
                        final displayText = code.isNotEmpty ? '$code - $name' : name;
                        return DropdownMenuItem<int>(
                          value: curr['id'] as int?,
                          child: Text(
                            displayText,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedCurrencyId = value;
                        });
                        _refreshData();
                      },
                    ),
                  ),
                  
                  // Person - استفاده از PersonComboboxWidget
                  SizedBox(
                    width: 280,
                    child: PersonComboboxWidget(
                      businessId: widget.businessId,
                      selectedPerson: _selectedPerson,
                      onChanged: (person) {
                        setState(() {
                          _selectedPerson = person;
                        });
                        _refreshData();
                      },
                      label: 'شخص',
                      hintText: 'همه اشخاص',
                      searchHint: 'جست‌وجو در اشخاص...',
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
                      items: const [
                        DropdownMenuItem<String>(
                          value: null,
                          child: Text('همه'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'invoice_sales',
                          child: Text('فروش'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'invoice_sales_return',
                          child: Text('برگشت از فروش'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'invoice_purchase',
                          child: Text('خرید'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'invoice_purchase_return',
                          child: Text('برگشت از خرید'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'invoice_direct_consumption',
                          child: Text('مصرف مستقیم'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'invoice_production',
                          child: Text('تولید'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'invoice_waste',
                          child: Text('ضایعات'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'inventory_transfer',
                          child: Text('انتقال موجودی'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'production',
                          child: Text('تولید'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'opening_balance',
                          child: Text('موجودی اولیه'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'expense',
                          child: Text('هزینه'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'income',
                          child: Text('درآمد'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'receipt',
                          child: Text('دریافت'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'payment',
                          child: Text('پرداخت'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'transfer',
                          child: Text('انتقال'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'manual',
                          child: Text('سند دستی'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'invoice',
                          child: Text('فاکتور'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'check',
                          child: Text('چک'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedDocumentType = value;
                        });
                        _refreshData();
                      },
                    ),
                  ),
                ],
              ),
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
                _selectedPerson?.id,
                _selectedDocumentType,
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
    );
  }
}

