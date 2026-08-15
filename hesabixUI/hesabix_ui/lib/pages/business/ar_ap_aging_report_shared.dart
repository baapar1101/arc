import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import 'package:hesabix_ui/utils/number_formatters.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/core/hesabix_back.dart';

enum AgingReportMode { ar, ap }

class ArApAgingReportPage extends StatefulWidget {
  const ArApAgingReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.mode,
  });

  final int businessId;
  final CalendarController calendarController;
  final AgingReportMode mode;

  @override
  State<ArApAgingReportPage> createState() => _ArApAgingReportPageState();
}

class _ArApAgingReportPageState extends State<ArApAgingReportPage> {
  final _minBalanceController = TextEditingController();
  DateTime? _asOf;
  int? _fiscalYearId;
  int? _currencyId;
  double? _minBalance;
  List<Map<String, dynamic>> _fiscalYears = [];
  List<Map<String, dynamic>> _currencies = [];
  Map<String, dynamic>? _summary;

  bool get _isAr => widget.mode == AgingReportMode.ar;
  String get _title => _isAr ? 'سن بدهی مشتریان' : 'سن بستانکاری تامین‌کنندگان';
  String get _endpoint =>
      '/api/v1/persons/businesses/${widget.businessId}/reports/${_isAr ? 'ar-aging' : 'ap-aging'}';

  @override
  void initState() {
    super.initState();
    _loadFilters();
  }

  @override
  void dispose() {
    _minBalanceController.dispose();
    super.dispose();
  }

  Future<void> _loadFilters() async {
    try {
      final results = await Future.wait([
        BusinessDashboardService(
          ApiClient(),
        ).listFiscalYears(widget.businessId),
        CurrencyService(
          ApiClient(),
        ).listBusinessCurrencies(businessId: widget.businessId),
      ]);
      if (!mounted) return;
      final years = results[0] as List<Map<String, dynamic>>;
      setState(() {
        _fiscalYears = years;
        _currencies = results[1] as List<Map<String, dynamic>>;
        final current = years.firstWhere(
          (item) => item['is_current'] == true,
          orElse: () => const <String, dynamic>{},
        );
        _fiscalYearId = current['id'] as int?;
      });
    } catch (_) {}
  }

  Map<String, dynamic> _params() => {
    if (_fiscalYearId != null) 'fiscal_year_id': _fiscalYearId,
    'currency_id': _currencyId,
    if (_asOf != null) 'as_of': _asOf!.toIso8601String().split('T').first,
    if (_minBalance != null) 'min_balance': _minBalance,
  };

  String _amount(dynamic value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse('$value') ?? 0;
    return formatWithThousands(amount, decimalPlaces: 2);
  }

  String _date(dynamic value) {
    final date = value is DateTime ? value : DateTime.tryParse('$value');
    return HesabixDateUtils.formatForDisplay(
      date,
      widget.calendarController.isJalali,
    );
  }

  DataTableConfig<Map<String, dynamic>> _tableConfig() => DataTableConfig(
    endpoint: _endpoint,
    businessId: widget.businessId,
    title: _title,
    reportModuleKey: _isAr ? 'ar_aging' : 'ap_aging',
    reportSubtype: 'list',
    showRowNumbers: true,
    defaultPageSize: 20,
    searchFields: const ['person_code', 'person_name'],
    additionalParams: _params(),
    onResponseData: (data) {
      final summary = data['summary'];
      if (mounted && summary is Map) {
        setState(() => _summary = Map<String, dynamic>.from(summary));
      }
    },
    columns: [
      TextColumn(
        'person_code',
        'کد',
        formatter: (i) => (i as Map)['person_code']?.toString() ?? '',
      ),
      TextColumn(
        'person_name',
        'نام طرف حساب',
        formatter: (i) => (i as Map)['person_name']?.toString() ?? '',
      ),
      NumberColumn(
        'outstanding',
        'مانده',
        formatter: (i) => _amount((i as Map)['outstanding']),
      ),
      NumberColumn(
        '0_30',
        '۰ تا ۳۰ روز',
        formatter: (i) => _amount((i as Map)['0_30']),
      ),
      NumberColumn(
        '31_60',
        '۳۱ تا ۶۰ روز',
        formatter: (i) => _amount((i as Map)['31_60']),
      ),
      NumberColumn(
        '61_90',
        '۶۱ تا ۹۰ روز',
        formatter: (i) => _amount((i as Map)['61_90']),
      ),
      NumberColumn(
        '91_120',
        '۹۱ تا ۱۲۰ روز',
        formatter: (i) => _amount((i as Map)['91_120']),
      ),
      NumberColumn(
        '120_plus',
        'بیش از ۱۲۰ روز',
        formatter: (i) => _amount((i as Map)['120_plus']),
      ),
      DateColumn(
        'last_transaction_date',
        'آخرین تراکنش',
        formatter: (i) => _date((i as Map)['last_transaction_date']),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
        title: Text(_title),
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
                  _fiscalYearDropdown(),
                  _currencyDropdown(),
                  SizedBox(
                    width: 200,
                    child: DateInputField(
                      labelText: 'تا تاریخ',
                      value: _asOf,
                      calendarController: widget.calendarController,
                      onChanged: (value) => setState(() => _asOf = value),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: TextFormField(
                      controller: _minBalanceController,
                      decoration: const InputDecoration(
                        labelText: 'حداقل مانده',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        const EnglishDigitsFormatter(),
                        FilteringTextInputFormatter.allow(RegExp(r'[\d,]')),
                        const ThousandsSeparatorInputFormatter(
                          allowDecimal: false,
                        ),
                      ],
                      onChanged: (value) => setState(
                        () => _minBalance = parseFormattedNumber(
                          value,
                        )?.toDouble(),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _asOf = null;
                      _minBalance = null;
                      _minBalanceController.clear();
                    }),
                    icon: const Icon(Icons.clear),
                    label: const Text('پاک کردن'),
                  ),
                ],
              ),
            ),
          ),
          if (_summary != null) _summaryCard(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: DataTableWidget<Map<String, dynamic>>(
                key: ValueKey(_params().toString()),
                config: _tableConfig(),
                fromJson: (json) => Map<String, dynamic>.from(json as Map),
                calendarController: widget.calendarController,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fiscalYearDropdown() => SizedBox(
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
      onChanged: (value) => setState(() => _fiscalYearId = value),
    ),
  );

  Widget _currencyDropdown() => SizedBox(
    width: 250,
    child: DropdownButtonFormField<int?>(
      value: _currencyId,
      decoration: const InputDecoration(
        labelText: 'ارز',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem(
          value: null,
          child: Text('همه ارزها (معادل پایه)'),
        ),
        ..._currencies.map(
          (item) => DropdownMenuItem<int?>(
            value: item['id'] as int?,
            child: Text('${item['title'] ?? item['code'] ?? ''}'),
          ),
        ),
      ],
      onChanged: (value) => setState(() => _currencyId = value),
    ),
  );

  Widget _summaryCard() {
    final values = _summary!;
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            _summaryValue(
              'جمع مانده',
              values['outstanding'] ?? values['total_outstanding'],
            ),
            _summaryValue('۰ تا ۳۰ روز', values['0_30']),
            _summaryValue('۳۱ تا ۶۰ روز', values['31_60']),
            _summaryValue('بیش از ۱۲۰ روز', values['120_plus']),
          ],
        ),
      ),
    );
  }

  Widget _summaryValue(String label, dynamic value) => Text(
    '$label: ${_amount(value)}',
    style: const TextStyle(fontWeight: FontWeight.w600),
  );
}
