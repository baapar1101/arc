import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../services/warehouse_service.dart';
import '../../widgets/invoice/warehouse_combobox_widget.dart';
import '../../widgets/invoice/product_combobox_widget.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;
import '../../core/calendar_controller.dart';
import '../../widgets/date_input_field.dart';
import '../../widgets/data_table/data_table.dart';

String _rowKey(int? productId, int? warehouseId) => '${productId ?? 0}:${warehouseId ?? 0}';

double? _tryParseNum(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  // پشتیبانی از اعداد با جداکننده هزارگان
  final normalized = s.replaceAll(',', '').replaceAll('٬', '').replaceAll(' ', '');
  return double.tryParse(normalized);
}

class _StockCountRowVm {
  final Map<String, dynamic> raw;
  final TextEditingController physicalCtrl;
  final FocusNode physicalFocus;

  _StockCountRowVm({
    required this.raw,
    required this.physicalCtrl,
    required this.physicalFocus,
  });

  int? get productId => (raw['product_id'] as num?)?.toInt();
  int? get warehouseId => (raw['warehouse_id'] as num?)?.toInt();
  String get key => _rowKey(productId, warehouseId);
}

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
  final _searchController = TextEditingController();
  
  bool _loading = false;
  bool _calculating = false;
  List<_StockCountRowVm> _rows = <_StockCountRowVm>[];
  final Map<String, _StockCountRowVm> _rowVmByKey = <String, _StockCountRowVm>{};
  Map<String, Map<String, dynamic>> _calculatedByKey = <String, Map<String, dynamic>>{};
  DateTime? _asOfDate;
  int? _selectedWarehouseId;
  Map<String, dynamic>? _selectedProduct;
  Map<String, dynamic>? _summary;
  String _stockCountCode = '';
  bool _onlyDifferences = false;
  static const double _mobileBreakpoint = 700.0;

  @override
  void initState() {
    super.initState();
    _asOfDate = DateTime.now();
    _generateStockCountCode();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.physicalCtrl.dispose();
      r.physicalFocus.dispose();
    }
    _searchController.dispose();
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
      final res = await _svc.startStockCount(
        businessId: widget.businessId,
        warehouseId: _selectedWarehouseId,
        productIds: _selectedProduct != null && _selectedProduct!['id'] != null
            ? [_selectedProduct!['id'] as int]
            : null,
        asOfDate: _asOfDate!.toIso8601String().split('T')[0],
      );
      
      final items = List<Map<String, dynamic>>.from(res['items'] ?? const []);

      // پاک‌سازی state قبلی
      for (final r in _rows) {
        r.physicalCtrl.dispose();
        r.physicalFocus.dispose();
      }

      final newRows = <_StockCountRowVm>[];
      for (final it in items) {
        final systemQty = (it['system_quantity'] as num?)?.toDouble();
        final physicalQty = (it['physical_quantity'] as num?)?.toDouble();
        final ctrl = TextEditingController(text: physicalQty?.toString() ?? '');
        final focus = FocusNode(debugLabel: 'stockcount:${it['product_id']}:${it['warehouse_id']}');
        // اگر سیستم مقدار دارد و فیزیکی خالی است، خالی می‌گذاریم (کاربر باید وارد کند)
        // اما امکان "کپی سیستم→فیزیکی" را در UI اضافه می‌کنیم.
        if ((ctrl.text.trim().isEmpty) && systemQty != null) {
          // keep empty
        }
        newRows.add(_StockCountRowVm(raw: it, physicalCtrl: ctrl, physicalFocus: focus));
      }

      if (!mounted) return;
      setState(() {
        _rows = newRows;
        _rowVmByKey
          ..clear()
          ..addEntries(newRows.map((r) => MapEntry(r.key, r)));
        _calculatedByKey = <String, Map<String, dynamic>>{};
        _summary = null;
        _onlyDifferences = false;
        _searchController.text = '';
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
    if (_rows.isEmpty) {
      _showError('ابتدا لیست محصولات را بارگذاری کنید');
      return;
    }

    // بررسی اینکه همه موجودی‌های فیزیکی وارد شده‌اند
    final missing = _rows.where((r) => _tryParseNum(r.physicalCtrl.text) == null).toList();
    if (missing.isNotEmpty) {
      _showError('لطفاً موجودی فیزیکی همه محصولات را وارد کنید (می‌توانید از گزینه «کپی سیستم → فیزیکی» استفاده کنید)');
      return;
    }

    setState(() => _calculating = true);
    try {
      final itemsToCalculate = _rows.map((r) {
        final item = r.raw;
        final physical = _tryParseNum(r.physicalCtrl.text) ?? 0.0;
        return {
          'product_id': item['product_id'],
          'warehouse_id': item['warehouse_id'],
          'system_quantity': item['system_quantity'],
          'physical_quantity': physical,
        };
      }).toList();

      final res = await _svc.calculateStockCountDifferences(
        businessId: widget.businessId,
        items: itemsToCalculate,
      );
      
      final calculatedItems = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      final map = <String, Map<String, dynamic>>{};
      for (final it in calculatedItems) {
        final pid = (it['product_id'] as num?)?.toInt();
        final wid = (it['warehouse_id'] as num?)?.toInt();
        map[_rowKey(pid, wid)] = it;
      }
      if (!mounted) return;
      setState(() {
        _calculatedByKey = map;
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
    if (_calculatedByKey.isEmpty) {
      _showError('ابتدا تفاوت‌ها را محاسبه کنید');
      return;
    }

    final calculatedItems = _calculatedByKey.values.toList();
    final itemsWithDifference = calculatedItems.where((item) => item['difference'] != 0).toList();
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
      await _svc.createStockCountAdjustment(
        businessId: widget.businessId,
        stockCountCode: _stockCountCodeController.text.trim(),
        stockCountDate: _asOfDate!.toIso8601String().split('T')[0],
        items: calculatedItems,
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

  List<_StockCountRowVm> _visibleRows() {
    final q = _searchController.text.trim();
    final lowerQ = q.toLowerCase();
    Iterable<_StockCountRowVm> base = _rows;

    if (q.isNotEmpty) {
      base = base.where((r) {
        final code = (r.raw['product_code'] ?? '').toString().toLowerCase();
        final name = (r.raw['product_name'] ?? '').toString().toLowerCase();
        final wh = (r.raw['warehouse_name'] ?? '').toString().toLowerCase();
        return code.contains(lowerQ) || name.contains(lowerQ) || wh.contains(lowerQ);
      });
    }

    if (_onlyDifferences && _calculatedByKey.isNotEmpty) {
      base = base.where((r) {
        final calc = _calculatedByKey[r.key];
        final diff = (calc?['difference'] as num?)?.toDouble() ?? 0.0;
        return diff != 0.0;
      });
    }

    return base.toList();
  }

  void _fillAllPhysicalWithSystem() {
    for (final r in _rows) {
      final systemQty = (r.raw['system_quantity'] as num?)?.toDouble();
      if (systemQty == null) continue;
      r.physicalCtrl.text = systemQty.toString();
    }
    // اگر قبلاً محاسبه شده، نتایج دیگر معتبر نیستند
    if (_calculatedByKey.isNotEmpty) {
      setState(() {
        _calculatedByKey = <String, Map<String, dynamic>>{};
        _summary = null;
      });
    }
    setState(() {}); // refresh UI
  }

  void _clearAllPhysical() {
    for (final r in _rows) {
      r.physicalCtrl.clear();
    }
    if (_calculatedByKey.isNotEmpty) {
      setState(() {
        _calculatedByKey = <String, Map<String, dynamic>>{};
        _summary = null;
      });
    }
    setState(() {});
  }

  DataTableConfig<Map<String, dynamic>> _buildDesktopTableConfig() {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: 'local_stock_count',
      tableId: 'stock_count_desktop_local',
      title: 'اقلام انبارگردانی',
      showSearch: true,
      showFilters: false,
      showPagination: true,
      showColumnSearch: false,
      showExportButtons: false,
      enableSorting: false,
      enableGlobalSearch: true,
      searchFields: const ['product_code', 'product_name', 'warehouse_name'],
      showRowNumbers: true,
      enableRowSelection: false,
      enableHorizontalScroll: true,
      minTableWidth: 1100,
      columns: [
        TextColumn(
          'product_code',
          'کد',
          width: ColumnWidth.small,
          sortable: false,
          searchable: false,
          formatter: (row) => (row as Map<String, dynamic>)['product_code']?.toString() ?? '-',
        ),
        TextColumn(
          'product_name',
          'نام محصول',
          width: ColumnWidth.large,
          sortable: false,
          searchable: false,
          formatter: (row) => (row as Map<String, dynamic>)['product_name']?.toString() ?? '-',
        ),
        TextColumn(
          'warehouse_name',
          'انبار',
          width: ColumnWidth.medium,
          sortable: false,
          searchable: false,
          formatter: (row) => (row as Map<String, dynamic>)['warehouse_name']?.toString() ?? '-',
        ),
        NumberColumn(
          'system_quantity',
          'موجودی سیستم',
          width: ColumnWidth.medium,
          sortable: false,
          searchable: false,
          formatter: (row) {
            final m = row as Map<String, dynamic>;
            final v = (m['system_quantity'] as num?)?.toDouble() ?? 0.0;
            return formatWithThousands(v);
          },
        ),
        CustomColumn(
          'physical_quantity',
          'موجودی فیزیکی',
          width: ColumnWidth.medium,
          sortable: false,
          searchable: false,
          builder: (row, index) {
            final m = row as Map<String, dynamic>;
            final pid = (m['product_id'] as num?)?.toInt();
            final wid = (m['warehouse_id'] as num?)?.toInt();
            final key = _rowKey(pid, wid);
            final vm = _rowVmByKey[key];
            final cs = Theme.of(context).colorScheme;

            if (vm == null) {
              return const SizedBox.shrink();
            }
            return SizedBox(
              width: 200,
              child: TextField(
                controller: vm.physicalCtrl,
                focusNode: vm.physicalFocus,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9\\.,٬\\s-]')),
                ],
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    tooltip: 'کپی سیستم → فیزیکی',
                    icon: const Icon(Icons.content_copy, size: 18),
                    onPressed: () {
                      final systemQty = (m['system_quantity'] as num?)?.toDouble();
                      if (systemQty == null) return;
                      vm.physicalCtrl.text = systemQty.toString();
                      if (_calculatedByKey.isNotEmpty) {
                        setState(() {
                          _calculatedByKey = <String, Map<String, dynamic>>{};
                          _summary = null;
                        });
                      }
                    },
                  ),
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.2),
                  filled: true,
                ),
                onChanged: (_) {
                  if (_calculatedByKey.isNotEmpty) {
                    setState(() {
                      _calculatedByKey = <String, Map<String, dynamic>>{};
                      _summary = null;
                    });
                  } else {
                    setState(() {});
                  }
                },
              ),
            );
          },
        ),
        CustomColumn(
          'difference',
          'تفاوت',
          width: ColumnWidth.medium,
          sortable: false,
          searchable: false,
          builder: (row, index) {
            final m = row as Map<String, dynamic>;
            final pid = (m['product_id'] as num?)?.toInt();
            final wid = (m['warehouse_id'] as num?)?.toInt();
            final key = _rowKey(pid, wid);
            final diff = (_calculatedByKey[key]?['difference'] as num?)?.toDouble();
            Color? c;
            if (diff != null) {
              if (diff > 0) c = Colors.green;
              if (diff < 0) c = Colors.red;
            }
            return Text(
              diff == null ? '-' : formatWithThousands(diff),
              textAlign: TextAlign.center,
              style: TextStyle(color: c, fontWeight: diff != null && diff != 0 ? FontWeight.w700 : FontWeight.w400),
            );
          },
        ),
        TextColumn(
          'unit',
          'واحد',
          width: ColumnWidth.small,
          sortable: false,
          searchable: false,
          formatter: (row) => (row as Map<String, dynamic>)['unit']?.toString() ?? '-',
        ),
      ],
      rowColorBuilder: (row, index) {
        final m = row as Map<String, dynamic>;
        final pid = (m['product_id'] as num?)?.toInt();
        final wid = (m['warehouse_id'] as num?)?.toInt();
        final key = _rowKey(pid, wid);
        final diff = (_calculatedByKey[key]?['difference'] as num?)?.toDouble() ?? 0.0;
        if (diff == 0) return null;
        return diff > 0 ? Colors.green.withValues(alpha: 0.05) : Colors.red.withValues(alpha: 0.05);
      },
      expandBodyHeightToFitRows: true,
    );
  }

  Widget _buildStepHeader(bool isMobile) {
    int step = 1;
    if (_rows.isNotEmpty) step = 2;
    if (_calculatedByKey.isNotEmpty) step = 3;

    Widget chip(String label, int idx) {
      final active = idx == step;
      final done = idx < step;
      final cs = Theme.of(context).colorScheme;
      return Chip(
        label: Text(label),
        avatar: done
            ? Icon(Icons.check_circle, size: 18, color: cs.primary)
            : Icon(active ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18),
        backgroundColor: active ? cs.primaryContainer : cs.surfaceContainerHighest,
        labelStyle: TextStyle(
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          color: active ? cs.onPrimaryContainer : cs.onSurfaceVariant,
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('مراحل انبارگردانی', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                chip('۱) فیلتر و بارگذاری', 1),
                chip('۲) ثبت موجودی فیزیکی', 2),
                chip('۳) محاسبه و ایجاد حواله', 3),
              ],
            ),
            if (isMobile) const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersCard(bool isMobile) {
    final dateField = widget.calendarController != null
        ? DateInputField(
            value: _asOfDate,
            onChanged: (date) => setState(() => _asOfDate = date),
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
          );

    final warehouseField = WarehouseComboboxWidget(
      businessId: widget.businessId,
      selectedWarehouseId: _selectedWarehouseId,
      onChanged: (id) => setState(() => _selectedWarehouseId = id),
      label: 'انبار (اختیاری)',
      height: 56,
    );

    final productField = ProductComboboxWidget(
      businessId: widget.businessId,
      selectedProduct: _selectedProduct,
      onChanged: (product) => setState(() => _selectedProduct = product),
      label: 'محصول (اختیاری)',
    );

    final loadButton = SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        icon: _loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.search),
        label: Text(_loading ? 'در حال بارگذاری...' : 'بارگذاری لیست محصولات'),
        onPressed: _loading ? null : _startStockCount,
        style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      ),
    );

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.filter_list, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('فیلترها', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            if (isMobile) ...[
              SizedBox(height: 56, child: dateField),
              const SizedBox(height: 12),
              SizedBox(height: 56, child: warehouseField),
              const SizedBox(height: 12),
              SizedBox(height: 56, child: productField),
              const SizedBox(height: 12),
              loadButton,
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: SizedBox(height: 56, child: dateField)),
                  const SizedBox(width: 16),
                  Expanded(child: warehouseField),
                  const SizedBox(width: 16),
                  Expanded(child: SizedBox(height: 56, child: Align(alignment: Alignment.centerLeft, child: productField))),
                ],
              ),
              const SizedBox(height: 12),
              loadButton,
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < _mobileBreakpoint;
    final visibleRows = _visibleRows();
    return Scaffold(
      appBar: AppBar(
        title: const Text('انبار گردانی'),
        actions: [
          if (_rows.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _startStockCount,
              tooltip: 'بارگذاری مجدد',
            ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate.fixed(
                [
                  _buildStepHeader(isMobile),
                  const SizedBox(height: 12),
                  _buildFiltersCard(isMobile),
                  const SizedBox(height: 12),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
          ),
          if (_rows.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('اطلاعات انبار گردانی', style: Theme.of(context).textTheme.titleMedium),
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
              ),
            ),
          if (_rows.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              sliver: SliverToBoxAdapter(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'لیست محصولات (${visibleRows.length}/${_rows.length})',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            IconButton(
                              tooltip: 'کپی موجودی سیستم → فیزیکی (برای همه)',
                              onPressed: _rows.isEmpty ? null : _fillAllPhysicalWithSystem,
                              icon: const Icon(Icons.content_copy),
                            ),
                            IconButton(
                              tooltip: 'پاک کردن همه موجودی‌های فیزیکی',
                              onPressed: _rows.isEmpty ? null : _clearAllPhysical,
                              icon: const Icon(Icons.clear_all),
                            ),
                            const SizedBox(width: 8),
                            if (_calculatedByKey.isEmpty)
                              FilledButton.icon(
                                icon: const Icon(Icons.calculate),
                                label: Text(isMobile ? 'محاسبه' : 'محاسبه تفاوت‌ها'),
                                onPressed: _calculating ? null : _calculateDifferences,
                              )
                            else
                              FilledButton.icon(
                                icon: const Icon(Icons.add),
                                label: Text(isMobile ? 'ایجاد حواله' : 'ایجاد حواله تعدیل'),
                                onPressed: _loading ? null : _createAdjustment,
                              ),
                          ],
                        ),
                        if (isMobile) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              labelText: 'جستجو (کد/نام/انبار)',
                              prefixIcon: const Icon(Icons.search),
                              border: const OutlineInputBorder(),
                              suffixIcon: _searchController.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'پاک کردن جستجو',
                                      icon: const Icon(Icons.close),
                                      onPressed: () {
                                        setState(() => _searchController.clear());
                                      },
                                    ),
                            ),
                            onChanged: (_) {
                              setState(() {});
                            },
                          ),
                          const SizedBox(height: 10),
                        ],
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            FilterChip(
                              label: const Text('فقط موارد اختلاف‌دار'),
                              selected: _onlyDifferences,
                              onSelected: (_calculatedByKey.isEmpty)
                                  ? null
                                  : (v) {
                                      setState(() => _onlyDifferences = v);
                                    },
                            ),
                            if (_calculatedByKey.isEmpty)
                              Text(
                                'برای فعال شدن این فیلتر ابتدا محاسبه را انجام دهید.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                        if (_summary != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Wrap(
                              spacing: 16,
                              runSpacing: 12,
                              alignment: WrapAlignment.spaceBetween,
                              children: [
                                _buildSummaryItem('کل', '${_summary!['total_items']}'),
                                _buildSummaryItem('با تفاوت', '${_summary!['items_with_difference']}'),
                                _buildSummaryItem('افزایش', '${_summary!['items_increased']}'),
                                _buildSummaryItem('کاهش', '${_summary!['items_decreased']}'),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_rows.isNotEmpty && isMobile)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.separated(
                itemCount: visibleRows.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final row = visibleRows[index];
                  final calc = _calculatedByKey[row.key];
                  return _StockCountRowCard(
                    row: row,
                    calculated: calc,
                    onCopySystemToPhysical: () {
                      final systemQty = (row.raw['system_quantity'] as num?)?.toDouble();
                      if (systemQty == null) return;
                      row.physicalCtrl.text = systemQty.toString();
                      if (_calculatedByKey.isNotEmpty) {
                        setState(() {
                          _calculatedByKey = <String, Map<String, dynamic>>{};
                          _summary = null;
                        });
                      }
                    },
                    onEditingChanged: () {
                      if (_calculatedByKey.isNotEmpty) {
                        setState(() {
                          _calculatedByKey = <String, Map<String, dynamic>>{};
                          _summary = null;
                        });
                      }
                    },
                  );
                },
              ),
            ),
          if (_rows.isNotEmpty && !isMobile)
            SliverFillRemaining(
              hasScrollBody: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Card(
                  child: SingleChildScrollView(
                    child: DataTableWidget<Map<String, dynamic>>(
                      config: _buildDesktopTableConfig(),
                      fromJson: (json) => json,
                      localRawItems: _rows.map((r) => r.raw).toList(),
                      localSummary: null,
                    ),
                  ),
                ),
              ),
            ),
        ],
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
            color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class _StockCountRowCard extends StatelessWidget {
  final _StockCountRowVm row;
  final Map<String, dynamic>? calculated;
  final VoidCallback onCopySystemToPhysical;
  final VoidCallback onEditingChanged;

  const _StockCountRowCard({
    required this.row,
    required this.calculated,
    required this.onCopySystemToPhysical,
    required this.onEditingChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final code = row.raw['product_code']?.toString() ?? '-';
    final name = row.raw['product_name']?.toString() ?? '-';
    final wh = row.raw['warehouse_name']?.toString() ?? '-';
    final unit = row.raw['unit']?.toString() ?? '-';
    final systemQty = (row.raw['system_quantity'] as num?)?.toDouble() ?? 0.0;
    final diff = (calculated?['difference'] as num?)?.toDouble();

    Color? diffColor;
    if (diff != null) {
      if (diff > 0) diffColor = Colors.green;
      if (diff < 0) diffColor = Colors.red;
    }

    final bg = (diff == null || diff == 0)
        ? cs.surface
        : (diff > 0 ? Colors.green.withValues(alpha: 0.06) : Colors.red.withValues(alpha: 0.06));

    return Card(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$code - $name',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'کپی سیستم → فیزیکی',
                  onPressed: onCopySystemToPhysical,
                  icon: const Icon(Icons.content_copy, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('انبار: $wh', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _kv(context, 'موجودی سیستم', formatWithThousands(systemQty))),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: row.physicalCtrl,
                    focusNode: row.physicalFocus,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,٬\s-]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'موجودی فیزیکی',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => onEditingChanged(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _kv(context, 'واحد', unit)),
                const SizedBox(width: 12),
                Expanded(
                  child: _kv(
                    context,
                    'تفاوت',
                    diff == null ? '-' : formatWithThousands(diff),
                    valueStyle: TextStyle(color: diffColor, fontWeight: diff != null && diff != 0 ? FontWeight.w700 : FontWeight.w400),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v, {TextStyle? valueStyle}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(v, style: valueStyle ?? theme.textTheme.bodyMedium),
      ],
    );
  }
}


