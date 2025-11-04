import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/warehouse_service.dart';
import '../../models/warehouse_model.dart';

class WarehouseComboboxWidget extends StatefulWidget {
  final int businessId;
  final int? selectedWarehouseId;
  final ValueChanged<int?> onChanged;
  final String label;
  final String hintText;
  final bool isRequired;

  const WarehouseComboboxWidget({
    super.key,
    required this.businessId,
    required this.onChanged,
    this.selectedWarehouseId,
    this.label = 'انبار',
    this.hintText = 'انتخاب انبار',
    this.isRequired = false,
  });

  @override
  State<WarehouseComboboxWidget> createState() => _WarehouseComboboxWidgetState();
}

class _WarehouseComboboxWidgetState extends State<WarehouseComboboxWidget> {
  final WarehouseService _service = WarehouseService();
  List<Warehouse> _items = const <Warehouse>[];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await _service.listWarehouses(businessId: widget.businessId);
      if (!mounted) return;
      setState(() => _items = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _items = const <Warehouse>[]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return SizedBox(
        height: 36,
        child: Center(
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary)),
        ),
      );
    }
    return DropdownButtonFormField<int>(
      value: widget.selectedWarehouseId,
      isDense: true,
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      items: _items.map((w) {
        final title = (w.code.isNotEmpty) ? '${w.code} - ${w.name}' : w.name;
        return DropdownMenuItem<int>(value: w.id!, child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis));
      }).toList(),
      onChanged: widget.onChanged,
      hint: Text(widget.hintText),
    );
  }
}


