import 'package:flutter/material.dart';
import '../../services/warehouse_service.dart';
import '../../models/warehouse_model.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';

class WarehousesPage extends StatefulWidget {
  final int businessId;
  const WarehousesPage({super.key, required this.businessId});

  @override
  State<WarehousesPage> createState() => _WarehousesPageState();
}

class _WarehousesPageState extends State<WarehousesPage> {
  final WarehouseService _service = WarehouseService();
  final GlobalKey _tableKey = GlobalKey();

  void _refreshTable() {
    try {
      final current = _tableKey.currentState as dynamic;
      current?.refresh();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DataTableWidget<Warehouse>(
        key: _tableKey,
        fromJson: (m) => Warehouse.fromJson(m),
        config: DataTableConfig<Warehouse>(
          endpoint: '/api/v1/warehouses/business/${widget.businessId}/query',
          title: 'فهرست انبارها',
          showBackButton: true,
          onBack: () => Navigator.of(context).maybePop(),
          showTableIcon: false,
          showSearch: true,
          showPagination: true,
          showRowNumbers: true,
          enableSorting: true,
          searchFields: const ['code', 'name', 'description'],
          customHeaderActions: [
            Tooltip(
              message: 'افزودن انبار',
              child: IconButton(
                onPressed: _showCreateDialog,
                icon: const Icon(Icons.add),
              ),
            ),
          ],
          columns: [
            ActionColumn('actions', 'عملیات', actions: [
              DataTableAction(
                icon: Icons.edit_outlined,
                label: 'ویرایش',
                onTap: (item) {
                  if (item is Warehouse) _showEditDialog(item);
                },
              ),
              DataTableAction(
                icon: Icons.delete_outline,
                label: 'حذف',
                onTap: (item) {
                  if (item is Warehouse) _delete(item);
                },
                isDestructive: true,
              ),
            ]),
            TextColumn('code', 'کد',
                formatter: (item) => (item as Warehouse).code,
                width: ColumnWidth.small),
            TextColumn('name', 'نام',
                formatter: (item) => (item as Warehouse).name,
                width: ColumnWidth.medium),
            TextColumn('description', 'توضیحات',
                formatter: (item) => (item as Warehouse).description ?? '',
                width: ColumnWidth.large,
                searchable: true),
            TextColumn('is_default', 'پیش‌فرض',
                formatter: (item) => (item as Warehouse).isDefault ? 'بله' : 'خیر',
                sortable: false,
                searchable: false,
                width: ColumnWidth.small),
            DateColumn('created_at', 'ایجاد',
                formatter: (item) => (item as Warehouse).createdAt?.toIso8601String() ?? '',
                showTime: false,
                width: ColumnWidth.small),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateDialog() async {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    bool isDefault = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('افزودن انبار'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'کد')), 
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'نام')), 
            StatefulBuilder(builder: (ctx, setSt) {
              return CheckboxListTile(
                value: isDefault,
                onChanged: (v) => setSt(() => isDefault = v ?? false),
                title: const Text('پیش‌فرض'),
                controlAffinity: ListTileControlAffinity.leading,
              );
            }),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('ذخیره')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.createWarehouse(
        businessId: widget.businessId,
        payload: {
          'code': codeCtrl.text.trim(),
          'name': nameCtrl.text.trim(),
          'is_default': isDefault,
        },
      );
      if (!mounted) return;
      _refreshTable();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
    }
  }

  Future<void> _showEditDialog(Warehouse w) async {
    final codeCtrl = TextEditingController(text: w.code);
    final nameCtrl = TextEditingController(text: w.name);
    bool isDefault = w.isDefault;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ویرایش انبار'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'کد')), 
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'نام')), 
            StatefulBuilder(builder: (ctx, setSt) {
              return CheckboxListTile(
                value: isDefault,
                onChanged: (v) => setSt(() => isDefault = v ?? false),
                title: const Text('پیش‌فرض'),
                controlAffinity: ListTileControlAffinity.leading,
              );
            }),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('ذخیره')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.updateWarehouse(
        businessId: widget.businessId,
        warehouseId: w.id!,
        payload: {
          'code': codeCtrl.text.trim(),
          'name': nameCtrl.text.trim(),
          'is_default': isDefault,
        },
      );
      if (!mounted) return;
      _refreshTable();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
    }
  }

  Future<void> _delete(Warehouse w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف انبار'),
        content: Text('آیا از حذف «${w.name}» مطمئن هستید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final deleted = await _service.deleteWarehouse(businessId: widget.businessId, warehouseId: w.id!);
      if (!mounted) return;
      if (deleted) {
        _refreshTable();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
    }
  }
}




