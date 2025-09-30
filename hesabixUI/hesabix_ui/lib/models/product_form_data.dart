class ProductFormData {
  // Basic Information
  String itemType;
  String? code;
  String name;
  String? description;
  int? categoryId;
  
  // Inventory
  bool trackInventory;
  int? reorderPoint;
  int? minOrderQty;
  int? leadTimeDays;
  
  // Pricing
  num? baseSalesPrice;
  num? basePurchasePrice;
  String? baseSalesNote;
  String? basePurchaseNote;
  
  // Units
  int? mainUnitId;
  int? secondaryUnitId;
  num? unitConversionFactor;
  
  // Taxes
  bool isSalesTaxable;
  bool isPurchaseTaxable;
  num? salesTaxRate;
  num? purchaseTaxRate;
  int? taxTypeId;
  String? taxCode;
  int? taxUnitId;
  
  // Attributes
  Set<int> selectedAttributeIds;

  ProductFormData({
    this.itemType = 'کالا',
    this.code,
    this.name = '',
    this.description,
    this.categoryId,
    this.trackInventory = false,
    this.reorderPoint,
    this.minOrderQty,
    this.leadTimeDays,
    this.baseSalesPrice,
    this.basePurchasePrice,
    this.baseSalesNote,
    this.basePurchaseNote,
    this.mainUnitId,
    this.secondaryUnitId,
    this.unitConversionFactor,
    this.isSalesTaxable = false,
    this.isPurchaseTaxable = false,
    this.salesTaxRate,
    this.purchaseTaxRate,
    this.taxTypeId,
    this.taxCode,
    this.taxUnitId,
    Set<int>? selectedAttributeIds,
  }) : selectedAttributeIds = selectedAttributeIds ?? <int>{};

  ProductFormData copyWith({
    String? itemType,
    String? code,
    String? name,
    String? description,
    int? categoryId,
    bool? trackInventory,
    int? reorderPoint,
    int? minOrderQty,
    int? leadTimeDays,
    num? baseSalesPrice,
    num? basePurchasePrice,
    String? baseSalesNote,
    String? basePurchaseNote,
    int? mainUnitId,
    int? secondaryUnitId,
    num? unitConversionFactor,
    bool? isSalesTaxable,
    bool? isPurchaseTaxable,
    num? salesTaxRate,
    num? purchaseTaxRate,
    int? taxTypeId,
    String? taxCode,
    int? taxUnitId,
    Set<int>? selectedAttributeIds,
  }) {
    return ProductFormData(
      itemType: itemType ?? this.itemType,
      code: code ?? this.code,
      name: name ?? this.name,
      description: description ?? this.description,
      categoryId: categoryId ?? this.categoryId,
      trackInventory: trackInventory ?? this.trackInventory,
      reorderPoint: reorderPoint ?? this.reorderPoint,
      minOrderQty: minOrderQty ?? this.minOrderQty,
      leadTimeDays: leadTimeDays ?? this.leadTimeDays,
      baseSalesPrice: baseSalesPrice ?? this.baseSalesPrice,
      basePurchasePrice: basePurchasePrice ?? this.basePurchasePrice,
      baseSalesNote: baseSalesNote ?? this.baseSalesNote,
      basePurchaseNote: basePurchaseNote ?? this.basePurchaseNote,
      mainUnitId: mainUnitId ?? this.mainUnitId,
      secondaryUnitId: secondaryUnitId ?? this.secondaryUnitId,
      unitConversionFactor: unitConversionFactor ?? this.unitConversionFactor,
      isSalesTaxable: isSalesTaxable ?? this.isSalesTaxable,
      isPurchaseTaxable: isPurchaseTaxable ?? this.isPurchaseTaxable,
      salesTaxRate: salesTaxRate ?? this.salesTaxRate,
      purchaseTaxRate: purchaseTaxRate ?? this.purchaseTaxRate,
      taxTypeId: taxTypeId ?? this.taxTypeId,
      taxCode: taxCode ?? this.taxCode,
      taxUnitId: taxUnitId ?? this.taxUnitId,
      selectedAttributeIds: selectedAttributeIds ?? this.selectedAttributeIds,
    );
  }

  Map<String, dynamic> toPayload() {
    return {
      'item_type': itemType,
      'code': code,
      'name': name,
      'description': description,
      'category_id': categoryId,
      'track_inventory': trackInventory,
      'base_sales_price': baseSalesPrice,
      'base_purchase_price': basePurchasePrice,
      'main_unit_id': mainUnitId,
      'secondary_unit_id': secondaryUnitId,
      'unit_conversion_factor': unitConversionFactor,
      'base_sales_note': baseSalesNote,
      'base_purchase_note': basePurchaseNote,
      'reorder_point': reorderPoint,
      'min_order_qty': minOrderQty,
      'lead_time_days': leadTimeDays,
      'is_sales_taxable': isSalesTaxable,
      'is_purchase_taxable': isPurchaseTaxable,
      'sales_tax_rate': salesTaxRate,
      'purchase_tax_rate': purchaseTaxRate,
      'tax_type_id': taxTypeId,
      'tax_code': taxCode,
      'tax_unit_id': taxUnitId,
      'attribute_ids': selectedAttributeIds.isEmpty ? null : selectedAttributeIds.toList(),
    }..removeWhere((k, v) => v == null);
  }

  factory ProductFormData.fromProduct(Map<String, dynamic> product) {
    return ProductFormData(
      itemType: (product['item_type'] as String?) ?? 'کالا',
      code: product['code']?.toString(),
      name: product['name'] ?? '',
      description: product['description']?.toString(),
      categoryId: product['category_id'] as int?,
      trackInventory: (product['track_inventory'] == true),
      baseSalesPrice: _parseNumeric(product['base_sales_price']),
      basePurchasePrice: _parseNumeric(product['base_purchase_price']),
      mainUnitId: product['main_unit_id'] as int?,
      secondaryUnitId: product['secondary_unit_id'] as int?,
      unitConversionFactor: _parseNumeric(product['unit_conversion_factor']),
      baseSalesNote: product['base_sales_note']?.toString(),
      basePurchaseNote: product['base_purchase_note']?.toString(),
      reorderPoint: _parseInt(product['reorder_point']),
      minOrderQty: _parseInt(product['min_order_qty']),
      leadTimeDays: _parseInt(product['lead_time_days']),
      isSalesTaxable: (product['is_sales_taxable'] == true),
      isPurchaseTaxable: (product['is_purchase_taxable'] == true),
      salesTaxRate: _parseNumeric(product['sales_tax_rate']),
      purchaseTaxRate: _parseNumeric(product['purchase_tax_rate']),
      taxTypeId: product['tax_type_id'] as int?,
      taxCode: product['tax_code']?.toString(),
      taxUnitId: product['tax_unit_id'] as int?,
      selectedAttributeIds: _parseAttributeIds(product['attribute_ids']),
    );
  }

  static num? _parseNumeric(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static Set<int> _parseAttributeIds(dynamic value) {
    if (value is List) {
      return value.whereType<int>().toSet();
    }
    return <int>{};
  }
}
