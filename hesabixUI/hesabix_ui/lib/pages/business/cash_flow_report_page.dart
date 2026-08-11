import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/number_formatters.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/fx/fx_data_quality_banner.dart';
import 'package:hesabix_ui/widgets/fx/report_currency_filter_dropdown.dart';

class CashFlowReportPage extends StatefulWidget {
  const CashFlowReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  final int businessId;
  final CalendarController calendarController;

  @override
  State<CashFlowReportPage> createState() => _CashFlowReportPageState();
}

class _CashFlowReportPageState extends State<CashFlowReportPage> {
  int? _fiscalYearId;
  int? _currencyId;
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _showIndirect = true;
  List<Map<String, dynamic>> _fiscalYears = [];
  List<Map<String, dynamic>> _currencies = [];
  Map<String, dynamic>? _data;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFilters();
  }

  Future<void> _loadFilters() async {
    try {
      final values = await Future.wait([
        BusinessDashboardService(
          ApiClient(),
        ).listFiscalYears(widget.businessId),
        CurrencyService(
          ApiClient(),
        ).listBusinessCurrencies(businessId: widget.businessId),
      ]);
      if (!mounted) return;
      final years = values[0] as List<Map<String, dynamic>>;
      setState(() {
        _fiscalYears = years;
        _currencies = values[1] as List<Map<String, dynamic>>;
        _fiscalYearId =
            years.firstWhere(
                  (item) => item['is_current'] == true,
                  orElse: () => const <String, dynamic>{},
                )['id']
                as int?;
      });
      _fetch();
    } catch (_) {}
  }

  Map<String, dynamic> _body() => {
        if (_fiscalYearId != null) 'fiscal_year_id': _fiscalYearId,
        'currency_id': _currencyId,
        if (_fromDate != null)
          'date_from': _fromDate!.toIso8601String().split('T').first,
        if (_toDate != null)
          'date_to': _toDate!.toIso8601String().split('T').first,
        'include_indirect': _showIndirect,
      };

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ApiClient().post<Map<String, dynamic>>(
        '/api/v1/businesses/${widget.businessId}/reports/cash-flow',
        data: _body(),
      );
      final payload = response.data?['data'];
      if (!mounted) return;
      setState(
        () =>
            _data = payload is Map ? Map<String, dynamic>.from(payload) : null,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = ErrorExtractor.forContext(error, context));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _number(dynamic value) {
    final n = value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    return formatWithThousands(n, decimalPlaces: 2);
  }

  Map<String, dynamic>? get _fxQuality {
    final meta = _data?['meta'];
    if (meta is! Map) return null;
    final q = meta['fx_data_quality'];
    return q is Map ? Map<String, dynamic>.from(q) : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: context.pop,
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('صورت جریان وجوه نقد'),
            Text(
              'روش مستقیم + غیرمستقیم (IAS 7)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _fetch,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _filters(),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _errorCard()
            else if (_data != null) ...[
              if (_fxQuality != null) ...[
                FxDataQualityBanner(quality: _fxQuality),
                const SizedBox(height: 12),
              ],
              _summary(),
              const SizedBox(height: 12),
              _sections(),
              if (_showIndirect) ...[
                const SizedBox(height: 12),
                _indirect(),
              ],
              _documents(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filters() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 250,
                child: DropdownButtonFormField<int>(
                  value: _fiscalYearId,
                  decoration: const InputDecoration(
                    labelText: 'سال مالی',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _fiscalYears
                      .map(
                        (i) => DropdownMenuItem(
                          value: i['id'] as int?,
                          child: Text('${i['title'] ?? ''}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _fiscalYearId = v),
                ),
              ),
              if (_currencies.length > 1)
                ReportCurrencyFilterDropdown(
                  businessId: widget.businessId,
                  isMultiCurrency: true,
                  selectedCurrencyId: _currencyId,
                  width: 250,
                  onChanged: (v) => setState(() => _currencyId = v),
                ),
              SizedBox(
                width: 200,
                child: DateInputField(
                  labelText: 'از تاریخ',
                  value: _fromDate,
                  calendarController: widget.calendarController,
                  onChanged: (v) => setState(() => _fromDate = v),
                ),
              ),
              SizedBox(
                width: 200,
                child: DateInputField(
                  labelText: 'تا تاریخ',
                  value: _toDate,
                  calendarController: widget.calendarController,
                  onChanged: (v) => setState(() => _toDate = v),
                ),
              ),
              FilterChip(
                label: const Text('روش غیرمستقیم'),
                selected: _showIndirect,
                onSelected: (v) => setState(() => _showIndirect = v),
              ),
              FilledButton.icon(
                onPressed: _loading ? null : _fetch,
                icon: const Icon(Icons.assessment_outlined),
                label: const Text('نمایش گزارش'),
              ),
            ],
          ),
        ),
      );

  Widget _summary() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              _metric('مانده ابتدای دوره', _data!['opening_cash']),
              _metric('تغییر خالص نقد', _data!['net_change']),
              _metric('مانده پایان دوره', _data!['closing_cash']),
            ],
          ),
        ),
      );

  Widget _sections() {
    final sections = _data!['sections'] is Map
        ? Map<String, dynamic>.from(_data!['sections'] as Map)
        : <String, dynamic>{};
    const labels = {
      'operating': 'فعالیت‌های عملیاتی (روش مستقیم)',
      'investing': 'فعالیت‌های سرمایه‌گذاری (IAS 7)',
      'financing': 'فعالیت‌های تأمین مالی (IAS 7)',
      'transfers': 'انتقالات',
      'fx_and_other': 'تسعیر و سایر',
    };
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ListTile(
            title: Text(
              'روش مستقیم — گردش نقد بر اساس طرف مقابل',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          ...labels.entries.map((entry) {
            final item = sections[entry.key] is Map
                ? sections[entry.key] as Map
                : const <String, dynamic>{};
            return ListTile(
              title: Text(entry.value),
              subtitle: Text(
                'ورودی: ${_number(item['inflows'])}  •  خروجی: ${_number(item['outflows'])}',
              ),
              trailing: Text(
                _number(item['net']),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _indirect() {
    final ind = _data!['indirect_operating'];
    if (ind is! Map) return const SizedBox.shrink();
    final lines = ind['lines'] is List ? ind['lines'] as List : const [];
    final bridge = ind['bridge_difference'];
    final note = (ind['note_fa'] ?? '').toString();

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ListTile(
            title: Text(
              'روش غیرمستقیم — از سود خالص به جریان عملیاتی',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text('IAS 7 · تعدیل سرمایه در گردش و استهلاک'),
          ),
          ...lines.map((raw) {
            final row = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
            return ListTile(
              dense: true,
              title: Text('${row['label_fa'] ?? row['key'] ?? ''}'),
              trailing: Text(
                _number(row['amount']),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            );
          }),
          const Divider(height: 1),
          ListTile(
            title: const Text(
              'جریان نقد عملیاتی (غیرمستقیم)',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            trailing: Text(
              _number(ind['operating_cash_flow']),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          ListTile(
            dense: true,
            title: const Text('اختلاف با روش مستقیم (bridge)'),
            subtitle: note.isEmpty ? null : Text(note, style: const TextStyle(fontSize: 11)),
            trailing: Text(
              _number(bridge),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _documents() {
    final docs = _data!['by_document_type'] is List
        ? _data!['by_document_type'] as List
        : const [];
    if (docs.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          const ListTile(
            title: Text(
              'گردش بر اساس نوع سند',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          ...docs.map((item) {
            final row = item as Map;
            return ListTile(
              title: Text(
                '${row['document_type_title'] ?? row['document_type'] ?? '-'}',
              ),
              trailing: Text(
                _number(row['net']),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _metric(String label, dynamic value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 4),
          Text(
            _number(value),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ],
      );

  Widget _errorCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.error_outline),
              const SizedBox(height: 8),
              Text(_error ?? 'خطا در دریافت گزارش'),
              TextButton(onPressed: _fetch, child: const Text('تلاش مجدد')),
            ],
          ),
        ),
      );
}
