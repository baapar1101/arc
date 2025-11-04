class InvoiceLineItem {
  final int? productId;
  final String? productCode;
  final String? productName;

  final String? mainUnit;
  final String? secondaryUnit;
  final num? unitConversionFactor; // 1 main = factor * secondary

  String? selectedUnit;

  num quantity;

  // unit price handling
  String unitPriceSource; // manual | base | priceList
  num unitPrice; // price per selected unit

  // base prices on main unit (as provided by product)
  final num? baseSalesPriceMainUnit;
  final num? basePurchasePriceMainUnit;

  // discount
  String discountType; // percent | amount
  num discountValue; // either percentage (0-100) or absolute amount

  // tax
  num taxRate; // percent, editable by user

  // inventory/constraints
  final int? minOrderQty;
  final bool trackInventory;
  final int? warehouseId; // انبار انتخابی برای ردیف

  // presentation
  String? description;

  InvoiceLineItem({
    this.productId,
    this.productCode,
    this.productName,
    this.mainUnit,
    this.secondaryUnit,
    this.unitConversionFactor,
    this.selectedUnit,
    this.description,
    this.unitPriceSource = 'base',
    this.unitPrice = 0,
    this.quantity = 1,
    this.discountType = 'amount',
    this.discountValue = 0,
    this.taxRate = 0,
    this.baseSalesPriceMainUnit,
    this.basePurchasePriceMainUnit,
    this.minOrderQty,
    this.trackInventory = false,
    this.warehouseId,
  });

  InvoiceLineItem copyWith({
    int? productId,
    String? productCode,
    String? productName,
    String? mainUnit,
    String? secondaryUnit,
    num? unitConversionFactor,
    String? selectedUnit,
    num? quantity,
    String? unitPriceSource,
    num? unitPrice,
    String? discountType,
    num? discountValue,
    num? taxRate,
    String? description,
    num? baseSalesPriceMainUnit,
    num? basePurchasePriceMainUnit,
    int? minOrderQty,
    bool? trackInventory,
    int? warehouseId,
  }) {
    return InvoiceLineItem(
      productId: productId ?? this.productId,
      productCode: productCode ?? this.productCode,
      productName: productName ?? this.productName,
      mainUnit: mainUnit ?? this.mainUnit,
      secondaryUnit: secondaryUnit ?? this.secondaryUnit,
      unitConversionFactor: unitConversionFactor ?? this.unitConversionFactor,
      selectedUnit: selectedUnit ?? this.selectedUnit,
      quantity: quantity ?? this.quantity,
      unitPriceSource: unitPriceSource ?? this.unitPriceSource,
      unitPrice: unitPrice ?? this.unitPrice,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
      taxRate: taxRate ?? this.taxRate,
      description: description ?? this.description,
      baseSalesPriceMainUnit: baseSalesPriceMainUnit ?? this.baseSalesPriceMainUnit,
      basePurchasePriceMainUnit: basePurchasePriceMainUnit ?? this.basePurchasePriceMainUnit,
      minOrderQty: minOrderQty ?? this.minOrderQty,
      trackInventory: trackInventory ?? this.trackInventory,
      warehouseId: warehouseId ?? this.warehouseId,
    );
  }

  num get subtotal => quantity * unitPrice;

  num get discountAmount {
    if (discountType == 'percent') {
      final p = discountValue;
      if (p <= 0) return 0;
      return subtotal * (p / 100);
    }
    return discountValue;
  }

  num get taxableAmount {
    final base = subtotal - discountAmount;
    return base < 0 ? 0 : base;
  }

  num get taxAmount => taxableAmount * (taxRate / 100);

  num get total => taxableAmount + taxAmount;
}


