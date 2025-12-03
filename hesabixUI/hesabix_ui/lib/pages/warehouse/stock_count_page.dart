import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/warehouse_service.dart';
import '../../widgets/invoice/warehouse_combobox_widget.dart';
import '../../widgets/invoice/product_combobox_widget.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;
import '../../utils/snackbar_helper.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart' show HesabixDateUtils;
import '../../widgets/date_input_field.dart';

class StockCountPage extends StatefulWidget {
  final int businessId;
  final CalendarController? calendarController;
  
  const StockCountPage({
    super.key,
    required this.businessId,
    this.calendarController,
  });

  @override
  State<StockCountPage> createState() => _StockCountPageState();
}

class _StockCountPageState extends State<StockCountPage> {
  final _svc = WarehouseService();
  final _stockCountCodeController = TextEditingController();
  final _notesController = TextEditingController();
  
  bool _loading = false;
  bool _calculating = false;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _calculatedItems = [];
  DateTime? _asOfDate;
  int? _selectedWarehouseId;
  Map<String, dynamic>? _selectedProduct;
  Map<String, dynamic>? _summary;
  String _stockCountCode = '';

  @override
  void initState() {
    super.initState();
    _asOfDate = DateTime.now();
    _generateStockCountCode();
  }

  @override
  void dispose() {
    _stockCountCodeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _generateStockCountCode() {
    final now = DateTime.now();
    _stockCountCode = 'INV-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    _stockCountCodeController.text = _stockCountCode;
  }

  Future<void> _startStockCount() async {
    if (_asOfDate == null) {
      _showError('لطفاً تاریخ شمارش را انتخاب کنید');
      return;
    }

    setState(() => _loading = true);
    try {
      final query = {
        'as_of_date': _asOfDate!.toIso8601String().split('T')[0],
        if (_selectedWarehouseId != null) 'warehouse_id': _selectedWarehouseId,
        if (_selectedProduct != null && _selectedProduct!['id'] != null)
          'product_ids': [_selectedProduct!['id']],
      };
      
      final res = await _svc.startStockCount(
        businessId: widget.businessId,
        warehouseId: _selectedWarehouseId,
        productIds: _selectedProduct != null && _selectedProduct!['id'] != null
            ? [_selectedProduct!['id'] as int]
            : null,
        asOfDate: _asOfDate!.toIso8601String().split('T')[0],
      );
      
      setState(() {
        _items = List<Map<String, dynamic>>.from(res['items'] ?? const []);
        _calculatedItems = [];
        _summary = null;
      });
    } catch (e) {
      if (!mounted) return;
      _showError('خطا در بارگذاری: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _calculateDifferences() async {
    if (_items.isEmpty) {
      _showError('ابتدا لیست محصولات را بارگذاری کنید');
      return;
    }

    // بررسی اینکه همه موجودی‌های فیزیکی وارد شده‌اند
    final missingItems = _items.where((item) {
      final physicalQty = item['physical_quantity'];
      return physicalQty == null || physicalQty == '';
    }).toList();

    if (missingItems.isNotEmpty) {
      _showError('لطفاً موجودی فیزیکی همه محصولات را وارد کنید');
      return;
    }

    setState(() => _calculating = true);
    try {
      final itemsToCalculate = _items.map((item) {
        return {
          'product_id': item['product_id'],
          'warehouse_id': item['warehouse_id'],
          'system_quantity': item['system_quantity'],
          'physical_quantity': item['physical_quantity'],
        };
      }).toList();

      final res = await _svc.calculateStockCountDifferences(
        businessId: widget.businessId,
        items: itemsToCalculate,
      );
      
      setState(() {
        _calculatedItems = List<Map<String, dynamic>>.from(res['items'] ?? const []);
        _summary = res['summary'] as Map<String, dynamic>?;
      });
    } catch (e) {
      if (!mounted) return;
      _showError('خطا در محاسبه تفاوت‌ها: $e');
    } finally {
      if (mounted) {
        setState(() => _calculating = false);
      }
    }
  }

  Future<void> _createAdjustment() async {
    if (_calculatedItems.isEmpty) {
      _showError('ابتدا تفاوت‌ها را محاسبه کنید');
      return;
    }

    final itemsWithDifference = _calculatedItems.where((item) => item['difference'] != 0).toList();
    if (itemsWithDifference.isEmpty) {
      _showError('هیچ تفاوتی برای ایجاد حواله تعدیل وجود ندارد');
      return;
    }

    if (_stockCountCodeController.text.trim().isEmpty) {
      _showError('لطفاً کد انبار گردانی را وارد کنید');
      return;
    }

    if (_asOfDate == null) {
      _showError('لطفاً تاریخ شمارش را انتخاب کنید');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تایید ایجاد حواله تعدیل'),
        content: Text(
          'آیا از ایجاد حواله تعدیل برای ${itemsWithDifference.length} محصول با تفاوت اطمینان دارید؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('تایید'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      final res = await _svc.createStockCountAdjustment(
        businessId: widget.businessId,
        stockCountCode: _stockCountCodeController.text.trim(),
        stockCountDate: _asOfDate!.toIso8601String().split('T')[0],
        items: _calculatedItems,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      if (!mounted) return;
      
      _showSuccess('حواله تعدیل با موفقیت ایجاد شد');
      
      // هدایت به صفحه لیست حواله‌های انبار
      context.go('/business/${widget.businessId}/warehouse-docs');
    } catch (e) {
      if (!mounted) return;
      _showError('خطا در ایجاد حواله تعدیل: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('انبار گردانی'),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _startStockCount,
              tooltip: 'بارگذاری مجدد',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // فیلترها
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.filter_list,
                          color: Theme.of(context).colorScheme.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'فیلترها',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: widget.calendarController != null
                              ? DateInputField(
                                  value: _asOfDate,
                                  onChanged: (date) {
                                    setState(() => _asOfDate = date);
                                  },
                                  labelText: 'تاریخ شمارش',
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                  calendarController: widget.calendarController!,
                                  isDense: true,
                                )
                              : TextFormField(
                                  decoration: const InputDecoration(
                                    labelText: 'تاریخ شمارش',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                                  ),
                                  readOnly: true,
                                  controller: TextEditingController(
                                    text: _asOfDate != null
                                        ? '${_asOfDate!.year}-${_asOfDate!.month.toString().padLeft(2, '0')}-${_asOfDate!.day.toString().padLeft(2, '0')}'
                                        : '',
                                  ),
                                  onTap: () async {
                                    final date = await showDatePicker(
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
                          child: _buildWarehouseFilter(),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildProductFilter(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        icon: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.search),
                        label: Text(_loading ? 'در حال بارگذاری...' : 'بارگذاری لیست محصولات'),
                        onPressed: _loading ? null : _startStockCount,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_items.isNotEmpty) ...[
              const SizedBox(height: 16),
              
              // اطلاعات انبار گردانی
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'اطلاعات انبار گردانی',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _stockCountCodeController,
                        decoration: const InputDecoration(
                          labelText: 'کد انبار گردانی',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _notesController,
                        decoration: const InputDecoration(
                          labelText: 'یادداشت (اختیاری)',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // جدول محصولات
              Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'لیست محصولات (${_items.length})',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Row(
                            children: [
                              if (_calculatedItems.isEmpty)
                                FilledButton.icon(
                                  icon: const Icon(Icons.calculate),
                                  label: const Text('محاسبه تفاوت‌ها'),
                                  onPressed: _calculating ? null : _calculateDifferences,
                                )
                              else
                                FilledButton.icon(
                                  icon: const Icon(Icons.add),
                                  label: const Text('ایجاد حواله تعدیل'),
                                  onPressed: _loading ? null : _createAdjustment,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_summary != null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildSummaryItem('کل', '${_summary!['total_items']}'),
                              _buildSummaryItem('با تفاوت', '${_summary!['items_with_difference']}'),
                              _buildSummaryItem('افزایش', '${_summary!['items_increased']}'),
                              _buildSummaryItem('کاهش', '${_summary!['items_decreased']}'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('کد محصول')),
                          DataColumn(label: Text('نام محصول')),
                          DataColumn(label: Text('انبار')),
                          DataColumn(label: Text('موجودی سیستم')),
                          DataColumn(label: Text('موجودی فیزیکی')),
                          DataColumn(label: Text('تفاوت')),
                          DataColumn(label: Text('واحد')),
                        ],
                        rows: _items.asMap().entries.map<DataRow>((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          final calculatedItem = _calculatedItems.isNotEmpty && index < _calculatedItems.length
                              ? _calculatedItems[index]
                              : null;
                          
                          final systemQty = (item['system_quantity'] as num?)?.toDouble() ?? 0.0;
                          final physicalQty = (item['physical_quantity'] as num?)?.toDouble();
                          final difference = calculatedItem != null
                              ? (calculatedItem['difference'] as num?)?.toDouble() ?? 0.0
                              : (physicalQty != null ? physicalQty - systemQty : 0.0);
                          
                          return DataRow(
                            cells: [
                              DataCell(Text(item['product_code']?.toString() ?? '-')),
                              DataCell(Text(item['product_name']?.toString() ?? '-')),
                              DataCell(Text(item['warehouse_name']?.toString() ?? '-')),
                              DataCell(Text(formatWithThousands(systemQty))),
                              DataCell(
                                SizedBox(
                                  width: 120,
                                  child: TextFormField(
                                    initialValue: physicalQty?.toString() ?? '',
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    onChanged: (value) {
                                      final qty = double.tryParse(value) ?? 0.0;
                                      setState(() {
                                        item['physical_quantity'] = qty;
                                      });
                                    },
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  formatWithThousands(difference),
                                  style: TextStyle(
                                    color: difference > 0
                                        ? Colors.green
                                        : difference < 0
                                            ? Colors.red
                                            : null,
                                    fontWeight: difference != 0 ? FontWeight.bold : null,
                                  ),
                                ),
                              ),
                              DataCell(Text(item['unit']?.toString() ?? '-')),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildWarehouseFilter() {
    return SizedBox(
      height: 56, // ارتفاع یکسان با DateInputField
      child: WarehouseComboboxWidget(
        businessId: widget.businessId,
        selectedWarehouseId: _selectedWarehouseId,
        onChanged: (id) {
          setState(() => _selectedWarehouseId = id);
        },
        label: 'انبار (اختیاری)',
      ),
    );
  }

  Widget _buildProductFilter() {
    return SizedBox(
      height: 56, // ارتفاع یکسان با DateInputField
      child: Align(
        alignment: Alignment.centerLeft,
        child: ProductComboboxWidget(
          businessId: widget.businessId,
          selectedProduct: _selectedProduct,
          onChanged: (product) {
            setState(() => _selectedProduct = product);
          },
          label: 'محصول (اختیاری)',
        ),
      ),
    );
  }
}

