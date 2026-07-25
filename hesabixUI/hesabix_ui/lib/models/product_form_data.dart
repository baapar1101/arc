import 'catalog_specification_item.dart';
import 'product_supplier_item.dart';

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
  /// قیمت فروش ارزی (چندارزی)
  num? salesPriceFx;
  /// قیمت خرید ارزی (چندارزی)
  num? purchasePriceFx;
  int? priceFxCurrencyId;
  bool autoUpdateBaseFromFx;
  
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

  /// انتشار در API عمومی کاتالوگ (شبکهٔ تأمین کالا)
  bool isPublicCatalog;

  // پروفایل شبکهٔ تأمین
  String? catalogShortDescription;
  String? catalogExpertReview;
  List<CatalogSpecificationItem> catalogSpecifications;
  String? catalogBrand;
  String? catalogModel;
  String? catalogCountryOfOrigin;
  String? catalogVideoUrl;
  List<String> catalogGalleryFileIds;

  /// تأمین‌کنندگان کالا
  List<ProductSupplierItem> suppliers;

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
    this.salesPriceFx,
    this.purchasePriceFx,
    this.priceFxCurrencyId,
    this.autoUpdateBaseFromFx = false,
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
    this.catalogShortDescription,
    this.catalogExpertReview,
    List<CatalogSpecificationItem>? catalogSpecifications,
    this.catalogBrand,
    this.catalogModel,
    this.catalogCountryOfOrigin,
    this.catalogVideoUrl,
    List<String>? catalogGalleryFileIds,
    List<ProductSupplierItem>? suppliers,
  })  : selectedAttributeIds = selectedAttributeIds ?? <int>{},
        catalogSpecifications = catalogSpecifications ?? <CatalogSpecificationItem>[],
        catalogGalleryFileIds = catalogGalleryFileIds ?? <String>[],
        suppliers = suppliers ?? <ProductSupplierItem>[];

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
    Object? salesPriceFx = _kProductFormFieldUnset,
    Object? purchasePriceFx = _kProductFormFieldUnset,
    Object? priceFxCurrencyId = _kProductFormFieldUnset,
    bool? autoUpdateBaseFromFx,
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
    Object? catalogShortDescription = _kProductFormFieldUnset,
    Object? catalogExpertReview = _kProductFormFieldUnset,
    Object? catalogSpecifications = _kProductFormFieldUnset,
    Object? catalogBrand = _kProductFormFieldUnset,
    Object? catalogModel = _kProductFormFieldUnset,
    Object? catalogCountryOfOrigin = _kProductFormFieldUnset,
    Object? catalogVideoUrl = _kProductFormFieldUnset,
    Object? catalogGalleryFileIds = _kProductFormFieldUnset,
    Object? suppliers = _kProductFormFieldUnset,
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
      salesPriceFx: _nullableCopyField<num>(salesPriceFx, this.salesPriceFx),
      purchasePriceFx: _nullableCopyField<num>(purchasePriceFx, this.purchasePriceFx),
      priceFxCurrencyId: _nullableCopyField<int>(priceFxCurrencyId, this.priceFxCurrencyId),
      autoUpdateBaseFromFx: autoUpdateBaseFromFx ?? this.autoUpdateBaseFromFx,
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
      catalogShortDescription: _nullableCopyField<String>(catalogShortDescription, this.catalogShortDescription),
      catalogExpertReview: _nullableCopyField<String>(catalogExpertReview, this.catalogExpertReview),
      catalogSpecifications: identical(catalogSpecifications, _kProductFormFieldUnset)
          ? this.catalogSpecifications
          : List<CatalogSpecificationItem>.from(
              (catalogSpecifications as List<CatalogSpecificationItem>?) ?? const <CatalogSpecificationItem>[],
            ),
      catalogBrand: _nullableCopyField<String>(catalogBrand, this.catalogBrand),
      catalogModel: _nullableCopyField<String>(catalogModel, this.catalogModel),
      catalogCountryOfOrigin: _nullableCopyField<String>(catalogCountryOfOrigin, this.catalogCountryOfOrigin),
      catalogVideoUrl: _nullableCopyField<String>(catalogVideoUrl, this.catalogVideoUrl),
      catalogGalleryFileIds: identical(catalogGalleryFileIds, _kProductFormFieldUnset)
          ? this.catalogGalleryFileIds
          : List<String>.from((catalogGalleryFileIds as List<String>?) ?? const <String>[]),
      suppliers: identical(suppliers, _kProductFormFieldUnset)
          ? this.suppliers
          : List<ProductSupplierItem>.from(
              (suppliers as List<ProductSupplierItem>?) ?? const <ProductSupplierItem>[],
            ),
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
      'sales_price_fx': salesPriceFx,
      'purchase_price_fx': purchasePriceFx,
      'price_fx_currency_id': priceFxCurrencyId,
      'auto_update_base_from_fx': autoUpdateBaseFromFx,
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
      'catalog_short_description': catalogShortDescription?.trim().isEmpty == true
          ? null
          : catalogShortDescription?.trim(),
      'catalog_expert_review': catalogExpertReview?.trim().isEmpty == true
          ? null
          : catalogExpertReview?.trim(),
      'catalog_specifications': catalogSpecifications.isEmpty
          ? null
          : catalogSpecifications.map((e) => e.toJson()).toList(),
      'catalog_brand': catalogBrand?.trim().isEmpty == true ? null : catalogBrand?.trim(),
      'catalog_model': catalogModel?.trim().isEmpty == true ? null : catalogModel?.trim(),
      'catalog_country_of_origin': catalogCountryOfOrigin?.trim().isEmpty == true
          ? null
          : catalogCountryOfOrigin?.trim(),
      'catalog_video_url': catalogVideoUrl?.trim().isEmpty == true ? null : catalogVideoUrl?.trim(),
      'catalog_gallery_file_ids': catalogGalleryFileIds.isEmpty ? null : catalogGalleryFileIds,
      'suppliers': suppliers.isEmpty
          ? []
          : suppliers
              .where((s) => !s.isEffectivelyEmpty)
              .toList()
              .asMap()
              .entries
              .map((e) => e.value.toApiWrite(sortOrder: e.key))
              .toList(),
    };
    // Remove only nulls we intentionally kept nullable
    // فیلدهای زیر حتی با null هم ارسال می‌شوند تا بک‌اند بتواند آن‌ها را به‌روزرسانی/پاک کند
    payload.removeWhere((k, v) =>
        v == null &&
        k != 'default_warehouse_id' &&
        k != 'attribute_ids' &&
        k != 'general_barcodes' &&
        k != 'tax_type_id' &&
        k != 'tax_code' &&
        k != 'tax_unit_id' &&
        k != 'sales_tax_rate' &&
        k != 'purchase_tax_rate');
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
      salesPriceFx: _parseNumeric(product['sales_price_fx']),
      purchasePriceFx: _parseNumeric(product['purchase_price_fx']),
      priceFxCurrencyId: _parseInt(product['price_fx_currency_id']),
      autoUpdateBaseFromFx: product['auto_update_base_from_fx'] == true,
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
      taxTypeId: _parseInt(product['tax_type_id']),
      taxCode: product['tax_code']?.toString(),
      taxUnitId: _parseInt(product['tax_unit_id']),
      selectedAttributeIds: _parseAttributeIds(product['attribute_ids']),
      imageFileId: product['image_file_id']?.toString(),
      imageUrl: product['image_url']?.toString(),
      defaultWarehouseId: _parseInt(product['default_warehouse_id']),
      isPublicCatalog: product['is_public_catalog'] == true,
      catalogShortDescription: product['catalog_short_description']?.toString(),
      catalogExpertReview: product['catalog_expert_review']?.toString(),
      catalogSpecifications: _parseCatalogSpecifications(product['catalog_specifications']),
      catalogBrand: product['catalog_brand']?.toString(),
      catalogModel: product['catalog_model']?.toString(),
      catalogCountryOfOrigin: product['catalog_country_of_origin']?.toString(),
      catalogVideoUrl: product['catalog_video_url']?.toString(),
      catalogGalleryFileIds: _parseStringList(product['catalog_gallery_file_ids']),
      suppliers: _parseSuppliers(product['suppliers']),
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

  static List<CatalogSpecificationItem> _parseCatalogSpecifications(dynamic value) {
    if (value is! List) return <CatalogSpecificationItem>[];
    return value
        .whereType<Map>()
        .map((e) => CatalogSpecificationItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static List<String> _parseStringList(dynamic value) {
    if (value is! List) return <String>[];
    return value.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
  }

  static List<ProductSupplierItem> _parseSuppliers(dynamic value) {
    if (value is! List) return <ProductSupplierItem>[];
    return value
        .whereType<Map>()
        .map((e) => ProductSupplierItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}

/// تعداد اولیه کالا — فقط در سند تراز افتتاحیه ذخیره می‌شود.
class ProductOpeningBalanceInput {
  final double quantity;
  final double costPrice;
  final int? warehouseId;
  final int? fiscalYearId;
  final bool clear;

  const ProductOpeningBalanceInput({
    this.quantity = 0,
    this.costPrice = 0,
    this.warehouseId,
    this.fiscalYearId,
    this.clear = false,
  });

  Map<String, dynamic> toJson() => {
        if (clear) 'clear': true,
        if (!clear) 'quantity': quantity,
        if (!clear && costPrice > 0) 'cost_price': costPrice,
        if (warehouseId != null) 'warehouse_id': warehouseId,
        if (fiscalYearId != null) 'fiscal_year_id': fiscalYearId,
      };
}
