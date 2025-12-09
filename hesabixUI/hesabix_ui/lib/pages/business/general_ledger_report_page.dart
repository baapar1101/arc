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
import 'package:hesabix_ui/widgets/invoice/account_tree_combobox_widget.dart';
import 'package:hesabix_ui/models/account_model.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/widgets/reports/common_report_filters.dart';

class GeneralLedgerReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  
  const GeneralLedgerReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<GeneralLedgerReportPage> createState() => _GeneralLedgerReportPageState();
}

class _GeneralLedgerReportPageState extends State<GeneralLedgerReportPage> {
  // Filters
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedFiscalYearId;
  int? _selectedCurrencyId;
  int? _selectedProjectId;  // 🆕 فیلتر پروژه
  List<Account> _selectedAccounts = [];
  Account? _accountToAdd;
  Person? _selectedPerson;
  bool _includeProforma = false;
  
  // Data
  List<Map<String, dynamic>> _fiscalYears = [];
  List<Map<String, dynamic>> _currencies = [];
  
  // Summary from API response
  Map<String, dynamic>? _summary;

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

  Future<void> _fetchSummary() async {
    if (_selectedAccounts.isEmpty) return;
    
    try {
      final api = ApiClient();
      final requestData = <String, dynamic>{
        'take': 1,
        'skip': 0,
        ..._additionalParams(),
      };
      
      final res = await api.post<Map<String, dynamic>>(
        '/api/v1/businesses/${widget.businessId}/reports/general-ledger',
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

  void _addAccount(Account? account) {
    if (account == null) return;
    if (_selectedAccounts.any((a) => a.id == account.id)) return;
    setState(() {
      _selectedAccounts.add(account);
      _accountToAdd = null;
    });
    _refreshData();
  }

  void _removeAccount(Account account) {
    setState(() {
      _selectedAccounts.removeWhere((a) => a.id == account.id);
    });
    _refreshData();
  }

  Map<String, dynamic> _additionalParams() {
    return {
      if (_fromDate != null) 'date_from': _fromDate!.toIso8601String().split('T').first,
      if (_toDate != null) 'date_to': _toDate!.toIso8601String().split('T').first,
      if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
      if (_selectedCurrencyId != null) 'currency_id': _selectedCurrencyId,
      if (_selectedAccounts.isNotEmpty) 'account_ids': _selectedAccounts.map((a) => a.id).toList(),
      if (_selectedPerson != null) 'person_id': _selectedPerson!.id,
      if (_selectedProjectId != null) 'project_id': _selectedProjectId,  // 🆕 فیلتر پروژه
      'include_proforma': _includeProforma,
    };
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  String _formatBalance(dynamic balance, dynamic balanceType) {
    if (balance == null) return '0';
    final b = balance is num ? balance.toDouble() : double.tryParse(balance.toString()) ?? 0.0;
    final formatted = DataTableUtils.formatNumber(b.abs());
    final type = (balanceType?.toString() ?? '').toLowerCase();
    if (type == 'debit') {
      return '$formatted بدهکار';
    } else if (type == 'credit') {
      return '$formatted بستانکار';
    }
    return formatted;
  }

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/businesses/${widget.businessId}/reports/general-ledger',
      businessId: widget.businessId,
      reportModuleKey: 'general_ledger',
      reportSubtype: 'list',
      title: t.reportsGeneralLedgerTitle,
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
          'counterpart_name',
          'طرف حساب',
          formatter: (item) => (item as Map<String, dynamic>)['counterpart_name']?.toString() ?? '',
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
        TextColumn(
          'balance',
          'مانده',
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            final balance = m['balance'];
            final balanceType = m['balance_type'];
            return _formatBalance(balance, balanceType);
          },
        ),
      ],
      searchFields: const ['document_code', 'description', 'counterpart_name'],
      defaultPageSize: 50,
      additionalParams: _additionalParams(),
      showExportButtons: true,
      excelEndpoint: '/api/v1/businesses/${widget.businessId}/reports/general-ledger/export/excel',
      pdfEndpoint: '/api/v1/businesses/${widget.businessId}/reports/general-ledger/export/pdf',
      getExportParams: () => _additionalParams(),
      footerTotals: {
        'debit': 'جمع بدهکار',
        'credit': 'جمع بستانکار',
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
        title: Text(t.reportsGeneralLedgerTitle),
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
                      
                      // Person
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
                  
                  const SizedBox(height: 16),
                  
                  // 🆕 فیلتر پروژه
                  CommonReportFilters(
                    businessId: widget.businessId,
                    apiClient: ApiClient(),
                    calendarController: widget.calendarController,
                    fromDate: _fromDate,
                    toDate: _toDate,
                    onFromDateChanged: (date) {
                      setState(() => _fromDate = date);
                      _refreshData();
                    },
                    onToDateChanged: (date) {
                      setState(() => _toDate = date);
                      _refreshData();
                    },
                    onClearDates: () {
                      setState(() {
                        _fromDate = null;
                        _toDate = null;
                      });
                      _refreshData();
                    },
                    selectedFiscalYearId: _selectedFiscalYearId,
                    fiscalYears: _fiscalYears,
                    onFiscalYearChanged: (fyId) {
                      setState(() => _selectedFiscalYearId = fyId);
                      _refreshData();
                    },
                    selectedProjectId: _selectedProjectId,
                    onProjectChanged: (projectId) {
                      setState(() => _selectedProjectId = projectId);
                      _refreshData();
                    },
                    showDateFilters: false,  // فیلترهای تاریخ بالاتر هستند
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Account Selection
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 280,
                        child: AccountTreeComboboxWidget(
                          businessId: widget.businessId,
                          selectedAccount: _accountToAdd,
                          onChanged: _addAccount,
                          label: 'افزودن حساب',
                          hintText: 'انتخاب حساب',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (_selectedAccounts.isEmpty)
                              Text(
                                'هیچ حسابی انتخاب نشده است',
                                style: TextStyle(color: cs.error),
                              )
                            else
                              ..._selectedAccounts.map((account) {
                                return Chip(
                                  label: Text('${account.code} - ${account.name}'),
                                  onDeleted: () => _removeAccount(account),
                                  deleteIcon: const Icon(Icons.close, size: 18),
                                );
                              }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Summary Cards (if available)
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
                              'مانده ابتدای دوره',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatBalance(
                                _summary!['opening_balance'],
                                _summary!['opening_balance_type'],
                              ),
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
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'مانده انتهای دوره',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatBalance(
                                _summary!['closing_balance'],
                                _summary!['closing_balance_type'],
                              ),
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
                ],
              ),
            ),
          
          // Data Table
          Expanded(
            child: _selectedAccounts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.account_tree_outlined, size: 64, color: cs.onSurface.withOpacity(0.5)),
                        const SizedBox(height: 16),
                        Text(
                          'لطفاً حداقل یک حساب انتخاب کنید',
                          style: TextStyle(
                            fontSize: 16,
                            color: cs.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  )
                : DataTableWidget<Map<String, dynamic>>(
                    key: ValueKey(
                      'general_ledger_${_selectedAccounts.map((a) => a.id).join('_')}_${_selectedFiscalYearId}_${_selectedCurrencyId}_${_selectedPerson?.id}_${_includeProforma}_${_fromDate?.toIso8601String()}_${_toDate?.toIso8601String()}',
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

