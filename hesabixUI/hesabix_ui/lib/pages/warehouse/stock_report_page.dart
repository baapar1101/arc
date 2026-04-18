import 'package:flutter/material.dart';
import '../../services/warehouse_service.dart';
import '../../widgets/invoice/product_combobox_widget.dart';
import '../../widgets/invoice/warehouse_combobox_widget.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;
import '../../utils/snackbar_helper.dart';
import '../../core/api_client.dart';
import '../../core/date_utils.dart';
import '../../widgets/jalali_date_picker.dart';

class StockReportPage extends StatefulWidget {
  final int businessId;
  const StockReportPage({super.key, required this.businessId});

  @override
  State<StockReportPage> createState() => _StockReportPageState();
}

class _StockReportPageState extends State<StockReportPage> {
  final _svc = WarehouseService();
  
  bool _loading = false;
  List<dynamic> _items = const [];
  DateTime? _asOfDate;
  List<int>? _selectedProductIds;
  List<int>? _selectedWarehouseIds;
  bool _includeZero = false;

  @override
  void initState() {
    super.initState();
    _asOfDate = DateTime.now();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    try {
      final query = {
        'as_of_date': _asOfDate?.toIso8601String().split('T')[0],
        'include_zero': _includeZero,
        if (_selectedProductIds != null && _selectedProductIds!.isNotEmpty)
          'product_ids': _selectedProductIds,
        if (_selectedWarehouseIds != null && _selectedWarehouseIds!.isNotEmpty)
          'warehouse_ids': _selectedWarehouseIds,
      };
      
      final res = await _svc.getStockReport(businessId: widget.businessId, query: query);
      setState(() {
        _items = List<dynamic>.from(res['items'] ?? const []);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('گزارش موجودی انبار'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReport,
            tooltip: 'به‌روزرسانی',
          ),
        ],
      ),
      body: Column(
        children: [
          // فیلترها
          Card(
            margin: const EdgeInsets.all(8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'فیلترها',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          decoration: const InputDecoration(
                            labelText: 'تاریخ گزارش',
                            border: OutlineInputBorder(),
                          ),
                          readOnly: true,
                          controller: TextEditingController(
                            text: _asOfDate != null
                                ? HesabixDateUtils.formatForDisplay(
                                    _asOfDate,
                                    ApiClient.getCalendarController()?.isJalali ?? true,
                                  )
                                : '',
                          ),
                          onTap: () async {
                            final date = await showAdaptiveDatePicker(
                              context: context,
                              initialDate: _asOfDate ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (date != null) {
                              setState(() => _asOfDate = date);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: CheckboxListTile(
                          title: const Text('نمایش موجودی صفر'),
                          value: _includeZero,
                          onChanged: (value) {
                            setState(() => _includeZero = value ?? false);
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: WarehouseComboboxWidget(
                          businessId: widget.businessId,
                          selectedWarehouseId: _selectedWarehouseIds?.isNotEmpty == true
                              ? _selectedWarehouseIds!.first
                              : null,
                          onChanged: (id) {
                            setState(() {
                              _selectedWarehouseIds = id != null ? [id] : null;
                            });
                          },
                          label: 'فیلتر انبار (اختیاری)',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ProductComboboxWidget(
                          businessId: widget.businessId,
                          selectedProduct: _selectedProductIds?.isNotEmpty == true
                              ? {'id': _selectedProductIds!.first}
                              : null,
                          onChanged: (product) {
                            setState(() {
                              _selectedProductIds = product?['id'] != null
                                  ? [product!['id'] as int]
                                  : null;
                            });
                          },
                          label: 'فیلتر محصول (اختیاری)',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.search),
                      label: const Text('جستجو'),
                      onPressed: _loadReport,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // نتایج
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(child: Text('نتیجه‌ای یافت نشد'))
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('کد محصول')),
                            DataColumn(label: Text('نام محصول')),
                            DataColumn(label: Text('کد انبار')),
                            DataColumn(label: Text('نام انبار')),
                            DataColumn(label: Text('موجودی')),
                            DataColumn(label: Text('واحد')),
                          ],
                          rows: _items.map<DataRow>((item) {
                            return DataRow(
                              cells: [
                                DataCell(Text(item['product_code']?.toString() ?? '-')),
                                DataCell(Text(item['product_name']?.toString() ?? '-')),
                                DataCell(Text(item['warehouse_code']?.toString() ?? '-')),
                                DataCell(Text(item['warehouse_name']?.toString() ?? '-')),
                                DataCell(Text(
                                  formatWithThousands(item['quantity']?.toDouble() ?? 0.0),
                                )),
                                DataCell(Text(item['unit']?.toString() ?? '-')),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

