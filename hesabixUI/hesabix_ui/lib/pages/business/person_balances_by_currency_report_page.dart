import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/utils/number_formatters.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/core/hesabix_back.dart';

class PersonBalancesByCurrencyReportPage extends StatefulWidget {
  const PersonBalancesByCurrencyReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  final int businessId;
  final CalendarController calendarController;

  @override
  State<PersonBalancesByCurrencyReportPage> createState() =>
      _PersonBalancesByCurrencyReportPageState();
}

class _PersonBalancesByCurrencyReportPageState
    extends State<PersonBalancesByCurrencyReportPage> {
  int? _fiscalYearId;
  List<Map<String, dynamic>> _fiscalYears = [];
  Map<String, dynamic>? _summary;
  bool _onlyWithBalance = true;

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
      if (!mounted) return;
      setState(() {
        _fiscalYears = years;
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
    'only_with_balance': _onlyWithBalance,
  };

  String _amount(dynamic value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return formatWithThousands(amount, decimalPlaces: 2);
  }

  DataTableConfig<Map<String, dynamic>> _tableConfig() => DataTableConfig(
    endpoint:
        '/api/v1/persons/businesses/${widget.businessId}/reports/person-balances-by-currency',
    businessId: widget.businessId,
    title: 'مانده اشخاص به تفکیک ارز',
    reportModuleKey: 'person_balances_by_currency',
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
        'کد شخص',
        formatter: (item) => (item as Map)['person_code']?.toString() ?? '',
      ),
      TextColumn(
        'person_name',
        'نام شخص',
        formatter: (item) => (item as Map)['person_name']?.toString() ?? '',
      ),
      TextColumn(
        'currency_code',
        'ارز',
        formatter: (item) => (item as Map)['currency_code']?.toString() ?? '',
      ),
      NumberColumn(
        'balance',
        'مانده بومی',
        formatter: (item) => _amount((item as Map)['balance']),
      ),
      NumberColumn(
        'base_equivalent',
        'معادل پایه',
        formatter: (item) => _amount((item as Map)['base_equivalent']),
      ),
      CustomColumn(
        'status',
        'وضعیت',
        builder: (item, _) {
          final row = item as Map;
          final status = row['status']?.toString() ?? '';
          final balance = row['balance'] is num
              ? (row['balance'] as num).toDouble()
              : double.tryParse(row['balance']?.toString() ?? '') ?? 0;
          final color = balance > 0
              ? Colors.green[700]
              : balance < 0
              ? Colors.red[700]
              : Colors.grey;
          return Text(
            status,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          );
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
        title: const Text('مانده اشخاص به تفکیک ارز'),
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
                crossAxisAlignment: WrapCrossAlignment.center,
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
                            (item) => DropdownMenuItem<int>(
                              value: item['id'] as int?,
                              child: Text('${item['title'] ?? ''}'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _fiscalYearId = value),
                    ),
                  ),
                  FilterChip(
                    label: const Text('فقط اشخاص دارای مانده'),
                    selected: _onlyWithBalance,
                    onSelected: (value) =>
                        setState(() => _onlyWithBalance = value),
                  ),
                  const Chip(
                    avatar: Icon(Icons.currency_exchange_outlined, size: 18),
                    label: Text('مانده بومی هر ارز + معادل ارز پایه'),
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

  Widget _summaryCard() {
    final summary = _summary!;
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            _summaryValue('تعداد اشخاص', summary['person_count']),
            _summaryValue('جمع بدهکار (پایه)', summary['total_debtor_base']),
            _summaryValue(
              'جمع بستانکار (پایه)',
              summary['total_creditor_base'],
            ),
            _summaryValue('جمع کل (پایه)', summary['total_base']),
          ],
        ),
      ),
    );
  }

  Widget _summaryValue(String label, dynamic value) => Text(
    '$label: ${label == 'تعداد اشخاص' ? value ?? 0 : _amount(value)}',
    style: const TextStyle(fontWeight: FontWeight.w600),
  );
}
