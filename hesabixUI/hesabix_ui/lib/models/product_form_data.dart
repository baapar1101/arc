const Object _kProductFormCodeUnset = Object();
const Object _kProductFormFieldUnset = Object();

T? _nullableCopyField<T extends Object>(Object? incoming, T? current) {
  if (identical(incoming, _kProductFormFieldUnset)) return current;
  return incoming as T?;
}

class ProductFormData {
  // Basic Information
  String itemType;
  String? code;
  /// اگر true باشد، کد در payload ارسال نمی‌شود و سرور کد یکتا تولید می‌کند.
  bool autoGenerateCode;
  String name;
  String? description;
  /// بارکدهای عمومی؛ با ویرگول از هم جدا می‌شوند (هم‌عرض با APIی `general_barcodes`).
  String? generalBarcodes;
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

  /// انتشار در API عمومی کاتالوگ (شبکهٔ انتشار کالا)
  bool isPublicCatalog;

  ProductFormData({
    this.itemType = 'کالا',
    this.code,
    this.autoGenerateCode = true,
    this.name = '',
    this.description,
    this.generalBarcodes,
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
    this.isPublicCatalog = false,
  }) : selectedAttributeIds = selectedAttributeIds ?? <int>{};

  ProductFormData copyWith({
    String? itemType,
    Object? code = _kProductFormCodeUnset,
    bool? autoGenerateCode,
    String? name,
    Object? description = _kProductFormFieldUnset,
    Object? generalBarcodes = _kProductFormFieldUnset,
    Object? categoryId = _kProductFormFieldUnset,
    bool? trackInventory,
    Object? reorderPoint = _kProductFormFieldUnset,
    Object? minOrderQty = _kProductFormFieldUnset,
    Object? leadTimeDays = _kProductFormFieldUnset,
    Object? inventoryMode = _kProductFormFieldUnset,
    bool? trackSerial,
    bool? trackBarcode,
    Object? baseSalesPrice = _kProductFormFieldUnset,
    Object? basePurchasePrice = _kProductFormFieldUnset,
    Object? baseSalesNote = _kProductFormFieldUnset,
    Object? basePurchaseNote = _kProductFormFieldUnset,
    String? mainUnit,
    Object? secondaryUnit = _kProductFormFieldUnset,
    num? unitConversionFactor,
    bool? isSalesTaxable,
    bool? isPurchaseTaxable,
    Object? salesTaxRate = _kProductFormFieldUnset,
    Object? purchaseTaxRate = _kProductFormFieldUnset,
    Object? taxTypeId = _kProductFormFieldUnset,
    Object? taxCode = _kProductFormFieldUnset,
    Object? taxUnitId = _kProductFormFieldUnset,
    Object? selectedAttributeIds = _kProductFormFieldUnset,
    Object? imageFileId = _kProductFormFieldUnset,
    Object? imageUrl = _kProductFormFieldUnset,
    Object? defaultWarehouseId = _kProductFormFieldUnset,
    bool? isPublicCatalog,
  }) {
    return ProductFormData(
      itemType: itemType ?? this.itemType,
      code: identical(code, _kProductFormCodeUnset) ? this.code : code as String?,
      autoGenerateCode: autoGenerateCode ?? this.autoGenerateCode,
      name: name ?? this.name,
      description: _nullableCopyField<String>(description, this.description),
      generalBarcodes: _nullableCopyField<String>(generalBarcodes, this.generalBarcodes),
      categoryId: _nullableCopyField<int>(categoryId, this.categoryId),
      trackInventory: trackInventory ?? this.trackInventory,
      reorderPoint: _nullableCopyField<int>(reorderPoint, this.reorderPoint),
      minOrderQty: _nullableCopyField<int>(minOrderQty, this.minOrderQty),
      leadTimeDays: _nullableCopyField<int>(leadTimeDays, this.leadTimeDays),
      inventoryMode: _nullableCopyField<String>(inventoryMode, this.inventoryMode),
      trackSerial: trackSerial ?? this.trackSerial,
      trackBarcode: trackBarcode ?? this.trackBarcode,
      baseSalesPrice: _nullableCopyField<num>(baseSalesPrice, this.baseSalesPrice),
      basePurchasePrice: _nullableCopyField<num>(basePurchasePrice, this.basePurchasePrice),
      baseSalesNote: _nullableCopyField<String>(baseSalesNote, this.baseSalesNote),
      basePurchaseNote: _nullableCopyField<String>(basePurchaseNote, this.basePurchaseNote),
      mainUnit: mainUnit ?? this.mainUnit,
      secondaryUnit: _nullableCopyField<String>(secondaryUnit, this.secondaryUnit),
      unitConversionFactor: unitConversionFactor ?? this.unitConversionFactor,
      isSalesTaxable: isSalesTaxable ?? this.isSalesTaxable,
      isPurchaseTaxable: isPurchaseTaxable ?? this.isPurchaseTaxable,
      salesTaxRate: _nullableCopyField<num>(salesTaxRate, this.salesTaxRate),
      purchaseTaxRate: _nullableCopyField<num>(purchaseTaxRate, this.purchaseTaxRate),
      taxTypeId: _nullableCopyField<int>(taxTypeId, this.taxTypeId),
      taxCode: _nullableCopyField<String>(taxCode, this.taxCode),
      taxUnitId: _nullableCopyField<int>(taxUnitId, this.taxUnitId),
      selectedAttributeIds: identical(selectedAttributeIds, _kProductFormFieldUnset)
          ? this.selectedAttributeIds
          : Set<int>.from((selectedAttributeIds as Set<int>?) ?? const <int>{}),
      imageFileId: _nullableCopyField<String>(imageFileId, this.imageFileId),
      imageUrl: _nullableCopyField<String>(imageUrl, this.imageUrl),
      defaultWarehouseId: _nullableCopyField<int>(defaultWarehouseId, this.defaultWarehouseId),
      isPublicCatalog: isPublicCatalog ?? this.isPublicCatalog,
    );
  }

  Map<String, dynamic> toPayload() {
    // اگر code خالی است یا برابر name باشد، آن را null کن
    // (احتمالاً کاربر به اشتباه نام را در فیلد کد نوشته یا فیلد کد را پاک کرده)
    final trimmedCode = autoGenerateCode ? null : code?.trim();
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
      'general_barcodes': generalBarcodes?.trim().isEmpty == true ? null : generalBarcodes?.trim(),
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
      'is_public_catalog': isPublicCatalog,
    };
    // Remove only nulls we intentionally kept nullable
    // اما default_warehouse_id و attribute_ids را همیشه نگه می‌داریم (حتی اگر null/خالی باشند) تا بک‌اند بتواند آن‌ها را به‌روزرسانی کند
    payload.removeWhere((k, v) =>
        v == null &&
        k != 'default_warehouse_id' &&
        k != 'attribute_ids' &&
        k != 'general_barcodes');
    return payload;
  }

  factory ProductFormData.fromProduct(Map<String, dynamic> product) {
    return ProductFormData(
      itemType: (product['item_type'] as String?) ?? 'کالا',
      code: product['code']?.toString(),
      autoGenerateCode: false,
      name: product['name'] ?? '',
      description: product['description']?.toString(),
      generalBarcodes: product['general_barcodes']?.toString(),
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
      isPublicCatalog: product['is_public_catalog'] == true,
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
