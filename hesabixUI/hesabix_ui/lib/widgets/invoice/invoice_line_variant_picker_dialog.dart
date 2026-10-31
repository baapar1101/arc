import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../services/product_variant_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/number_normalizer.dart';
import '../../utils/snackbar_helper.dart';

class InvoiceLineVariantPickerDialog extends StatefulWidget {
  final int businessId;
  final int productId;
  final String productName;
  final num lineQuantity;
  final int? warehouseId;
  final List<Map<String, dynamic>> initialAllocations;
  final bool allowSplit;

  const InvoiceLineVariantPickerDialog({
    super.key,
    required this.businessId,
    required this.productId,
    required this.productName,
    required this.lineQuantity,
    this.warehouseId,
    this.initialAllocations = const [],
    this.allowSplit = true,
  });

  @override
  State<InvoiceLineVariantPickerDialog> createState() => _InvoiceLineVariantPickerDialogState();
}

class _InvoiceLineVariantPickerDialogState extends State<InvoiceLineVariantPickerDialog> {
  final _svc = ProductVariantService();
  List<Map<String, dynamic>> _variants = [];
  Map<int, String> _balances = {};
  final Map<int, TextEditingController> _qty = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final variants = await _svc.listVariants(
        businessId: widget.businessId,
        productId: widget.productId,
      );
      final balances = await _svc.listBalances(
        businessId: widget.businessId,
        productId: widget.productId,
        warehouseId: widget.warehouseId,
      );
      final initial = <int, String>{};
      for (final item in widget.initialAllocations) {
        final id = (item['variant_id'] as num?)?.toInt();
        if (id != null) initial[id] = item['quantity']?.toString() ?? '';
      }
      if (!widget.allowSplit && initial.isEmpty && variants.length == 1) {
        final only = (variants.first['id'] as num?)?.toInt();
        if (only != null) initial[only] = widget.lineQuantity.toString();
      }
      if (mounted) {
        setState(() {
          _variants = variants.where((v) => v['is_active'] != false).toList();
          _balances = {
            for (final b in balances)
              if ((widget.warehouseId == null || (b['warehouse_id'] as num?)?.toInt() == widget.warehouseId)
                  && (b['variant_id'] as num?) != null)
                (b['variant_id'] as num).toInt(): b['quantity']?.toString() ?? '0',
          };
          for (final row in _variants) {
            final id = (row['id'] as num).toInt();
            _qty[id] = TextEditingController(text: initial[id] ?? '');
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.userMessage(e));
    }
  }

  void _submit() {
    final t = AppLocalizations.of(context);
    final allocations = <Map<String, dynamic>>[];
    num total = 0;
    _qty.forEach((id, ctrl) {
      final qty = parseFormattedNumber(ctrl.text) ?? 0;
      if (qty > 0) {
        allocations.add({'variant_id': id, 'quantity': qty});
        total += qty;
      }
    });
    if (allocations.isEmpty) {
      SnackBarHelper.showError(context, message: t.productVariantRequired);
      return;
    }
    if ((total - widget.lineQuantity).abs() > 0.000001) {
      SnackBarHelper.showError(context, message: t.productVariantAllocationMismatch);
      return;
    }
    Navigator.pop(context, allocations);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text('${t.productVariantSelectCombination} — ${widget.productName}'),
      content: SizedBox(
        width: 460,
        child: _loading
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  children: _variants.map((row) {
                    final id = (row['id'] as num).toInt();
                    final stock = _balances[id];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        controller: _qty[id],
                        decoration: InputDecoration(
                          labelText: row['display_title']?.toString() ?? id.toString(),
                          helperText: stock == null ? null : '${t.productVariantPhysicalStock}: $stock',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    );
                  }).toList(),
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(onPressed: _submit, child: Text(t.save)),
      ],
    );
  }
}

List<Map<String, dynamic>> allocationsFromExtra(Map<String, dynamic>? extra) {
  final raw = extra?['allocations'];
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}
