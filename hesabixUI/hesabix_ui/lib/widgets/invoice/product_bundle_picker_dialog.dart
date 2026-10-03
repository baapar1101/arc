import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/material.dart';

import '../../models/invoice_line_item.dart';
import '../../models/product_bundle.dart';
import '../../services/product_bundle_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/number_normalizer.dart';
import '../../utils/snackbar_helper.dart';

Future<List<InvoiceLineItem>?> showProductBundlePickerDialog({
  required BuildContext context,
  required int businessId,
}) {
  return showGlassDialog<List<InvoiceLineItem>>(
    context: context,
    builder: (_) => _ProductBundlePickerDialog(businessId: businessId),
  );
}

class _ProductBundlePickerDialog extends StatefulWidget {
  final int businessId;

  const _ProductBundlePickerDialog({required this.businessId});

  @override
  State<_ProductBundlePickerDialog> createState() =>
      _ProductBundlePickerDialogState();
}

class _ProductBundlePickerDialogState
    extends State<_ProductBundlePickerDialog> {
  final ProductBundleService _service = ProductBundleService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController(
    text: '1',
  );
  List<ProductBundle> _bundles = const [];
  ProductBundle? _selected;
  bool _loading = true;
  bool _loadingDetails = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadBundles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _loadBundles([String? query]) async {
    setState(() => _loading = true);
    try {
      final bundles = await _service.search(
        businessId: widget.businessId,
        query: query,
        isActive: true,
      );
      if (!mounted) return;
      setState(() => _bundles = bundles);
    } catch (error) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(error, context),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectBundle(ProductBundle bundle) async {
    setState(() {
      _selected = bundle;
      _loadingDetails = true;
    });
    try {
      final details = await _service.getOne(
        businessId: widget.businessId,
        bundleId: bundle.id,
      );
      if (mounted && _selected?.id == bundle.id) {
        setState(() => _selected = details);
      }
    } catch (error) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(error, context),
          isError: true,
        );
      }
    } finally {
      if (mounted && _selected?.id == bundle.id) {
        setState(() => _loadingDetails = false);
      }
    }
  }

  Future<void> _submit() async {
    final selected = _selected;
    if (selected == null) {
      SnackBarHelper.show(context, message: 'یک باندل را انتخاب کنید.');
      return;
    }
    final multiplier = num.tryParse(
      toEnglishDigits(_quantityController.text.trim()),
    );
    if (multiplier == null || multiplier <= 0) {
      SnackBarHelper.show(
        context,
        message: 'تعداد باندل باید بیشتر از صفر باشد.',
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final items = await _service.expand(
        businessId: widget.businessId,
        bundleId: selected.id,
        quantity: multiplier,
      );
      final lines = items.map(_toInvoiceLine).toList();
      if (mounted) Navigator.of(context).pop(lines);
    } catch (error) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(error, context),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InvoiceLineItem _toInvoiceLine(ProductBundleItem item) {
    final product = item.product;
    final taxable = product['is_sales_taxable'] == true;
    final configuredTaxRate = _asNum(product['sales_tax_rate']) ?? 0;
    final salesNote = product['base_sales_note']?.toString().trim() ?? '';
    final description = product['description']?.toString().trim() ?? '';
    return InvoiceLineItem(
      productId: item.productId,
      productCode: product['code']?.toString(),
      productName: product['name']?.toString(),
      mainUnit: product['main_unit']?.toString(),
      secondaryUnit: product['secondary_unit']?.toString(),
      unitConversionFactor: _asNum(product['unit_conversion_factor']) ?? 1,
      selectedUnit: product['main_unit']?.toString(),
      quantity: item.quantity,
      unitPriceSource: 'base',
      unitPrice: 0,
      baseSalesPriceMainUnit: _asNum(product['base_sales_price']),
      salesPriceFxMainUnit: _asNum(product['sales_price_fx']),
      priceFxCurrencyId: _asInt(product['price_fx_currency_id']),
      taxRate: taxable ? (configuredTaxRate > 0 ? configuredTaxRate : 9) : 0,
      minOrderQty: _asInt(product['min_order_qty']),
      trackInventory: product['track_inventory'] == true,
      warehouseId: _asInt(product['default_warehouse_id']),
      description: salesNote.isNotEmpty
          ? salesNote
          : (description.isNotEmpty ? description : null),
      extraInfo: const {'_local_resolve_unit_price': true},
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('وارد کردن باندل کالا'),
      content: SizedBox(
        width: 720,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'جست‌وجوی باندل',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'جست‌وجو',
                  onPressed: () => _loadBundles(_searchController.text),
                  icon: const Icon(Icons.arrow_forward),
                ),
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: _loadBundles,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _bundles.isEmpty
                          ? const Center(child: Text('باندل فعالی یافت نشد.'))
                          : ListView.separated(
                              itemCount: _bundles.length,
                                  separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final bundle = _bundles[index];
                                return ListTile(
                                  selected: _selected?.id == bundle.id,
                                  title: Text(bundle.name),
                                  subtitle: Text(
                                    '${bundle.itemsCount} قلم کالا',
                                  ),
                                  trailing: _selected?.id == bundle.id
                                      ? const Icon(Icons.check_circle)
                                      : null,
                                  onTap: () => _selectBundle(bundle),
                                );
                              },
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: _selected == null
                            ? const Center(
                                child: Text('یک باندل را انتخاب کنید.'),
                              )
                            : _loadingDetails
                            ? const Center(child: CircularProgressIndicator())
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    _selected!.name,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  if (_selected!.description
                                          ?.trim()
                                          .isNotEmpty ==
                                      true) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      _selected!.description!,
                                      style: theme.textTheme.bodySmall,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  const Divider(height: 24),
                                  Expanded(
                                    child: ListView.builder(
                                      itemCount: _selected!.items.length,
                                      itemBuilder: (context, index) {
                                        final item = _selected!.items[index];
                                        final product = item.product;
                                        final code =
                                            product['code']?.toString() ?? '';
                                        final name =
                                            product['name']?.toString() ?? '';
                                        return ListTile(
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(
                                            code.isEmpty
                                                ? name
                                                : '$code - $name',
                                          ),
                                          trailing: Text(
                                            '× ${_formatQuantity(item.quantity)}',
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantityController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [EnglishDigitsFormatter()],
              decoration: const InputDecoration(
                labelText: 'تعداد باندل',
                helperText: 'تعداد هر کالا در این ضریب ضرب می‌شود.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('انصراف'),
        ),
        FilledButton.icon(
          onPressed: _submitting || _loadingDetails ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.playlist_add),
          label: const Text('افزودن ردیف‌ها'),
        ),
      ],
    );
  }
}

num? _asNum(dynamic value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '');
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String _formatQuantity(num value) {
  if (value.remainder(1) == 0) return value.toInt().toString();
  return value.toString();
}
