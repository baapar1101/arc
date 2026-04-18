import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/warehouse_model.dart';
import '../../services/product_service.dart';
import '../../services/warehouse_location_service.dart';
import '../../services/warehouse_service.dart';
import '../../utils/snackbar_helper.dart';

const _kLocationKinds = <String, String>{
  'zone': 'منطقه',
  'aisle': 'ردیف / راهرو',
  'rack': 'قفسه',
  'shelf': 'طبقه',
  'bin': 'سلول / باکس',
  'other': 'سایر',
};

/// مدیریت سلسله‌مراتب محل‌ها و ثبت قرارگیری کالا برای یک انبار مشخص.
class WarehouseLocationsPage extends StatefulWidget {
  final int businessId;
  final int warehouseId;

  const WarehouseLocationsPage({
    super.key,
    required this.businessId,
    required this.warehouseId,
  });

  @override
  State<WarehouseLocationsPage> createState() => _WarehouseLocationsPageState();
}

class _WarehouseLocationsPageState extends State<WarehouseLocationsPage> {
  final WarehouseService _whService = WarehouseService();
  final WarehouseLocationService _locService = WarehouseLocationService();
  final ProductService _productService = ProductService();

  Warehouse? _warehouse;
  bool _loadingMeta = true;
  bool _loadingTree = true;
  String? _error;

  List<Map<String, dynamic>> _roots = [];
  List<Map<String, dynamic>> _flat = [];
  List<Map<String, dynamic>> _placements = [];

  int? _selectedLocationId;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loadingMeta = true;
      _error = null;
    });
    try {
      final w = await _whService.getWarehouse(
        businessId: widget.businessId,
        warehouseId: widget.warehouseId,
      );
      if (!mounted) return;
      setState(() {
        _warehouse = w;
        _loadingMeta = false;
      });
      await _reloadTree();
      await _reloadPlacements();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMeta = false;
        _error = '$e';
      });
    }
  }

  Future<void> _reloadTree() async {
    setState(() => _loadingTree = true);
    try {
      final data = await _locService.fetchLocationsTree(
        businessId: widget.businessId,
        warehouseId: widget.warehouseId,
      );
      final tree = (data['tree'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final flat = (data['flat'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _roots = tree;
        _flat = flat;
        _loadingTree = false;
        if (_selectedLocationId != null &&
            !_flat.any((x) => x['id'] == _selectedLocationId)) {
          _selectedLocationId = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingTree = false;
        _error = '$e';
      });
    }
  }

  Future<void> _reloadPlacements() async {
    try {
      final data = await _locService.listPlacements(
        businessId: widget.businessId,
        warehouseId: widget.warehouseId,
        locationId: _selectedLocationId,
      );
      final items = (data['items'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() => _placements = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _placements = []);
    }
  }

  Future<void> _pickLocationFilter() async {
    final chosen = await showModalBottomSheet<int?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              ListTile(
                title: const Text('همهٔ قرارگیری‌ها در این انبار'),
                leading: const Icon(Icons.all_inclusive),
                onTap: () => Navigator.pop(ctx, -1),
              ),
              const Divider(height: 1),
              ..._flat.map((loc) {
                final id = loc['id'] as int?;
                final label = '${loc['path_codes'] ?? loc['code']} — ${loc['name']}';
                return ListTile(
                  title: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
                  selected: id == _selectedLocationId,
                  onTap: () => Navigator.pop(ctx, id),
                );
              }),
            ],
          ),
        );
      },
    );
    if (!mounted || chosen == null) return;
    setState(() {
      _selectedLocationId = chosen == -1 ? null : chosen;
    });
    await _reloadPlacements();
  }

  Future<void> _showLocationDialog({Map<String, dynamic>? existing, int? parentId}) async {
    final codeCtrl = TextEditingController(text: existing?['code']?.toString() ?? '');
    final nameCtrl = TextEditingController(text: existing?['name']?.toString() ?? '');
    final notesCtrl = TextEditingController(text: existing?['notes']?.toString() ?? '');
    String kind = (existing?['location_kind']?.toString() ?? 'zone');
    if (!_kLocationKinds.containsKey(kind)) kind = 'zone';
    int sortOrder = int.tryParse('${existing?['sort_order'] ?? 0}') ?? 0;
    bool active = existing?['is_active'] != false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(existing == null ? 'محل جدید' : 'ویرایش محل'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: codeCtrl,
                      decoration: const InputDecoration(labelText: 'کد محل (یکتا در این انبار)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'نام نمایشی'),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey(kind),
                      initialValue: kind,
                      decoration: const InputDecoration(labelText: 'نوع'),
                      items: _kLocationKinds.entries
                          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                          .toList(),
                      onChanged: (v) => setLocal(() => kind = v ?? 'zone'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(labelText: 'ترتیب نمایش'),
                            keyboardType: TextInputType.number,
                            controller: TextEditingController(text: '$sortOrder'),
                            onChanged: (v) => sortOrder = int.tryParse(v) ?? 0,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('فعال'),
                            value: active,
                            onChanged: (v) => setLocal(() => active = v),
                          ),
                        ),
                      ],
                    ),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(labelText: 'یادداشت'),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ذخیره')),
              ],
            );
          },
        );
      },
    );

    if (ok != true || !mounted) return;

    final payload = <String, dynamic>{
      'code': codeCtrl.text.trim(),
      'name': nameCtrl.text.trim(),
      'location_kind': kind,
      'sort_order': sortOrder,
      'is_active': active,
      'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
    };

    if (existing == null && parentId != null) {
      payload['parent_id'] = parentId;
    }

    try {
      if (existing == null) {
        await _locService.createLocation(
          businessId: widget.businessId,
          warehouseId: widget.warehouseId,
          payload: payload,
        );
      } else {
        await _locService.updateLocation(
          businessId: widget.businessId,
          warehouseId: widget.warehouseId,
          locationId: existing['id'] as int,
          payload: payload,
        );
      }
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: 'ذخیره شد');
      await _reloadTree();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: '$e');
    }
  }

  Future<void> _deleteLocation(Map<String, dynamic> loc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف محل'),
        content: Text('حذف «${loc['name']}»؟ زیرمجموعه یا قرارگیری‌ها مانع حذف می‌شوند.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('خیر')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      final deleted = await _locService.deleteLocation(
        businessId: widget.businessId,
        warehouseId: widget.warehouseId,
        locationId: loc['id'] as int,
      );
      if (!mounted) return;
      if (deleted) {
        SnackBarHelper.showSuccess(context, message: 'حذف شد');
        await _reloadTree();
        await _reloadPlacements();
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: '$e');
    }
  }

  Future<void> _showPlacementDialog({Map<String, dynamic>? existing}) async {
    int? productId = existing?['product_id'] as int?;
    final qtyCtrl = TextEditingController(
      text: existing == null ? '0' : '${existing['quantity'] ?? 0}',
    );
    final notesCtrl = TextEditingController(text: existing?['notes']?.toString() ?? '');
    int? locationId = existing?['warehouse_location_id'] as int? ?? _selectedLocationId;
    if (locationId == null && _flat.isNotEmpty) {
      locationId = _flat.first['id'] as int?;
    }

    List<Map<String, dynamic>> searchResults = [];
    String? pickedSummary = existing == null
        ? null
        : '${existing['product_code']} — ${existing['product_name']}';

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text(existing == null ? 'قرارگیری کالا' : 'ویرایش قرارگیری'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (existing == null) ...[
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'جستجوی کالا (نام یا کد)',
                          ),
                          onChanged: (v) async {
                            if (v.trim().length < 2) {
                              setLocal(() => searchResults = []);
                              return;
                            }
                            final rows = await _productService.searchProducts(
                              businessId: widget.businessId,
                              searchQuery: v.trim(),
                              limit: 15,
                            );
                            setLocal(() => searchResults = rows);
                          },
                        ),
                        const SizedBox(height: 8),
                        if (productId != null)
                          Text(
                            'کالای انتخاب‌شده: ${pickedSummary ?? productId}',
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ...searchResults.map((p) {
                          final pid = p['id'] as int?;
                          final code = p['code']?.toString() ?? '';
                          final name = p['name']?.toString() ?? '';
                          return ListTile(
                            dense: true,
                            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(code),
                            onTap: () {
                              setLocal(() {
                                productId = pid;
                                pickedSummary = '$code — $name';
                                searchResults = [];
                              });
                            },
                          );
                        }),
                        const Divider(),
                      ] else
                        Text(pickedSummary ?? '', style: Theme.of(ctx).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        key: ValueKey(locationId ?? -1),
                        initialValue: locationId,
                        decoration: const InputDecoration(labelText: 'محل انبار'),
                        items: _flat
                            .map(
                              (loc) => DropdownMenuItem(
                                value: loc['id'] as int,
                                child: Text(
                                  '${loc['path_codes'] ?? loc['code']} — ${loc['name']}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setLocal(() => locationId = v),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: qtyCtrl,
                        decoration: const InputDecoration(labelText: 'مقدار در این محل'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: notesCtrl,
                        decoration: const InputDecoration(labelText: 'یادداشت'),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
                FilledButton(
                  onPressed: () async {
                    if (productId == null && existing == null) {
                      SnackBarHelper.showError(ctx, message: 'کالا را انتخاب کنید');
                      return;
                    }
                    if (locationId == null) {
                      SnackBarHelper.showError(ctx, message: 'محل را انتخاب کنید');
                      return;
                    }
                    try {
                      final qty = double.tryParse(qtyCtrl.text.trim()) ?? 0;
                      if (existing == null) {
                        await _locService.createPlacement(
                          businessId: widget.businessId,
                          warehouseId: widget.warehouseId,
                          payload: {
                            'product_id': productId,
                            'warehouse_location_id': locationId,
                            'quantity': qty,
                            'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                          },
                        );
                      } else {
                        await _locService.updatePlacement(
                          businessId: widget.businessId,
                          warehouseId: widget.warehouseId,
                          placementId: existing['id'] as int,
                          payload: {
                            'warehouse_location_id': locationId,
                            'quantity': qty,
                            'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                          },
                        );
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (!mounted) return;
                      SnackBarHelper.showSuccess(context, message: 'ذخیره شد');
                      await _reloadPlacements();
                    } catch (e) {
                      if (ctx.mounted) {
                        SnackBarHelper.showError(ctx, message: '$e');
                      }
                    }
                  },
                  child: const Text('ذخیره'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showReconciliationDialog() async {
    try {
      final data = await _locService.fetchPlacementReconciliation(
        businessId: widget.businessId,
        warehouseId: widget.warehouseId,
      );
      if (!mounted) return;
      final items = (data['items'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final mismatch = data['mismatch_count'];
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تطبیق قرارگیری با موجودی حسابداری'),
          content: SizedBox(
            width: 520,
            height: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'کالاهایی که حداقل یک قرارگیری ثبت شده دارند. تفاوت مثبت یعنی مجموع محل‌ها بیشتر از ماندهٔ سیستم است.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text('تعداد اختلاف معنادار: ${mismatch ?? 0}'),
                const SizedBox(height: 8),
                Expanded(
                  child: items.isEmpty
                      ? const Center(child: Text('داده‌ای برای مقایسه نیست'))
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, index) => const Divider(height: 1),
                          itemBuilder: (c, i) {
                            final row = items[i];
                            final diff = row['difference'];
                            return ListTile(
                              dense: true,
                              title: Text(row['product_name']?.toString() ?? ''),
                              subtitle: Text(
                                'حسابداری: ${row['accounting_quantity']} — مجموع محل‌ها: ${row['placed_quantity_sum']} — اختلاف: $diff',
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: '$e');
    }
  }

  Future<void> _deletePlacement(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف قرارگیری'),
        content: Text('حذف رکورد برای «${row['product_name']}»؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('خیر')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _locService.deletePlacement(
        businessId: widget.businessId,
        warehouseId: widget.warehouseId,
        placementId: row['id'] as int,
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: 'حذف شد');
      await _reloadPlacements();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _warehouse == null
        ? 'چیدمان انبار'
        : 'چیدمان: ${_warehouse!.name}';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            }
          },
        ),
        actions: [
          IconButton(
            tooltip: 'تطبیق موجودی با قرارگیری',
            onPressed: _showReconciliationDialog,
            icon: const Icon(Icons.fact_check_outlined),
          ),
          IconButton(
            tooltip: 'تازه‌سازی',
            onPressed: () {
              _loadAll();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loadingMeta
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _warehouse == null
              ? Center(child: Text(_error!))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    final treePane = Card(
                      margin: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Text(
                                  'درخت محل‌ها',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const Spacer(),
                                FilledButton.tonalIcon(
                                  onPressed: _loadingTree
                                      ? null
                                      : () => _showLocationDialog(parentId: null),
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('ریشه'),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: _loadingTree
                                ? const Center(child: CircularProgressIndicator())
                                : _roots.isEmpty
                                    ? Center(
                                        child: Text(
                                          'هنوز محلی تعریف نشده.\nاز «ریشه» یک منطقه یا قفسه اضافه کنید.',
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context).textTheme.bodyMedium,
                                        ),
                                      )
                                    : ListView(
                                        padding: const EdgeInsets.only(bottom: 80),
                                        children: _roots
                                            .map((n) => _LocationNodeTile(
                                                  node: n,
                                                  onAddChild: (pid) =>
                                                      _showLocationDialog(parentId: pid),
                                                  onEdit: (m) =>
                                                      _showLocationDialog(existing: m),
                                                  onDelete: _deleteLocation,
                                                ))
                                            .toList(),
                                      ),
                          ),
                        ],
                      ),
                    );

                    final placePane = Card(
                      margin: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'قرارگیری کالاها',
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                    const Spacer(),
                                    FilledButton.icon(
                                      onPressed: _flat.isEmpty
                                          ? null
                                          : () => _showPlacementDialog(),
                                      icon: const Icon(Icons.add, size: 18),
                                      label: const Text('افزودن'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: _pickLocationFilter,
                                  icon: const Icon(Icons.filter_alt_outlined, size: 18),
                                  label: Text(
                                    _selectedLocationId == null
                                        ? 'فیلتر: همهٔ انبار'
                                        : 'فیلتر: یک محل خاص',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: _placements.isEmpty
                                ? Center(
                                    child: Text(
                                      _flat.isEmpty
                                          ? 'ابتدا محل تعریف کنید.'
                                          : 'برای این فیلتر قرارگیری ثبت نشده.',
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.all(8),
                                    itemCount: _placements.length,
                                    separatorBuilder: (context, index) => const Divider(height: 1),
                                    itemBuilder: (ctx, i) {
                                      final row = _placements[i];
                                      return ListTile(
                                        title: Text(
                                          row['product_name']?.toString() ?? '',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text(
                                          '${row['path_codes'] ?? row['location_code']} — '
                                          '${row['quantity']} ${row['main_unit']}',
                                          maxLines: 2,
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              tooltip: 'ویرایش',
                                              icon: const Icon(Icons.edit_outlined),
                                              onPressed: () =>
                                                  _showPlacementDialog(existing: row),
                                            ),
                                            IconButton(
                                              tooltip: 'حذف',
                                              icon: const Icon(Icons.delete_outline),
                                              onPressed: () => _deletePlacement(row),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    );

                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 5, child: treePane),
                          Expanded(flex: 6, child: placePane),
                        ],
                      );
                    }
                    return ListView(
                      children: [
                        SizedBox(height: 420, child: treePane),
                        SizedBox(height: 480, child: placePane),
                      ],
                    );
                  },
                ),
    );
  }
}

class _LocationNodeTile extends StatelessWidget {
  final Map<String, dynamic> node;
  final void Function(int parentId) onAddChild;
  final void Function(Map<String, dynamic>) onEdit;
  final void Function(Map<String, dynamic>) onDelete;

  const _LocationNodeTile({
    required this.node,
    required this.onAddChild,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final children = (node['children'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final code = node['code']?.toString() ?? '';
    final name = node['name']?.toString() ?? '';
    final kind = node['location_kind']?.toString() ?? '';
    final kindLabel = _kLocationKinds[kind] ?? kind;
    final active = node['is_active'] != false;

    return ExpansionTile(
      key: PageStorageKey<int?>(node['id'] as int?),
      title: Text(
        '$code — $name',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: active ? null : Theme.of(context).disabledColor,
        ),
      ),
      subtitle: Text(kindLabel, style: Theme.of(context).textTheme.bodySmall),
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 12, bottom: 8),
          child: Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => onAddChild(node['id'] as int),
                icon: const Icon(Icons.subdirectory_arrow_right, size: 18),
                label: const Text('زیرمجموعه'),
              ),
              TextButton.icon(
                onPressed: () => onEdit(node),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('ویرایش'),
              ),
              TextButton.icon(
                onPressed: () => onDelete(node),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('حذف'),
              ),
            ],
          ),
        ),
        ...children.map(
          (c) => Padding(
            padding: const EdgeInsetsDirectional.only(start: 12),
            child: _LocationNodeTile(
              node: c,
              onAddChild: onAddChild,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
          ),
        ),
      ],
    );
  }
}
