import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/warehouse_model.dart';
import '../../services/warehouse_service.dart';
import '../../utils/snackbar_helper.dart';
import 'product_label_print_dialog.dart';

/// تب «سریال و بارکد» برای کالاهای یونیک در دیالوگ جزئیات کالا.
class ProductUniqueInstancesTab extends StatefulWidget {
  final int businessId;
  final int productId;
  final Map<String, dynamic> product;

  const ProductUniqueInstancesTab({
    super.key,
    required this.businessId,
    required this.productId,
    required this.product,
  });

  @override
  State<ProductUniqueInstancesTab> createState() => _ProductUniqueInstancesTabState();
}

class _ProductUniqueInstancesTabState extends State<ProductUniqueInstancesTab> {
  final WarehouseService _warehouse = WarehouseService();

  static int? _parseId(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  Map<int, String> _warehouseNames = {};
  final Set<int> _selected = {};

  static String _statusLabel(String? s) {
    switch (s) {
      case 'available':
        return 'موجود';
      case 'sold':
        return 'فروخته‌شده';
      case 'warranty':
        return 'گارانتی';
      case 'defective':
        return 'معیوب';
      default:
        return s ?? '-';
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final whList = await _warehouse.listWarehouses(businessId: widget.businessId);
      final whMap = <int, String>{
        for (final Warehouse w in whList)
          if (w.id != null) w.id!: w.name,
      };

      final res = await _warehouse.searchProductInstances(
        businessId: widget.businessId,
        productId: widget.productId,
        allStatuses: true,
      );
      final items = res['items'] as List<dynamic>? ?? const [];
      final parsed = items.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      if (!mounted) return;
      setState(() {
        _warehouseNames = whMap;
        _rows = parsed;
        _selected.clear();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _warehouseLine(Map<String, dynamic> row) {
    final wid = row['warehouse_id'];
    if (wid == null) return '-';
    final id = wid is int ? wid : int.tryParse(wid.toString());
    if (id == null) return '-';
    return _warehouseNames[id] ?? '#$id';
  }

  ProductLabelPrintItem _toLabel(Map<String, dynamic> row) {
    final name = widget.product['name']?.toString() ?? '';
    final code = widget.product['code']?.toString() ?? '';
    final serial = row['serial_number']?.toString() ?? '';
    final bc = row['barcode']?.toString();
    final st = _statusLabel(row['status']?.toString());
    return ProductLabelPrintItem(
      productName: name,
      productCode: code,
      serialNumber: serial,
      instanceBarcode: (bc != null && bc.isNotEmpty) ? bc : null,
      warehouseLabel: 'انبار: ${_warehouseLine(row)}',
      status: st,
    );
  }

  Future<void> _printAll() async {
    if (_rows.isEmpty) return;
    await ProductLabelPrintDialog.show(
      context,
      items: _rows.map(_toLabel).toList(),
    );
  }

  Future<void> _printSelected() async {
    if (_selected.isEmpty) {
      SnackBarHelper.showError(context, message: 'حداقل یک ردیف را انتخاب کنید');
      return;
    }
    final list = _rows
        .where((r) => _selected.contains(_parseId(r['id'])))
        .map(_toLabel)
        .toList();
    await ProductLabelPrintDialog.show(context, items: list);
  }

  Future<void> _printOne(Map<String, dynamic> row) async {
    await ProductLabelPrintDialog.show(context, items: [_toLabel(row)]);
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    SnackBarHelper.show(context, message: 'در کلیپ‌بورد کپی شد');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('تلاش مجدد'),
              ),
            ],
          ),
        ),
      );
    }

    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'هنوز واحد یونیکی برای این کالا ثبت نشده است.',
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: _selected.isEmpty ? null : _printSelected,
                icon: const Icon(Icons.print_outlined),
                label: Text('چاپ انتخاب‌شده (${_selected.length})'),
              ),
              FilledButton.icon(
                onPressed: _printAll,
                icon: const Icon(Icons.print),
                label: const Text('چاپ همه'),
              ),
              IconButton(
                tooltip: 'بارگذاری مجدد',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SingleChildScrollView(
                child: DataTable(
                headingRowHeight: 44,
                dataRowMinHeight: 48,
                columns: [
                  DataColumn(
                      label: Checkbox(
                      value: _selected.length == _rows.length && _rows.isNotEmpty,
                      tristate: true,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selected
                              ..clear()
                              ..addAll(
                                _rows.map((r) => _parseId(r['id'])).whereType<int>(),
                              );
                          } else {
                            _selected.clear();
                          }
                        });
                      },
                    ),
                  ),
                  const DataColumn(label: Text('سریال')),
                  const DataColumn(label: Text('بارکد')),
                  const DataColumn(label: Text('انبار')),
                  const DataColumn(label: Text('وضعیت')),
                  const DataColumn(label: Text('عملیات')),
                ],
                rows: _rows.map((row) {
                  final id = _parseId(row['id']);
                  final sel = id != null && _selected.contains(id);
                  final serial = row['serial_number']?.toString() ?? '';
                  final bc = row['barcode']?.toString() ?? '';
                  return DataRow(
                    selected: sel,
                    cells: [
                      DataCell(
                        Checkbox(
                          value: sel,
                          onChanged: id == null
                              ? null
                              : (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selected.add(id);
                                    } else {
                                      _selected.remove(id);
                                    }
                                  });
                                },
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(child: Text(serial)),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: serial.isEmpty ? null : () => _copy(serial),
                              tooltip: 'کپی سریال',
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(child: Text(bc.isEmpty ? '—' : bc)),
                            if (bc.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.copy, size: 18),
                                onPressed: () => _copy(bc),
                                tooltip: 'کپی بارکد',
                              ),
                          ],
                        ),
                      ),
                      DataCell(Text(_warehouseLine(row))),
                      DataCell(Text(_statusLabel(row['status']?.toString()))),
                      DataCell(
                        IconButton(
                          icon: const Icon(Icons.print_outlined),
                          tooltip: 'چاپ این واحد',
                          onPressed: () => _printOne(row),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
            ),
          ),
        ),
      ],
    );
  }
}
