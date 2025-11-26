import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:flutter/services.dart';

import '../../../models/product_form_data.dart';
import '../../../utils/number_normalizer.dart';
import '../../../utils/product_form_validator.dart';
import '../../../widgets/invoice/warehouse_combobox_widget.dart';

class ProductPricingInventorySection extends StatefulWidget {
  final int businessId;
  final ProductFormData formData;
  final ValueChanged<ProductFormData> onChanged;
  final List<Map<String, dynamic>> priceLists;
  final List<Map<String, dynamic>> currencies;
  final List<Map<String, dynamic>> warehouses;
  final List<Map<String, dynamic>> draftPriceItems;
  final void Function(Map<String, dynamic> item) onAddOrUpdatePriceItem;
  final void Function(Map<String, dynamic> item) onDeletePriceItem;
  final dynamic controller; // ProductFormController
  final int? productId; // برای تشخیص ویرایش

  const ProductPricingInventorySection({
    super.key,
    required this.businessId,
    required this.formData,
    required this.onChanged,
    required this.priceLists,
    required this.currencies,
    required this.warehouses,
    required this.draftPriceItems,
    required this.onAddOrUpdatePriceItem,
    required this.onDeletePriceItem,
    this.controller,
    this.productId,
  });

  @override
  State<ProductPricingInventorySection> createState() => _ProductPricingInventorySectionState();
}

class _ProductPricingInventorySectionState extends State<ProductPricingInventorySection> {
  late TextEditingController _salesPriceController;
  late TextEditingController _purchasePriceController;
  late TextEditingController _salesNoteController;
  late TextEditingController _purchaseNoteController;

  @override
  void initState() {
    super.initState();
    _salesPriceController = TextEditingController(
      text: formatNumberForInput(widget.formData.baseSalesPrice),
    );
    _purchasePriceController = TextEditingController(
      text: formatNumberForInput(widget.formData.basePurchasePrice),
    );
    _salesNoteController = TextEditingController(text: widget.formData.baseSalesNote ?? '');
    _purchaseNoteController = TextEditingController(text: widget.formData.basePurchaseNote ?? '');
  }

  @override
  void didUpdateWidget(ProductPricingInventorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // به‌روزرسانی کنترلرها فقط وقتی مقدار واقعاً تغییر کرده (نه از طریق تایپ کاربر)
    // این برای حفظ جداکننده هزارگان بعد از تغییر تب‌ها مهم است
    if (oldWidget.formData.baseSalesPrice != widget.formData.baseSalesPrice) {
      final newSalesPrice = formatNumberForInput(widget.formData.baseSalesPrice);
      if (_salesPriceController.text != newSalesPrice) {
        _salesPriceController.text = newSalesPrice;
      }
    }
    if (oldWidget.formData.basePurchasePrice != widget.formData.basePurchasePrice) {
      final newPurchasePrice = formatNumberForInput(widget.formData.basePurchasePrice);
      if (_purchasePriceController.text != newPurchasePrice) {
        _purchasePriceController.text = newPurchasePrice;
      }
    }
    if (oldWidget.formData.baseSalesNote != widget.formData.baseSalesNote) {
      final newSalesNote = widget.formData.baseSalesNote ?? '';
      if (_salesNoteController.text != newSalesNote) {
        _salesNoteController.text = newSalesNote;
      }
    }
    if (oldWidget.formData.basePurchaseNote != widget.formData.basePurchaseNote) {
      final newPurchaseNote = widget.formData.basePurchaseNote ?? '';
      if (_purchaseNoteController.text != newPurchaseNote) {
        _purchaseNoteController.text = newPurchaseNote;
      }
    }
  }

  @override
  void dispose() {
    _salesPriceController.dispose();
    _purchasePriceController.dispose();
    _salesNoteController.dispose();
    _purchaseNoteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // اگر نوع کالا "خدمت" است، بخش کنترل موجودی را نمایش نده
    final isService = widget.formData.itemType == 'خدمت';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isService) ...[
          _buildInventorySection(context),
          const SizedBox(height: 24),
        ],
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
          value: widget.formData.trackInventory,
          onChanged: (value) => _updateFormData(widget.formData.copyWith(trackInventory: value)),
          title: Text(t.inventoryControl),
        ),
        if (widget.formData.trackInventory) ...[
          const SizedBox(height: 16),
          // انتخاب حالت موجودی (فله‌ای/یونیک)
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'حالت موجودی',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'bulk',
                        label: Text('فله‌ای'),
                        icon: Icon(Icons.inventory_2_outlined),
                      ),
                      ButtonSegment(
                        value: 'unique',
                        label: Text('یونیک'),
                        icon: Icon(Icons.qr_code_scanner),
                      ),
                    ],
                    selected: {widget.formData.inventoryMode ?? 'bulk'},
                    onSelectionChanged: (Set<String> newSelection) {
                      final mode = newSelection.first;
                      _updateFormData(
                        widget.formData.copyWith(
                          inventoryMode: mode,
                          // اگر به حالت فله‌ای تغییر کرد، track_serial و track_barcode را false کن
                          trackSerial: mode == 'unique' ? widget.formData.trackSerial : false,
                          trackBarcode: mode == 'unique' ? widget.formData.trackBarcode : false,
                        ),
                      );
                    },
                  ),
                  // گزینه‌های ردیابی برای حالت یونیک
                  if (widget.formData.inventoryMode == 'unique') ...[
                    const SizedBox(height: 16),
                    SwitchListTile(
                      value: widget.formData.trackSerial,
                      onChanged: (value) => _updateFormData(widget.formData.copyWith(trackSerial: value)),
                      title: const Text('ردیابی سریال نامبر'),
                      subtitle: const Text('هر واحد کالا دارای شماره سریال یکتا خواهد بود'),
                    ),
                    SwitchListTile(
                      value: widget.formData.trackBarcode,
                      onChanged: (value) => _updateFormData(widget.formData.copyWith(trackBarcode: value)),
                      title: const Text('ردیابی بارکد'),
                      subtitle: const Text('هر واحد کالا دارای بارکد یکتا خواهد بود'),
                    ),
                  ],
                  // هشدار تبدیل از bulk به unique
                  if (widget.productId != null && widget.controller != null) 
                    _buildConversionWarning(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          WarehouseComboboxWidget(
            businessId: widget.businessId,
            selectedWarehouseId: widget.formData.defaultWarehouseId,
            onChanged: (warehouseId) {
              _updateFormData(widget.formData.copyWith(defaultWarehouseId: warehouseId));
            },
            label: 'انبار پیش‌فرض',
            hintText: 'انتخاب انبار پیش‌فرض',
            isRequired: false,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('reorderPoint_${widget.formData.reorderPoint}'),
                  initialValue: widget.formData.reorderPoint?.toString(),
                  decoration: InputDecoration(labelText: t.reorderPointRepeat),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    const EnglishDigitsFormatter(),
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: (value) => ProductFormValidator.validateQuantity(value, fieldName: t.reorderPointRepeat),
                  onChanged: (value) => _updateFormData(widget.formData.copyWith(reorderPoint: int.tryParse(value))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: ValueKey('minOrderQty_${widget.formData.minOrderQty}'),
                  initialValue: widget.formData.minOrderQty?.toString(),
                  decoration: InputDecoration(labelText: t.minOrderQty),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    const EnglishDigitsFormatter(),
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: (value) => ProductFormValidator.validateQuantity(value, fieldName: t.minOrderQty),
                  onChanged: (value) => _updateFormData(widget.formData.copyWith(minOrderQty: int.tryParse(value))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: ValueKey('leadTimeDays_${widget.formData.leadTimeDays}'),
                  initialValue: widget.formData.leadTimeDays?.toString(),
                  decoration: InputDecoration(labelText: t.leadTimeDays),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    const EnglishDigitsFormatter(),
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: ProductFormValidator.validateLeadTime,
                  onChanged: (value) => _updateFormData(widget.formData.copyWith(leadTimeDays: int.tryParse(value))),
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
          controller: _salesPriceController,
          decoration: InputDecoration(labelText: t.salesPrice),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            const EnglishDigitsFormatter(),
            ThousandsSeparatorInputFormatter(),
          ],
          validator: (value) => ProductFormValidator.validatePrice(value, fieldName: t.salesPrice),
          onChanged: (value) => _updateFormData(widget.formData.copyWith(baseSalesPrice: num.tryParse(value.replaceAll(',', '')))),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _salesNoteController,
          decoration: InputDecoration(labelText: t.salesPriceNote),
          maxLines: 2,
          onChanged: (value) => _updateFormData(
            widget.formData.copyWith(
              baseSalesNote: value.trim().isEmpty ? null : value,
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _purchasePriceController,
          decoration: InputDecoration(labelText: t.purchasePrice),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            const EnglishDigitsFormatter(),
            ThousandsSeparatorInputFormatter(),
          ],
          validator: (value) => ProductFormValidator.validatePrice(value, fieldName: t.purchasePrice),
          onChanged: (value) => _updateFormData(widget.formData.copyWith(basePurchasePrice: num.tryParse(value.replaceAll(',', '')))),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _purchaseNoteController,
          decoration: InputDecoration(labelText: t.purchasePriceNote),
          maxLines: 2,
          onChanged: (value) => _updateFormData(
            widget.formData.copyWith(
              basePurchaseNote: value.trim().isEmpty ? null : value,
            ),
          ),
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
              if (widget.priceLists.isEmpty) {
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
        ...widget.draftPriceItems.map((it) {
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
                      if (widget.priceLists.isEmpty) {
                        _showNoPriceListsWarning(context);
                        return;
                      }
                      await _openEditorDialog(context, existing: it);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => widget.onDeletePriceItem(it),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  String _resolvePriceListTitle(dynamic id) {
    if (id == null) return '-';
    for (final pl in widget.priceLists) {
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
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
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
    if (priceListId == null && widget.priceLists.isNotEmpty) {
      priceListId = (widget.priceLists.first['id'] as num).toInt();
    }
    
    // Default select business default currency if none provided
    if (currencyId == null && widget.currencies.isNotEmpty) {
      try {
        final def = widget.currencies.firstWhere((c) => (c['is_default'] == true));
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
                  initialValue: priceListId,
                  items: widget.priceLists
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
                  initialValue: currencyId,
                  items: widget.currencies
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
                  inputFormatters: [
                    const EnglishDigitsFormatter(),
                    ThousandsSeparatorInputFormatter(),
                  ],
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
              widget.onAddOrUpdatePriceItem(payload);
              Navigator.of(ctx).pop(true);
            },
            child: Text(AppLocalizations.of(ctx).save),
          ),
        ],
      ),
    );
  }

  void _updateFormData(ProductFormData newData) {
    widget.onChanged(newData);
  }

  Widget _buildConversionWarning() {
    if (widget.productId == null || widget.controller == null) {
      return const SizedBox.shrink();
    }
    
    // استفاده از dynamic برای دسترسی به controller
    final controller = widget.controller;
    final needsConversion = controller?.needsConversion ?? false;
    
    if (!needsConversion) {
      return const SizedBox.shrink();
    }
    
    return FutureBuilder<int?>(
      future: controller?.getCurrentStock(widget.productId!),
      builder: (context, snapshot) {
        final stock = snapshot.data ?? 0;
        
        if (stock <= 0) {
          return const SizedBox.shrink();
        }
        
        return Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            border: Border.all(color: Colors.orange.shade200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تبدیل به حالت یونیک',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'این کالا دارای $stock واحد موجودی است. برای تبدیل به حالت یونیک، باید برای هر واحد موجودی یک instance ایجاد شود.',
                style: TextStyle(color: Colors.orange.shade800),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      // بازگشت به حالت bulk
                      _updateFormData(widget.formData.copyWith(inventoryMode: 'bulk'));
                    },
                    child: const Text('انصراف'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () async {
                      // تبدیل کالا
                      final success = await controller?.convertProductToUnique(widget.productId!);
                      if (success == true && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('کالا با موفقیت به حالت یونیک تبدیل شد'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        // به‌روزرسانی فرم
                        setState(() {});
                      } else if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(controller?.errorMessage ?? 'خطا در تبدیل کالا'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.transform),
                    label: const Text('تبدیل و ایجاد Instance ها'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
