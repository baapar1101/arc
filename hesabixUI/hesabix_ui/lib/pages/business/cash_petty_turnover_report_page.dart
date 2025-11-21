import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import 'package:hesabix_ui/services/cash_register_service.dart';
import 'package:hesabix_ui/services/petty_cash_service.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/data_table_utils.dart';
import 'package:hesabix_ui/core/date_utils.dart';

class CashPettyTurnoverReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  
  const CashPettyTurnoverReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<CashPettyTurnoverReportPage> createState() => _CashPettyTurnoverReportPageState();
}

class _CashPettyTurnoverReportPageState extends State<CashPettyTurnoverReportPage> {
  // Filters
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedFiscalYearId;
  int? _selectedCurrencyId;
  List<int>? _selectedCashRegisterIds;
  List<int>? _selectedPettyCashIds;
  
  // Data
  List<Map<String, dynamic>> _fiscalYears = [];
  List<Map<String, dynamic>> _currencies = [];
  List<Map<String, dynamic>> _cashRegisters = [];
  List<Map<String, dynamic>> _pettyCashList = [];

  @override
  void initState() {
    super.initState();
    _loadFiscalYears();
    _loadCurrencies();
    _loadCashRegisters();
    _loadPettyCash();
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

  Future<void> _loadCashRegisters() async {
    try {
      final svc = CashRegisterService();
      final response = await svc.list(
        businessId: widget.businessId,
        queryInfo: {'take': 1000, 'skip': 0},
      );
      if (!mounted) return;
      final items = (response['data']?['items'] ?? response['items'] ?? []) as List<dynamic>;
      setState(() {
        _cashRegisters = items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (_) {
      // ignore errors
    }
  }

  Future<void> _loadPettyCash() async {
    try {
      final svc = PettyCashService();
      final response = await svc.list(
        businessId: widget.businessId,
        queryInfo: {'take': 1000, 'skip': 0},
      );
      if (!mounted) return;
      final items = (response['data']?['items'] ?? response['items'] ?? []) as List<dynamic>;
      setState(() {
        _pettyCashList = items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (_) {
      // ignore errors
    }
  }

  void _refreshData() {
    // فقط باعث rebuild می‌شود تا DataTableWidget با پارامترهای جدید refresh شود
    // نیازی به setState نیست چون تغییرات state قبلاً انجام شده
  }

  Map<String, dynamic> _additionalParams() {
    return {
      if (_fromDate != null) 'date_from': _fromDate!.toIso8601String().split('T').first,
      if (_toDate != null) 'date_to': _toDate!.toIso8601String().split('T').first,
      if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
      if (_selectedCurrencyId != null) 'currency_id': _selectedCurrencyId,
      if (_selectedCashRegisterIds != null && _selectedCashRegisterIds!.isNotEmpty) 
        'cash_register_ids': _selectedCashRegisterIds,
      if (_selectedPettyCashIds != null && _selectedPettyCashIds!.isNotEmpty) 
        'petty_cash_ids': _selectedPettyCashIds,
    };
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  String _formatDate(dynamic value) {
    if (value == null) return '';
    return HesabixDateUtils.formatForDisplay(
      value is DateTime ? value : (value is String ? DateTime.tryParse(value) : null),
      widget.calendarController.isJalali,
    );
  }

  String _formatSourceType(dynamic value) {
    if (value == null) return '';
    final type = value.toString();
    if (type == 'cash_register') {
      return 'صندوق';
    } else if (type == 'petty_cash') {
      return 'تنخواه';
    }
    return type;
  }

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/cash-registers/businesses/${widget.businessId}/reports/cash-petty-turnover',
      businessId: widget.businessId,
      reportModuleKey: 'cash_petty_turnover',
      reportSubtype: 'list',
      title: t.reportsCashPettyTurnoverTitle,
      showRowNumbers: true,
      columns: [
        DateColumn(
          'document_date',
          'تاریخ',
          formatter: (item) => _formatDate((item as Map<String, dynamic>)['document_date']),
        ),
        TextColumn(
          'document_type_name',
          'نوع سند',
          formatter: (item) => (item as Map<String, dynamic>)['document_type_name']?.toString() ?? '',
        ),
        TextColumn(
          'document_code',
          'شماره سند',
          formatter: (item) => (item as Map<String, dynamic>)['document_code']?.toString() ?? '',
        ),
        TextColumn(
          'source_type',
          'نوع',
          formatter: (item) => _formatSourceType((item as Map<String, dynamic>)['source_type']),
        ),
        TextColumn(
          'source_code',
          'کد',
          formatter: (item) => (item as Map<String, dynamic>)['source_code']?.toString() ?? '',
        ),
        TextColumn(
          'source_name',
          'نام',
          formatter: (item) => (item as Map<String, dynamic>)['source_name']?.toString() ?? '',
        ),
        NumberColumn(
          'deposit',
          'واریز',
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['deposit']),
        ),
        NumberColumn(
          'withdrawal',
          'برداشت',
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['withdrawal']),
        ),
        NumberColumn(
          'balance',
          'مانده',
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['balance']),
        ),
        TextColumn(
          'description',
          'توضیحات',
          formatter: (item) => (item as Map<String, dynamic>)['description']?.toString() ?? '',
        ),
      ],
      searchFields: const ['document_code', 'source_code', 'source_name', 'description'],
      defaultPageSize: 20,
      additionalParams: _additionalParams(),
      showExportButtons: true,
      excelEndpoint: '/api/v1/cash-registers/businesses/${widget.businessId}/reports/cash-petty-turnover/export/excel',
      getExportParams: () => _additionalParams(),
      footerTotals: {
        'deposit': 'جمع واریز',
        'withdrawal': 'جمع برداشت',
        'balance': 'موجودی فعلی',
      },
    );
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
        title: Text(t.reportsCashPettyTurnoverTitle),
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
            margin: const EdgeInsets.all(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<int>(
                      value: _selectedFiscalYearId,
                      decoration: InputDecoration(
                        labelText: t.fiscalYear,
                        border: const OutlineInputBorder(),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      ),
                      items: _fiscalYears.map<DropdownMenuItem<int>>((fy) {
                        final id = fy['id'] as int?;
                        final title = (fy['title'] ?? '').toString();
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text(
                            title.isNotEmpty ? title : 'FY ${id ?? ''}',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedFiscalYearId = val;
                        });
                        _refreshData();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<int>(
                      value: _selectedCurrencyId,
                      decoration: InputDecoration(
                        labelText: t.currency,
                        border: const OutlineInputBorder(),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      ),
                      items: _currencies.map<DropdownMenuItem<int>>((c) {
                        final id = c['id'] as int?;
                        final code = (c['code'] ?? '').toString();
                        final title = (c['title'] ?? code).toString();
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text(
                            '$code - $title',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        );
                      }).toList(),
                      menuMaxHeight: 300,
                      onChanged: (val) {
                        setState(() {
                          _selectedCurrencyId = val;
                        });
                        _refreshData();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    child: Builder(
                      builder: (context) {
                        // ساخت Map برای نگهداری لیست‌های ساخته شده تا بتوانیم همان reference را استفاده کنیم
                        final cashRegisterValueMap = <int, List<int>>{};
                        for (final cr in _cashRegisters) {
                          final id = cr['id'] as int?;
                          if (id != null) {
                            cashRegisterValueMap[id] = [id];
                          }
                        }
                        
                        // پیدا کردن value مناسب برای dropdown
                        List<int>? currentValue;
                        if (_selectedCashRegisterIds != null && _selectedCashRegisterIds!.isNotEmpty) {
                          final selectedId = _selectedCashRegisterIds!.first;
                          currentValue = cashRegisterValueMap[selectedId];
                        }
                        
                        return DropdownButtonFormField<List<int>>(
                          value: currentValue,
                          decoration: InputDecoration(
                            labelText: 'صندوق‌ها',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          ),
                          hint: const Text('همه صندوق‌ها'),
                          items: [
                            const DropdownMenuItem<List<int>>(
                              value: null,
                              child: Text('همه صندوق‌ها'),
                            ),
                            ..._cashRegisters.map<DropdownMenuItem<List<int>>>((cr) {
                              final id = cr['id'] as int?;
                              if (id == null) return const DropdownMenuItem<List<int>>(value: null, child: SizedBox.shrink());
                              final code = (cr['code'] ?? '').toString();
                              final name = (cr['name'] ?? '').toString();
                              final displayName = code.isNotEmpty ? '$code - $name' : name;
                              // استفاده از همان reference که در Map ذخیره شده
                              return DropdownMenuItem<List<int>>(
                                key: ValueKey('cash_register_$id'),
                                value: cashRegisterValueMap[id]!,
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
                              _selectedCashRegisterIds = val;
                            });
                            _refreshData();
                          },
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    child: Builder(
                      builder: (context) {
                        // ساخت Map برای نگهداری لیست‌های ساخته شده تا بتوانیم همان reference را استفاده کنیم
                        final pettyCashValueMap = <int, List<int>>{};
                        for (final pc in _pettyCashList) {
                          final id = pc['id'] as int?;
                          if (id != null) {
                            pettyCashValueMap[id] = [id];
                          }
                        }
                        
                        // پیدا کردن value مناسب برای dropdown
                        List<int>? currentValue;
                        if (_selectedPettyCashIds != null && _selectedPettyCashIds!.isNotEmpty) {
                          final selectedId = _selectedPettyCashIds!.first;
                          currentValue = pettyCashValueMap[selectedId];
                        }
                        
                        return DropdownButtonFormField<List<int>>(
                          value: currentValue,
                          decoration: InputDecoration(
                            labelText: 'تنخواه‌ها',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          ),
                          hint: const Text('همه تنخواه‌ها'),
                          items: [
                            const DropdownMenuItem<List<int>>(
                              value: null,
                              child: Text('همه تنخواه‌ها'),
                            ),
                            ..._pettyCashList.map<DropdownMenuItem<List<int>>>((pc) {
                              final id = pc['id'] as int?;
                              if (id == null) return const DropdownMenuItem<List<int>>(value: null, child: SizedBox.shrink());
                              final code = (pc['code'] ?? '').toString();
                              final name = (pc['name'] ?? '').toString();
                              final displayName = code.isNotEmpty ? '$code - $name' : name;
                              // استفاده از همان reference که در Map ذخیره شده
                              return DropdownMenuItem<List<int>>(
                                key: ValueKey('petty_cash_$id'),
                                value: pettyCashValueMap[id]!,
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
                              _selectedPettyCashIds = val;
                            });
                            _refreshData();
                          },
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: DateInputField(
                      labelText: t.dateFrom,
                      value: _fromDate,
                      onChanged: (d) {
                        setState(() => _fromDate = d);
                        _refreshData();
                      },
                      calendarController: widget.calendarController,
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: DateInputField(
                      labelText: t.dateTo,
                      value: _toDate,
                      onChanged: (d) {
                        setState(() => _toDate = d);
                        _refreshData();
                      },
                      calendarController: widget.calendarController,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _fromDate = null;
                        _toDate = null;
                        _selectedCashRegisterIds = null;
                        _selectedPettyCashIds = null;
                      });
                      _refreshData();
                    },
                    icon: const Icon(Icons.clear),
                    label: Text(t.clear),
                  ),
                ],
              ),
            ),
          ),
          // Table
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: DataTableWidget<Map<String, dynamic>>(
                key: ValueKey({
                  'fiscal_year': _selectedFiscalYearId,
                  'currency': _selectedCurrencyId,
                  'cash_registers': _selectedCashRegisterIds?.join(',') ?? '',
                  'petty_cash': _selectedPettyCashIds?.join(',') ?? '',
                  'from_date': _fromDate?.toIso8601String() ?? '',
                  'to_date': _toDate?.toIso8601String() ?? '',
                }.toString()),
                config: _buildTableConfig(t),
                fromJson: (json) => Map<String, dynamic>.from(json as Map),
                calendarController: widget.calendarController,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

