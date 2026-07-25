import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/utils/financial_report_navigation.dart';
import 'package:dio/dio.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/project/project_selector_widget.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import 'package:hesabix_ui/widgets/reports/balance_sheet_report_shared.dart';
import 'package:hesabix_ui/utils/web/web_utils.dart' as web_utils;
import 'package:hesabix_ui/utils/responsive_helper.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

class BalanceSheetReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;

  const BalanceSheetReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<BalanceSheetReportPage> createState() => _BalanceSheetReportPageState();
}

class _BalanceSheetReportPageState extends State<BalanceSheetReportPage> {
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedFiscalYearId;
  int? _selectedCurrencyId;
  int? _selectedProjectId;
  bool _includeZeroBalance = false;
  int _accountLevel = 4;
  String? _compareMode;

  List<Map<String, dynamic>> _fiscalYears = [];
  List<Map<String, dynamic>> _currencies = [];
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
        final current = items.firstWhere((e) => e['is_current'] == true, orElse: () => const <String, dynamic>{});
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
        // تک‌ارزی یا چندارزی: پیش‌فرض «همه» (= مبالغ پایه در بک‌اند)
        _selectedCurrencyId = null;
      });
    } catch (_) {}
  }

  Map<String, dynamic> _requestBody() => {
        if (_fromDate != null) 'date_from': _fromDate!.toIso8601String().split('T').first,
        if (_toDate != null) 'date_to': _toDate!.toIso8601String().split('T').first,
        if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
        if (_selectedCurrencyId != null) 'currency_id': _selectedCurrencyId,
        if (_selectedProjectId != null) 'project_id': _selectedProjectId,
        'include_zero_balance': _includeZeroBalance,
        'account_level': _accountLevel,
        if (_compareMode != null) 'compare_mode': _compareMode,
        'compare_prior_period': _compareMode != null,
      };

  Future<void> _fetchData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient().post<Map<String, dynamic>>(
        '/api/v1/businesses/${widget.businessId}/reports/balance-sheet',
        data: _requestBody(),
      );
      final body = res.data;
      if (body is Map<String, dynamic> && body['data'] is Map<String, dynamic>) {
        final data = body['data'] as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          _statementLines = List<Map<String, dynamic>>.from(data['statement_lines'] ?? []);
          _summary = data['summary'] is Map ? Map<String, dynamic>.from(data['summary'] as Map) : null;
          _comparison = data['comparison'] is Map ? Map<String, dynamic>.from(data['comparison'] as Map) : null;
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

  Future<void> _export(String type) async {
    setState(() => _exporting = true);
    try {
      final isPdf = type == 'pdf';
      final bytes = await ApiClient().post<List<int>>(
        '/api/v1/businesses/${widget.businessId}/reports/balance-sheet/export/$type',
        data: _requestBody(),
        responseType: ResponseType.bytes,
        options: Options(headers: {'Accept': isPdf ? 'application/pdf' : 'application/octet-stream'}),
      );
      final data = bytes.data ?? <int>[];
      if (kIsWeb) {
        await web_utils.saveBytesAsFileWeb(
          data,
          'balance_sheet_${widget.businessId}.${isPdf ? 'pdf' : 'xlsx'}',
          mimeType: isPdf ? 'application/pdf' : 'application/octet-stream',
        );
      } else if (mounted) {
        SnackBarHelper.show(context, message: 'Export only available on web');
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: 'Export error: ${ErrorExtractor.forContext(e, context)}');
    } finally {
      if (mounted) setState(() => _exporting = false);
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
          dateFrom: _fromDate,
          dateTo: _toDate,
          currencyId: _selectedCurrencyId,
          projectId: _selectedProjectId,
        ),
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final isMobile = ResponsiveHelper.isMobile(context);
    final pagePadding = ResponsiveHelper.getPadding(context);
    final fieldWidth = isMobile ? double.infinity : 220.0;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.reportsBalanceSheetTitle, style: const TextStyle(fontSize: 18)),
            Text(
              t.reportsBalanceSheetSubtitle,
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
            onSelected: _export,
            itemBuilder: (context) => [
              PopupMenuItem(value: 'excel', child: Row(children: [Icon(Icons.table_chart_outlined, color: Colors.green[700]), const SizedBox(width: 8), Text(t.exportToExcel)])),
              PopupMenuItem(value: 'pdf', child: Row(children: [Icon(Icons.picture_as_pdf_outlined, color: Colors.red[700]), const SizedBox(width: 8), Text(t.exportToPdf)])),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: (_loading || !_filtersReady) ? null : _fetchData),
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
                        Material(
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: EdgeInsets.all(isMobile ? 12 : 16),
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 12,
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
                                      _fetchData();
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: fieldWidth,
                                  child: DateInputField(
                                    value: _toDate,
                                    calendarController: widget.calendarController,
                                    labelText: 'تاریخ مبنا (تا تاریخ)',
                                    onChanged: (v) {
                                      setState(() => _toDate = v);
                                      _fetchData();
                                    },
                                  ),
                                ),
                                if (_currencies.length > 1)
                                  SizedBox(
                                    width: fieldWidth,
                                    child: DropdownButtonFormField<int>(
                                      value: _selectedCurrencyId,
                                      isExpanded: true,
                                      decoration: _decoration('ارز'),
                                      items: [
                                        const DropdownMenuItem<int>(
                                          value: null,
                                          child: Text('همه ارزها'),
                                        ),
                                        ..._currencies.map(
                                          (c) => DropdownMenuItem<int>(
                                            value: c['id'] as int?,
                                            child: Text(
                                              c['code']?.toString() ??
                                                  c['name']?.toString() ??
                                                  '',
                                            ),
                                          ),
                                        ),
                                      ],
                                      onChanged: (v) {
                                        setState(() => _selectedCurrencyId = v);
                                        _fetchData();
                                      },
                                    ),
                                  ),
                                SizedBox(
                                  width: fieldWidth,
                                  child: ProjectSelectorWidget(
                                    businessId: widget.businessId,
                                    apiClient: ApiClient(),
                                    selectedProjectId: _selectedProjectId,
                                    onChanged: (v) {
                                      setState(() => _selectedProjectId = v);
                                      _fetchData();
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: fieldWidth,
                                  child: DropdownButtonFormField<int>(
                                    value: _accountLevel,
                                    decoration: _decoration('سطح نمایش'),
                                    items: const [
                                      DropdownMenuItem(value: 1, child: Text('گروه')),
                                      DropdownMenuItem(value: 2, child: Text('کل')),
                                      DropdownMenuItem(value: 3, child: Text('معین')),
                                      DropdownMenuItem(value: 4, child: Text('تفصیل')),
                                    ],
                                    onChanged: (v) {
                                      if (v == null) return;
                                      setState(() => _accountLevel = v);
                                      _fetchData();
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: fieldWidth,
                                  child: DropdownButtonFormField<String?>(
                                    value: _compareMode,
                                    decoration: _decoration('مقایسه با'),
                                    items: const [
                                      DropdownMenuItem(value: null, child: Text('بدون مقایسه')),
                                      DropdownMenuItem(value: 'prior_period', child: Text('دوره قبل')),
                                      DropdownMenuItem(value: 'prior_year', child: Text('سال قبل')),
                                    ],
                                    onChanged: (v) {
                                      setState(() => _compareMode = v);
                                      _fetchData();
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: fieldWidth,
                                  child: CheckboxListTile(
                                    title: const Text('نمایش حساب‌های صفر'),
                                    value: _includeZeroBalance,
                                    onChanged: (v) {
                                      setState(() => _includeZeroBalance = v ?? false);
                                      _fetchData();
                                    },
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_summary != null) ...[
                          BalanceSheetSummaryPanel(summary: _summary, isMobile: isMobile),
                          const SizedBox(height: 16),
                        ],
                        if (_loading)
                          const Padding(padding: EdgeInsets.symmetric(vertical: 64), child: Center(child: CircularProgressIndicator()))
                        else if (_error != null)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(child: Text(_error!, style: TextStyle(color: cs.error))),
                          )
                        else
                          BalanceSheetStatementView(
                            statementLines: _statementLines,
                            hasCompare: _comparison != null && _comparison!.isNotEmpty,
                            onAccountTap: _openGeneralLedger,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
