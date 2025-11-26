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
  
  // Unique Inventory Mode
  String? inventoryMode; // "bulk" or "unique"
  bool trackSerial;
  bool trackBarcode;
  
  // Pricing
  num? baseSalesPrice;
  num? basePurchasePrice;
  String? baseSalesNote;
  String? basePurchaseNote;
  
  // Units
  String? mainUnit;
  String? secondaryUnit;
  num unitConversionFactor;
  
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
  
  // Image
  String? imageFileId;
  String? imageUrl;
  
  // Warehouse
  int? defaultWarehouseId;

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
    this.inventoryMode,
    this.trackSerial = false,
    this.trackBarcode = false,
    this.baseSalesPrice,
    this.basePurchasePrice,
    this.baseSalesNote,
    this.basePurchaseNote,
    this.mainUnit = 'عدد',
    this.secondaryUnit,
    this.unitConversionFactor = 1,
    this.isSalesTaxable = false,
    this.isPurchaseTaxable = false,
    this.salesTaxRate,
    this.purchaseTaxRate,
    this.taxTypeId,
    this.taxCode,
    this.taxUnitId,
    Set<int>? selectedAttributeIds,
    this.imageFileId,
    this.imageUrl,
    this.defaultWarehouseId,
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
    String? inventoryMode,
    bool? trackSerial,
    bool? trackBarcode,
    num? baseSalesPrice,
    num? basePurchasePrice,
    String? baseSalesNote,
    String? basePurchaseNote,
    String? mainUnit,
    String? secondaryUnit,
    num? unitConversionFactor,
    bool? isSalesTaxable,
    bool? isPurchaseTaxable,
    num? salesTaxRate,
    num? purchaseTaxRate,
    int? taxTypeId,
    String? taxCode,
    int? taxUnitId,
    Set<int>? selectedAttributeIds,
    String? imageFileId,
    String? imageUrl,
    int? defaultWarehouseId,
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
      inventoryMode: inventoryMode ?? this.inventoryMode,
      trackSerial: trackSerial ?? this.trackSerial,
      trackBarcode: trackBarcode ?? this.trackBarcode,
      baseSalesPrice: baseSalesPrice ?? this.baseSalesPrice,
      basePurchasePrice: basePurchasePrice ?? this.basePurchasePrice,
      baseSalesNote: baseSalesNote ?? this.baseSalesNote,
      basePurchaseNote: basePurchaseNote ?? this.basePurchaseNote,
      mainUnit: mainUnit ?? this.mainUnit,
      secondaryUnit: secondaryUnit ?? this.secondaryUnit,
      unitConversionFactor: unitConversionFactor ?? this.unitConversionFactor,
      isSalesTaxable: isSalesTaxable ?? this.isSalesTaxable,
      isPurchaseTaxable: isPurchaseTaxable ?? this.isPurchaseTaxable,
      salesTaxRate: salesTaxRate ?? this.salesTaxRate,
      purchaseTaxRate: purchaseTaxRate ?? this.purchaseTaxRate,
      taxTypeId: taxTypeId ?? this.taxTypeId,
      taxCode: taxCode ?? this.taxCode,
      taxUnitId: taxUnitId ?? this.taxUnitId,
      selectedAttributeIds: selectedAttributeIds ?? this.selectedAttributeIds,
      imageFileId: imageFileId ?? this.imageFileId,
      imageUrl: imageUrl ?? this.imageUrl,
      defaultWarehouseId: defaultWarehouseId ?? this.defaultWarehouseId,
    );
  }

  Map<String, dynamic> toPayload() {
    // اگر code خالی است یا برابر name باشد، آن را null کن
    // (احتمالاً کاربر به اشتباه نام را در فیلد کد نوشته یا فیلد کد را پاک کرده)
    final trimmedCode = code?.trim();
    final trimmedName = name.trim();
    final codeValue = (trimmedCode != null && 
                      trimmedCode.isNotEmpty && 
                      trimmedCode != trimmedName) 
        ? trimmedCode 
        : null;
    
    final payload = <String, dynamic>{
      'item_type': itemType,
      'code': codeValue,
      'name': name,
      'description': description,
      'category_id': categoryId,
      'track_inventory': trackInventory,
      'inventory_mode': inventoryMode ?? 'bulk',
      'track_serial': trackSerial,
      'track_barcode': trackBarcode,
      // Default numeric fields to zero when null
      'base_sales_price': baseSalesPrice ?? 0,
      'base_purchase_price': basePurchasePrice ?? 0,
      'reorder_point': reorderPoint ?? 0,
      'min_order_qty': minOrderQty ?? 0,
      'lead_time_days': leadTimeDays ?? 0,
      'is_sales_taxable': isSalesTaxable,
      'is_purchase_taxable': isPurchaseTaxable,
      'sales_tax_rate': salesTaxRate ?? 0,
      'purchase_tax_rate': purchaseTaxRate ?? 0,
      // Units as strings
      'main_unit': mainUnit,
      'secondary_unit': secondaryUnit,
      'unit_conversion_factor': unitConversionFactor,
      'base_sales_note': baseSalesNote,
      'base_purchase_note': basePurchaseNote,
      'tax_type_id': taxTypeId,
      'tax_code': taxCode,
      'tax_unit_id': taxUnitId,
      'attribute_ids': selectedAttributeIds.toList(), // همیشه لیست ارسال می‌شود (حتی اگر خالی باشد) تا بک‌اند بتواند ویژگی‌ها را به‌روزرسانی کند
      'image_file_id': imageFileId,
      'default_warehouse_id': defaultWarehouseId,
    };
    // Remove only nulls we intentionally kept nullable
    // اما default_warehouse_id و attribute_ids را همیشه نگه می‌داریم (حتی اگر null/خالی باشند) تا بک‌اند بتواند آن‌ها را به‌روزرسانی کند
    payload.removeWhere((k, v) => v == null && k != 'default_warehouse_id' && k != 'attribute_ids');
    return payload;
  }

  factory ProductFormData.fromProduct(Map<String, dynamic> product) {
    return ProductFormData(
      itemType: (product['item_type'] as String?) ?? 'کالا',
      code: product['code']?.toString(),
      name: product['name'] ?? '',
      description: product['description']?.toString(),
      categoryId: product['category_id'] as int?,
      trackInventory: (product['track_inventory'] == true),
      inventoryMode: product['inventory_mode']?.toString(),
      trackSerial: (product['track_serial'] == true),
      trackBarcode: (product['track_barcode'] == true),
      baseSalesPrice: _parseNumeric(product['base_sales_price']),
      basePurchasePrice: _parseNumeric(product['base_purchase_price']),
      mainUnit: product['main_unit']?.toString(),
      secondaryUnit: product['secondary_unit']?.toString(),
      unitConversionFactor: _parseNumeric(product['unit_conversion_factor']) ?? 1,
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
      imageFileId: product['image_file_id']?.toString(),
      imageUrl: product['image_url']?.toString(),
      defaultWarehouseId: _parseInt(product['default_warehouse_id']),
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
