import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/bom_service.dart';
import '../../services/product_service.dart';
import '../../models/bom_models.dart';
import '../../models/invoice_line_item.dart';
import '../../widgets/invoice/product_combobox_widget.dart';
import '../../utils/number_normalizer.dart';

/// ویجت انفجار فرمول تولید برای فاکتور تولید
class BomExplosionWidget extends StatefulWidget {
  final int businessId;
  final Function(List<InvoiceLineItem>) onExploded;

  const BomExplosionWidget({
    super.key,
    required this.businessId,
    required this.onExploded,
  });

  @override
  State<BomExplosionWidget> createState() => _BomExplosionWidgetState();
}

class _BomExplosionWidgetState extends State<BomExplosionWidget> {
  final BomService _bomService = BomService();
  final ProductService _productService = ProductService();
  
  Map<String, dynamic>? _selectedProduct;
  List<ProductBOM> _boms = [];
  ProductBOM? _selectedBom;
  final TextEditingController _quantityController = TextEditingController(text: '1');
  bool _loadingBoms = false;
  bool _exploding = false;

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _loadBomsForProduct(int productId) async {
    setState(() {
      _loadingBoms = true;
      _selectedBom = null;
    });
    try {
      final boms = await _bomService.list(
        businessId: widget.businessId,
        productId: productId,
      );
      if (!mounted) return;
      setState(() {
        _boms = boms;
        // انتخاب فرمول پیش‌فرض اگر وجود دارد
        _selectedBom = boms.firstWhere(
          (b) => b.isDefault,
          orElse: () => boms.isNotEmpty ? boms.first : boms.first,
        );
        _loadingBoms = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _boms = [];
        _selectedBom = null;
        _loadingBoms = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در بارگذاری فرمول‌ها: $e')),
        );
      }
    }
  }

  Future<void> _explodeAndAdd() async {
    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لطفاً کالای تولیدی را انتخاب کنید')),
      );
      return;
    }

    if (_boms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('برای این کالا فرمول تولیدی تعریف نشده است')),
      );
      return;
    }

    final quantity = double.tryParse(_quantityController.text.replaceAll(',', '.')) ?? 0;
    if (quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مقدار تولید باید بزرگ‌تر از صفر باشد')),
      );
      return;
    }

    setState(() {
      _exploding = true;
    });

    try {
      final bomId = _selectedBom?.id;
      final productId = _selectedProduct!['id'] as int;

      // انفجار فرمول
      final explosionResult = await _bomService.explode(
        businessId: widget.businessId,
        productId: bomId == null ? productId : null,
        bomId: bomId,
        quantity: quantity,
      );

      // دریافت اطلاعات کامل محصولات برای ساخت InvoiceLineItem
      final lineItems = <InvoiceLineItem>[];

      // افزودن مواد اولیه (inputs) - movement: out
      for (final item in explosionResult.items) {
        try {
          final productData = await _productService.getProduct(
            businessId: widget.businessId,
            productId: item.componentProductId,
          );
          
          final mainUnit = productData['main_unit']?.toString();
          final secondaryUnit = productData['secondary_unit']?.toString();
          final unitFactor = _toNum(productData['unit_conversion_factor'], fallback: 1);
          
          // تعیین واحد انتخابی بر اساس uom در BOM
          String? selectedUnit = mainUnit;
          num finalQuantity = item.requiredQty;
          
          if (item.uom != null) {
            if (item.uom == secondaryUnit && secondaryUnit != null) {
              selectedUnit = secondaryUnit;
              // اگر uom در BOM واحد فرعی است، quantity را تبدیل نکنیم (از API آمده)
            } else if (item.uom == mainUnit) {
              selectedUnit = mainUnit;
            }
          }

          lineItems.add(
            InvoiceLineItem(
              productId: item.componentProductId,
              productCode: item.componentProductCode ?? productData['code']?.toString(),
              productName: item.componentProductName ?? productData['name']?.toString(),
              mainUnit: mainUnit,
              secondaryUnit: secondaryUnit,
              unitConversionFactor: unitFactor,
              selectedUnit: selectedUnit,
              quantity: finalQuantity,
              description: 'مصرف مواد برای تولید',
              unitPriceSource: 'base',
              unitPrice: _toNum(productData['base_purchase_price'], fallback: 0),
              basePurchasePriceMainUnit: _toNum(productData['base_purchase_price']),
              baseSalesPriceMainUnit: _toNum(productData['base_sales_price']),
              taxRate: _toNum(productData['sales_tax_rate'], fallback: 0),
              trackInventory: productData['track_inventory'] == true,
              warehouseId: item.suggestedWarehouseId,
            ),
          );
        } catch (e) {
          // اگر محصول یافت نشد، با اطلاعات محدود اضافه می‌کنیم
          lineItems.add(
            InvoiceLineItem(
              productId: item.componentProductId,
              productCode: item.componentProductCode,
              productName: item.componentProductName ?? 'کالا #${item.componentProductId}',
              quantity: item.requiredQty,
              description: 'مصرف مواد برای تولید',
              unitPriceSource: 'base',
              unitPrice: 0,
              warehouseId: item.suggestedWarehouseId,
            ),
          );
        }
      }

      // افزودن خروجی‌ها (outputs) - movement: in
      for (final output in explosionResult.outputs) {
        try {
          final productData = await _productService.getProduct(
            businessId: widget.businessId,
            productId: output.outputProductId,
          );
          
          final mainUnit = productData['main_unit']?.toString();
          final secondaryUnit = productData['secondary_unit']?.toString();
          final unitFactor = _toNum(productData['unit_conversion_factor'], fallback: 1);
          
          // تعیین واحد انتخابی
          String? selectedUnit = mainUnit;
          num finalQuantity = output.ratio;
          
          if (output.uom != null) {
            if (output.uom == secondaryUnit && secondaryUnit != null) {
              selectedUnit = secondaryUnit;
            } else if (output.uom == mainUnit) {
              selectedUnit = mainUnit;
            }
          }

          lineItems.add(
            InvoiceLineItem(
              productId: output.outputProductId,
              productCode: output.outputProductCode ?? productData['code']?.toString(),
              productName: output.outputProductName ?? productData['name']?.toString(),
              mainUnit: mainUnit,
              secondaryUnit: secondaryUnit,
              unitConversionFactor: unitFactor,
              selectedUnit: selectedUnit,
              quantity: finalQuantity,
              description: 'خروجی تولید',
              unitPriceSource: 'base',
              unitPrice: _toNum(productData['base_sales_price'], fallback: 0),
              baseSalesPriceMainUnit: _toNum(productData['base_sales_price']),
              basePurchasePriceMainUnit: _toNum(productData['base_purchase_price']),
              taxRate: _toNum(productData['sales_tax_rate'], fallback: 0),
              trackInventory: productData['track_inventory'] == true,
            ),
          );
        } catch (e) {
          // اگر محصول یافت نشد، با اطلاعات محدود اضافه می‌کنیم
          lineItems.add(
            InvoiceLineItem(
              productId: output.outputProductId,
              productCode: output.outputProductCode,
              productName: output.outputProductName ?? 'کالا #${output.outputProductId}',
              quantity: output.ratio,
              description: 'خروجی تولید',
              unitPriceSource: 'base',
              unitPrice: 0,
            ),
          );
        }
      }

      if (!mounted) return;

      // افزودن ردیف‌ها به فاکتور
      widget.onExploded(lineItems);

      // نمایش پیام موفقیت
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${lineItems.length} ردیف به فاکتور اضافه شد'),
          backgroundColor: Colors.green,
        ),
      );

      // پاک کردن فرم
      setState(() {
        _selectedProduct = null;
        _boms = [];
        _selectedBom = null;
        _quantityController.text = '1';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در انفجار فرمول: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exploding = false;
        });
      }
    }
  }

  num _toNum(dynamic value, {num fallback = 0}) {
    if (value == null) return fallback;
    if (value is num) return value;
    return num.tryParse(value.toString()) ?? fallback;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'انفجار فرمول تولید',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // انتخاب کالا
            ProductComboboxWidget(
              businessId: widget.businessId,
              selectedProduct: _selectedProduct,
              onChanged: (product) {
                setState(() {
                  _selectedProduct = product;
                  _boms = [];
                  _selectedBom = null;
                });
                if (product != null) {
                  _loadBomsForProduct(product['id'] as int);
                }
              },
              label: 'کالای تولیدی',
              hintText: 'انتخاب کالای تولیدی',
            ),
            
            const SizedBox(height: 16),
            
            // نمایش فرمول‌ها
            if (_loadingBoms)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_selectedProduct != null && _boms.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'برای این کالا فرمول تولیدی تعریف نشده است',
                  style: TextStyle(fontSize: 13),
                ),
              )
            else if (_boms.isNotEmpty) ...[
              // انتخاب فرمول
              DropdownButtonFormField<ProductBOM>(
                initialValue: _selectedBom,
                decoration: const InputDecoration(
                  labelText: 'فرمول تولید',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.list_alt),
                ),
                items: _boms.map((bom) {
                  return DropdownMenuItem<ProductBOM>(
                    value: bom,
                    child: Row(
                      children: [
                        if (bom.isDefault)
                          Icon(Icons.star, size: 16, color: Colors.orange),
                        if (bom.isDefault) const SizedBox(width: 4),
                        Text('${bom.name} (${bom.version})'),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (bom) {
                  setState(() {
                    _selectedBom = bom;
                  });
                },
              ),
              
              const SizedBox(height: 16),
              
              // ورود مقدار تولید
              TextField(
                controller: _quantityController,
                decoration: const InputDecoration(
                  labelText: 'مقدار تولید',
                  hintText: 'مثلاً 10',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.numbers),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  EnglishDigitsFormatter(),
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // دکمه انفجار
              FilledButton.icon(
                onPressed: _exploding ? null : _explodeAndAdd,
                icon: _exploding
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(_exploding ? 'در حال انفجار...' : 'انفجار و افزودن به فاکتور'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

