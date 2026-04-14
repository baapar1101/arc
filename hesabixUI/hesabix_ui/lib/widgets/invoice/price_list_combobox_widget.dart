import 'package:flutter/material.dart';
import '../../services/price_list_service.dart';
import '../../core/api_client.dart';

class PriceListComboboxWidget extends StatefulWidget {
  final int businessId;
  final int? selectedPriceListId;
  final ValueChanged<Map<String, dynamic>?> onChanged;
  final String label;
  final String hintText;

  const PriceListComboboxWidget({
    super.key,
    required this.businessId,
    required this.onChanged,
    this.selectedPriceListId,
    this.label = 'لیست قیمت',
    this.hintText = 'انتخاب لیست قیمت',
  });

  @override
  State<PriceListComboboxWidget> createState() => _PriceListComboboxWidgetState();
}

class _PriceListComboboxWidgetState extends State<PriceListComboboxWidget> {
  final PriceListService _service = PriceListService(apiClient: ApiClient());
  bool _loading = false;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];
  Map<String, dynamic>? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _service.listPriceLists(businessId: widget.businessId, limit: 50);
      final items = (res['items'] as List?)?.cast<dynamic>().map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? const <Map<String, dynamic>>[];
      Map<String, dynamic>? selected;
      if (widget.selectedPriceListId != null) {
        selected = items.firstWhere((e) => e['id'] == widget.selectedPriceListId, orElse: () => <String, dynamic>{});
        if (selected.isEmpty) selected = null;
      }
      setState(() {
        _items = items;
        _selected = selected ?? (items.isNotEmpty ? items.first : null);
      });
      widget.onChanged(_selected);
    } catch (_) {
      setState(() {
        _items = const <Map<String, dynamic>>[];
        _selected = null;
      });
      widget.onChanged(null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Tooltip(
        message: _selected != null ? (_selected!['name']?.toString() ?? '') : widget.hintText,
        child: DropdownButtonFormField<int>(
        initialValue: _selected != null ? (_selected!['id'] as int) : null,
        isExpanded: true,
        items: _items
            .map((e) => DropdownMenuItem<int>(
                  value: e['id'] as int,
                  child: Tooltip(message: e['name']?.toString() ?? '', child: Text(e['name']?.toString() ?? '')),
                ))
            .toList(),
        onChanged: _loading
            ? null
            : (val) {
                final sel = _items.firstWhere((e) => e['id'] == val, orElse: () => <String, dynamic>{});
                setState(() => _selected = sel.isEmpty ? null : sel);
                widget.onChanged(_selected);
              },
        decoration: InputDecoration(
          isDense: true,
          labelText: widget.label,
          hintText: widget.hintText,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        ),
      ),
    );
  }
}


