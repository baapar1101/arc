import 'package:flutter/material.dart';

import '../../services/warehouse_location_service.dart';

/// انتخاب اختیاری محل فیزیکی داخل یک انبار (درخت محل‌ها به صورت لیست مسطح).
class WarehouseLocationDropdown extends StatefulWidget {
  final int businessId;
  final int? warehouseId;
  final int? selectedLocationId;
  final ValueChanged<int?> onChanged;
  final String label;
  final bool enabled;

  const WarehouseLocationDropdown({
    super.key,
    required this.businessId,
    required this.warehouseId,
    required this.selectedLocationId,
    required this.onChanged,
    this.label = 'محل انبار',
    this.enabled = true,
  });

  @override
  State<WarehouseLocationDropdown> createState() =>
      _WarehouseLocationDropdownState();
}

class _WarehouseLocationDropdownState extends State<WarehouseLocationDropdown> {
  final WarehouseLocationService _svc = WarehouseLocationService();
  List<Map<String, dynamic>> _flat = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(WarehouseLocationDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.warehouseId != widget.warehouseId ||
        oldWidget.businessId != widget.businessId) {
      _load();
    }
  }

  Future<void> _load() async {
    final wid = widget.warehouseId;
    if (wid == null) {
      setState(() {
        _flat = [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final data = await _svc.fetchLocationsTree(
        businessId: widget.businessId,
        warehouseId: wid,
      );
      final flat = (data['flat'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _flat = flat;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _flat = [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wid = widget.warehouseId;
    if (wid == null) {
      return const SizedBox.shrink();
    }

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    final ids = _flat.map((m) => m['id'] as int?).whereType<int>().toSet();
    var selected = widget.selectedLocationId;
    if (selected != null && !ids.contains(selected)) {
      selected = null;
    }

    final items = <DropdownMenuItem<int?>>[
      const DropdownMenuItem<int?>(
        value: null,
        child: Text('— بدون محل —'),
      ),
      ..._flat.map((loc) {
        final id = loc['id'] as int?;
        final path = loc['path_codes']?.toString() ?? loc['code']?.toString() ?? '';
        final name = loc['name']?.toString() ?? '';
        final label = path.isNotEmpty ? '$path — $name' : name;
        return DropdownMenuItem<int?>(
          value: id,
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }),
    ];

    return DropdownButtonFormField<int?>(
      key: ValueKey('whloc_${wid}_${selected}_${_flat.length}'),
      initialValue: selected,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      isExpanded: true,
      items: items,
      onChanged: widget.enabled ? widget.onChanged : null,
    );
  }
}
