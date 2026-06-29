import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../services/payroll_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';

/// گزارش‌های پیشرفته حقوق و دستمزد (فاز ۴).
class PayrollReportsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const PayrollReportsPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<PayrollReportsPage> createState() => _PayrollReportsPageState();
}

class _PayrollReportsPageState extends State<PayrollReportsPage> {
  final PayrollService _svc = PayrollService();
  final NumberFormat _money = NumberFormat('#,###');

  bool _loading = true;
  bool _loadingReports = false;
  List<Map<String, dynamic>> _periods = [];
  int? _selectedPeriodId;
  int? _selectedYear;
  Map<String, dynamic>? _itemSummary;
  Map<String, dynamic>? _employeeSummary;
  Map<String, dynamic>? _statutorySummary;
  Map<String, dynamic>? _periodOverview;

  @override
  void initState() {
    super.initState();
    _loadPeriods();
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
        year = (first['year'] as num?)?.toInt();
        periodId = (first['id'] as num?)?.toInt();
      }
      setState(() {
        _periods = list;
        _selectedYear = year ?? DateTime.now().year;
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
          year: _selectedYear,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _itemSummary = Map<String, dynamic>.from(results[0] as Map);
        _employeeSummary = Map<String, dynamic>.from(results[1] as Map);
        _statutorySummary = Map<String, dynamic>.from(results[2] as Map);
        _periodOverview = Map<String, dynamic>.from(results[3] as Map);
        _loadingReports = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingReports = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  String _periodLabel(Map<String, dynamic> p) {
    final title = '${p['title'] ?? ''}'.trim();
    if (title.isNotEmpty) return title;
    return '${p['year']}/${p['month']}';
  }

  String _fmt(dynamic v) => _money.format((v as num?)?.toDouble() ?? 0);

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
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.payrollReportsFilters, style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 12),
                        if (_periods.isNotEmpty)
                          DropdownButtonFormField<int>(
                            value: _selectedPeriodId,
                            decoration: InputDecoration(labelText: t.payrollPeriod),
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
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          value: _selectedYear,
                          decoration: InputDecoration(labelText: t.payrollPeriodYear),
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
                ),
                if (_loadingReports) const LinearProgressIndicator(),
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
                  ),
                ],
              ],
            ),
    );
  }

  List<int> _availableYears() {
    final years = _periods.map((p) => (p['year'] as num?)?.toInt()).whereType<int>().toSet().toList()
      ..sort();
    if (years.isEmpty) {
      final y = DateTime.now().year;
      return [y - 1, y, y + 1];
    }
    return years;
  }
}

class _StatutoryCard extends StatelessWidget {
  final Map<String, dynamic> summary;
  final String Function(dynamic) fmt;
  final AppLocalizations t;

  const _StatutoryCard({required this.summary, required this.fmt, required this.t});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _row(t.payrollGrossTotal, fmt(summary['gross_earnings_total'])),
            _row(t.payrollInsuranceEmployee, fmt(summary['insurance_employee_total'])),
            _row(t.payrollInsuranceEmployer, fmt(summary['insurance_employer_total'])),
            _row(t.payrollTaxTotal, fmt(summary['tax_total'])),
          ],
        ),
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
    return Card(
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
    return Card(
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

  const _PeriodOverviewTable({required this.periods, required this.fmt, required this.t});

  @override
  Widget build(BuildContext context) {
    return Card(
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
                    DataCell(Text('${row['title'] ?? '${row['year']}/${row['month']}'}')),
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
