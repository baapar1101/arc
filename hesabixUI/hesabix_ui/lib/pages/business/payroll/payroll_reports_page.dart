import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../core/calendar_controller.dart';
import '../../../services/payroll_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import 'payroll_calendar_utils.dart';
import 'payroll_ui.dart';

/// گزارش‌های پیشرفته حقوق و دستمزد (فاز ۴).
class PayrollReportsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const PayrollReportsPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<PayrollReportsPage> createState() => _PayrollReportsPageState();
}

class _PayrollReportsPageState extends State<PayrollReportsPage> {
  final PayrollService _svc = PayrollService();

  bool _loading = true;
  bool _loadingReports = false;
  List<Map<String, dynamic>> _periods = [];
  int? _selectedPeriodId;
  int? _selectedYear;
  Map<String, dynamic>? _itemSummary;
  Map<String, dynamic>? _employeeSummary;
  Map<String, dynamic>? _statutorySummary;
  Map<String, dynamic>? _periodOverview;

  bool get _isJalali => widget.calendarController.isJalali;

  @override
  void initState() {
    super.initState();
    widget.calendarController.addListener(_onCalendarChanged);
    _loadPeriods();
  }

  void _onCalendarChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.calendarController.removeListener(_onCalendarChanged);
    super.dispose();
  }

  Future<void> _loadPeriods() async {
    setState(() => _loading = true);
    try {
      final periods = await _svc.listPeriods(businessId: widget.businessId);
      if (!mounted) return;
      final list = List<Map<String, dynamic>>.from(periods);
      int? year;
      int? periodId;
      if (list.isNotEmpty) {
        final first = list.first;
        periodId = (first['id'] as num?)?.toInt();
        year = PayrollCalendarUtils.displayYearFromPeriod(first, _isJalali);
      }
      final defaults = PayrollCalendarUtils.defaultDisplayYearMonth(_isJalali);
      setState(() {
        _periods = list;
        _selectedYear = year ?? defaults.year;
        _selectedPeriodId = periodId;
        _loading = false;
      });
      await _loadReports();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _loadReports() async {
    if (_selectedPeriodId == null && _selectedYear == null) return;
    setState(() => _loadingReports = true);
    try {
      final results = await Future.wait([
        if (_selectedPeriodId != null)
          _svc.getItemSummaryReport(
            businessId: widget.businessId,
            periodId: _selectedPeriodId,
          )
        else
          Future.value(const <String, dynamic>{}),
        if (_selectedPeriodId != null)
          _svc.getEmployeeSummaryReport(
            businessId: widget.businessId,
            periodId: _selectedPeriodId,
          )
        else
          Future.value(const <String, dynamic>{}),
        if (_selectedPeriodId != null)
          _svc.getStatutorySummaryReport(
            businessId: widget.businessId,
            periodId: _selectedPeriodId,
          )
        else
          Future.value(const <String, dynamic>{}),
        _svc.getPeriodOverviewReport(
          businessId: widget.businessId,
          year: _apiYearForOverview(),
        ),
      ]);
      if (!mounted) return;
      var overview = Map<String, dynamic>.from(results[3] as Map);
      overview = _filterPeriodOverview(overview);
      setState(() {
        _itemSummary = Map<String, dynamic>.from(results[0] as Map);
        _employeeSummary = Map<String, dynamic>.from(results[1] as Map);
        _statutorySummary = Map<String, dynamic>.from(results[2] as Map);
        _periodOverview = overview;
        _loadingReports = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingReports = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  /// سال شمسی برای فیلتر API؛ در تقویم میلادی null تا همه دوره‌ها بیاید و سمت کلاینت فیلتر شود.
  int? _apiYearForOverview() {
    if (_selectedYear == null) return null;
    if (_isJalali) return _selectedYear;
    return null;
  }

  Map<String, dynamic> _filterPeriodOverview(Map<String, dynamic> overview) {
    if (_isJalali || _selectedYear == null) return overview;
    final raw = overview['periods'];
    if (raw is! List) return overview;
    final filtered = raw
        .where(
          (p) => PayrollCalendarUtils.periodMatchesDisplayYear(
            Map<String, dynamic>.from(p as Map),
            _selectedYear!,
            false,
          ),
        )
        .toList();
    return {...overview, 'periods': filtered};
  }

  String _periodLabel(Map<String, dynamic> p) => PayrollCalendarUtils.periodTitle(p, _isJalali);

  String _fmt(dynamic v) => PayrollUi.formatMoney(v);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'payroll')),
        ),
        title: Text(t.payrollReportsTitle),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadPeriods),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: PayrollUi.pagePadding,
              children: [
                PayrollUi.sectionCard(
                  context: context,
                  title: t.payrollReportsFilters,
                  icon: Icons.filter_list,
                  child: Column(
                    children: [
                      if (_periods.isNotEmpty)
                        DropdownButtonFormField<int>(
                          initialValue: _selectedPeriodId,
                          decoration: PayrollUi.fieldDecoration(context, t.payrollPeriod, prefixIcon: Icons.calendar_month),
                          items: _periods
                              .map(
                                (p) => DropdownMenuItem<int>(
                                  value: (p['id'] as num).toInt(),
                                  child: Text(_periodLabel(p)),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            setState(() => _selectedPeriodId = v);
                            _loadReports();
                          },
                        ),
                      if (_periods.isNotEmpty) const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: _selectedYear,
                        decoration: PayrollUi.fieldDecoration(context, t.payrollPeriodYear, prefixIcon: Icons.date_range),
                        items: _availableYears()
                            .map(
                              (y) => DropdownMenuItem<int>(
                                value: y,
                                child: Text('$y'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          setState(() => _selectedYear = v);
                          _loadReports();
                        },
                      ),
                    ],
                  ),
                ),
                if (_loadingReports) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                const SizedBox(height: 16),
                if (_statutorySummary != null && _statutorySummary!.isNotEmpty) ...[
                  Text(t.payrollStatutorySummary, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _StatutoryCard(summary: _statutorySummary!, fmt: _fmt, t: t),
                  const SizedBox(height: 24),
                ],
                if (_itemSummary != null && (_itemSummary!['items'] as List?)?.isNotEmpty == true) ...[
                  Text(t.payrollItemSummaryReport, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _ItemSummaryTable(items: List<Map<String, dynamic>>.from(_itemSummary!['items'] as List), fmt: _fmt, t: t),
                  const SizedBox(height: 24),
                ],
                if (_employeeSummary != null && (_employeeSummary!['items'] as List?)?.isNotEmpty == true) ...[
                  Text(t.payrollEmployeeSummaryReport, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _EmployeeSummaryTable(
                    items: List<Map<String, dynamic>>.from(_employeeSummary!['items'] as List),
                    fmt: _fmt,
                    t: t,
                  ),
                  const SizedBox(height: 24),
                ],
                if (_periodOverview != null && (_periodOverview!['periods'] as List?)?.isNotEmpty == true) ...[
                  Text(t.payrollPeriodOverviewReport, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _PeriodOverviewTable(
                    periods: List<Map<String, dynamic>>.from(_periodOverview!['periods'] as List),
                    fmt: _fmt,
                    t: t,
                    isJalali: _isJalali,
                  ),
                ],
              ],
            ),
    );
  }

  List<int> _availableYears() =>
      PayrollCalendarUtils.displayYearsFromPeriods(_periods, _isJalali);
}

class _StatutoryCard extends StatelessWidget {
  final Map<String, dynamic> summary;
  final String Function(dynamic) fmt;
  final AppLocalizations t;

  const _StatutoryCard({required this.summary, required this.fmt, required this.t});

  @override
  Widget build(BuildContext context) {
    return PayrollUi.sectionCard(
      context: context,
      title: t.payrollStatutorySummary,
      icon: Icons.gavel_outlined,
      child: Column(
        children: [
          _row(t.payrollGrossTotal, fmt(summary['gross_earnings_total'])),
          _row(t.payrollInsuranceEmployee, fmt(summary['insurance_employee_total'])),
          _row(t.payrollInsuranceEmployer, fmt(summary['insurance_employer_total'])),
          _row(t.payrollTaxTotal, fmt(summary['tax_total'])),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ItemSummaryTable extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final String Function(dynamic) fmt;
  final AppLocalizations t;

  const _ItemSummaryTable({required this.items, required this.fmt, required this.t});

  @override
  Widget build(BuildContext context) {
    return PayrollUi.sectionCard(
      context: context,
      title: t.payrollItemSummaryReport,
      icon: Icons.table_chart_outlined,
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            DataColumn(label: Text(t.payrollItemName)),
            DataColumn(label: Text(t.payrollItemKindLabel)),
            DataColumn(label: Text(t.payrollGrossTotal)),
          ],
          rows: items
              .map(
                (row) => DataRow(
                  cells: [
                    DataCell(Text('${row['item_name'] ?? row['item_code']}')),
                    DataCell(Text('${row['item_kind'] ?? ''}')),
                    DataCell(Text(fmt(row['total_amount']))),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _EmployeeSummaryTable extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final String Function(dynamic) fmt;
  final AppLocalizations t;

  const _EmployeeSummaryTable({required this.items, required this.fmt, required this.t});

  @override
  Widget build(BuildContext context) {
    return PayrollUi.sectionCard(
      context: context,
      title: t.payrollEmployeeSummaryReport,
      icon: Icons.people_outline,
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            DataColumn(label: Text(t.payrollEmployeeCode)),
            DataColumn(label: Text(t.payrollEmployeesTab)),
            DataColumn(label: Text(t.payrollGrossTotal)),
            DataColumn(label: Text(t.payrollDeductionTotal)),
            DataColumn(label: Text(t.payrollNetTotal)),
          ],
          rows: items
              .map(
                (row) => DataRow(
                  cells: [
                    DataCell(Text('${row['employee_code'] ?? ''}')),
                    DataCell(Text('${row['person_name'] ?? ''}')),
                    DataCell(Text(fmt(row['gross_total']))),
                    DataCell(Text(fmt(row['deduction_total']))),
                    DataCell(Text(fmt(row['net_total']))),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _PeriodOverviewTable extends StatelessWidget {
  final List<Map<String, dynamic>> periods;
  final String Function(dynamic) fmt;
  final AppLocalizations t;
  final bool isJalali;

  const _PeriodOverviewTable({
    required this.periods,
    required this.fmt,
    required this.t,
    required this.isJalali,
  });

  @override
  Widget build(BuildContext context) {
    return PayrollUi.sectionCard(
      context: context,
      title: t.payrollPeriodOverviewReport,
      icon: Icons.calendar_view_month,
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            DataColumn(label: Text(t.payrollPeriod)),
            DataColumn(label: Text(t.payrollRunsTab)),
            DataColumn(label: Text(t.payrollGrossTotal)),
            DataColumn(label: Text(t.payrollNetTotal)),
          ],
          rows: periods
              .map(
                (row) => DataRow(
                  cells: [
                    DataCell(Text(PayrollCalendarUtils.periodTitle(row, isJalali))),
                    DataCell(Text('${row['run_count'] ?? 0}')),
                    DataCell(Text(fmt(row['gross_total']))),
                    DataCell(Text(fmt(row['net_total']))),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
