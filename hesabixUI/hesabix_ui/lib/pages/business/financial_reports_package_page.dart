import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/project/project_selector_widget.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import 'package:hesabix_ui/widgets/reports/balance_sheet_report_shared.dart';
import 'package:hesabix_ui/widgets/reports/pnl_report_shared.dart';
import 'package:hesabix_ui/widgets/reports/trial_balance_tree_view.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/data_table_utils.dart';
import 'package:hesabix_ui/utils/financial_report_navigation.dart';
import 'package:hesabix_ui/utils/responsive_helper.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import 'package:hesabix_ui/services/bytes_export/bytes_export_service.dart';
import 'package:hesabix_ui/widgets/fx/fx_data_quality_banner.dart';
import 'package:hesabix_ui/widgets/fx/report_currency_filter_dropdown.dart';
import 'package:hesabix_ui/core/hesabix_back.dart';

/// بسته یکپارچه گزارش‌های مالی: تراز آزمایشی، ترازنامه و سود و زیان با فیلتر مشترک.
class FinancialReportsPackagePage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;

  const FinancialReportsPackagePage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<FinancialReportsPackagePage> createState() => _FinancialReportsPackagePageState();
}

class _FinancialReportsPackagePageState extends State<FinancialReportsPackagePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedFiscalYearId;
  int? _selectedCurrencyId;
  int? _selectedProjectId;
  bool _includeZeroBalance = false;
  bool _includeBaseEquivalent = true;
  int _accountLevel = 4;
  String? _compareMode;

  List<Map<String, dynamic>> _fiscalYears = [];
  List<Map<String, dynamic>> _currencies = [];

  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _fxDataQuality;

  // Trial balance
  List<Map<String, dynamic>> _trialBalanceAccounts = [];
  Map<String, dynamic>? _trialBalanceSummary;

  // Balance sheet
  List<Map<String, dynamic>> _balanceSheetLines = [];
  Map<String, dynamic>? _balanceSheetSummary;
  Map<String, dynamic>? _balanceSheetComparison;

  // P&L
  List<Map<String, dynamic>> _pnlStatementLines = [];
  Map<String, dynamic>? _pnlSummary;
  Map<String, dynamic>? _pnlComparison;

  bool _filtersReady = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _bootstrap();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_loadFiscalYears(), _loadCurrencies()]);
    if (!mounted) return;
    setState(() => _filtersReady = true);
    await _fetchAll();
  }

  Future<void> _loadFiscalYears() async {
    try {
      final items = await BusinessDashboardService(ApiClient()).listFiscalYears(widget.businessId);
      if (!mounted) return;
      setState(() {
        _fiscalYears = items;
        final current = items.firstWhere((e) => e['is_current'] == true, orElse: () => const <String, dynamic>{});
        final id = current['id'];
        if (id is int) _selectedFiscalYearId = id;
      });
    } catch (_) {}
  }

  Future<void> _loadCurrencies() async {
    try {
      final items = await CurrencyService(ApiClient()).listBusinessCurrencies(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _currencies = items;
        // پیش‌فرض: همه ارزها (= مبالغ پایه)
        _selectedCurrencyId = null;
      });
    } catch (_) {}
  }

  FinancialReportLedgerContext get _ledgerContext => FinancialReportLedgerContext(
        fiscalYearId: _selectedFiscalYearId,
        dateFrom: _fromDate,
        dateTo: _toDate,
        currencyId: _selectedCurrencyId,
        projectId: _selectedProjectId,
      );

  Map<String, dynamic> _sharedBody() => {
        if (_fromDate != null) 'date_from': _fromDate!.toIso8601String().split('T').first,
        if (_toDate != null) 'date_to': _toDate!.toIso8601String().split('T').first,
        if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
        if (_selectedCurrencyId != null) 'currency_id': _selectedCurrencyId,
        if (_selectedCurrencyId != null && _includeBaseEquivalent)
          'include_base_equivalent': true,
        if (_selectedProjectId != null) 'project_id': _selectedProjectId,
        'include_zero_balance': _includeZeroBalance,
        'account_level': _accountLevel,
        if (_compareMode != null) 'compare_mode': _compareMode,
        'compare_prior_period': _compareMode != null,
      };

  Future<void> _fetchAll() async {
    setState(() {
      _loading = true;
      _error = null;
      _fxDataQuality = null;
    });
    try {
      final api = ApiClient();
      final base = '/api/v1/businesses/${widget.businessId}/reports';
      final results = await Future.wait([
        api.post<Map<String, dynamic>>(
          '$base/trial-balance',
          data: {
            ..._sharedBody(),
            'display_mode': 'tree',
            'column_mode': 8,
            'take': 500,
            'skip': 0,
          },
        ),
        api.post<Map<String, dynamic>>('$base/balance-sheet', data: _sharedBody()),
        api.post<Map<String, dynamic>>('$base/pnl-period', data: _sharedBody()),
      ]);

      if (!mounted) return;
      setState(() {
        _applyTrialBalance(results[0].data);
        _applyBalanceSheet(results[1].data);
        _applyPnl(results[2].data);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  void _applyTrialBalance(Map<String, dynamic>? body) {
    if (body?['data'] is! Map) return;
    final data = body!['data'] as Map<String, dynamic>;
    _trialBalanceAccounts = List<Map<String, dynamic>>.from(data['accounts'] ?? []);
    _trialBalanceSummary = data['summary'] is Map ? Map<String, dynamic>.from(data['summary'] as Map) : null;
    final meta = data['meta'] is Map ? Map<String, dynamic>.from(data['meta'] as Map) : null;
    final fq = meta?['fx_data_quality'];
    if (fq is Map) {
      _fxDataQuality = Map<String, dynamic>.from(fq);
    }
  }

  void _applyBalanceSheet(Map<String, dynamic>? body) {
    if (body?['data'] is! Map) return;
    final data = body!['data'] as Map<String, dynamic>;
    _balanceSheetLines = List<Map<String, dynamic>>.from(data['statement_lines'] ?? []);
    _balanceSheetSummary = data['summary'] is Map ? Map<String, dynamic>.from(data['summary'] as Map) : null;
    _balanceSheetComparison = data['comparison'] is Map ? Map<String, dynamic>.from(data['comparison'] as Map) : null;
    final meta = data['meta'] is Map ? Map<String, dynamic>.from(data['meta'] as Map) : null;
    final fq = meta?['fx_data_quality'];
    if (fq is Map && _fxDataQuality == null) {
      _fxDataQuality = Map<String, dynamic>.from(fq);
    }
  }

  void _applyPnl(Map<String, dynamic>? body) {
    if (body?['data'] is! Map) return;
    final data = body!['data'] as Map<String, dynamic>;
    _pnlStatementLines = List<Map<String, dynamic>>.from(data['statement_lines'] ?? []);
    _pnlSummary = data['summary'] is Map ? Map<String, dynamic>.from(data['summary'] as Map) : null;
    _pnlComparison = data['comparison'] is Map ? Map<String, dynamic>.from(data['comparison'] as Map) : null;
  }

  void _openLedger(Map<String, dynamic> row) {
    context.push(
      buildGeneralLedgerRoute(
        businessId: widget.businessId,
        accountRow: row,
        context: _ledgerContext,
      ),
    );
  }

  Future<void> _exportCurrentTab(String type) async {
    setState(() => _exporting = true);
    final tab = _tabController.index;
    final endpoints = ['trial-balance', 'balance-sheet', 'pnl-period'];
    final names = ['trial_balance', 'balance_sheet', 'pnl_period'];
    try {
      final isPdf = type == 'pdf';
      final bytes = await ApiClient().post<List<int>>(
        '/api/v1/businesses/${widget.businessId}/reports/${endpoints[tab]}/export/$type',
        data: _sharedBody(),
        responseType: ResponseType.bytes,
        options: Options(headers: {'Accept': isPdf ? 'application/pdf' : 'application/octet-stream'}),
      );
      final result = await BytesExportService.export(
        bytes: bytes.data ?? <int>[],
        filename: '${names[tab]}_${widget.businessId}.${isPdf ? 'pdf' : 'xlsx'}',
        mimeType: isPdf ? 'application/pdf' : 'application/octet-stream',
      );
      if (mounted) BytesExportService.showFeedback(context, result);
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportPackage(String type) async {
    setState(() => _exporting = true);
    try {
      final isPdf = type == 'pdf';
      final bytes = await ApiClient().post<List<int>>(
        '/api/v1/businesses/${widget.businessId}/reports/financial-package/export/$type',
        data: {
          ..._sharedBody(),
          'column_mode': 8,
        },
        responseType: ResponseType.bytes,
        options: Options(headers: {'Accept': isPdf ? 'application/pdf' : 'application/octet-stream'}),
      );
      final result = await BytesExportService.export(
        bytes: bytes.data ?? <int>[],
        filename: 'financial_package_${widget.businessId}.${isPdf ? 'pdf' : 'xlsx'}',
        mimeType: isPdf ? 'application/pdf' : 'application/octet-stream',
      );
      if (mounted) BytesExportService.showFeedback(context, result);
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _onExportSelected(String value) {
    if (value == 'package_pdf') {
      _exportPackage('pdf');
    } else if (value == 'package_excel') {
      _exportPackage('excel');
    } else {
      _exportCurrentTab(value);
    }
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      );

  String _fmt(dynamic v) {
    if (v == null) return '0';
    final n = v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  Widget _overviewCards() {
    final isMobile = ResponsiveHelper.isMobile(context);
    final tb = _trialBalanceSummary;
    final bs = _balanceSheetSummary;
    final pnl = _pnlSummary;

    final cards = [
      ('تراز آزمایشی', tb?['balance_valid'] == true ? 'متوازن' : 'نامتوازن', Icons.check_circle_outline),
      ('جمع دارایی‌ها', _fmt(bs?['total_assets']), Icons.account_balance_wallet_outlined),
      ('جمع بدهی‌ها', _fmt(bs?['total_liabilities']), Icons.credit_card_outlined),
      ('سود خالص دوره', _fmt(pnl?['net_profit_after_tax'] ?? pnl?['net_profit_loss']), Icons.trending_up),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: cards.map((c) {
        return SizedBox(
          width: isMobile ? double.infinity : 200,
          child: Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(c.$3, size: 22, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.$1, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        Text(c.$2, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final isMobile = ResponsiveHelper.isMobile(context);
    final pagePadding = ResponsiveHelper.getPadding(context);
    final fieldWidth = isMobile ? double.infinity : 200.0;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.reportsFinancialPackageTitle, style: const TextStyle(fontSize: 18)),
            Text(
              t.reportsFinancialPackageSubtitle,
              style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.65), fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: _exporting
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onSurface))
                : const Icon(Icons.download_outlined),
            enabled: !_exporting && !_loading,
            onSelected: _onExportSelected,
            itemBuilder: (context) => [
              PopupMenuItem(value: 'package_pdf', child: Text(t.exportFinancialPackagePdf)),
              PopupMenuItem(value: 'package_excel', child: Text(t.exportFinancialPackageExcel)),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'excel', child: Text(t.exportToExcel)),
              PopupMenuItem(value: 'pdf', child: Text(t.exportToPdf)),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: (_loading || !_filtersReady) ? null : _fetchAll),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: t.reportsTrialBalanceTitle),
            Tab(text: t.reportsBalanceSheetTitle),
            Tab(text: t.reportsPnlPeriodTitle),
          ],
        ),
      ),
      body: !_filtersReady
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(pagePadding),
                  child: Material(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          SizedBox(
                            width: fieldWidth,
                            child: DropdownButtonFormField<int>(
                              value: _selectedFiscalYearId,
                              isExpanded: true,
                              decoration: _decoration('سال مالی'),
                              items: _fiscalYears
                                  .map((fy) => DropdownMenuItem<int>(value: fy['id'] as int?, child: Text(fy['title']?.toString() ?? '')))
                                  .toList(),
                              onChanged: (v) {
                                setState(() => _selectedFiscalYearId = v);
                                _fetchAll();
                              },
                            ),
                          ),
                          SizedBox(
                            width: fieldWidth,
                            child: DateInputField(
                              value: _fromDate,
                              calendarController: widget.calendarController,
                              labelText: 'از تاریخ',
                              onChanged: (v) {
                                setState(() => _fromDate = v);
                                _fetchAll();
                              },
                            ),
                          ),
                          SizedBox(
                            width: fieldWidth,
                            child: DateInputField(
                              value: _toDate,
                              calendarController: widget.calendarController,
                              labelText: 'تا تاریخ',
                              onChanged: (v) {
                                setState(() => _toDate = v);
                                _fetchAll();
                              },
                            ),
                          ),
                          if (_currencies.length > 1)
                            ReportCurrencyFilterDropdown(
                              businessId: widget.businessId,
                              isMultiCurrency: true,
                              selectedCurrencyId: _selectedCurrencyId,
                              width: fieldWidth,
                              onChanged: (v) {
                                setState(() {
                                  _selectedCurrencyId = v;
                                  if (v == null) _includeBaseEquivalent = false;
                                });
                                _fetchAll();
                              },
                            ),
                          if (_selectedCurrencyId != null)
                            FilterChip(
                              label: const Text('نمایش معادل پایه'),
                              selected: _includeBaseEquivalent,
                              onSelected: (value) {
                                setState(() => _includeBaseEquivalent = value);
                                _fetchAll();
                              },
                            ),
                          SizedBox(
                            width: fieldWidth,
                            child: ProjectSelectorWidget(
                              businessId: widget.businessId,
                              apiClient: ApiClient(),
                              selectedProjectId: _selectedProjectId,
                              onChanged: (v) {
                                setState(() => _selectedProjectId = v);
                                _fetchAll();
                              },
                            ),
                          ),
                          SizedBox(
                            width: fieldWidth,
                            child: DropdownButtonFormField<int>(
                              value: _accountLevel,
                              decoration: _decoration('سطح حساب'),
                              items: const [
                                DropdownMenuItem(value: 1, child: Text('گروه')),
                                DropdownMenuItem(value: 2, child: Text('کل')),
                                DropdownMenuItem(value: 3, child: Text('معین')),
                                DropdownMenuItem(value: 4, child: Text('تفصیل')),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() => _accountLevel = v);
                                _fetchAll();
                              },
                            ),
                          ),
                          SizedBox(
                            width: fieldWidth,
                            child: DropdownButtonFormField<String?>(
                              value: _compareMode,
                              decoration: _decoration('مقایسه'),
                              items: const [
                                DropdownMenuItem(value: null, child: Text('بدون مقایسه')),
                                DropdownMenuItem(value: 'prior_period', child: Text('دوره قبل')),
                                DropdownMenuItem(value: 'prior_year', child: Text('سال قبل')),
                              ],
                              onChanged: (v) {
                                setState(() => _compareMode = v);
                                _fetchAll();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!_loading && _error == null) ...[
                  if (_fxDataQuality != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(pagePadding, 0, pagePadding, 8),
                      child: FxDataQualityBanner(quality: _fxDataQuality),
                    ),
                  Padding(padding: EdgeInsets.symmetric(horizontal: pagePadding), child: _overviewCards()),
                ],
                const SizedBox(height: 8),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Text(_error!))
                          : TabBarView(
                              controller: _tabController,
                              children: [
                                SingleChildScrollView(
                                  padding: EdgeInsets.only(bottom: pagePadding + 24),
                                  child: TrialBalanceTreeView(
                                    businessId: widget.businessId,
                                    accounts: _trialBalanceAccounts,
                                    columnMode: 8,
                                    ledgerContext: _ledgerContext,
                                    summary: _trialBalanceSummary,
                                  ),
                                ),
                                SingleChildScrollView(
                                  padding: EdgeInsets.all(pagePadding),
                                  child: Column(
                                    children: [
                                      if (_balanceSheetSummary != null)
                                        BalanceSheetSummaryPanel(
                                          summary: _balanceSheetSummary,
                                          isMobile: isMobile,
                                        ),
                                      const SizedBox(height: 12),
                                      BalanceSheetStatementView(
                                        statementLines: _balanceSheetLines,
                                        hasCompare: _balanceSheetComparison != null && _balanceSheetComparison!.isNotEmpty,
                                        showBaseEquivalent:
                                            _selectedCurrencyId != null && _includeBaseEquivalent,
                                        onAccountTap: _openLedger,
                                      ),
                                    ],
                                  ),
                                ),
                                SingleChildScrollView(
                                  padding: EdgeInsets.all(pagePadding),
                                  child: Column(
                                    children: [
                                      if (_pnlSummary != null)
                                        PnlSummaryPanel(
                                          summary: _pnlSummary,
                                          comparison: _pnlComparison,
                                          isMobile: isMobile,
                                        ),
                                      const SizedBox(height: 12),
                                      PnlStatementView(
                                        statementLines: _pnlStatementLines,
                                        onAccountTap: _openLedger,
                                      ),
                                    ],
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
