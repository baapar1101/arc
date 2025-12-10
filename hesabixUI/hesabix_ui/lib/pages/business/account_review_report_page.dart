import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/data_table_utils.dart';
import 'package:hesabix_ui/core/date_utils.dart';import '../../utils/snackbar_helper.dart';

import 'package:hesabix_ui/utils/web/web_utils.dart' as web_utils;

class AccountReviewReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  
  const AccountReviewReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<AccountReviewReportPage> createState() => _AccountReviewReportPageState();
}

class _AccountReviewReportPageState extends State<AccountReviewReportPage> {
  // Filters
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedFiscalYearId;
  int? _selectedCurrencyId;
  String? _selectedAccountType;
  bool _includeZeroBalance = false;
  int? _selectedAccountId;  // برای نمایش جزئیات حساب انتخاب شده
  
  // Data
  List<Map<String, dynamic>> _fiscalYears = [];
  List<Map<String, dynamic>> _currencies = [];
  
  // Report data
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _accountDetails = [];
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _pagination;  // اطلاعات pagination برای جزئیات حساب
  Map<String, bool> _expandedAccounts = {};  // {account_id.toString(): isExpanded}
  bool _loading = false;
  String? _error;
  bool _filtersLoaded = false;  // برای جلوگیری از درخواست قبل از لود شدن فیلترها
  
  // Account types
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
    // Don't fetch data immediately - wait for filters to be loaded
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
      // Check if both filters are loaded
      if (!mounted) return;
      _checkFiltersLoaded();
    } catch (_) {
      // ignore errors
      if (!mounted) return;
      _checkFiltersLoaded();
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
      // Check if both filters are loaded
      if (!mounted) return;
      _checkFiltersLoaded();
    } catch (_) {
      // ignore errors
      if (!mounted) return;
      _checkFiltersLoaded();
    }
  }

  void _checkFiltersLoaded() {
    // فقط یک بار بعد از لود شدن هر دو فیلتر، داده را دریافت کن
    if (!_filtersLoaded && _fiscalYears.isNotEmpty && _currencies.isNotEmpty) {
      _filtersLoaded = true;
      _fetchData();
    }
  }

  Future<void> _fetchData({bool fetchDetails = false, int? page}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ApiClient();
      final requestData = <String, dynamic>{
        if (_fromDate != null) 'date_from': _fromDate!.toIso8601String().split('T').first,
        if (_toDate != null) 'date_to': _toDate!.toIso8601String().split('T').first,
        if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
        if (_selectedCurrencyId != null) 'currency_id': _selectedCurrencyId,
        if (_selectedAccountType != null) 'account_type': _selectedAccountType,
        'include_zero_balance': _includeZeroBalance,
        if (fetchDetails && _selectedAccountId != null) 'account_id': _selectedAccountId,
        if (fetchDetails && page != null) 'skip': (page - 1) * 50,
        if (fetchDetails) 'take': 50,
      };
      
      final res = await api.post<Map<String, dynamic>>(
        '/api/v1/businesses/${widget.businessId}/reports/accounts-review',
        data: requestData,
      );
      
      final body = res.data;
      if (body is Map<String, dynamic> && body['data'] is Map<String, dynamic>) {
        final data = body['data'] as Map<String, dynamic>;
        
        if (mounted) {
          // Parse accounts recursively to ensure proper type conversion
          List<Map<String, dynamic>> parseAccounts(dynamic accountsData) {
            if (accountsData == null) return [];
            if (accountsData is! List) return [];
            
            return accountsData.map((account) {
              if (account is! Map<String, dynamic>) return null;
              
              final accountMap = Map<String, dynamic>.from(account);
              
              // Parse children recursively
              if (accountMap['children'] != null) {
                accountMap['children'] = parseAccounts(accountMap['children']);
              } else {
                accountMap['children'] = [];
              }
              
              return accountMap;
            }).whereType<Map<String, dynamic>>().toList();
          }
          
          setState(() {
            _accounts = parseAccounts(data['accounts']);
            _accountDetails = List<Map<String, dynamic>>.from(data['account_details'] ?? []);
            _summary = data['summary'] is Map ? Map<String, dynamic>.from(data['summary']) : null;
            _pagination = data['pagination'] is Map ? Map<String, dynamic>.from(data['pagination']) : null;
            _loading = false;
          });
          
          // Debug: Log accounts count
          if (_accounts.isEmpty) {
            debugPrint('AccountReview: No accounts returned. Check backend logs.');
          } else {
            debugPrint('AccountReview: ${_accounts.length} root accounts loaded.');
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Invalid response format';
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  void _refreshData() {
    _fetchData(fetchDetails: _selectedAccountId != null);
  }

  Future<void> _exportExcel() async {
    setState(() => _loading = true);
    try {
      final api = ApiClient();
      final requestData = <String, dynamic>{
        if (_fromDate != null) 'date_from': _fromDate!.toIso8601String().split('T').first,
        if (_toDate != null) 'date_to': _toDate!.toIso8601String().split('T').first,
        if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
        if (_selectedCurrencyId != null) 'currency_id': _selectedCurrencyId,
        if (_selectedAccountType != null) 'account_type': _selectedAccountType,
        'include_zero_balance': _includeZeroBalance,
      };

      final bytes = await api.post<List<int>>(
        '/api/v1/businesses/${widget.businessId}/reports/accounts-review/export/excel',
        data: requestData,
        responseType: ResponseType.bytes,
        options: Options(
          headers: {'Accept': 'application/octet-stream'},
        ),
      );
      final data = bytes.data ?? <int>[];
      if (kIsWeb) {
        await web_utils.saveBytesAsFileWeb(
          data,
          'accounts_review_${widget.businessId}.xlsx',
          mimeType: 'application/octet-stream',
        );
      } else {
        if (mounted) {
          SnackBarHelper.show(context, message: 'Export only available on web');
        }
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'Export error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportPdf() async {
    setState(() => _loading = true);
    try {
      final api = ApiClient();
      final requestData = <String, dynamic>{
        if (_fromDate != null) 'date_from': _fromDate!.toIso8601String().split('T').first,
        if (_toDate != null) 'date_to': _toDate!.toIso8601String().split('T').first,
        if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
        if (_selectedCurrencyId != null) 'currency_id': _selectedCurrencyId,
        if (_selectedAccountType != null) 'account_type': _selectedAccountType,
        'include_zero_balance': _includeZeroBalance,
      };

      final bytes = await api.post<List<int>>(
        '/api/v1/businesses/${widget.businessId}/reports/accounts-review/export/pdf',
        data: requestData,
        responseType: ResponseType.bytes,
        options: Options(
          headers: {'Accept': 'application/pdf'},
        ),
      );
      final data = bytes.data ?? <int>[];
      if (kIsWeb) {
        await web_utils.saveBytesAsFileWeb(
          data,
          'accounts_review_${widget.businessId}.pdf',
          mimeType: 'application/pdf',
        );
      } else {
        if (mounted) {
          SnackBarHelper.show(context, message: 'Export only available on web');
        }
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'Export error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleExpand(String accountIdKey) {
    setState(() {
      _expandedAccounts[accountIdKey] = !(_expandedAccounts[accountIdKey] ?? false);
    });
  }

  void _selectAccount(int? accountId) {
    setState(() {
      _selectedAccountId = accountId;
    });
    _fetchData(fetchDetails: true, page: 1);
  }

  Widget _buildAccountTree(List<Map<String, dynamic>> accounts, int level) {
    if (accounts.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      children: accounts.map((account) {
        final accountId = account['account_id'];
        if (accountId == null) return const SizedBox.shrink();
        
        final accountIdInt = accountId is int ? accountId : (accountId is num ? accountId.toInt() : null);
        if (accountIdInt == null) return const SizedBox.shrink();
        
        final accountIdKey = accountIdInt.toString();
        final childrenData = account['children'];
        final children = childrenData is List 
            ? List<Map<String, dynamic>>.from(
                childrenData.map((c) => c is Map ? Map<String, dynamic>.from(c) : <String, dynamic>{})
                    .whereType<Map<String, dynamic>>()
              )
            : <Map<String, dynamic>>[];
        final hasChildren = account['has_children'] == true || children.isNotEmpty;
        final isExpanded = _expandedAccounts[accountIdKey] ?? false;
        final isSelected = _selectedAccountId == accountIdInt;
        
        return Column(
          children: [
            InkWell(
              onTap: () {
                _toggleExpand(accountIdKey);
                if (!hasChildren) {
                  _selectAccount(accountIdInt);
                }
              },
              child: Container(
                padding: EdgeInsets.only(
                  right: level * 24.0,
                  left: 0,
                  top: 8,
                  bottom: 8,
                ),
                color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3) : null,
                child: IntrinsicWidth(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: hasChildren
                            ? IconButton(
                                padding: EdgeInsets.zero,
                                iconSize: 20,
                                onPressed: () => _toggleExpand(accountIdKey),
                                icon: Icon(isExpanded ? Icons.expand_more : Icons.chevron_right),
                              )
                            : const SizedBox.shrink(),
                      ),
                      SizedBox(
                        width: 100,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            account['account_code']?.toString() ?? '',
                            style: const TextStyle(fontFeatures: []),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 200,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            account['account_name']?.toString() ?? '',
                            style: TextStyle(
                              fontWeight: hasChildren ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            _localizedAccountType(AppLocalizations.of(context), account['account_type']?.toString()),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            _formatNumber(account['opening_debit']),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            _formatNumber(account['opening_credit']),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            _formatNumber(account['period_debit']),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            _formatNumber(account['period_credit']),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            _formatNumber(account['closing_debit']),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            _formatNumber(account['closing_credit']),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: !hasChildren
                            ? IconButton(
                                icon: const Icon(Icons.visibility, size: 20),
                                onPressed: () => _selectAccount(accountIdInt),
                                tooltip: 'مشاهده جزئیات',
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (hasChildren && isExpanded && children.isNotEmpty)
              _buildAccountTree(
                children,
                level + 1,
              ),
          ],
        );
      }).toList(),
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
        title: const Text('گزارش مرور حساب‌ها'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.download),
            tooltip: t.export,
            onSelected: (value) {
              if (value == 'excel') {
                _exportExcel();
              } else if (value == 'pdf') {
                _exportPdf();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'excel',
                child: Row(
                  children: [
                    Icon(Icons.table_chart, color: Colors.green[600]),
                    const SizedBox(width: 8),
                    Text(t.exportToExcel),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'pdf',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf, color: Colors.red[600]),
                    const SizedBox(width: 8),
                    Text(t.exportToPdf),
                  ],
                ),
              ),
            ],
          ),
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
                          title: const Text('شامل حساب‌های با مانده صفر'),
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
                          _summary!['balance_error']?.toString() ?? 'تراز حساب‌ها برقرار نیست',
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
                      margin: const EdgeInsets.only(right: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'جمع مانده ابتدای دوره (بدهکار)',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatNumber(_summary!['total_opening_debit']),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'جمع مانده ابتدای دوره (بستانکار)',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatNumber(_summary!['total_opening_credit']),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'جمع بدهکار دوره',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatNumber(_summary!['total_period_debit']),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'جمع بستانکار دوره',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatNumber(_summary!['total_period_credit']),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'جمع مانده انتهای دوره (بدهکار)',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatNumber(_summary!['total_closing_debit']),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Card(
                      margin: const EdgeInsets.only(left: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'جمع مانده انتهای دوره (بستانکار)',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatNumber(_summary!['total_closing_credit']),
                              style: const TextStyle(
                                fontSize: 16,
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
          
          // Main Content
          Expanded(
            child: Row(
              children: [
                // Account Tree
                Expanded(
                  flex: 3,
                  child: Card(
                    margin: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Header
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          color: cs.surfaceContainerHighest,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: IntrinsicWidth(
                              child: Row(
                                children: [
                                  const SizedBox(width: 28), // expander space
                                  SizedBox(
                                    width: 100,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Text('کد', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 200,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Text('نام', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 120,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Text('نوع', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 140,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Text('ابتدای دوره (بدهکار)', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 140,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Text('ابتدای دوره (بستانکار)', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 120,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Text('بدهکار دوره', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 120,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Text('بستانکار دوره', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 140,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Text('انتهای دوره (بدهکار)', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 140,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Text('انتهای دوره (بستانکار)', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                    ),
                                  ),
                                  const SizedBox(width: 40), // action space
                                ],
                              ),
                            ),
                          ),
                        ),
                        
                        // Account Tree
                        Expanded(
                          child: _loading
                              ? const Center(child: CircularProgressIndicator())
                              : _error != null
                                  ? Center(child: Text('خطا: $_error', style: TextStyle(color: cs.error)))
                                  : _accounts.isEmpty
                                      ? const Center(child: Text('هیچ حسابی یافت نشد'))
                                      : SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: SingleChildScrollView(
                                            child: _buildAccountTree(_accounts, 0),
                                          ),
                                        ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // Account Details (if selected)
                if (_selectedAccountId != null)
                  Expanded(
                    flex: 2,
                    child: Card(
                      margin: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // Header
                          Container(
                            padding: const EdgeInsets.all(12),
                            color: cs.primaryContainer,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'جزئیات تراکنش‌های حساب انتخاب شده',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: cs.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    setState(() {
                                      _selectedAccountId = null;
                                      _accountDetails = [];
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          
                          // Details Table
                          Expanded(
                            child: _accountDetails.isEmpty
                                ? const Center(child: Text('هیچ تراکنشی یافت نشد'))
                                : Column(
                                    children: [
                                      Expanded(
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: SingleChildScrollView(
                                            child: DataTable(
                                              columnSpacing: 16,
                                              columns: const [
                                                DataColumn(label: Text('تاریخ')),
                                                DataColumn(label: Text('نوع سند')),
                                                DataColumn(label: Text('شماره سند')),
                                                DataColumn(label: Text('شرح')),
                                                DataColumn(label: Text('طرف حساب')),
                                                DataColumn(label: Text('بدهکار', textAlign: TextAlign.center)),
                                                DataColumn(label: Text('بستانکار', textAlign: TextAlign.center)),
                                                DataColumn(label: Text('مانده', textAlign: TextAlign.center)),
                                              ],
                                              rows: _accountDetails.map((detail) {
                                                return DataRow(
                                                  cells: [
                                                    DataCell(Text(
                                                      HesabixDateUtils.formatForDisplay(
                                                        DateTime.tryParse(detail['document_date']?.toString() ?? ''),
                                                        widget.calendarController.isJalali,
                                                      ),
                                                    )),
                                                    DataCell(Text(detail['document_type_name']?.toString() ?? '')),
                                                    DataCell(Text(detail['document_code']?.toString() ?? '')),
                                                    DataCell(Text(detail['description']?.toString() ?? '')),
                                                    DataCell(Text(detail['counterpart_name']?.toString() ?? '')),
                                                    DataCell(Text(_formatNumber(detail['debit']), textAlign: TextAlign.center)),
                                                    DataCell(Text(_formatNumber(detail['credit']), textAlign: TextAlign.center)),
                                                    DataCell(Text(
                                                      _formatNumber(detail['balance']),
                                                      textAlign: TextAlign.center,
                                                      style: TextStyle(
                                                        color: (detail['balance_type']?.toString() == 'debit')
                                                            ? Colors.blue
                                                            : (detail['balance_type']?.toString() == 'credit')
                                                                ? Colors.orange
                                                                : null,
                                                      ),
                                                    )),
                                                  ],
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Pagination Controls
                                      if (_pagination != null && (_pagination!['total'] as int? ?? 0) > 50)
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              top: BorderSide(color: cs.outline.withOpacity(0.2)),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.chevron_right),
                                                onPressed: (_pagination!['has_prev'] == true)
                                                    ? () {
                                                        final currentPage = _pagination!['page'] as int? ?? 1;
                                                        _fetchData(fetchDetails: true, page: currentPage - 1);
                                                      }
                                                    : null,
                                                tooltip: 'صفحه قبل',
                                              ),
                                              Text(
                                                'صفحه ${_pagination!['page']} از ${_pagination!['total_pages']}',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.chevron_left),
                                                onPressed: (_pagination!['has_next'] == true)
                                                    ? () {
                                                        final currentPage = _pagination!['page'] as int? ?? 1;
                                                        _fetchData(fetchDetails: true, page: currentPage + 1);
                                                      }
                                                    : null,
                                                tooltip: 'صفحه بعد',
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

