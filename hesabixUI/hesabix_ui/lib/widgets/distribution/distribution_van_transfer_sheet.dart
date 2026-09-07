import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth_store.dart';
import '../../l10n/app_localizations.dart';
import '../../services/distribution_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../invoice/product_combobox_widget.dart';
import '../invoice/warehouse_combobox_widget.dart';
import 'distribution_form_helpers.dart';

/// شیت بارگیری یا تخلیهٔ ون: انتخاب انبار، افزودن قلم و ثبت انتقال.
Future<bool> showDistributionVanTransferSheet({
  required BuildContext context,
  required int businessId,
  required DistributionService service,
  required int vanId,
  required bool load,
  String? vanName,
  AuthStore? authStore,
  List<Map<String, dynamic>> vanStockItems = const [],
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.92,
        child: _VanTransferSheet(
          businessId: businessId,
          service: service,
          vanId: vanId,
          load: load,
          vanName: vanName,
          authStore: authStore,
          vanStockItems: vanStockItems,
        ),
      ),
    ),
  );
  return ok == true;
}

class _Line {
  _Line({
    required this.productId,
    required this.productName,
    required this.quantity,
  });

  final int productId;
  final String productName;
  double quantity;
}

class _VanTransferSheet extends StatefulWidget {
  final int businessId;
  final DistributionService service;
  final int vanId;
  final bool load;
  final String? vanName;
  final AuthStore? authStore;
  final List<Map<String, dynamic>> vanStockItems;

  const _VanTransferSheet({
    required this.businessId,
    required this.service,
    required this.vanId,
    required this.load,
    this.vanName,
    this.authStore,
    this.vanStockItems = const [],
  });

  @override
  State<_VanTransferSheet> createState() => _VanTransferSheetState();
}

class _VanTransferSheetState extends State<_VanTransferSheet> {
  int? _warehouseId;
  final List<_Line> _lines = [];
  Map<String, dynamic>? _product;
  int? _stockProductId;
  final TextEditingController _qtyCtl = TextEditingController(text: '1');
  Key _productPickerKey = UniqueKey();
  bool _saving = false;

  @override
  void dispose() {
    _qtyCtl.dispose();
    super.dispose();
  }

  double _parseQty() {
    final raw = _qtyCtl.text.trim().replaceAll(',', '.');
    return double.tryParse(raw) ?? 0;
  }

  String _fmtQty(double q) {
    if (q == q.roundToDouble()) return q.round().toString();
    return q.toString();
  }

  String _productLabel(Map<String, dynamic> p) {
    final name = '${p['name'] ?? p['product_name'] ?? ''}'.trim();
    final code = '${p['code'] ?? ''}'.trim();
    if (code.isNotEmpty && name.isNotEmpty) return '$code · $name';
    if (name.isNotEmpty) return name;
    return '#${p['id'] ?? p['product_id'] ?? ''}';
  }

  double _vanStockOf(int productId) {
    for (final s in widget.vanStockItems) {
      if (int.tryParse('${s['product_id']}') == productId) {
        return double.tryParse('${s['quantity']}') ?? 0;
      }
    }
    return 0;
  }

  double _qtyAlreadyInLines(int productId) {
    var sum = 0.0;
    for (final l in _lines) {
      if (l.productId == productId) sum += l.quantity;
    }
    return sum;
  }

  Map<String, dynamic>? _stockRow(int? productId) {
    if (productId == null) return null;
    for (final s in widget.vanStockItems) {
      if (int.tryParse('${s['product_id']}') == productId) return s;
    }
    return null;
  }

  void _setQty(double next) {
    final q = next < 0.001 ? 1.0 : next;
    _qtyCtl.text = _fmtQty(q);
    setState(() {});
  }

  void _addLine() {
    final t = AppLocalizations.of(context);
    final qty = _parseQty();
    if (qty <= 0) {
      SnackBarHelper.showError(context, message: t.distributionVanQtyInvalid);
      return;
    }

    int productId;
    String productName;

    if (widget.load) {
      if (_product == null) {
        SnackBarHelper.showError(context, message: t.distributionVanPickProductFirst);
        return;
      }
      final rawId = _product!['id'] ?? _product!['product_id'];
      productId = rawId is int ? rawId : int.tryParse('$rawId') ?? 0;
      if (productId <= 0) {
        SnackBarHelper.showError(context, message: t.distributionVanPickProductFirst);
        return;
      }
      productName = _productLabel(_product!);
    } else {
      if (_stockProductId == null) {
        SnackBarHelper.showError(context, message: t.distributionVanPickProductFirst);
        return;
      }
      productId = _stockProductId!;
      final row = _stockRow(productId);
      productName = '${row?['product_name'] ?? 'product $productId'}';
      final available = _vanStockOf(productId);
      if (_qtyAlreadyInLines(productId) + qty > available + 1e-9) {
        SnackBarHelper.showError(context, message: t.distributionVanQtyExceedsStock);
        return;
      }
    }

    setState(() {
      _Line? existing;
      for (final l in _lines) {
        if (l.productId == productId) {
          existing = l;
          break;
        }
      }
      if (existing != null) {
        existing.quantity += qty;
      } else {
        _lines.add(_Line(productId: productId, productName: productName, quantity: qty));
      }
      _product = null;
      _stockProductId = null;
      _productPickerKey = UniqueKey();
      _qtyCtl.text = '1';
    });
  }

  void _changeLineQty(_Line line, double next) {
    final t = AppLocalizations.of(context);
    if (next <= 0) {
      setState(() => _lines.remove(line));
      return;
    }
    if (!widget.load) {
      final others = _qtyAlreadyInLines(line.productId) - line.quantity;
      if (others + next > _vanStockOf(line.productId) + 1e-9) {
        SnackBarHelper.showError(context, message: t.distributionVanQtyExceedsStock);
        return;
      }
    }
    setState(() => line.quantity = next);
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    if (_warehouseId == null) {
      SnackBarHelper.showError(context, message: t.distributionVanNoWarehouse);
      return;
    }
    if (_lines.isEmpty) {
      SnackBarHelper.showError(context, message: t.distributionVanLinesEmpty);
      return;
    }
    setState(() => _saving = true);
    try {
      final payload = _lines
          .map(
            (l) => <String, dynamic>{
              'product_id': l.productId,
              'quantity': l.quantity,
            },
          )
          .toList();
      if (widget.load) {
        await widget.service.loadVan(
          businessId: widget.businessId,
          vanId: widget.vanId,
          lines: payload,
          sourceWarehouseId: _warehouseId,
        );
      } else {
        await widget.service.unloadVan(
          businessId: widget.businessId,
          vanId: widget.vanId,
          lines: payload,
          destWarehouseId: _warehouseId,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = widget.load ? t.distributionVanLoad : t.distributionVanUnload;
    final hint = widget.load ? t.distributionVanLoadHint : t.distributionVanUnloadHint;
    final vanLabel = (widget.vanName ?? '').trim();

    return Material(
      color: cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                if (vanLabel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(vanLabel, style: theme.textTheme.titleSmall?.copyWith(color: cs.primary)),
                ],
                const SizedBox(height: 6),
                Text(hint, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                WarehouseComboboxWidget(
                  businessId: widget.businessId,
                  selectedWarehouseId: _warehouseId,
                  label: widget.load ? t.distributionSourceWarehouse : t.distributionDestWarehouse,
                  selectDefaultWhenUnset: true,
                  onChanged: (id) => setState(() => _warehouseId = id),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  color: cs.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          t.distributionReturnAddLine,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 10),
                        if (widget.load)
                          ProductComboboxWidget(
                            key: _productPickerKey,
                            businessId: widget.businessId,
                            selectedProduct: _product,
                            authStore: widget.authStore,
                            label: t.distributionSelectProduct,
                            onChanged: (p) => setState(() => _product = p),
                          )
                        else if (widget.vanStockItems.isEmpty)
                          Text(
                            t.distributionVanEmptyStockUnload,
                            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                          )
                        else
                          DistributionChoiceField<Map<String, dynamic>>(
                            label: t.distributionSelectProduct,
                            items: widget.vanStockItems,
                            selectedLabel: () {
                              final row = _stockRow(_stockProductId);
                              if (row == null || _stockProductId == null) return null;
                              final avail = double.tryParse('${row['quantity']}') ?? 0;
                              final remaining = avail - _qtyAlreadyInLines(_stockProductId!);
                              return '${row['product_name']} · ${t.distributionVanStock}: ${_fmtQty(remaining < 0 ? 0 : remaining)}';
                            }(),
                            labelOf: (s) {
                              final id = int.tryParse('${s['product_id']}');
                              final avail = double.tryParse('${s['quantity']}') ?? 0;
                              final remaining = id == null ? avail : avail - _qtyAlreadyInLines(id);
                              return '${s['product_name']} · ${t.distributionVanStock}: ${_fmtQty(remaining < 0 ? 0 : remaining)}';
                            },
                            enabledOf: (s) {
                              final id = int.tryParse('${s['product_id']}');
                              if (id == null) return false;
                              final avail = double.tryParse('${s['quantity']}') ?? 0;
                              return avail - _qtyAlreadyInLines(id) > 1e-9;
                            },
                            selectedOf: (s) => int.tryParse('${s['product_id']}') == _stockProductId,
                            onSelected: (s) => setState(() {
                              _stockProductId = int.tryParse('${s['product_id']}');
                            }),
                          ),
                        if (widget.load && _product != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _productLabel(_product!),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        _QtyStepper(
                          controller: _qtyCtl,
                          onMinus: () => _setQty(_parseQty() - 1),
                          onPlus: () => _setQty(_parseQty() + 1),
                          label: t.quantity,
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: (!widget.load && widget.vanStockItems.isEmpty) ? null : _addLine,
                          icon: const Icon(Icons.add),
                          label: Text(t.distributionReturnAddLine),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '${t.distributionVanTransferLines} (${_lines.length})',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                if (_lines.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      t.distributionVanLinesEmpty,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  )
                else
                  ..._lines.map(
                    (line) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(line.productName, style: theme.textTheme.titleSmall),
                                ),
                                IconButton(
                                  tooltip: t.delete,
                                  onPressed: () => setState(() => _lines.remove(line)),
                                  icon: Icon(Icons.delete_outline, color: cs.error),
                                ),
                              ],
                            ),
                            if (!widget.load)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  t.distributionVanStockAvailable(_fmtQty(_vanStockOf(line.productId))),
                                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ),
                            Row(
                              children: [
                                IconButton(
                                  onPressed: () => _changeLineQty(line, line.quantity - 1),
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                                Text(_fmtQty(line.quantity), style: theme.textTheme.titleMedium),
                                IconButton(
                                  onPressed: () => _changeLineQty(line, line.quantity + 1),
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context, false),
                    child: Text(t.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving || _lines.isEmpty ? null : _submit,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            widget.load ? t.distributionVanConfirmLoad : t.distributionVanConfirmUnload,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final String label;

  const _QtyStepper({
    required this.controller,
    required this.onMinus,
    required this.onPlus,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          prefixIcon: IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onMinus,
            icon: const Icon(Icons.remove),
          ),
          suffixIcon: IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onPlus,
            icon: const Icon(Icons.add),
          ),
        ),
      ),
    );
  }
}
