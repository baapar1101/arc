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
import 'package:hesabix_ui/services/category_service.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/data_table_utils.dart';
import 'package:hesabix_ui/widgets/invoice/product_combobox_widget.dart';
import 'package:hesabix_ui/widgets/category/category_picker_field.dart';
import 'package:hesabix_ui/core/date_utils.dart';

class SalesByProductReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  
  const SalesByProductReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<SalesByProductReportPage> createState() => _SalesByProductReportPageState();
}

class _SalesByProductReportPageState extends State<SalesByProductReportPage> {
  // Filters
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedFiscalYearId;
  int? _selectedCurrencyId;
  int? _selectedCategoryId;
  Map<String, dynamic>? _selectedProduct;
  bool _includeZeroSales = false;
  
  // Data
  List<Map<String, dynamic>> _fiscalYears = [];
  List<Map<String, dynamic>> _currencies = [];
  List<Map<String, dynamic>> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadFiscalYears();
    _loadCurrencies();
    _loadCategories();
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

  Future<void> _loadCategories() async {
    try {
      final svc = CategoryService(ApiClient());
      final items = await svc.getTree(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _categories = items;
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

  // تابع برای جمع‌آوری تمام ID های زیرشاخه‌های یک دسته‌بندی
  List<int> _getAllCategoryIds(int categoryId, List<Map<String, dynamic>> categories) {
    final result = <int>[categoryId];
    
    // تابع بازگشتی برای پیدا کردن زیرشاخه‌ها
    void findChildren(int parentId, List<Map<String, dynamic>> tree) {
      for (final cat in tree) {
        final id = cat['id'] as int?;
        
        if (id != null) {
          // بررسی اینکه آیا این دسته‌بندی فرزند parentId است
          final parentIdFromTree = cat['parent_id'] as int?;
          if (parentIdFromTree == parentId) {
            result.add(id);
            // ادامه جستجو در زیرشاخه‌های این دسته‌بندی
            final children = cat['children'] as List<dynamic>?;
            if (children != null && children.isNotEmpty) {
              findChildren(id, children.cast<Map<String, dynamic>>());
            }
          }
          
          // بررسی زیرشاخه‌های این دسته‌بندی
          final children = cat['children'] as List<dynamic>?;
          if (children != null && children.isNotEmpty) {
            findChildren(parentId, children.cast<Map<String, dynamic>>());
          }
        }
      }
    }
    
    findChildren(categoryId, categories);
    return result;
  }

  Map<String, dynamic> _additionalParams() {
    // اگر دسته‌بندی انتخاب شده، تمام زیرشاخه‌هایش را هم اضافه کن
    List<int>? categoryIds;
    if (_selectedCategoryId != null) {
      categoryIds = _getAllCategoryIds(_selectedCategoryId!, _categories);
    }
    
    return {
      if (_fromDate != null) 'date_from': _fromDate!.toIso8601String().split('T').first,
      if (_toDate != null) 'date_to': _toDate!.toIso8601String().split('T').first,
      if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
      if (_selectedCurrencyId != null) 'currency_id': _selectedCurrencyId,
      if (categoryIds != null) 'category_ids': categoryIds,
      if (_selectedProduct != null) 'product_ids': [_selectedProduct!['id']],
      'include_zero_sales': _includeZeroSales,
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

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/products/businesses/${widget.businessId}/reports/sales-by-product',
      businessId: widget.businessId,
      reportModuleKey: 'sales_by_product',
      reportSubtype: 'list',
      title: t.reportsSalesByProductTitle,
      showRowNumbers: true,
      columns: [
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
          'unit',
          'واحد',
          formatter: (item) => (item as Map<String, dynamic>)['unit']?.toString() ?? '',
        ),
        TextColumn(
          'category_name',
          'دسته‌بندی',
          formatter: (item) => (item as Map<String, dynamic>)['category_name']?.toString() ?? '',
        ),
        NumberColumn(
          'total_quantity',
          'تعداد فروش',
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['total_quantity']),
        ),
        NumberColumn(
          'total_amount',
          'مبلغ کل فروش',
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['total_amount']),
        ),
        NumberColumn(
          'average_price',
          'میانگین قیمت',
          formatter: (item) => _formatNumber((item as Map<String, dynamic>)['average_price']),
        ),
        DateColumn(
          'last_sale_date',
          'آخرین تاریخ فروش',
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            final date = m['last_sale_date'];
            return _formatDate(date);
          },
        ),
      ],
      searchFields: const ['product_code', 'product_name'],
      defaultPageSize: 20,
      additionalParams: _additionalParams(),
      showExportButtons: true,
      excelEndpoint: '/api/v1/products/businesses/${widget.businessId}/reports/sales-by-product/export/excel',
      pdfEndpoint: '/api/v1/products/businesses/${widget.businessId}/reports/sales-by-product/export/pdf',
      getExportParams: () => _additionalParams(),
      footerTotals: {
        'total_quantity': 'جمع تعداد فروش',
        'total_amount': 'جمع مبلغ کل فروش',
      },
      expandBodyHeightToFitRows: true,
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
        title: Text(t.reportsSalesByProductTitle),
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
                    width: 220,
                    child: DropdownButtonFormField<int>(
                      value: _selectedCurrencyId,
                      decoration: InputDecoration(
                        labelText: 'واحد پول',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      ),
                      items: [
                        const DropdownMenuItem<int>(
                          value: null,
                          child: Text('همه ارزها'),
                        ),
                        ..._currencies.map((curr) {
                          final code = curr['code']?.toString() ?? '';
                          final name = curr['name']?.toString() ?? '';
                          return DropdownMenuItem<int>(
                            value: curr['id'] as int?,
                            child: Text(
                              code.isNotEmpty ? '$code - $name' : name,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedCurrencyId = value;
                        });
                        _refreshData();
                      },
                    ),
                  ),
                  
                  // Category - استفاده از CategoryPickerField
                  SizedBox(
                    width: 280,
                    child: CategoryPickerField(
                      businessId: widget.businessId,
                      categoriesTree: _categories,
                      initialValue: _selectedCategoryId,
                      label: 'دسته‌بندی',
                      onChanged: (value) {
                        setState(() {
                          _selectedCategoryId = value;
                        });
                        _refreshData();
                      },
                    ),
                  ),
                  
                  // Product
                  SizedBox(
                    width: 280,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'کالا',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 8),
                        ProductComboboxWidget(
                          businessId: widget.businessId,
                          selectedProduct: _selectedProduct,
                          onChanged: (product) {
                            setState(() {
                              _selectedProduct = product;
                            });
                            _refreshData();
                          },
                          hintText: 'همه کالاها',
                        ),
                      ],
                    ),
                  ),
                  
                  // Include Zero Sales
                  SizedBox(
                    width: 200,
                    child: CheckboxListTile(
                      title: const Text('نمایش کالاهای با فروش صفر'),
                      value: _includeZeroSales,
                      onChanged: (value) {
                        setState(() {
                          _includeZeroSales = value ?? false;
                        });
                        _refreshData();
                      },
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Data Table
          SingleChildScrollView(
            child: DataTableWidget<Map<String, dynamic>>(
              key: ValueKey(
                '${_selectedFiscalYearId}_${_fromDate?.toIso8601String()}_${_toDate?.toIso8601String()}_${_selectedCurrencyId}_${_selectedCategoryId}_${_selectedProduct?['id']}_$_includeZeroSales',
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

