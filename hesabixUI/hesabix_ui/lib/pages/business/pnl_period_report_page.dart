import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/data_table_utils.dart';

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
  // Filters
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedFiscalYearId;
  int? _selectedCurrencyId;
  
  // Data
  List<Map<String, dynamic>> _fiscalYears = [];
  List<Map<String, dynamic>> _currencies = [];
  
  // Report data
  List<Map<String, dynamic>> _revenueItems = [];
  List<Map<String, dynamic>> _expenseItems = [];
  Map<String, dynamic>? _summary;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFiscalYears();
    _loadCurrencies();
    _fetchData();
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
      // ignore errors
    }
  }

  Future<void> _loadCurrencies() async {
    try {
      final svc = CurrencyService(ApiClient());
      final items = await svc.listBusinessCurrencies(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _currencies = items;
        // انتخاب ارز پیش‌فرض
        if (items.isNotEmpty) {
          final defaultCurrency = items.firstWhere(
            (c) => c['is_default'] == true,
            orElse: () => items.first,
          );
          _selectedCurrencyId = defaultCurrency['id'] as int?;
        }
      });
    } catch (_) {
      // ignore errors
    }
  }

  Future<void> _fetchData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ApiClient();
      final requestData = <String, dynamic>{
        if (_fromDate != null) 'date_from': _fromDate!.toIso8601String().split('T').first,
        if (_toDate != null) 'date_to': _toDate!.toIso8601String().split('T').first,
        if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
        if (_selectedCurrencyId != null) 'currency_id': _selectedCurrencyId,
      };
      
      final res = await api.post<Map<String, dynamic>>(
        '/api/v1/businesses/${widget.businessId}/reports/pnl-period',
        data: requestData,
      );
      
      final body = res.data;
      if (body is Map<String, dynamic> && body['data'] is Map<String, dynamic>) {
        final data = body['data'] as Map<String, dynamic>;
        
        if (mounted) {
          setState(() {
            _revenueItems = List<Map<String, dynamic>>.from(data['revenue_items'] ?? []);
            _expenseItems = List<Map<String, dynamic>>.from(data['expense_items'] ?? []);
            _summary = data['summary'] as Map<String, dynamic>?;
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  void _refreshData() {
    _fetchData();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(t.reportsPnlPeriodTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t.refresh,
            onPressed: _refreshData,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  // Fiscal Year
                  SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<int>(
                      value: _selectedFiscalYearId,
                      decoration: InputDecoration(
                        labelText: 'سال مالی',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      ),
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
                        setState(() {
                          _selectedFiscalYearId = value;
                        });
                        _refreshData();
                      },
                    ),
                  ),
                  
                  // Date From
                  SizedBox(
                    width: 180,
                    child: DateInputField(
                      value: _fromDate,
                      calendarController: widget.calendarController,
                      onChanged: (date) {
                        setState(() {
                          _fromDate = date;
                        });
                        _refreshData();
                      },
                    ),
                  ),
                  
                  // Date To
                  SizedBox(
                    width: 180,
                    child: DateInputField(
                      value: _toDate,
                      calendarController: widget.calendarController,
                      onChanged: (date) {
                        setState(() {
                          _toDate = date;
                        });
                        _refreshData();
                      },
                    ),
                  ),
                  
                  // Currency
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<int>(
                      value: _selectedCurrencyId,
                      decoration: InputDecoration(
                        labelText: 'ارز',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      ),
                      items: [
                        const DropdownMenuItem<int>(
                          value: null,
                          child: Text('همه ارزها'),
                        ),
                        ..._currencies.map<DropdownMenuItem<int>>((c) {
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
                        }).toList(),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedCurrencyId = val;
                        });
                        _refreshData();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Summary Cards
          if (_summary != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Card(
                      color: Colors.green.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'جمع درآمد',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatNumber(_summary!['total_revenue']),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'جمع هزینه',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatNumber(_summary!['total_expense']),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Card(
                      color: ((_summary!['net_profit_loss'] as num?)?.toDouble() ?? 0) >= 0
                          ? Colors.blue.shade50
                          : Colors.orange.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'سود/زیان خالص',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatNumber(_summary!['net_profit_loss']),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: ((_summary!['net_profit_loss'] as num?)?.toDouble() ?? 0) >= 0
                                    ? Colors.blue
                                    : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          // Data Tables
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('خطا: $_error', style: TextStyle(color: cs.error)))
                    : DefaultTabController(
                        length: 2,
                        child: Column(
                          children: [
                            TabBar(
                              tabs: [
                                Tab(text: 'درآمدها (${_revenueItems.length})'),
                                Tab(text: 'هزینه‌ها (${_expenseItems.length})'),
                              ],
                            ),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  _buildRevenueTable(),
                                  _buildExpenseTable(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueTable() {
    if (_revenueItems.isEmpty) {
      return const Center(child: Text('هیچ درآمدی یافت نشد'));
    }
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 24,
          columns: const [
            DataColumn(label: Text('کد حساب')),
            DataColumn(label: Text('نام حساب')),
            DataColumn(label: Text('گردش بستانکار', textAlign: TextAlign.center)),
            DataColumn(label: Text('گردش بدهکار', textAlign: TextAlign.center)),
            DataColumn(label: Text('درآمد خالص', textAlign: TextAlign.center)),
          ],
          rows: [
            ..._revenueItems.map((item) {
              return DataRow(
                cells: [
                  DataCell(Text(item['account_code']?.toString() ?? '')),
                  DataCell(Text(item['account_name']?.toString() ?? '')),
                  DataCell(Text(_formatNumber(item['credit']), textAlign: TextAlign.center)),
                  DataCell(Text(_formatNumber(item['debit']), textAlign: TextAlign.center)),
                  DataCell(Text(_formatNumber(item['revenue']), textAlign: TextAlign.center)),
                ],
              );
            }),
            DataRow(
              color: WidgetStateProperty.all(Colors.grey.shade100),
              cells: [
                const DataCell(Text('', style: TextStyle(fontWeight: FontWeight.bold))),
                const DataCell(Text('جمع', style: TextStyle(fontWeight: FontWeight.bold))),
                DataCell(Text(
                  _formatNumber(_summary?['total_revenue']),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                )),
                const DataCell(Text('', style: TextStyle(fontWeight: FontWeight.bold))),
                DataCell(Text(
                  _formatNumber(_summary?['total_revenue']),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseTable() {
    if (_expenseItems.isEmpty) {
      return const Center(child: Text('هیچ هزینه‌ای یافت نشد'));
    }
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 24,
          columns: const [
            DataColumn(label: Text('کد حساب')),
            DataColumn(label: Text('نام حساب')),
            DataColumn(label: Text('گردش بدهکار', textAlign: TextAlign.center)),
            DataColumn(label: Text('گردش بستانکار', textAlign: TextAlign.center)),
            DataColumn(label: Text('هزینه خالص', textAlign: TextAlign.center)),
          ],
          rows: [
            ..._expenseItems.map((item) {
              return DataRow(
                cells: [
                  DataCell(Text(item['account_code']?.toString() ?? '')),
                  DataCell(Text(item['account_name']?.toString() ?? '')),
                  DataCell(Text(_formatNumber(item['debit']), textAlign: TextAlign.center)),
                  DataCell(Text(_formatNumber(item['credit']), textAlign: TextAlign.center)),
                  DataCell(Text(_formatNumber(item['expense']), textAlign: TextAlign.center)),
                ],
              );
            }),
            DataRow(
              color: WidgetStateProperty.all(Colors.grey.shade100),
              cells: [
                const DataCell(Text('', style: TextStyle(fontWeight: FontWeight.bold))),
                const DataCell(Text('جمع', style: TextStyle(fontWeight: FontWeight.bold))),
                DataCell(Text(
                  _formatNumber(_summary?['total_expense']),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                )),
                const DataCell(Text('', style: TextStyle(fontWeight: FontWeight.bold))),
                DataCell(Text(
                  _formatNumber(_summary?['total_expense']),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

