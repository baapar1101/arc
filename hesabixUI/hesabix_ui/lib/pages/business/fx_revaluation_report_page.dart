import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/fiscal_year_controller.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/utils/number_formatters.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/core/hesabix_back.dart';

class FxRevaluationReportPage extends StatefulWidget {
  const FxRevaluationReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  final int businessId;
  final CalendarController calendarController;

  @override
  State<FxRevaluationReportPage> createState() =>
      _FxRevaluationReportPageState();
}

class _FxRevaluationReportPageState extends State<FxRevaluationReportPage> {
  int? _fiscalYearId;
  DateTime? _fromDate;
  DateTime? _toDate;
  List<Map<String, dynamic>> _fiscalYears = [];
  Map<String, dynamic>? _summary;
  dynamic _preview;

  @override
  void initState() {
    super.initState();
    _loadFiscalYears();
  }

  Future<void> _loadFiscalYears() async {
    try {
      final years = await BusinessDashboardService(
        ApiClient(),
      ).listFiscalYears(widget.businessId);
      final defaultFyId = await FiscalYearController.resolveDefaultId(widget.businessId, years);
      if (!mounted) return;
      setState(() {
        _fiscalYears = years;
        _fiscalYearId = defaultFyId;
      });
    } catch (_) {}
  }

  Map<String, dynamic> _params() => {
    if (_fiscalYearId != null) 'fiscal_year_id': _fiscalYearId,
    if (_fromDate != null)
      'date_from': _fromDate!.toIso8601String().split('T').first,
    if (_toDate != null) 'date_to': _toDate!.toIso8601String().split('T').first,
  };

  String _amount(dynamic value) {
    final n = value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    return formatWithThousands(n, decimalPlaces: 2);
  }

  String _date(dynamic value) {
    final date = value is DateTime ? value : DateTime.tryParse('$value');
    return HesabixDateUtils.formatForDisplay(
      date,
      widget.calendarController.isJalali,
    );
  }

  DataTableConfig<Map<String, dynamic>> _config() => DataTableConfig(
    endpoint: '/api/v1/businesses/${widget.businessId}/reports/fx-revaluation',
    businessId: widget.businessId,
    title: 'گزارش تسعیر ارز',
    reportModuleKey: 'fx_revaluation',
    reportSubtype: 'list',
    showRowNumbers: true,
    defaultPageSize: 20,
    additionalParams: _params(),
    onResponseData: (data) {
      if (!mounted) return;
      setState(() {
        _summary = data['summary'] is Map
            ? Map<String, dynamic>.from(data['summary'] as Map)
            : null;
        _preview = data['preview'];
      });
    },
    columns: [
      TextColumn(
        'document_code',
        'شماره سند',
        formatter: (i) => (i as Map)['document_code']?.toString() ?? '',
      ),
      DateColumn(
        'document_date',
        'تاریخ سند',
        formatter: (i) => _date((i as Map)['document_date']),
      ),
      TextColumn(
        'description',
        'شرح',
        formatter: (i) => (i as Map)['description']?.toString() ?? '',
      ),
      NumberColumn(
        'fx_gain',
        'سود تسعیر',
        formatter: (i) => _amount((i as Map)['fx_gain']),
      ),
      NumberColumn(
        'fx_loss',
        'زیان تسعیر',
        formatter: (i) => _amount((i as Map)['fx_loss']),
      ),
      NumberColumn(
        'net_fx',
        'خالص تسعیر',
        formatter: (i) => _amount((i as Map)['net_fx']),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
        title: const Text('گزارش تسعیر ارز'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<int>(
                      value: _fiscalYearId,
                      decoration: const InputDecoration(
                        labelText: 'سال مالی',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _fiscalYears
                          .map(
                            (item) => DropdownMenuItem(
                              value: item['id'] as int?,
                              child: Text('${item['title'] ?? ''}'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _fiscalYearId = value),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: DateInputField(
                      labelText: 'از تاریخ',
                      value: _fromDate,
                      calendarController: widget.calendarController,
                      onChanged: (value) => setState(() => _fromDate = value),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: DateInputField(
                      labelText: 'تا تاریخ',
                      value: _toDate,
                      calendarController: widget.calendarController,
                      onChanged: (value) => setState(() => _toDate = value),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.assessment_outlined),
                    label: const Text('نمایش گزارش'),
                  ),
                ],
              ),
            ),
          ),
          if (_summary != null) _summaryPanel(),
          if (_preview != null) _previewPanel(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: DataTableWidget<Map<String, dynamic>>(
                key: ValueKey(_params().toString()),
                config: _config(),
                fromJson: (json) => Map<String, dynamic>.from(json as Map),
                calendarController: widget.calendarController,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryPanel() => Card(
    margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 24,
        children: [
          Text(
            'جمع سود تسعیر: ${_amount(_summary!['fx_gain'] ?? _summary!['total_fx_gain'])}',
          ),
          Text(
            'جمع زیان تسعیر: ${_amount(_summary!['fx_loss'] ?? _summary!['total_fx_loss'])}',
          ),
          Text(
            'خالص تسعیر: ${_amount(_summary!['net_fx'] ?? _summary!['total_net_fx'])}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );

  Widget _previewPanel() => Card(
    margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
    child: ListTile(
      leading: const Icon(Icons.visibility_outlined),
      title: const Text('پیش‌نمایش تسعیر'),
      subtitle: Text(
        _preview is Map
            ? 'اطلاعات پیش‌نمایش برای دوره انتخاب‌شده آماده است.'
            : 'پیش‌نمایش محاسبات تسعیر',
      ),
    ),
  );
}
