import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product_form_data.dart';

/// سرویس برای ذخیره و بارگذاری خودکار فرم کالا
class ProductFormAutoSave {
  static const String _keyPrefix = 'product_form_draft_';
  static const Duration _autoSaveInterval = Duration(seconds: 2);
  
  DateTime? _lastSaveTime;
  bool _isSaving = false;
  
  /// کلید ذخیره‌سازی برای یک business
  String _getKey(int businessId, int? productId) {
    if (productId != null) {
      return '${_keyPrefix}${businessId}_edit_$productId';
    }
    return '${_keyPrefix}${businessId}_new';
  }
  
  /// ذخیره فرم (با debounce)
  Future<void> saveFormData(int businessId, int? productId, ProductFormData formData) async {
    // Debounce: فقط اگر 2 ثانیه از آخرین ذخیره گذشته باشد
    final now = DateTime.now();
    if (_lastSaveTime != null && 
        now.difference(_lastSaveTime!) < _autoSaveInterval &&
        _isSaving) {
      return;
    }
    
    _isSaving = true;
    _lastSaveTime = now;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getKey(businessId, productId);
      
      // تبدیل ProductFormData به Map
      final data = {
        'itemType': formData.itemType,
        'code': formData.code,
        'autoGenerateCode': formData.autoGenerateCode,
        'name': formData.name,
        'description': formData.description,
        'generalBarcodes': formData.generalBarcodes,
        'categoryId': formData.categoryId,
        'trackInventory': formData.trackInventory,
        'reorderPoint': formData.reorderPoint,
        'minOrderQty': formData.minOrderQty,
        'leadTimeDays': formData.leadTimeDays,
        'inventoryMode': formData.inventoryMode,
        'trackSerial': formData.trackSerial,
        'trackBarcode': formData.trackBarcode,
        'baseSalesPrice': formData.baseSalesPrice,
        'basePurchasePrice': formData.basePurchasePrice,
        'baseSalesNote': formData.baseSalesNote,
        'basePurchaseNote': formData.basePurchaseNote,
        'mainUnit': formData.mainUnit,
        'secondaryUnit': formData.secondaryUnit,
        'unitConversionFactor': formData.unitConversionFactor,
        'isSalesTaxable': formData.isSalesTaxable,
        'isPurchaseTaxable': formData.isPurchaseTaxable,
        'salesTaxRate': formData.salesTaxRate,
        'purchaseTaxRate': formData.purchaseTaxRate,
        'taxTypeId': formData.taxTypeId,
        'taxCode': formData.taxCode,
        'taxUnitId': formData.taxUnitId,
        'selectedAttributeIds': formData.selectedAttributeIds.toList(),
        'imageFileId': formData.imageFileId,
        'imageUrl': formData.imageUrl,
        'defaultWarehouseId': formData.defaultWarehouseId,
        'savedAt': DateTime.now().toIso8601String(),
      };
      
      await prefs.setString(key, jsonEncode(data));
    } catch (e) {
      // Silent fail - auto-save should not interrupt user
      print('Error saving form draft: $e');
    } finally {
      _isSaving = false;
    }
  }
  
  /// بارگذاری فرم ذخیره شده
  Future<ProductFormData?> loadFormData(int businessId, int? productId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getKey(businessId, productId);
      final jsonString = prefs.getString(key);
      
      if (jsonString == null) return null;
      
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final hasCode = (data['code'] as String?)?.trim().isNotEmpty == true;
      final autoGen = (data['autoGenerateCode'] as bool?) ?? !hasCode;

      // بررسی اینکه آیا داده قدیمی است (بیش از 24 ساعت)
      final savedAt = data['savedAt'] as String?;
      if (savedAt != null) {
        final savedTime = DateTime.parse(savedAt);
        if (DateTime.now().difference(savedTime).inHours > 24) {
          // حذف داده قدیمی
          await prefs.remove(key);
          return null;
        }
      }
      
      return ProductFormData(
        itemType: data['itemType'] as String? ?? 'کالا',
        code: autoGen ? null : (data['code'] as String?),
        autoGenerateCode: autoGen,
        name: data['name'] as String? ?? '',
        description: data['description'] as String?,
        generalBarcodes: data['generalBarcodes'] as String?,
        categoryId: data['categoryId'] as int?,
        trackInventory: data['trackInventory'] as bool? ?? false,
        reorderPoint: data['reorderPoint'] as int?,
        minOrderQty: data['minOrderQty'] as int?,
        leadTimeDays: data['leadTimeDays'] as int?,
        inventoryMode: data['inventoryMode'] as String?,
        trackSerial: data['trackSerial'] as bool? ?? false,
        trackBarcode: data['trackBarcode'] as bool? ?? false,
        baseSalesPrice: data['baseSalesPrice'] as num?,
        basePurchasePrice: data['basePurchasePrice'] as num?,
        baseSalesNote: data['baseSalesNote'] as String?,
        basePurchaseNote: data['basePurchaseNote'] as String?,
        mainUnit: data['mainUnit'] as String?,
        secondaryUnit: data['secondaryUnit'] as String?,
        unitConversionFactor: data['unitConversionFactor'] as num? ?? 1,
        isSalesTaxable: data['isSalesTaxable'] as bool? ?? false,
        isPurchaseTaxable: data['isPurchaseTaxable'] as bool? ?? false,
        salesTaxRate: data['salesTaxRate'] as num?,
        purchaseTaxRate: data['purchaseTaxRate'] as num?,
        taxTypeId: data['taxTypeId'] as int?,
        taxCode: data['taxCode'] as String?,
        taxUnitId: data['taxUnitId'] as int?,
        selectedAttributeIds: (data['selectedAttributeIds'] as List<dynamic>?)
            ?.map((e) => e as int)
            .toSet() ?? <int>{},
        imageFileId: data['imageFileId'] as String?,
        imageUrl: data['imageUrl'] as String?,
        defaultWarehouseId: data['defaultWarehouseId'] as int?,
      );
    } catch (e) {
      print('Error loading form draft: $e');
      return null;
    }
  }
  
  /// حذف فرم ذخیره شده
  Future<void> clearFormData(int businessId, int? productId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getKey(businessId, productId);
      await prefs.remove(key);
    } catch (e) {
      print('Error clearing form draft: $e');
    }
  }
  
  /// حذف تمام فرم‌های ذخیره شده برای یک business
  Future<void> clearAllFormData(int businessId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('${_keyPrefix}${businessId}_')) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      print('Error clearing all form drafts: $e');
    }
  }
}


