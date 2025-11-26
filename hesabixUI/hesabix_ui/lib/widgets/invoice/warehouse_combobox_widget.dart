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
  int? _selectedValue;

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.selectedWarehouseId;
    _load();
  }

  @override
  void didUpdateWidget(WarehouseComboboxWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedWarehouseId != widget.selectedWarehouseId) {
      _selectedValue = widget.selectedWarehouseId;
    }
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
    // ساخت لیست آیتم‌ها
    final List<DropdownMenuItem<int?>> menuItems = [
      if (!widget.isRequired)
        const DropdownMenuItem<int?>(
          value: null,
          child: Text('بدون انبار', maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ..._items.map((w) {
        final title = (w.code.isNotEmpty) ? '${w.code} - ${w.name}' : w.name;
        return DropdownMenuItem<int?>(
          value: w.id!,
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        );
      }),
    ];

    return DropdownButtonFormField<int?>(
      value: _selectedValue,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        labelText: widget.label,
        hintText: widget.hintText,
        border: const OutlineInputBorder(),
        suffixIcon: _selectedValue != null && !widget.isRequired
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  // به‌روزرسانی state داخلی و فراخوانی callback
                  setState(() {
                    _selectedValue = null;
                  });
                  widget.onChanged(null);
                },
                tooltip: 'پاک کردن',
              )
            : null,
      ),
      selectedItemBuilder: (BuildContext context) {
        // برگرداندن لیست ویجت‌ها با همان ترتیب items برای نمایش متن انتخاب شده
        final List<Widget> result = [];
        if (!widget.isRequired) {
          result.add(
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                'بدون انبار',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          );
        }
        for (final w in _items) {
          final title = (w.code.isNotEmpty) ? '${w.code} - ${w.name}' : w.name;
          result.add(
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          );
        }
        return result;
      },
      items: menuItems,
      onChanged: (int? value) {
        setState(() {
          _selectedValue = value;
        });
        widget.onChanged(value);
      },
      validator: widget.isRequired
          ? (value) => value == null ? '${widget.label} الزامی است' : null
          : null,
    );
  }
}


