import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import '../../../utils/number_formatters.dart';
import '../../../models/product_form_data.dart';
import '../../../utils/product_form_validator.dart';

class ProductPricingInventorySection extends StatelessWidget {
  final ProductFormData formData;
  final ValueChanged<ProductFormData> onChanged;
  final List<Map<String, dynamic>> units;
  final List<Map<String, dynamic>> priceLists;
  final List<Map<String, dynamic>> currencies;
  final List<Map<String, dynamic>> draftPriceItems;
  final void Function(Map<String, dynamic> item) onAddOrUpdatePriceItem;
  final void Function(Map<String, dynamic> item) onDeletePriceItem;

  const ProductPricingInventorySection({
    super.key,
    required this.formData,
    required this.onChanged,
    required this.units,
    required this.priceLists,
    required this.currencies,
    required this.draftPriceItems,
    required this.onAddOrUpdatePriceItem,
    required this.onDeletePriceItem,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInventorySection(context),
        const SizedBox(height: 24),
        _buildPricingSection(context),
        const SizedBox(height: 24),
        _buildPerPriceListPricing(context),
      ],
    );
  }


  Widget _buildInventorySection(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          value: formData.trackInventory,
          onChanged: (value) => _updateFormData(formData.copyWith(trackInventory: value)),
          title: Text(t.inventoryControl),
        ),
        if (formData.trackInventory) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: formData.reorderPoint?.toString(),
                  decoration: InputDecoration(labelText: t.reorderPointRepeat),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: (value) => ProductFormValidator.validateQuantity(value, fieldName: t.reorderPointRepeat),
                  onChanged: (value) => _updateFormData(formData.copyWith(reorderPoint: int.tryParse(value))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: formData.minOrderQty?.toString(),
                  decoration: InputDecoration(labelText: t.minOrderQty),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: (value) => ProductFormValidator.validateQuantity(value, fieldName: t.minOrderQty),
                  onChanged: (value) => _updateFormData(formData.copyWith(minOrderQty: int.tryParse(value))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: formData.leadTimeDays?.toString(),
                  decoration: InputDecoration(labelText: t.leadTimeDays),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: ProductFormValidator.validateLeadTime,
                  onChanged: (value) => _updateFormData(formData.copyWith(leadTimeDays: int.tryParse(value))),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildPricingSection(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.pricing, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: formData.baseSalesPrice?.toString(),
          decoration: InputDecoration(labelText: t.salesPrice),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [ThousandsSeparatorInputFormatter()],
          validator: (value) => ProductFormValidator.validatePrice(value, fieldName: t.salesPrice),
          onChanged: (value) => _updateFormData(formData.copyWith(baseSalesPrice: num.tryParse(value.replaceAll(',', '')))),
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: formData.baseSalesNote,
          decoration: InputDecoration(labelText: t.salesPriceNote),
          maxLines: 2,
          onChanged: (value) => _updateFormData(formData.copyWith(baseSalesNote: value.trim().isEmpty ? null : value)),
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: formData.basePurchasePrice?.toString(),
          decoration: InputDecoration(labelText: t.purchasePrice),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [ThousandsSeparatorInputFormatter()],
          validator: (value) => ProductFormValidator.validatePrice(value, fieldName: t.purchasePrice),
          onChanged: (value) => _updateFormData(formData.copyWith(basePurchasePrice: num.tryParse(value.replaceAll(',', '')))),
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: formData.basePurchaseNote,
          decoration: InputDecoration(labelText: t.purchasePriceNote),
          maxLines: 2,
          onChanged: (value) => _updateFormData(formData.copyWith(basePurchaseNote: value.trim().isEmpty ? null : value)),
        ),
      ],
    );
  }

  Widget _buildPerPriceListPricing(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.pricesInPriceLists, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () async {
              if (priceLists.isEmpty) {
                _showNoPriceListsWarning(context);
                return;
              }
              await _openEditorDialog(context);
            },
            icon: const Icon(Icons.add),
            label: Text(t.addPrice),
          ),
        ),
        const SizedBox(height: 12),
        ...draftPriceItems.map((it) {
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ListTile(
              title: Text(_resolvePriceListTitle(it['price_list_id'])),
              subtitle: Text('${t.currency}: ${it['currency_id'] ?? '-'} | ${t.price}: ${it['price']}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () async {
                      if (priceLists.isEmpty) {
                        _showNoPriceListsWarning(context);
                        return;
                      }
                      await _openEditorDialog(context, existing: it);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => onDeletePriceItem(it),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  String _resolvePriceListTitle(dynamic id) {
    if (id == null) return '-';
    for (final pl in priceLists) {
      if (pl['id'] == id) return (pl['name'] ?? '').toString();
    }
    return 'لیست ${id.toString()}';
  }

  void _showNoPriceListsWarning(BuildContext context) {
    final t = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange[700]),
            const SizedBox(width: 8),
            Text(t.noPriceListsTitle),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.noPriceListsMessage),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t.noPriceListsHint,
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t.gotIt),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditorDialog(BuildContext context, {Map<String, dynamic>? existing}) async {
    final formKey = GlobalKey<FormState>();
    int? priceListId = (existing?['price_list_id'] as num?)?.toInt();
    int? currencyId = (existing?['currency_id'] as num?)?.toInt();
    
    // Set first price list as default if none provided and price lists exist
    if (priceListId == null && priceLists.isNotEmpty) {
      priceListId = (priceLists.first['id'] as num).toInt();
    }
    
    // Default select business default currency if none provided
    if (currencyId == null && currencies.isNotEmpty) {
      try {
        final def = currencies.firstWhere((c) => (c['is_default'] == true));
        currencyId = (def['id'] as num?)?.toInt() ?? currencyId;
      } catch (_) {
        // If no explicit default flagged, keep null to force selection
      }
    }
    num price = (existing?['price'] as num?) ?? 0;

    final t = AppLocalizations.of(context);
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? t.addPriceTitle : t.editPriceTitle),
        content: SizedBox(
          width: 560,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: priceListId,
                  items: priceLists
                      .map((pl) => DropdownMenuItem<int>(
                            value: (pl['id'] as num).toInt(),
                            child: Text((pl['name'] ?? '').toString()),
                          ))
                      .toList(),
                  onChanged: (v) => priceListId = v,
                  decoration: InputDecoration(labelText: t.priceList),
                  validator: (v) => v == null ? t.required : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: currencyId,
                  items: currencies
                      .map((c) => DropdownMenuItem<int>(
                            value: (c['id'] as num).toInt(),
                            child: Text('${c['title'] ?? c['name']} (${c['code']})'),
                          ))
                      .toList(),
                  onChanged: (v) => currencyId = v,
                  decoration: InputDecoration(labelText: t.currency),
                  validator: (v) => v == null ? t.required : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: price.toString(),
                  decoration: InputDecoration(labelText: t.price),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [ThousandsSeparatorInputFormatter()],
                  validator: (v) => (num.tryParse((v ?? '').replaceAll(',', '')) == null) ? t.invalid : null,
                  onChanged: (v) => price = num.tryParse((v).replaceAll(',', '')) ?? 0,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(AppLocalizations.of(ctx).cancel)),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final payload = {
                'price_list_id': priceListId,
                'currency_id': currencyId,
                'price': price,
              }..removeWhere((k, v) => v == null);
              onAddOrUpdatePriceItem(payload);
              Navigator.of(ctx).pop(true);
            },
            child: Text(AppLocalizations.of(ctx).save),
          ),
        ],
      ),
    );
  }

  void _updateFormData(ProductFormData newData) {
    onChanged(newData);
  }
}
