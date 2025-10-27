import 'package:flutter/material.dart';
import '../../services/warehouse_service.dart';
import '../../models/warehouse_model.dart';

class WarehousesPage extends StatefulWidget {
  final int businessId;
  const WarehousesPage({super.key, required this.businessId});

  @override
  State<WarehousesPage> createState() => _WarehousesPageState();
}

class _WarehousesPageState extends State<WarehousesPage> {
  final WarehouseService _service = WarehouseService();
  bool _loading = true;
  String? _error;
  List<Warehouse> _items = const <Warehouse>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final items = await _service.listWarehouses(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _items = items;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مدیریت انبارها')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: Colors.red.shade700)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, idx) {
                      final w = _items[idx];
                      return ListTile(
                        leading: Icon(w.isDefault ? Icons.star : Icons.store, color: w.isDefault ? Colors.orange : null),
                        title: Text('${w.code} - ${w.name}'),
                        subtitle: Text(w.description ?? ''),
                        onTap: () => _showEditDialog(w),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(w),
                        ),
                      );
                    },
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
      final created = await _service.createWarehouse(
        businessId: widget.businessId,
        payload: {
          'code': codeCtrl.text.trim(),
          'name': nameCtrl.text.trim(),
          'is_default': isDefault,
        },
      );
      if (!mounted) return;
      setState(() {
        _items = [created, ..._items];
      });
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
      final updated = await _service.updateWarehouse(
        businessId: widget.businessId,
        warehouseId: w.id!,
        payload: {
          'code': codeCtrl.text.trim(),
          'name': nameCtrl.text.trim(),
          'is_default': isDefault,
        },
      );
      if (!mounted) return;
      setState(() {
        _items = _items.map((e) => e.id == updated.id ? updated : e).toList();
      });
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
        setState(() {
          _items = _items.where((e) => e.id != w.id).toList();
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
    }
  }
}




