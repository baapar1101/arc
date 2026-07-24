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
import 'package:hesabix_ui/widgets/project/project_selector_widget.dart';
import 'package:hesabix_ui/services/list_filter_preferences_service.dart';
import 'package:hesabix_ui/widgets/reports/trial_balance_tree_view.dart';
import 'package:hesabix_ui/utils/financial_report_navigation.dart';
import 'package:hesabix_ui/utils/responsive_helper.dart';
import '../../utils/error_extractor.dart';

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
  int? _selectedProjectId;
  int _columnMode = 8;
  String _displayMode = 'flat';
  int _accountLevel = 4;
  
  // Data
  List<Map<String, dynamic>> _fiscalYears = [];
  List<Map<String, dynamic>> _currencies = [];
  List<Map<String, dynamic>> _treeAccounts = [];
  Map<String, dynamic>? _treeSummary;
  bool _treeLoading = false;
  String? _treeError;
  
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
    // مقادیر عددی از seed قدیمی چارت حساب
    const numericTypeMap = {
      '0': 'accounting_document',
      '1': 'cash_register',
      '2': 'petty_cash',
      '3': 'bank',
      '4': 'check',
    };
    final normalized = numericTypeMap[value] ?? value;
    if (ln.startsWith('fa')) {
      switch (normalized) {
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
    switch (normalized) {
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
    if (_displayMode == 'tree') {
      _fetchTreeData();
    } else if (mounted) {
      setState(() {});
    }
  }

  FinancialReportLedgerContext get _ledgerContext => FinancialReportLedgerContext(
        fiscalYearId: _selectedFiscalYearId,
        dateFrom: _fromDate,
        dateTo: _toDate,
        currencyId: _selectedCurrencyId,
        projectId: _selectedProjectId,
      );

  void _openGeneralLedger(Map<String, dynamic> row) {
    context.push(
      buildGeneralLedgerRoute(
        businessId: widget.businessId,
        accountRow: row,
        context: _ledgerContext,
      ),
    );
  }

  Future<void> _fetchTreeData() async {
    setState(() {
      _treeLoading = true;
      _treeError = null;
    });
    try {
      final res = await ApiClient().post<Map<String, dynamic>>(
        '/api/v1/businesses/${widget.businessId}/reports/trial-balance',
        data: {
          ..._additionalParams(),
          'take': 500,
          'skip': 0,
        },
      );
      final body = res.data;
      if (body is Map<String, dynamic> && body['data'] is Map<String, dynamic>) {
        final data = body['data'] as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          _treeAccounts = List<Map<String, dynamic>>.from(data['accounts'] ?? []);
          _treeSummary = data['summary'] is Map ? Map<String, dynamic>.from(data['summary'] as Map) : null;
          _treeLoading = false;
        });
      } else if (mounted) {
        setState(() => _treeLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _treeError = ErrorExtractor.forContext(e, context);
        _treeLoading = false;
      });
    }
  }

  Map<String, dynamic> _additionalParams() {
    return {
      if (_fromDate != null) 'date_from': _fromDate!.toIso8601String().split('T').first,
      if (_toDate != null) 'date_to': _toDate!.toIso8601String().split('T').first,
      if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
      if (_selectedCurrencyId != null) 'currency_id': _selectedCurrencyId,
      if (_selectedAccountType != null) 'account_type': _selectedAccountType,
      if (_selectedProjectId != null) 'project_id': _selectedProjectId,
      'include_zero_balance': _includeZeroBalance,
      'column_mode': _columnMode,
      'display_mode': _displayMode,
      'account_level': _accountLevel,
    };
  }

  List<DataTableColumn> _buildColumns(AppLocalizations t) {
    final cols = <DataTableColumn>[
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
    ];

    if (_columnMode >= 6) {
      cols.addAll([
        NumberColumn('opening_debit', 'مانده ابتدای دوره (بدهکار)', formatter: (item) => _formatNumber((item as Map<String, dynamic>)['opening_debit'])),
        NumberColumn('opening_credit', 'مانده ابتدای دوره (بستانکار)', formatter: (item) => _formatNumber((item as Map<String, dynamic>)['opening_credit'])),
      ]);
    }
    if (_columnMode >= 4) {
      cols.addAll([
        NumberColumn('period_debit', 'جمع بدهکار دوره', formatter: (item) => _formatNumber((item as Map<String, dynamic>)['period_debit'])),
        NumberColumn('period_credit', 'جمع بستانکار دوره', formatter: (item) => _formatNumber((item as Map<String, dynamic>)['period_credit'])),
      ]);
    }
    cols.addAll([
      NumberColumn('closing_debit', 'مانده انتهای دوره (بدهکار)', formatter: (item) => _formatNumber((item as Map<String, dynamic>)['closing_debit'])),
      NumberColumn('closing_credit', 'مانده انتهای دوره (بستانکار)', formatter: (item) => _formatNumber((item as Map<String, dynamic>)['closing_credit'])),
    ]);
    return cols;
  }

  Map<String, String> _buildFooterTotals() {
    final totals = <String, String>{};
    if (_columnMode >= 6) {
      totals['opening_debit'] = 'جمع مانده ابتدای دوره (بدهکار)';
      totals['opening_credit'] = 'جمع مانده ابتدای دوره (بستانکار)';
    }
    if (_columnMode >= 4) {
      totals['period_debit'] = 'جمع بدهکار دوره';
      totals['period_credit'] = 'جمع بستانکار دوره';
    }
    totals['closing_debit'] = 'جمع مانده انتهای دوره (بدهکار)';
    totals['closing_credit'] = 'جمع مانده انتهای دوره (بستانکار)';
    return totals;
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      );

  String _currencyShortLabel(Map<String, dynamic> currency) {
    final code = (currency['code'] ?? '').toString().trim();
    final name = (currency['name'] ?? '').toString().trim();
    if (code.isNotEmpty) return code;
    return name;
  }

  String _currencyFullLabel(Map<String, dynamic> currency) {
    final code = (currency['code'] ?? '').toString().trim();
    final name = (currency['name'] ?? '').toString().trim();
    if (code.isNotEmpty && name.isNotEmpty) return '$code — $name';
    return code.isNotEmpty ? code : name;
  }

  Widget _filterField({required double width, required Widget child}) {
    return SizedBox(width: width, child: child);
  }

  Widget _buildFiltersPanel(BuildContext context, {required double fieldWidth}) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: EdgeInsets.all(ResponsiveHelper.isMobile(context) ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'فیلترها',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _filterField(
                  width: fieldWidth,
                  child: DropdownButtonFormField<int>(
                    value: _selectedFiscalYearId,
                    isExpanded: true,
                    decoration: _decoration('سال مالی'),
                    items: _fiscalYears
                        .map(
                          (fy) => DropdownMenuItem<int>(
                            value: fy['id'] as int?,
                            child: Text(
                              fy['title']?.toString() ?? '',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() => _selectedFiscalYearId = value);
                      _refreshData();
                    },
                  ),
                ),
                _filterField(
                  width: fieldWidth,
                  child: DateInputField(
                    value: _fromDate,
                    calendarController: widget.calendarController,
                    labelText: 'از تاریخ',
                    isDense: true,
                    onChanged: (date) {
                      setState(() => _fromDate = date);
                      _refreshData();
                    },
                  ),
                ),
                _filterField(
                  width: fieldWidth,
                  child: DateInputField(
                    value: _toDate,
                    calendarController: widget.calendarController,
                    labelText: 'تا تاریخ',
                    isDense: true,
                    onChanged: (date) {
                      setState(() => _toDate = date);
                      _refreshData();
                    },
                  ),
                ),
                _filterField(
                  width: fieldWidth,
                  child: DropdownButtonFormField<int>(
                    value: _selectedCurrencyId,
                    isExpanded: true,
                    decoration: _decoration('ارز'),
                    selectedItemBuilder: (context) => [
                      const Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text('همه ارزها', overflow: TextOverflow.ellipsis, maxLines: 1),
                      ),
                      ..._currencies.map(
                        (c) => Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            _currencyShortLabel(c),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ],
                    items: [
                      const DropdownMenuItem<int>(
                        value: null,
                        child: Text('همه ارزها', overflow: TextOverflow.ellipsis, maxLines: 1),
                      ),
                      ..._currencies.map((c) {
                        final id = c['id'] as int?;
                        return DropdownMenuItem<int>(
                          key: ValueKey('currency_$id'),
                          value: id,
                          child: Text(
                            _currencyFullLabel(c),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedCurrencyId = val);
                      _refreshData();
                    },
                  ),
                ),
                _filterField(
                  width: fieldWidth,
                  child: DropdownButtonFormField<String>(
                    value: _selectedAccountType,
                    isExpanded: true,
                    decoration: _decoration('نوع حساب'),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('همه انواع', overflow: TextOverflow.ellipsis, maxLines: 1),
                      ),
                      ..._accountTypes.map((type) {
                        final loc = AppLocalizations.of(context);
                        return DropdownMenuItem<String>(
                          value: type,
                          child: Text(
                            _localizedAccountType(loc, type),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        );
                      }),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedAccountType = value);
                      _refreshData();
                    },
                  ),
                ),
                _filterField(
                  width: fieldWidth,
                  child: ProjectSelectorWidget(
                    businessId: widget.businessId,
                    apiClient: ApiClient(),
                    selectedProjectId: _selectedProjectId,
                    isDense: true,
                    onChanged: (val) {
                      setState(() => _selectedProjectId = val);
                      _refreshData();
                    },
                  ),
                ),
                _filterField(
                  width: fieldWidth,
                  child: DropdownButtonFormField<int>(
                    value: _columnMode,
                    isExpanded: true,
                    decoration: _decoration('تعداد ستون'),
                    items: const [
                      DropdownMenuItem(value: 2, child: Text('۲ ستونی')),
                      DropdownMenuItem(value: 4, child: Text('۴ ستونی')),
                      DropdownMenuItem(value: 6, child: Text('۶ ستونی')),
                      DropdownMenuItem(value: 8, child: Text('۸ ستونی')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _columnMode = value);
                      _refreshData();
                    },
                  ),
                ),
                _filterField(
                  width: fieldWidth,
                  child: DropdownButtonFormField<String>(
                    value: _displayMode,
                    isExpanded: true,
                    decoration: _decoration('نحوه نمایش'),
                    items: const [
                      DropdownMenuItem(value: 'flat', child: Text('لیست تخت')),
                      DropdownMenuItem(value: 'tree', child: Text('درختی')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _displayMode = value);
                      if (value == 'tree') {
                        _fetchTreeData();
                      } else {
                        setState(() {});
                      }
                    },
                  ),
                ),
                _filterField(
                  width: fieldWidth,
                  child: DropdownButtonFormField<int>(
                    value: _accountLevel,
                    isExpanded: true,
                    decoration: _decoration('سطح حساب'),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('گروه')),
                      DropdownMenuItem(value: 2, child: Text('کل')),
                      DropdownMenuItem(value: 3, child: Text('معین')),
                      DropdownMenuItem(value: 4, child: Text('تفصیل')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _accountLevel = value);
                      _refreshData();
                    },
                  ),
                ),
                FilterChip(
                  label: const Text('مانده صفر'),
                  selected: _includeZeroBalance,
                  onSelected: (selected) {
                    setState(() => _includeZeroBalance = selected);
                    _refreshData();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTreeContent() {
    if (_treeLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_treeError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text(_treeError!)),
      );
    }
    return TrialBalanceTreeView(
      businessId: widget.businessId,
      accounts: _treeAccounts,
      columnMode: _columnMode,
      ledgerContext: _ledgerContext,
      summary: _treeSummary,
    );
  }

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/businesses/${widget.businessId}/reports/trial-balance',
      businessId: widget.businessId,
      persistTableFiltersPageId: ListFilterPageIds.trialBalanceReportTable,
      reportModuleKey: 'trial_balance',
      reportSubtype: 'list',
      title: t.reportsTrialBalanceTitle,
      showRowNumbers: true,
      columns: _buildColumns(t),
      searchFields: const ['account_code', 'account_name'],
      defaultPageSize: 50,
      additionalParams: _additionalParams(),
      showExportButtons: true,
      excelEndpoint: '/api/v1/businesses/${widget.businessId}/reports/trial-balance/export/excel',
      pdfEndpoint: '/api/v1/businesses/${widget.businessId}/reports/trial-balance/export/pdf',
      getExportParams: () => _additionalParams(),
      footerTotals: _buildFooterTotals(),
      onRowTap: (item) => _openGeneralLedger(Map<String, dynamic>.from(item as Map)),
      defaultSortBy: 'account_code',
      defaultSortDesc: false,
      expandBodyHeightToFitRows: true,
      deferVerticalScrollToParent: true,
      margin: EdgeInsets.zero,
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.reportsTrialBalanceTitle, style: const TextStyle(fontSize: 18)),
            Text(
              'برای مشاهده دفتر کل روی هر سطر کلیک کنید',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.65),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t.refresh,
            onPressed: _refreshData,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = ResponsiveHelper.isMobile(context);
          final pagePadding = ResponsiveHelper.getPadding(context);
          final fieldWidth = isMobile ? (constraints.maxWidth - pagePadding * 2) : 220.0;

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.fromLTRB(pagePadding, pagePadding, pagePadding, pagePadding + 24),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildFiltersPanel(context, fieldWidth: fieldWidth),
                      const SizedBox(height: 16),
                      if (_displayMode == 'tree')
                        _buildTreeContent()
                      else
                        DataTableWidget<Map<String, dynamic>>(
                          key: ValueKey(
                            'trial_balance_${_selectedFiscalYearId}_${_selectedCurrencyId}_${_selectedAccountType}_${_includeZeroBalance}_${_columnMode}_${_displayMode}_${_accountLevel}_${_selectedProjectId}_${_fromDate?.toIso8601String()}_${_toDate?.toIso8601String()}',
                          ),
                          config: _buildTableConfig(t),
                          fromJson: (json) => Map<String, dynamic>.from(json),
                          calendarController: widget.calendarController,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

