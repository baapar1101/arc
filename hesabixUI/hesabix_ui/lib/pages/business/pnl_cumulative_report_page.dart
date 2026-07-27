import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import 'package:hesabix_ui/utils/responsive_helper.dart';
import 'package:hesabix_ui/widgets/reports/pnl_report_shared.dart';
import 'package:hesabix_ui/utils/financial_report_navigation.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import 'package:hesabix_ui/services/bytes_export/bytes_export_service.dart';

class PnlCumulativeReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;

  const PnlCumulativeReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<PnlCumulativeReportPage> createState() => _PnlCumulativeReportPageState();
}

class _PnlCumulativeReportPageState extends State<PnlCumulativeReportPage> {
  DateTime? _toDate;
  int? _selectedFiscalYearId;
  int? _selectedCurrencyId;
  int? _selectedProjectId;
  bool _includeZeroBalance = false;
  String? _compareMode;

  List<Map<String, dynamic>> _fiscalYears = [];
  List<Map<String, dynamic>> _currencies = [];

  List<Map<String, dynamic>> _salesItems = [];
  List<Map<String, dynamic>> _otherIncomeItems = [];
  List<Map<String, dynamic>> _cogsItems = [];
  List<Map<String, dynamic>> _operatingItems = [];
  List<Map<String, dynamic>> _nonOperatingIncomeItems = [];
  List<Map<String, dynamic>> _nonOperatingExpenseItems = [];
  List<Map<String, dynamic>> _taxItems = [];
  List<Map<String, dynamic>> _statementLines = [];
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _comparison;
  bool _loading = false;
  bool _exporting = false;
  String? _error;
  bool _filtersReady = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_loadFiscalYears(), _loadCurrencies()]);
    if (!mounted) return;
    setState(() => _filtersReady = true);
    await _fetchData();
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
        if (id is int) _selectedFiscalYearId = id;
      });
    } catch (_) {}
  }

  Future<void> _loadCurrencies() async {
    try {
      final svc = CurrencyService(ApiClient());
      final items = await svc.listBusinessCurrencies(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _currencies = items;
        // پیش‌فرض: همه ارزها (= تبدیل به پایه در بک‌اند)
        _selectedCurrencyId = null;
      });
    } catch (_) {}
  }

  Map<String, dynamic> _requestBody() => {
        if (_toDate != null) 'date_to': _toDate!.toIso8601String().split('T').first,
        if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
        if (_selectedCurrencyId != null) 'currency_id': _selectedCurrencyId,
        if (_selectedProjectId != null) 'project_id': _selectedProjectId,
        'include_zero_balance': _includeZeroBalance,
        if (_compareMode != null) 'compare_mode': _compareMode,
        'compare_prior_period': _compareMode != null,
      };

  void _applyData(Map<String, dynamic> data) {
    _salesItems = List<Map<String, dynamic>>.from(data['sales_items'] ?? []);
    _otherIncomeItems = List<Map<String, dynamic>>.from(data['other_income_items'] ?? []);
    _cogsItems = List<Map<String, dynamic>>.from(data['cogs_items'] ?? []);
    _operatingItems = List<Map<String, dynamic>>.from(data['operating_expense_items'] ?? []);
    _nonOperatingIncomeItems = List<Map<String, dynamic>>.from(data['non_operating_income_items'] ?? []);
    _nonOperatingExpenseItems = List<Map<String, dynamic>>.from(data['non_operating_expense_items'] ?? []);
    _taxItems = List<Map<String, dynamic>>.from(data['tax_expense_items'] ?? []);
    _statementLines = List<Map<String, dynamic>>.from(data['statement_lines'] ?? []);
    _summary = data['summary'] is Map ? Map<String, dynamic>.from(data['summary'] as Map) : null;
    _comparison = data['comparison'] is Map ? Map<String, dynamic>.from(data['comparison'] as Map) : null;
  }

  Future<void> _fetchData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await ApiClient().post<Map<String, dynamic>>(
        '/api/v1/businesses/${widget.businessId}/reports/pnl-cumulative',
        data: _requestBody(),
      );
      final body = res.data;
      if (body is Map<String, dynamic> && body['data'] is Map<String, dynamic>) {
        if (!mounted) return;
        setState(() {
          _applyData(body['data'] as Map<String, dynamic>);
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  void _openGeneralLedger(Map<String, dynamic> line) {
    final accountId = line['account_id'];
    if (accountId == null && line['account_code'] == null) return;
    context.push(
      buildGeneralLedgerRoute(
        businessId: widget.businessId,
        accountRow: {
          'account_id': accountId,
          'account_code': line['account_code'],
          'account_name': line['account_name'],
          'account_type': line['account_type'] ?? 'accounting_document',
        },
        context: FinancialReportLedgerContext(
          fiscalYearId: _selectedFiscalYearId,
          dateFrom: null,
          dateTo: _toDate,
          currencyId: _selectedCurrencyId,
          projectId: _selectedProjectId,
        ),
      ),
    );
  }

  Future<void> _export(String type) async {
    setState(() => _exporting = true);
    try {
      final isPdf = type == 'pdf';
      final bytes = await ApiClient().post<List<int>>(
        '/api/v1/businesses/${widget.businessId}/reports/pnl-cumulative/export/$type',
        data: _requestBody(),
        responseType: ResponseType.bytes,
        options: Options(headers: {'Accept': isPdf ? 'application/pdf' : 'application/octet-stream'}),
      );
      final data = bytes.data ?? <int>[];
      final result = await BytesExportService.export(
        bytes: data,
        filename: 'pnl_cumulative_${widget.businessId}.${isPdf ? 'pdf' : 'xlsx'}',
        mimeType: isPdf ? 'application/pdf' : 'application/octet-stream',
      );
      if (mounted) BytesExportService.showFeedback(context, result);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'Export error: ${ErrorExtractor.forContext(e, context)}');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final isMobile = ResponsiveHelper.isMobile(context);
    final pagePadding = ResponsiveHelper.getPadding(context);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.reportsPnlCumulativeTitle, style: const TextStyle(fontSize: 18)),
            Text(
              'از ابتدای سال مالی تا تاریخ انتخابی',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.65),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: _exporting
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: cs.onSurface),
                  )
                : const Icon(Icons.download_outlined),
            tooltip: t.export,
            enabled: !_exporting && !_loading,
            onSelected: _export,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'excel',
                child: Row(
                  children: [
                    Icon(Icons.table_chart_outlined, color: Colors.green[700]),
                    const SizedBox(width: 8),
                    Text(t.exportToExcel),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'pdf',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf_outlined, color: Colors.red[700]),
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
            onPressed: (_loading || !_filtersReady) ? null : _fetchData,
          ),
        ],
      ),
      body: !_filtersReady
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(pagePadding, pagePadding, pagePadding, pagePadding + 24),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PnlReportFilters(
                          isCumulative: true,
                          isMobile: isMobile,
                          fiscalYears: _fiscalYears,
                          currencies: _currencies,
                          selectedFiscalYearId: _selectedFiscalYearId,
                          fromDate: null,
                          toDate: _toDate,
                          selectedCurrencyId: _selectedCurrencyId,
                          selectedProjectId: _selectedProjectId,
                          businessId: widget.businessId,
                          calendarController: widget.calendarController,
                          includeZeroBalance: _includeZeroBalance,
                          compareMode: _compareMode,
                          onFiscalYearChanged: (v) {
                            setState(() => _selectedFiscalYearId = v);
                            _fetchData();
                          },
                          onFromDateChanged: (_) {},
                          onToDateChanged: (v) {
                            setState(() => _toDate = v);
                            _fetchData();
                          },
                          onCurrencyChanged: (v) {
                            setState(() => _selectedCurrencyId = v);
                            _fetchData();
                          },
                          onProjectChanged: (v) {
                            setState(() => _selectedProjectId = v);
                            _fetchData();
                          },
                          onIncludeZeroBalanceChanged: (v) {
                            setState(() => _includeZeroBalance = v);
                            _fetchData();
                          },
                          onCompareModeChanged: (v) {
                            setState(() => _compareMode = v);
                            _fetchData();
                          },
                        ),
                        const SizedBox(height: 16),
                        if (_summary != null) ...[
                          PnlSummaryPanel(
                            summary: _summary,
                            comparison: _comparison,
                            isMobile: isMobile,
                            isCumulative: true,
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 64),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_error != null)
                          _buildErrorState(cs)
                        else ...[
                          PnlStatementView(
                            statementLines: _statementLines,
                            onAccountTap: _openGeneralLedger,
                          ),
                          const SizedBox(height: 16),
                          if (_salesItems.isNotEmpty) ...[
                            PnlDetailSection(
                              title: 'فروش و درآمد عملیاتی (تجمعی)',
                              count: _salesItems.length,
                              icon: Icons.storefront_outlined,
                              accent: const Color(0xFF15803D),
                              emptyText: 'موردی یافت نشد',
                              headers: const ['کد حساب', 'نام حساب', 'بستانکار', 'بدهکار', 'درآمد خالص'],
                              rows: PnlTableRows.revenueRows(_salesItems),
                              totalLabel: 'جمع فروش',
                              totalValue: PnlTableRows.fmt(_summary?['total_sales']),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_otherIncomeItems.isNotEmpty) ...[
                            PnlDetailSection(
                              title: 'درآمدهای عملیاتی (۶۰۱) — تجمعی',
                              count: _otherIncomeItems.length,
                              icon: Icons.trending_up_rounded,
                              accent: const Color(0xFF059669),
                              emptyText: 'موردی یافت نشد',
                              headers: const ['کد حساب', 'نام حساب', 'بستانکار', 'بدهکار', 'درآمد خالص'],
                              rows: PnlTableRows.revenueRows(_otherIncomeItems),
                              totalLabel: 'جمع درآمد عملیاتی',
                              totalValue: PnlTableRows.fmt(_summary?['total_other_income']),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_cogsItems.isNotEmpty) ...[
                            PnlDetailSection(
                              title: 'بهای تمام‌شده (تجمعی)',
                              count: _cogsItems.length,
                              icon: Icons.inventory_2_outlined,
                              accent: const Color(0xFFB45309),
                              emptyText: 'موردی یافت نشد',
                              headers: const ['کد حساب', 'نام حساب', 'بدهکار', 'بستانکار', 'هزینه خالص'],
                              rows: PnlTableRows.expenseRows(_cogsItems),
                              totalLabel: 'جمع بهای تمام‌شده',
                              totalValue: PnlTableRows.fmt(_summary?['total_cogs']),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_operatingItems.isNotEmpty) ...[
                            PnlDetailSection(
                              title: 'هزینه‌های عملیاتی (تجمعی)',
                              count: _operatingItems.length,
                              icon: Icons.trending_down_rounded,
                              accent: const Color(0xFFB91C1C),
                              emptyText: 'موردی یافت نشد',
                              headers: const ['کد حساب', 'نام حساب', 'بدهکار', 'بستانکار', 'هزینه خالص'],
                              rows: PnlTableRows.expenseRows(_operatingItems),
                              totalLabel: 'جمع هزینه عملیاتی',
                              totalValue: PnlTableRows.fmt(_summary?['total_operating_expense']),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_nonOperatingIncomeItems.isNotEmpty) ...[
                            PnlDetailSection(
                              title: 'درآمدهای غیرعملیاتی (تجمعی)',
                              count: _nonOperatingIncomeItems.length,
                              icon: Icons.savings_outlined,
                              accent: const Color(0xFF047857),
                              emptyText: 'موردی یافت نشد',
                              headers: const ['کد حساب', 'نام حساب', 'بستانکار', 'بدهکار', 'درآمد خالص'],
                              rows: PnlTableRows.revenueRows(_nonOperatingIncomeItems),
                              totalLabel: 'جمع درآمد غیرعملیاتی',
                              totalValue: PnlTableRows.fmt(_summary?['total_non_operating_income']),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_nonOperatingExpenseItems.isNotEmpty) ...[
                            PnlDetailSection(
                              title: 'هزینه‌های غیرعملیاتی (تجمعی)',
                              count: _nonOperatingExpenseItems.length,
                              icon: Icons.money_off_csred_outlined,
                              accent: const Color(0xFF9F1239),
                              emptyText: 'موردی یافت نشد',
                              headers: const ['کد حساب', 'نام حساب', 'بدهکار', 'بستانکار', 'هزینه خالص'],
                              rows: PnlTableRows.expenseRows(_nonOperatingExpenseItems),
                              totalLabel: 'جمع هزینه غیرعملیاتی',
                              totalValue: PnlTableRows.fmt(_summary?['total_non_operating_expense']),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_taxItems.isNotEmpty)
                            PnlDetailSection(
                              title: 'مالیات بر درآمد (تجمعی)',
                              count: _taxItems.length,
                              icon: Icons.receipt_long_outlined,
                              accent: const Color(0xFF9A3412),
                              emptyText: 'موردی یافت نشد',
                              headers: const ['کد حساب', 'نام حساب', 'بدهکار', 'بستانکار', 'هزینه خالص'],
                              rows: PnlTableRows.expenseRows(_taxItems),
                              totalLabel: 'جمع مالیات',
                              totalValue: PnlTableRows.fmt(_summary?['total_tax_expense']),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildErrorState(ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 48),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.error.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline, color: cs.error, size: 36),
          const SizedBox(height: 12),
          Text('خطا در دریافت گزارش', style: TextStyle(fontWeight: FontWeight.w700, color: cs.error)),
          const SizedBox(height: 8),
          Text(_error ?? '', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: _fetchData, child: const Text('تلاش مجدد')),
        ],
      ),
    );
  }
}
