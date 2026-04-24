import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/warehouse_model.dart';
import '../../services/product_service.dart';
import '../../services/warehouse_location_service.dart';
import '../../services/warehouse_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/invoice/code_field_widget.dart';

const _kLocationKinds = <String, String>{
  'zone': 'منطقه',
  'aisle': 'ردیف / راهرو',
  'rack': 'قفسه',
  'shelf': 'طبقه',
  'bin': 'سلول / باکس',
  'other': 'سایر',
};

IconData _warehouseLocationKindIcon(String kind) {
  switch (kind) {
    case 'zone':
      return Icons.map_outlined;
    case 'aisle':
      return Icons.alt_route_outlined;
    case 'rack':
      return Icons.view_week_outlined;
    case 'shelf':
      return Icons.view_agenda_outlined;
    case 'bin':
      return Icons.inventory_2_outlined;
    default:
      return Icons.place_outlined;
  }
}

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

  Widget _locationDialogSectionTitle(
    BuildContext context,
    String title,
    IconData icon, {
    bool first = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 16, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: tt.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showLocationDialog({Map<String, dynamic>? existing, int? parentId}) async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: existing?['name']?.toString() ?? '');
    final notesCtrl = TextEditingController(text: existing?['notes']?.toString() ?? '');
    final sortOrderCtrl = TextEditingController(text: '${existing?['sort_order'] ?? 0}');
    String kind = (existing?['location_kind']?.toString() ?? 'zone');
    if (!_kLocationKinds.containsKey(kind)) kind = 'zone';
    bool active = existing?['is_active'] != false;
    var autoGenerateLocationCode = existing == null;
    String? manualLocationCode = existing?['code']?.toString();

    String? parentSummary;
    if (parentId != null) {
      try {
        final p = _flat.firstWhere((e) => e['id'] == parentId);
        parentSummary = '${p['path_codes'] ?? p['code']} — ${p['name']}';
      } catch (_) {
        parentSummary = null;
      }
    }

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocal) {
              final cs = Theme.of(ctx).colorScheme;
              final tt = Theme.of(ctx).textTheme;
              final screenW = MediaQuery.sizeOf(ctx).width;
              final dialogMaxW = math.min(screenW - 40, 460.0);

              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                constraints: BoxConstraints(maxWidth: dialogMaxW),
                insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                titlePadding: const EdgeInsets.fromLTRB(24, 24, 16, 8),
                contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                actionsAlignment: MainAxisAlignment.end,
                title: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: cs.primaryContainer,
                      foregroundColor: cs.onPrimaryContainer,
                      child: Icon(
                        existing == null ? Icons.add_location_alt_outlined : Icons.edit_location_alt_outlined,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            existing == null ? 'محل جدید' : 'ویرایش محل',
                            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _warehouse?.name ?? 'انبار',
                            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          if (parentSummary != null) ...[
                            const SizedBox(height: 10),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.subdirectory_arrow_right, size: 20, color: cs.primary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'افزودن به عنوان زیرمجموعه',
                                            style: tt.labelSmall?.copyWith(color: cs.primary),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(parentSummary!, style: tt.bodySmall),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                content: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _locationDialogSectionTitle(ctx, 'شناسه و نام', Icons.tag_outlined, first: true),
                        CodeFieldWidget(
                          key: ValueKey<Object?>(
                            existing == null ? 'loc_new' : 'loc_edit_${existing['id']}',
                          ),
                          initialValue: existing?['code']?.toString(),
                          autoGenerateCode: existing == null,
                          warehouseLocationCode: true,
                          showAutoManualToggle: existing == null,
                          isRequired: true,
                          label: 'کد محل',
                          hintText: 'مثال: LOC-20260419-0001',
                          onChanged: (v) => manualLocationCode = v,
                          onAutoGenerateChanged: existing == null
                              ? (auto) {
                                  autoGenerateLocationCode = auto;
                                  setLocal(() {});
                                }
                              : null,
                        ),
                        if (existing == null && autoGenerateLocationCode)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'کد از تنظیمات «کد محل انبار» در شماره‌گذاری اسناد تولید می‌شود.',
                              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: nameCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'نام نمایشی',
                            hintText: 'مثال: ردیف الف — قفسه ۳',
                            filled: true,
                            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'نام نمایشی الزامی است';
                            }
                            return null;
                          },
                        ),
                        _locationDialogSectionTitle(ctx, 'نوع محل', Icons.category_outlined),
                        DropdownButtonFormField<String>(
                          key: ValueKey(kind),
                          initialValue: kind,
                          decoration: InputDecoration(
                            labelText: 'نوع در سلسله‌مراتب',
                            filled: true,
                            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          items: _kLocationKinds.entries
                              .map(
                                (e) => DropdownMenuItem<String>(
                                  value: e.key,
                                  child: Row(
                                    children: [
                                      Icon(_warehouseLocationKindIcon(e.key), size: 20, color: cs.primary),
                                      const SizedBox(width: 10),
                                      Text(e.value),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setLocal(() => kind = v ?? 'zone'),
                        ),
                        _locationDialogSectionTitle(ctx, 'نمایش و وضعیت', Icons.tune_outlined),
                        Material(
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextFormField(
                                  controller: sortOrderCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'ترتیب نمایش در درخت',
                                    hintText: 'عدد کوچکتر = بالاتر (مثلاً ۰، ۱، ۲)',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) return null;
                                    if (int.tryParse(v.trim()) == null) {
                                      return 'عدد معتبر وارد کنید';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 4),
                                SwitchListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                  title: const Text('فعال در سیستم'),
                                  subtitle: Text(
                                    active
                                        ? 'در لیست محل‌ها و انتخاب‌ها دیده می‌شود.'
                                        : 'نامعتبر؛ در انتخاب‌های جدید پیشنهاد نمی‌شود.',
                                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                  ),
                                  value: active,
                                  onChanged: (v) => setLocal(() => active = v),
                                ),
                              ],
                            ),
                          ),
                        ),
                        _locationDialogSectionTitle(ctx, 'یادداشت', Icons.notes_outlined),
                        TextField(
                          controller: notesCtrl,
                          minLines: 2,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: 'اختیاری — برای راهنمای پرسنل انبار',
                            filled: true,
                            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('انصراف'),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      if (!formKey.currentState!.validate()) return;
                      Navigator.pop(ctx, true);
                    },
                    icon: const Icon(Icons.save_outlined, size: 20),
                    label: const Text('ذخیره'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (ok != true || !mounted) return;

      final payload = <String, dynamic>{
        'name': nameCtrl.text.trim(),
        'location_kind': kind,
        'sort_order': int.tryParse(sortOrderCtrl.text.trim()) ?? 0,
        'is_active': active,
        'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
      };

      if (existing == null) {
        if (autoGenerateLocationCode) {
          payload['auto_generate_code'] = true;
        } else {
          payload['code'] = (manualLocationCode ?? '').trim();
          payload['auto_generate_code'] = false;
        }
      } else {
        payload['code'] = (manualLocationCode ?? '').trim();
      }

      if (existing == null && parentId != null) {
        payload['parent_id'] = parentId;
      }

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
    } finally {
      nameCtrl.dispose();
      notesCtrl.dispose();
      sortOrderCtrl.dispose();
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
