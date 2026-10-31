import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/calendar_controller.dart';
import '../../models/product_form_data.dart';
import '../../services/product_variant_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/number_normalizer.dart';
import '../../utils/snackbar_helper.dart';
import '../date_input_field.dart';

class ProductVariantInventorySection extends StatefulWidget {
  final int businessId;
  final int? productId;
  final ProductFormData formData;
  final List<Map<String, dynamic>> attributes;
  final ValueChanged<ProductFormData> onChanged;
  final List<Map<String, dynamic>> warehouses;

  const ProductVariantInventorySection({
    super.key,
    required this.businessId,
    required this.productId,
    required this.formData,
    required this.attributes,
    required this.onChanged,
    this.warehouses = const [],
  });

  @override
  State<ProductVariantInventorySection> createState() => _ProductVariantInventorySectionState();
}

class _ProductVariantInventorySectionState extends State<ProductVariantInventorySection> {
  final _svc = ProductVariantService();
  List<Map<String, dynamic>> _variants = [];
  bool _loading = false;

  bool get _isBulk => (widget.formData.inventoryMode ?? 'bulk') != 'unique';

  List<Map<String, dynamic>> get _selectAttributes => widget.attributes.where((attr) {
        final selected = widget.formData.selectedAttributeIds.contains(_asInt(attr['id']));
        return selected && (attr['data_type']?.toString() ?? 'text') == 'select';
      }).toList();

  @override
  void initState() {
    super.initState();
    _reloadVariants();
  }

  @override
  void didUpdateWidget(covariant ProductVariantInventorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId) {
      _reloadVariants();
    }
  }

  Future<void> _reloadVariants() async {
    final productId = widget.productId;
    if (productId == null) {
      setState(() => _variants = []);
      return;
    }
    setState(() => _loading = true);
    try {
      final rows = await _svc.listVariants(businessId: widget.businessId, productId: productId);
      if (mounted) setState(() => _variants = rows);
    } catch (_) {
      if (mounted) setState(() => _variants = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleDimension(int attributeId, bool enabled) {
    final t = AppLocalizations.of(context);
    final next = Set<int>.from(widget.formData.inventoryDimensionAttributeIds);
    if (enabled) {
      if (next.length >= 2 && !next.contains(attributeId)) {
        SnackBarHelper.showError(context, message: t.productVariantDimensionLimit);
        return;
      }
      next.add(attributeId);
    } else {
      next.remove(attributeId);
    }
    widget.onChanged(widget.formData.copyWith(inventoryDimensionAttributeIds: next));
  }

  Future<void> _addCombination() async {
    final t = AppLocalizations.of(context);
    final productId = widget.productId;
    if (productId == null) {
      SnackBarHelper.show(context, message: t.productVariantSaveThenCombine);
      return;
    }
    final dims = widget.formData.inventoryDimensionAttributeIds;
    if (dims.isEmpty) return;
    final selected = <int, int>{};
    final codeCtrl = TextEditingController();
    final barcodeCtrl = TextEditingController();
    final salesCtrl = TextEditingController();
    final purchaseCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(t.productVariantAddCombination),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ..._selectAttributes.where((a) => dims.contains(_asInt(a['id']))).map((attr) {
                    final options = _optionItems(attr);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: DropdownButtonFormField<int>(
                        decoration: InputDecoration(labelText: attr['title']?.toString() ?? ''),
                        items: options
                            .map(
                              (opt) => DropdownMenuItem<int>(
                                value: _asInt(opt['id']),
                                child: Text(opt['label']?.toString() ?? opt.toString()),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) selected[_asInt(attr['id'])!] = v;
                        },
                      ),
                    );
                  }),
                  TextField(controller: codeCtrl, decoration: InputDecoration(labelText: t.productVariantCode)),
                  const SizedBox(height: 8),
                  TextField(controller: barcodeCtrl, decoration: InputDecoration(labelText: t.productVariantBarcode)),
                  const SizedBox(height: 8),
                  TextField(controller: salesCtrl, decoration: InputDecoration(labelText: t.productVariantSalesPrice)),
                  const SizedBox(height: 8),
                  TextField(controller: purchaseCtrl, decoration: InputDecoration(labelText: t.productVariantPurchasePrice)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
          ],
        );
      },
    );
    if (ok != true || !mounted) return;
    try {
      await _svc.createVariant(
        businessId: widget.businessId,
        productId: productId,
        payload: {
          'attribute_values': [
            for (final e in selected.entries) {'attribute_id': e.key, 'option_id': e.value},
          ],
          if (codeCtrl.text.trim().isNotEmpty) 'code': codeCtrl.text.trim(),
          if (barcodeCtrl.text.trim().isNotEmpty) 'barcode': barcodeCtrl.text.trim(),
          if (salesCtrl.text.trim().isNotEmpty) 'sales_price': salesCtrl.text.trim(),
          if (purchaseCtrl.text.trim().isNotEmpty) 'purchase_price': purchaseCtrl.text.trim(),
        },
      );
      await _reloadVariants();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.userMessage(e));
    }
  }

  Future<void> _openEnableWizard() async {
    final productId = widget.productId;
    if (productId == null || _variants.isEmpty) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => ProductVariantEnableWizardDialog(
        businessId: widget.businessId,
        productId: productId,
        variants: _variants,
        warehouses: widget.warehouses,
      ),
    );
    if (result == true && mounted) {
      SnackBarHelper.show(context, message: AppLocalizations.of(context).productVariantEnableSuccess);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isBulk || widget.formData.selectedAttributeIds.isEmpty) {
      return const SizedBox.shrink();
    }
    final t = AppLocalizations.of(context);
    final selectAttrs = _selectAttributes;
    if (selectAttrs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(t.productVariantInventorySplit, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(t.productVariantInventorySplitHint, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: selectAttrs.map((attr) {
            final id = _asInt(attr['id']);
            if (id == null) return const SizedBox.shrink();
            final selected = widget.formData.inventoryDimensionAttributeIds.contains(id);
            return FilterChip(
              label: Text('${attr['title'] ?? id} · ${t.productVariantInventorySplit}'),
              selected: selected,
              onSelected: (v) => _toggleDimension(id, v),
            );
          }).toList(),
        ),
        if (widget.productId == null && widget.formData.inventoryDimensionAttributeIds.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(t.productVariantSaveThenCombine, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (widget.productId != null && widget.formData.inventoryDimensionAttributeIds.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Text(t.productVariantCombinations, style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              TextButton.icon(
                onPressed: _addCombination,
                icon: const Icon(Icons.add),
                label: Text(t.productVariantAddCombination),
              ),
              if (_variants.where((v) => v['is_active'] != false).isNotEmpty)
                FilledButton(
                  onPressed: _openEnableWizard,
                  child: Text(t.productVariantEnableInventory),
                ),
            ],
          ),
          if (_loading) const LinearProgressIndicator(),
          if (!_loading && _variants.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(t.productVariantNoCombinations),
            ),
          ..._variants.map((row) {
            final active = row['is_active'] != false;
            return ListTile(
              dense: true,
              title: Text(row['display_title']?.toString() ?? row['combination_key']?.toString() ?? ''),
              subtitle: Text([
                if ((row['code'] ?? '').toString().isNotEmpty) '${t.productVariantCode}: ${row['code']}',
                if ((row['barcode'] ?? '').toString().isNotEmpty) '${t.productVariantBarcode}: ${row['barcode']}',
              ].join(' · ')),
              trailing: active
                  ? TextButton(
                      onPressed: () async {
                        try {
                          await _svc.deactivateVariant(
                            businessId: widget.businessId,
                            productId: widget.productId!,
                            variantId: _asInt(row['id'])!,
                          );
                          await _reloadVariants();
                        } catch (e) {
                          if (!mounted) return;
                          SnackBarHelper.showError(context, message: ErrorExtractor.userMessage(e));
                        }
                      },
                      child: Text(t.productVariantDeactivate),
                    )
                  : Text(t.productVariantActive, style: Theme.of(context).textTheme.bodySmall),
            );
          }),
        ],
      ],
    );
  }

  List<Map<String, dynamic>> _optionItems(Map<String, dynamic> attr) {
    final raw = attr['option_items'];
    if (raw is List && raw.isNotEmpty) {
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    final labels = attr['options'];
    if (labels is List) {
      return [
        for (var i = 0; i < labels.length; i++)
          {'id': i + 1, 'label': labels[i].toString()},
      ];
    }
    return const [];
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

class ProductVariantEnableWizardDialog extends StatefulWidget {
  final int businessId;
  final int productId;
  final List<Map<String, dynamic>> variants;
  final List<Map<String, dynamic>> warehouses;

  const ProductVariantEnableWizardDialog({
    super.key,
    required this.businessId,
    required this.productId,
    required this.variants,
    required this.warehouses,
  });

  @override
  State<ProductVariantEnableWizardDialog> createState() => _ProductVariantEnableWizardDialogState();
}

class _ProductVariantEnableWizardDialogState extends State<ProductVariantEnableWizardDialog> {
  final _svc = ProductVariantService();
  final Map<int, TextEditingController> _qty = {};
  int? _warehouseId;
  DateTime _documentDate = DateTime.now();
  CalendarController? _calendar;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final row in widget.variants) {
      if (row['is_active'] == false) continue;
      final id = (row['id'] as num).toInt();
      _qty[id] = TextEditingController(text: '0');
    }
    if (widget.warehouses.isNotEmpty) {
      _warehouseId = (widget.warehouses.first['id'] as num?)?.toInt();
    }
    CalendarController.load().then((c) {
      if (mounted) setState(() => _calendar = c);
    });
  }

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_warehouseId == null) return;
    setState(() => _saving = true);
    try {
      final splits = <Map<String, dynamic>>[];
      _qty.forEach((id, ctrl) {
        final qty = parseFormattedNumber(ctrl.text) ?? 0;
        if (qty > 0) {
          splits.add({'variant_id': id, 'quantity': qty.toString()});
        }
      });
      await _svc.enableInventoryVariants(
        businessId: widget.businessId,
        productId: widget.productId,
        warehouseId: _warehouseId!,
        splits: splits,
        documentDate: _documentDate.toIso8601String().split('T').first,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.userMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.productVariantEnableWizardTitle),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t.productVariantEnableWizardHelp),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _warehouseId,
                decoration: InputDecoration(labelText: t.warehouse),
                items: widget.warehouses
                    .map(
                      (w) => DropdownMenuItem<int>(
                        value: (w['id'] as num?)?.toInt(),
                        child: Text(w['name']?.toString() ?? w['id'].toString()),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _warehouseId = v),
              ),
              const SizedBox(height: 12),
              if (_calendar != null)
                DateInputField(
                  value: _documentDate,
                  calendarController: _calendar!,
                  labelText: t.documentDate,
                  onChanged: (v) {
                    if (v != null) setState(() => _documentDate = v);
                  },
                ),
              const SizedBox(height: 12),
              ...widget.variants.where((v) => v['is_active'] != false).map((row) {
                final id = (row['id'] as num).toInt();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _qty[id],
                    decoration: InputDecoration(
                      labelText: '${row['display_title'] ?? id} — ${t.productVariantSplitQuantity}',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: Text(t.cancel)),
        FilledButton(onPressed: _saving ? null : _submit, child: Text(t.save)),
      ],
    );
  }
}
