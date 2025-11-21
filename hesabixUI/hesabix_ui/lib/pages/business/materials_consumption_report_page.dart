import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/services/warehouse_service.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/data_table_utils.dart';
import 'package:hesabix_ui/widgets/invoice/product_combobox_widget.dart';
import 'package:hesabix_ui/models/warehouse_model.dart';
import 'package:hesabix_ui/core/date_utils.dart';

class MaterialsConsumptionReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  
  const MaterialsConsumptionReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<MaterialsConsumptionReportPage> createState() => _MaterialsConsumptionReportPageState();
}

class _MaterialsConsumptionReportPageState extends State<MaterialsConsumptionReportPage> {
  // Filters
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedFiscalYearId;
  int? _selectedCurrencyId;
  int? _selectedWarehouseId;
  Map<String, dynamic>? _selectedProduct;
  
  // Data
  List<Map<String, dynamic>> _fiscalYears = [];
  List<Map<String, dynamic>> _currencies = [];
  List<Warehouse> _warehouses = [];

  @override
  void initState() {
    super.initState();
    _loadFiscalYears();
    _loadCurrencies();
    _loadWarehouses();
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

  Future<void> _loadWarehouses() async {
    try {
      final svc = WarehouseService();
      final items = await svc.listWarehouses(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _warehouses = items;
      });
    } catch (_) {
      // ignore errors
    }
  }

  void _refreshData() {
    if (mounted) {
      setState(() {});
    }
  }

  Map<String, dynamic> _additionalParams() {
    return {
      if (_fromDate != null) 'date_from': _fromDate!.toIso8601String().split('T').first,
      if (_toDate != null) 'date_to': _toDate!.toIso8601String().split('T').first,
      if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
      if (_selectedCurrencyId != null) 'currency_id': _selectedCurrencyId,
      if (_selectedWarehouseId != null) 'warehouse_id': _selectedWarehouseId,
      if (_selectedProduct != null && _selectedProduct!['id'] != null) 'product_id': _selectedProduct!['id'],
    };
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/businesses/${widget.businessId}/reports/materials-consumption',
      businessId: widget.businessId,
      reportModuleKey: 'materials_consumption',
      reportSubtype: 'list',
      title: t.reportsMaterialsConsumptionTitle,
      showRowNumbers: true,
      columns: [
        DateColumn(
          'document_date',
          'تاریخ سند',
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            final date = m['document_date'];
            if (date == null) return '';
            DateTime? dateObj;
            if (date is DateTime) {
              dateObj = date;
            } else if (date is String) {
              dateObj = DateTime.tryParse(date);
            }
            if (dateObj == null) return date.toString();
            return HesabixDateUtils.formatForDisplay(
              dateObj,
              widget.calendarController.isJalali,
            );
          },
        ),
        TextColumn(
          'document_code',
          'کد سند',
          formatter: (item) => (item as Map<String, dynamic>)['document_code']?.toString() ?? '',
        ),
        TextColumn(
          'product_code',
          'کد کالا',
          formatter: (item) => (item as Map<String, dynamic>)['product_code']?.toString() ?? '',
        ),
        TextColumn(
          'product_name',
          'نام کالا',
          formatter: (item) => (item as Map<String, dynamic>)['product_name']?.toString() ?? '',
        ),
        TextColumn(
          'warehouse_code',
          'کد انبار',
          formatter: (item) => (item as Map<String, dynamic>)['warehouse_code']?.toString() ?? '',
        ),
        TextColumn(
          'warehouse_name',
          'نام انبار',
          formatter: (item) => (item as Map<String, dynamic>)['warehouse_name']?.toString() ?? '',
        ),
        NumberColumn(
          'quantity',
          'مقدار',
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['quantity']),
        ),
        TextColumn(
          'product_unit',
          'واحد',
          formatter: (item) => (item as Map<String, dynamic>)['product_unit']?.toString() ?? '',
        ),
        NumberColumn(
          'unit_price',
          'قیمت واحد',
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['unit_price']),
        ),
        NumberColumn(
          'amount',
          'مبلغ',
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['amount']),
        ),
        TextColumn(
          'description',
          'توضیحات',
          formatter: (item) => (item as Map<String, dynamic>)['description']?.toString() ?? '',
        ),
      ],
      searchFields: const ['document_code', 'product_code', 'product_name'],
      defaultPageSize: 50,
      additionalParams: _additionalParams(),
      showExportButtons: true,
      excelEndpoint: '/api/v1/businesses/${widget.businessId}/reports/materials-consumption/export/excel',
      getExportParams: () => _additionalParams(),
      footerTotals: {
        'quantity': 'جمع مقدار',
        'amount': 'جمع مبلغ',
      },
      defaultSortBy: 'document_date',
      defaultSortDesc: true,
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
        title: Text(t.reportsMaterialsConsumptionTitle),
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
                  
                  // Warehouse
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<int>(
                      value: _selectedWarehouseId,
                      decoration: InputDecoration(
                        labelText: 'انبار',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      ),
                      items: [
                        const DropdownMenuItem<int>(
                          value: null,
                          child: Text('همه انبارها'),
                        ),
                        ..._warehouses.map((wh) {
                          return DropdownMenuItem<int>(
                            value: wh.id,
                            child: Text(
                              '${wh.code} - ${wh.name}',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedWarehouseId = value;
                        });
                        _refreshData();
                      },
                    ),
                  ),
                  
                  // Product
                  SizedBox(
                    width: 300,
                    child: ProductComboboxWidget(
                      businessId: widget.businessId,
                      selectedProduct: _selectedProduct,
                      onChanged: (product) {
                        setState(() {
                          _selectedProduct = product;
                        });
                        _refreshData();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Data Table
          Expanded(
            child: DataTableWidget<Map<String, dynamic>>(
              key: ValueKey(
                'materials_consumption_${_selectedFiscalYearId}_${_selectedCurrencyId}_${_selectedWarehouseId}_${_selectedProduct?['id']}_${_fromDate?.toIso8601String()}_${_toDate?.toIso8601String()}',
              ),
              config: _buildTableConfig(t),
              fromJson: (json) => Map<String, dynamic>.from(json),
              calendarController: widget.calendarController,
            ),
          ),
        ],
      ),
    );
  }
}
