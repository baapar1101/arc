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
import 'package:hesabix_ui/utils/web/web_utils.dart' as web_utils;
import 'package:hesabix_ui/widgets/project/project_selector_widget.dart';
import 'package:hesabix_ui/utils/responsive_helper.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

class PnlPeriodReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;

  const PnlPeriodReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<PnlPeriodReportPage> createState() => _PnlPeriodReportPageState();
}

class _PnlPeriodReportPageState extends State<PnlPeriodReportPage> {
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedFiscalYearId;
  int? _selectedCurrencyId;
  int? _selectedProjectId;

  List<Map<String, dynamic>> _fiscalYears = [];
  List<Map<String, dynamic>> _currencies = [];

  List<Map<String, dynamic>> _revenueItems = [];
  List<Map<String, dynamic>> _expenseItems = [];
  Map<String, dynamic>? _summary;
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
        if (id is int) {
          _selectedFiscalYearId = id;
        }
      });
    } catch (_) {
      // ignore
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
      // ignore
    }
  }

  Map<String, dynamic> _requestBody() {
    return <String, dynamic>{
      if (_fromDate != null) 'date_from': _fromDate!.toIso8601String().split('T').first,
      if (_toDate != null) 'date_to': _toDate!.toIso8601String().split('T').first,
      if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
      if (_selectedCurrencyId != null) 'currency_id': _selectedCurrencyId,
      if (_selectedProjectId != null) 'project_id': _selectedProjectId,
    };
  }

  Future<void> _fetchData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ApiClient();
      final res = await api.post<Map<String, dynamic>>(
        '/api/v1/businesses/${widget.businessId}/reports/pnl-period',
        data: _requestBody(),
      );

      final body = res.data;
      if (body is Map<String, dynamic> && body['data'] is Map<String, dynamic>) {
        final data = body['data'] as Map<String, dynamic>;
        if (!mounted) return;
        setState(() {
          _revenueItems = List<Map<String, dynamic>>.from(data['revenue_items'] ?? []);
          _expenseItems = List<Map<String, dynamic>>.from(data['expense_items'] ?? []);
          _summary = data['summary'] is Map
              ? Map<String, dynamic>.from(data['summary'] as Map)
              : null;
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

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  double _asDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  Future<void> _exportExcel() async {
    setState(() => _exporting = true);
    try {
      final api = ApiClient();
      final bytes = await api.post<List<int>>(
        '/api/v1/businesses/${widget.businessId}/reports/pnl-period/export/excel',
        data: _requestBody(),
        responseType: ResponseType.bytes,
        options: Options(headers: {'Accept': 'application/octet-stream'}),
      );
      final data = bytes.data ?? <int>[];
      if (kIsWeb) {
        await web_utils.saveBytesAsFileWeb(
          data,
          'pnl_period_${widget.businessId}.xlsx',
          mimeType: 'application/octet-stream',
        );
      } else if (mounted) {
        SnackBarHelper.show(context, message: 'Export only available on web');
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: 'Export error: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    try {
      final api = ApiClient();
      final bytes = await api.post<List<int>>(
        '/api/v1/businesses/${widget.businessId}/reports/pnl-period/export/pdf',
        data: _requestBody(),
        responseType: ResponseType.bytes,
        options: Options(headers: {'Accept': 'application/pdf'}),
      );
      final data = bytes.data ?? <int>[];
      if (kIsWeb) {
        await web_utils.saveBytesAsFileWeb(
          data,
          'pnl_period_${widget.businessId}.pdf',
          mimeType: 'application/pdf',
        );
      } else if (mounted) {
        SnackBarHelper.show(context, message: 'Export only available on web');
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: 'Export error: ${ErrorExtractor.forContext(e, context)}',
      );
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
    final net = _asDouble(_summary?['net_profit_loss']);

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
            Text(t.reportsPnlPeriodTitle, style: const TextStyle(fontSize: 18)),
            Text(
              t.reportsPnlPeriodSubtitle,
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
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onSurface,
                    ),
                  )
                : const Icon(Icons.download_outlined),
            tooltip: t.export,
            enabled: !_exporting && !_loading,
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
                        _buildFilters(context, isMobile),
                        const SizedBox(height: 16),
                        if (_summary != null) ...[
                          _buildSummary(context, isMobile, net),
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
                          _buildStatementSection(
                            context: context,
                            title: 'درآمدها',
                            count: _revenueItems.length,
                            icon: Icons.trending_up_rounded,
                            accent: const Color(0xFF15803D),
                            emptyText: 'هیچ درآمدی در این بازه یافت نشد',
                            headers: const ['کد حساب', 'نام حساب', 'بستانکار', 'بدهکار', 'درآمد خالص'],
                            rows: _revenueItems
                                .map(
                                  (item) => [
                                    item['account_code']?.toString() ?? '',
                                    item['account_name']?.toString() ?? '',
                                    _formatNumber(item['credit']),
                                    _formatNumber(item['debit']),
                                    _formatNumber(item['revenue']),
                                  ],
                                )
                                .toList(),
                            totalLabel: 'جمع درآمد',
                            totalValue: _formatNumber(_summary?['total_revenue']),
                          ),
                          const SizedBox(height: 16),
                          _buildStatementSection(
                            context: context,
                            title: 'هزینه‌ها',
                            count: _expenseItems.length,
                            icon: Icons.trending_down_rounded,
                            accent: const Color(0xFFB91C1C),
                            emptyText: 'هیچ هزینه‌ای در این بازه یافت نشد',
                            headers: const ['کد حساب', 'نام حساب', 'بدهکار', 'بستانکار', 'هزینه خالص'],
                            rows: _expenseItems
                                .map(
                                  (item) => [
                                    item['account_code']?.toString() ?? '',
                                    item['account_name']?.toString() ?? '',
                                    _formatNumber(item['debit']),
                                    _formatNumber(item['credit']),
                                    _formatNumber(item['expense']),
                                  ],
                                )
                                .toList(),
                            totalLabel: 'جمع هزینه',
                            totalValue: _formatNumber(_summary?['total_expense']),
                          ),
                          const SizedBox(height: 16),
                          _buildNetResult(context, net),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildFilters(BuildContext context, bool isMobile) {
    final cs = Theme.of(context).colorScheme;
    final fieldWidth = isMobile ? double.infinity : 220.0;

    InputDecoration decoration(String label) => InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        );

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'فیلترها',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<int>(
                    value: _selectedFiscalYearId,
                    isExpanded: true,
                    decoration: decoration('سال مالی'),
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
                      setState(() => _selectedFiscalYearId = value);
                      _fetchData();
                    },
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: DateInputField(
                    value: _fromDate,
                    calendarController: widget.calendarController,
                    labelText: 'از تاریخ',
                    onChanged: (date) {
                      setState(() => _fromDate = date);
                      _fetchData();
                    },
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: DateInputField(
                    value: _toDate,
                    calendarController: widget.calendarController,
                    labelText: 'تا تاریخ',
                    onChanged: (date) {
                      setState(() => _toDate = date);
                      _fetchData();
                    },
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<int>(
                    value: _selectedCurrencyId,
                    isExpanded: true,
                    decoration: decoration('ارز'),
                    items: [
                      const DropdownMenuItem<int>(
                        value: null,
                        child: Text('همه ارزها'),
                      ),
                      ..._currencies.map((c) {
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
                      }),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedCurrencyId = val);
                      _fetchData();
                    },
                  ),
                ),
                SizedBox(
                  width: isMobile ? double.infinity : 260,
                  child: ProjectSelectorWidget(
                    businessId: widget.businessId,
                    apiClient: ApiClient(),
                    selectedProjectId: _selectedProjectId,
                    onChanged: (projectId) {
                      setState(() => _selectedProjectId = projectId);
                      _fetchData();
                    },
                    allowNull: true,
                    labelText: 'پروژه (همه)',
                    calendarController: widget.calendarController,
                    isDense: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(BuildContext context, bool isMobile, double net) {
    final cards = [
      _SummaryMetric(
        label: 'جمع درآمد',
        value: _formatNumber(_summary?['total_revenue']),
        icon: Icons.south_west_rounded,
        color: const Color(0xFF15803D),
        background: const Color(0xFFECFDF5),
      ),
      _SummaryMetric(
        label: 'جمع هزینه',
        value: _formatNumber(_summary?['total_expense']),
        icon: Icons.north_east_rounded,
        color: const Color(0xFFB91C1C),
        background: const Color(0xFFFEF2F2),
      ),
      _SummaryMetric(
        label: 'سود/زیان خالص',
        value: _formatNumber(_summary?['net_profit_loss']),
        icon: net >= 0 ? Icons.insights_rounded : Icons.warning_amber_rounded,
        color: net >= 0 ? const Color(0xFF1D4ED8) : const Color(0xFFC2410C),
        background: net >= 0 ? const Color(0xFFEFF6FF) : const Color(0xFFFFF7ED),
      ),
    ];

    if (isMobile) {
      return Column(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            cards[i],
          ],
        ],
      );
    }

    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: cards[i]),
        ],
      ],
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
          Text(
            'خطا در دریافت گزارش',
            style: TextStyle(fontWeight: FontWeight.w700, color: cs.error),
          ),
          const SizedBox(height: 8),
          Text(_error ?? '', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: _fetchData,
            child: const Text('تلاش مجدد'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatementSection({
    required BuildContext context,
    required String title,
    required int count,
    required IconData icon,
    required Color accent,
    required String emptyText,
    required List<String> headers,
    required List<List<String>> rows,
    required String totalLabel,
    required String totalValue,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isMobile = ResponsiveHelper.isMobile(context);

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 16,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              border: Border(
                bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Text(
                    '$count مورد',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ],
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
              child: Center(
                child: Text(
                  emptyText,
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final table = DataTable(
                  headingRowHeight: 44,
                  dataRowMinHeight: 40,
                  dataRowMaxHeight: 52,
                  columnSpacing: isMobile ? 16 : 28,
                  horizontalMargin: isMobile ? 12 : 16,
                  headingRowColor: WidgetStatePropertyAll(
                    cs.surfaceContainerHighest.withValues(alpha: 0.45),
                  ),
                  columns: [
                    for (final h in headers)
                      DataColumn(
                        label: Text(
                          h,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                  rows: [
                    for (final row in rows)
                      DataRow(
                        cells: [
                          for (var i = 0; i < row.length; i++)
                            DataCell(
                              Text(
                                row[i],
                                textAlign: i >= 2 ? TextAlign.center : TextAlign.start,
                                style: i == row.length - 1
                                    ? const TextStyle(fontWeight: FontWeight.w600)
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    DataRow(
                      color: WidgetStatePropertyAll(
                        cs.surfaceContainerHighest.withValues(alpha: 0.55),
                      ),
                      cells: [
                        const DataCell(SizedBox.shrink()),
                        DataCell(
                          Text(
                            totalLabel,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const DataCell(SizedBox.shrink()),
                        const DataCell(SizedBox.shrink()),
                        DataCell(
                          Text(
                            totalValue,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );

                if (constraints.maxWidth < 720) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 720),
                      child: table,
                    ),
                  );
                }
                return table;
              },
            ),
        ],
      ),
    );
  }

  Widget _buildNetResult(BuildContext context, double net) {
    final isProfit = net >= 0;
    final color = isProfit ? const Color(0xFF065F46) : const Color(0xFF9A3412);
    final bg = isProfit ? const Color(0xFFECFDF5) : const Color(0xFFFFF7ED);
    final border = isProfit ? const Color(0xFFA7F3D0) : const Color(0xFFFED7AA);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(
            isProfit ? Icons.check_circle_outline : Icons.info_outline,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'سود/زیان خالص',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: color,
                fontSize: 15,
              ),
            ),
          ),
          Text(
            _formatNumber(_summary?['net_profit_loss']),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: color,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color background;

  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: color.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color,
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
