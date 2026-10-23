import 'package:flutter/material.dart';
import '../../models/bom_models.dart';
import '../../models/invoice_line_item.dart';
import '../../models/production_order_models.dart';
import '../../services/bom_service.dart';
import '../../services/product_service.dart';
import '../../widgets/invoice/product_combobox_widget.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

/// ویجت انفجار فرمول تولید برای استفاده در فاکتور تولید
/// این ویجت فقط در فاکتور تولید نمایش داده می‌شود
class BomExplosionWidget extends StatefulWidget {
  final int businessId;
  final Function(List<InvoiceLineItem>, int bomId) onExploded;
  final double? productionOperationsTotal; // هزینه عملیات/سربار تولید
  final ProductionOrder? productionOrder;

  const BomExplosionWidget({
    super.key,
    required this.businessId,
    required this.onExploded,
    this.productionOperationsTotal,
    this.productionOrder,
  });

  @override
  State<BomExplosionWidget> createState() => _BomExplosionWidgetState();
}

class _BomExplosionWidgetState extends State<BomExplosionWidget> {
  final BomService _bomService = BomService();
  final ProductService _productService = ProductService();

  Map<String, dynamic>? _selectedProduct;
  ProductBOM? _selectedBom;
  List<ProductBOM> _availableBoms = [];
  double? _productionQuantity;
  bool _isLoadingBoms = false;
  bool _isExploding = false;

  @override
  void initState() {
    super.initState();
    final order = widget.productionOrder;
    if (order != null) {
      _selectedProduct = {
        'id': order.productId,
        'name': order.productName,
        'code': order.productCode,
      };
      _productionQuantity = _remainingOrderQuantity(order);
      _loadLinkedBom(order.bomId);
    }
  }

  double _remainingOrderQuantity(ProductionOrder order) {
    final primaryOutputs = order.outputs
        .where((output) => output.productId == order.productId)
        .toList();
    if (primaryOutputs.isEmpty || order.plannedQuantity <= 0) {
      return (order.plannedQuantity - order.producedQuantity).clamp(
        0,
        double.infinity,
      );
    }
    final remainingOutput = primaryOutputs
        .fold<double>(
          0,
          (sum, output) =>
              sum + output.plannedQuantity - output.producedQuantity,
        )
        .clamp(0, double.infinity);
    final plannedOutput = primaryOutputs.fold<double>(
      0,
      (sum, output) => sum + output.plannedQuantity,
    );
    final outputRatio = plannedOutput / order.plannedQuantity;
    return outputRatio > 0 ? remainingOutput / outputRatio : 0;
  }

  Future<void> _loadLinkedBom(int bomId) async {
    setState(() => _isLoadingBoms = true);
    try {
      final bom = await _bomService.getById(
        businessId: widget.businessId,
        bomId: bomId,
      );
      if (!mounted) return;
      setState(() {
        _availableBoms = [bom];
        _selectedBom = bom;
        _isLoadingBoms = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingBoms = false);
      SnackBarHelper.showError(
        context,
        message:
            'خطا در بارگذاری فرمول سفارش: ${ErrorExtractor.forContext(e, context)}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.build_circle_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'انفجار فرمول تولید',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'برای افزودن مواد اولیه و محصولات نهایی به فاکتور، فرمول تولید را منفجر کنید',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // انتخاب کالا
            if (widget.productionOrder == null)
              ProductComboboxWidget(
                businessId: widget.businessId,
                selectedProduct: _selectedProduct,
                onChanged: (product) {
                  setState(() {
                    _selectedProduct = product;
                    _selectedBom = null;
                    _availableBoms = [];
                    if (product != null && product['id'] != null) {
                      _loadBomsForProduct();
                    }
                  });
                },
                hintText: 'کالای تولیدی را انتخاب کنید',
              ),
            SizedBox(height: 16),
            // انتخاب فرمول (اگر کالا انتخاب شده باشد)
            if (_selectedProduct != null &&
                _selectedProduct!['id'] != null) ...[
              if (_isLoadingBoms)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_availableBoms.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.errorContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Theme.of(context).colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'برای این کالا فرمول تولیدی تعریف نشده است',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onErrorContainer,
                              ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (widget.productionOrder == null)
                DropdownButtonFormField<ProductBOM>(
                  value: _selectedBom,
                  decoration: InputDecoration(
                    labelText: 'فرمول تولید',
                    hintText: 'فرمول را انتخاب کنید',
                    prefixIcon: Icon(Icons.assignment_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                  ),
                  items: _availableBoms.map((bom) {
                    return DropdownMenuItem<ProductBOM>(
                      value: bom,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  bom.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'v${bom.version}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          if (bom.isDefault)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: SemanticColorResolver.warning(
                                  context,
                                ).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'پیش‌فرض',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: SemanticColorResolver.warning(
                                        context,
                                      ),
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ),
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
              if (widget.productionOrder != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _selectedProduct?['name']?.toString() ?? 'محصول سفارش',
                  ),
                  subtitle: Text(
                    'فرمول سفارش ${widget.productionOrder!.code} · مقدار مبنای باقی‌مانده: ${_remainingOrderQuantity(widget.productionOrder!)}',
                  ),
                ),
              TextFormField(
                initialValue: widget.productionOrder == null
                    ? null
                    : _productionQuantity?.toString(),
                decoration: InputDecoration(
                  labelText: 'مقدار تولید',
                  hintText: 'مثال: 100',
                  prefixIcon: const Icon(Icons.numbers_outlined),
                  suffixText: 'واحد',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (value) {
                  setState(() {
                    _productionQuantity = double.tryParse(value);
                  });
                },
              ),
              const SizedBox(height: 16),
              // دکمه انفجار
              FilledButton.icon(
                onPressed:
                    (_selectedBom != null &&
                        _productionQuantity != null &&
                        _productionQuantity! > 0 &&
                        !_isExploding)
                    ? _explodeAndAdd
                    : null,
                icon: _isExploding
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  _isExploding
                      ? 'در حال انفجار...'
                      : 'انفجار و افزودن به فاکتور',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _loadBomsForProduct() async {
    final productId = _selectedProduct?['id'] as int?;
    if (productId == null) return;

    setState(() {
      _isLoadingBoms = true;
      _selectedBom = null;
    });

    try {
      final boms = await _bomService.list(
        businessId: widget.businessId,
        productId: productId,
      );

      if (!mounted) return;

      ProductBOM? preferredBom;
      for (final bom in boms) {
        if (bom.isDefault) {
          preferredBom = bom;
          break;
        }
      }
      setState(() {
        _availableBoms = boms;
        _selectedBom = preferredBom ?? (boms.isNotEmpty ? boms.first : null);
        _isLoadingBoms = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _availableBoms = [];
        _selectedBom = null;
        _isLoadingBoms = false;
      });
      SnackBarHelper.showError(
        context,
        message:
            'خطا در بارگذاری فرمول‌ها: ${ErrorExtractor.forContext(e, context)}',
      );
    }
  }

  Future<void> _explodeAndAdd() async {
    if (_selectedBom == null ||
        _productionQuantity == null ||
        _productionQuantity! <= 0) {
      return;
    }

    setState(() {
      _isExploding = true;
    });

    try {
      // فراخوانی API انفجار
      final result = await _bomService.explode(
        businessId: widget.businessId,
        bomId: _selectedBom!.id,
        quantity: _productionQuantity!,
        recursive: widget.productionOrder != null,
        date: DateTime.now().toIso8601String().split('T').first,
      );

      if (!mounted) return;

      // تبدیل نتایج به InvoiceLineItem
      final lineItems = await _convertToLineItems(result, _selectedBom!.id!);
      if (!mounted) return;

      // فراخوانی callback
      widget.onExploded(lineItems, _selectedBom!.id!);

      // نمایش پیام موفقیت
      SnackBarHelper.showSuccess(
        context,
        message:
            'فرمول با موفقیت منفجر شد و ${lineItems.length} ردیف به فاکتور اضافه شد',
      );

      // پاک کردن فیلدها
      setState(() {
        _productionQuantity = null;
        _isExploding = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isExploding = false;
      });
      SnackBarHelper.showError(
        context,
        message:
            'خطا در انفجار فرمول: ${ErrorExtractor.forContext(e, context)}',
      );
    }
  }

  /// تبدیل نتایج انفجار به ردیف‌های فاکتور
  Future<List<InvoiceLineItem>> _convertToLineItems(
    BomExplosionResult result,
    int bomId,
  ) async {
    final lineItems = <InvoiceLineItem>[];

    // محاسبه مجموع هزینه مواد اولیه
    double totalMaterialsCost = 0;
    final productCosts = <int, double>{};
    final consumedOrderMaterialIds = <int>{};
    final orderMaterialIds = <int?>[];
    final linkedMaterials = <dynamic>[];

    for (final item in result.items) {
      final linkedCandidates =
          widget.productionOrder?.materials
              .where(
                (row) =>
                    row.productId == item.componentProductId &&
                    (item.suggestedWarehouseId == null ||
                        row.warehouseId == item.suggestedWarehouseId) &&
                    row.id != null &&
                    !consumedOrderMaterialIds.contains(row.id),
              )
              .toList() ??
          const [];
      final linkedMaterial = linkedCandidates.isNotEmpty
          ? linkedCandidates.first
          : null;
      try {
        final product = widget.productionOrder == null || linkedMaterial == null
            ? await _productService.getProduct(
                businessId: widget.businessId,
                productId: item.componentProductId,
              )
            : null;
        final costPrice =
            linkedMaterial?.standardUnitCost ??
            (product?['base_purchase_price'] as num?)?.toDouble() ??
            0.0;
        final inventoryQty = item.requiredQtyMainUnit ?? item.requiredQty;
        final itemCost = inventoryQty * costPrice;
        totalMaterialsCost += itemCost;
        productCosts[item.componentProductId] = costPrice;
        if (linkedMaterial?.id != null) {
          consumedOrderMaterialIds.add(linkedMaterial!.id!);
        }
        orderMaterialIds.add(linkedMaterial?.id);
        linkedMaterials.add(linkedMaterial);
      } catch (e) {
        // در صورت خطا، از 0 استفاده می‌کنیم
        productCosts[item.componentProductId] = 0.0;
        orderMaterialIds.add(linkedMaterial?.id);
        linkedMaterials.add(linkedMaterial);
      }
    }

    // محاسبه تعداد کل محصولات نهایی
    double totalOutputQty = 0;
    for (final output in result.outputs) {
      totalOutputQty += output.ratioMainUnit ?? output.ratio;
    }

    // تبدیل items به ردیف‌ها (movement: "out" - مواد اولیه)
    for (var itemIndex = 0; itemIndex < result.items.length; itemIndex++) {
      final item = result.items[itemIndex];
      final costPrice = productCosts[item.componentProductId] ?? 0.0;
      final linkedMaterial = itemIndex < linkedMaterials.length
          ? linkedMaterials[itemIndex]
          : null;

      lineItems.add(
        InvoiceLineItem(
          productId: item.componentProductId,
          productName: item.componentProductName,
          productCode: item.componentProductCode,
          quantity: item.requiredQtyMainUnit ?? item.requiredQty,
          unitPrice: costPrice,
          unitPriceSource: 'manual',
          mainUnit: item.mainUnit ?? item.componentProductMainUnit,
          selectedUnit:
              item.mainUnit ?? item.componentProductMainUnit ?? item.uom,
          warehouseId: linkedMaterial?.warehouseId ?? item.suggestedWarehouseId,
          trackInventory: true,
          extraInfo: {
            'movement': 'out',
            'bom_id': bomId,
            'cost_price': costPrice,
            if (itemIndex < orderMaterialIds.length &&
                orderMaterialIds[itemIndex] != null)
              'production_order_material_id': orderMaterialIds[itemIndex],
            if (linkedMaterial?.warehouseId != null)
              'warehouse_id': linkedMaterial!.warehouseId,
            if (linkedMaterial?.warehouseId == null &&
                item.suggestedWarehouseId != null)
              'warehouse_id': item.suggestedWarehouseId,
          },
        ),
      );
    }

    // تبدیل outputs به ردیف‌ها (movement: "in" - محصولات نهایی)
    // استفاده از هزینه عملیات از UI
    final operationsTotal = widget.productionOperationsTotal ?? 0.0;
    final totalCost = totalMaterialsCost + operationsTotal;
    final costPricePerUnit = totalOutputQty > 0
        ? totalCost / totalOutputQty
        : 0.0;
    final consumedOrderOutputIds = <int>{};

    for (final output in result.outputs) {
      final linkedCandidates =
          widget.productionOrder?.outputs
              .where(
                (row) =>
                    row.productId == output.outputProductId &&
                    row.id != null &&
                    !consumedOrderOutputIds.contains(row.id),
              )
              .toList() ??
          const [];
      final linkedOutput = linkedCandidates.isNotEmpty
          ? linkedCandidates.first
          : null;
      if (linkedOutput?.id != null) {
        consumedOrderOutputIds.add(linkedOutput!.id!);
      }
      final outputCostPrice =
          linkedOutput?.standardUnitCost ?? costPricePerUnit;
      lineItems.add(
        InvoiceLineItem(
          productId: output.outputProductId,
          productName: output.outputProductName,
          productCode: output.outputProductCode,
          quantity: output.ratioMainUnit ?? output.ratio,
          unitPrice: outputCostPrice,
          unitPriceSource: 'manual',
          mainUnit: output.mainUnit,
          selectedUnit: output.mainUnit ?? output.uom,
          warehouseId: widget.productionOrder?.outputWarehouseId,
          trackInventory: true,
          extraInfo: {
            'movement': 'in',
            'bom_id': bomId,
            'cost_price': outputCostPrice,
            if (widget.productionOrder?.outputWarehouseId != null)
              'warehouse_id': widget.productionOrder!.outputWarehouseId,
            if (linkedOutput?.id != null)
              'production_order_output_id': linkedOutput!.id,
          },
        ),
      );
    }

    return lineItems;
  }
}
