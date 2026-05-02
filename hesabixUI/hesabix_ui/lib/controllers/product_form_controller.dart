import 'package:flutter/material.dart';
import '../models/product_form_data.dart';
import '../services/product_service.dart';
import '../services/category_service.dart';
import '../services/product_attribute_service.dart';
import '../services/tax_service.dart';
import '../services/price_list_service.dart';
import '../services/currency_service.dart';
import '../services/warehouse_service.dart';
import '../core/api_client.dart';
import '../utils/error_extractor.dart';
import '../utils/product_form_auto_save.dart';
import '../utils/product_form_validator.dart';

class ProductFormController extends ChangeNotifier {
  final int businessId;
  final ApiClient _apiClient;
  
  late final ProductService _productService;
  late final CategoryService _categoryService;
  late final ProductAttributeService _attributeService;
  late final TaxService _taxService;
  late final PriceListService _priceListService;
  late final CurrencyService _currencyService;
  late final WarehouseService _warehouseService;

  ProductFormData _formData = ProductFormData();
  bool _isLoading = false;
  String? _errorMessage;
  int? _editingProductId;
  int? _lastCreatedProductId;
  String? _originalInventoryMode; // برای تشخیص تغییر از bulk به unique
  
  // Reference data
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _attributes = [];
  List<Map<String, dynamic>> _taxTypes = [];
  List<Map<String, dynamic>> _taxUnits = [];
  List<Map<String, dynamic>> _priceLists = [];
  List<Map<String, dynamic>> _currencies = [];
  List<Map<String, dynamic>> _warehouses = [];

  // Draft price items per price list (for multi-currency)
  final List<Map<String, dynamic>> _draftPriceItems = [];
  
  // Image management
  List<int>? _selectedImageBytes;
  String? _selectedImageFilename;
  
  // Auto-save
  final ProductFormAutoSave _autoSave = ProductFormAutoSave();
  bool _autoSaveEnabled = true;

  ProductFormController({
    required this.businessId,
    ApiClient? apiClient,
  }) : _apiClient = apiClient ?? ApiClient() {
    _initializeServices();
  }

  void _initializeServices() {
    _productService = ProductService(apiClient: _apiClient);
    _categoryService = CategoryService(_apiClient);
    _attributeService = ProductAttributeService(apiClient: _apiClient);
    _taxService = TaxService(apiClient: _apiClient);
    _priceListService = PriceListService(apiClient: _apiClient);
    _currencyService = CurrencyService(_apiClient);
    _warehouseService = WarehouseService();
  }

  // Getters
  ProductFormData get formData => _formData;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isEditingProduct => _editingProductId != null;
  int? get lastCreatedProductId => _lastCreatedProductId;
  List<Map<String, dynamic>> get categories => _categories;
  List<Map<String, dynamic>> get attributes => _attributes;
  List<Map<String, dynamic>> get taxTypes => _taxTypes;
  List<Map<String, dynamic>> get taxUnits => _taxUnits;
  List<Map<String, dynamic>> get priceLists => _priceLists;
  List<Map<String, dynamic>> get currencies => _currencies;
  List<Map<String, dynamic>> get warehouses => _warehouses;
  List<Map<String, dynamic>> get draftPriceItems => List.unmodifiable(_draftPriceItems);

  void addOrUpdateDraftPriceItem(Map<String, dynamic> item) {
    final String key = (
      '${item['price_list_id']?.toString() ?? ''}|${item['product_id']?.toString() ?? ''}|${item['unit_id']?.toString() ?? 'null'}|${item['currency_id']?.toString() ?? ''}|${item['tier_name']?.toString() ?? ''}|${item['min_qty']?.toString() ?? '0'}'
    );
    int existingIndex = -1;
    for (int i = 0; i < _draftPriceItems.length; i++) {
      final it = _draftPriceItems[i];
      final itKey = (
        '${it['price_list_id']?.toString() ?? ''}|${it['product_id']?.toString() ?? ''}|${it['unit_id']?.toString() ?? 'null'}|${it['currency_id']?.toString() ?? ''}|${it['tier_name']?.toString() ?? ''}|${it['min_qty']?.toString() ?? '0'}'
      );
      if (itKey == key) {
        existingIndex = i;
        break;
      }
    }
    if (existingIndex >= 0) {
      _draftPriceItems[existingIndex] = item;
    } else {
      _draftPriceItems.add(item);
    }
    notifyListeners();
  }

  void removeDraftPriceItem(Map<String, dynamic> item) {
    _draftPriceItems.remove(item);
    notifyListeners();
  }

  /// عنوان پیشنهادی برای کپی کالا (بدون تکرار پسوند «کپی»).
  static String cloneSuggestedDisplayName(String rawName) {
    final t = rawName.trim();
    if (t.isEmpty) return '';
    const suffix = ' (کپی)';
    if (t.endsWith(suffix)) return t;
    return '$t$suffix';
  }

  // Initialize form with existing product data یا حالت کپی از محصول موجود
  Future<void> initializeWithProduct(
    Map<String, dynamic>? product, {
    int? cloneSourceProductId,
  }) async {
    _setLoading(true);
    try {
      // موازی کردن بارگذاری داده‌های مرجع برای بهبود عملکرد
      await Future.wait([
        _loadReferenceData(),
        _loadPriceListsAndCurrencies(),
        _loadWarehouses(),
      ]);

      if (cloneSourceProductId != null) {
        _editingProductId = null;
        final full = await _productService.getProduct(
          businessId: businessId,
          productId: cloneSourceProductId,
        );
        if (full.isEmpty || full['id'] == null) {
          throw Exception('کالای مبدأ یافت نشد یا حذف شده است');
        }
        final parsed = ProductFormData.fromProduct(full);
        _formData = parsed.copyWith(
          autoGenerateCode: true,
          code: null,
          name: cloneSuggestedDisplayName(parsed.name),
          generalBarcodes: null,
        );
        _originalInventoryMode = _formData.inventoryMode ?? 'bulk';
        await _loadExistingPriceItems(productId: cloneSourceProductId);
        await _autoSave.clearFormData(businessId, null);
      } else if (product != null) {
        _editingProductId = product['id'] as int?;
        _formData = ProductFormData.fromProduct(product);
        // ذخیره inventory_mode اولیه برای تشخیص تغییر
        _originalInventoryMode = _formData.inventoryMode ?? 'bulk';
        if (_editingProductId != null) {
          await _loadExistingPriceItems(productId: _editingProductId!);
        }
        // حذف draft ذخیره شده برای این محصول
        await _autoSave.clearFormData(businessId, _editingProductId);
      } else {
        // تلاش برای بارگذاری draft ذخیره شده
        final draftData = await _autoSave.loadFormData(businessId, null);
        if (draftData != null) {
          _formData = draftData;
        } else {
          _formData = ProductFormData(
            baseSalesPrice: 0,
            basePurchasePrice: 0,
            unitConversionFactor: 1,
            autoGenerateCode: true,
          );
        }
        _originalInventoryMode = 'bulk';
      }

      // دیگر واحد اصلی را به‌صورت خودکار مقداردهی نکن؛
      // کاربر می‌تواند عنوان واحد را در فرم وارد کند و در صورت تطبیق با لیست، آیدی ست می‌شود
      
      _clearError();
      notifyListeners();
    } catch (e) {
      _setError(ErrorExtractor.userMessage(e));
    } finally {
      _setLoading(false);
    }
  }

  // Load all reference data (موازی برای بهبود عملکرد)
  Future<void> _loadReferenceData() async {
    try {
      // بارگذاری موازی تمام داده‌های مرجع
      final results = await Future.wait([
        _categoryService.getTree(businessId: businessId).catchError((_) => <Map<String, dynamic>>[]),
        _attributeService.search(businessId: businessId, limit: 100)
            .then((res) => List<Map<String, dynamic>>.from(res['items'] ?? const []))
            .catchError((_) => <Map<String, dynamic>>[]),
        _taxService.getTaxTypes().catchError((_) => <Map<String, dynamic>>[]),
        _taxService.getTaxUnits().catchError((_) => <Map<String, dynamic>>[]),
      ]);
      
      _categories = results[0] as List<Map<String, dynamic>>;
      _attributes = results[1] as List<Map<String, dynamic>>;
      _taxTypes = results[2] as List<Map<String, dynamic>>;
      _taxUnits = results[3] as List<Map<String, dynamic>>;
    } catch (e) {
      throw Exception('خطا در بارگذاری اطلاعات مرجع: $e');
    }
  }

  // Refresh categories (for use after adding/editing/deleting categories)
  Future<void> refreshCategories() async {
    try {
      _categories = await _categoryService.getTree(businessId: businessId);
      notifyListeners();
    } catch (e) {
      // Silently fail - categories will be refreshed on next form load
    }
  }

  Future<void> _loadPriceListsAndCurrencies() async {
    try {
      // بارگذاری موازی price lists و currencies
      final results = await Future.wait([
        _priceListService.listPriceLists(businessId: businessId, page: 1, limit: 100)
            .then((res) => List<Map<String, dynamic>>.from(res['items'] ?? const []))
            .catchError((_) => <Map<String, dynamic>>[]),
        _currencyService.listBusinessCurrencies(businessId: businessId)
            .catchError((_) => <Map<String, dynamic>>[]),
      ]);
      
      _priceLists = results[0] as List<Map<String, dynamic>>;
      _currencies = results[1] as List<Map<String, dynamic>>;
    } catch (e) {
      // ignore; optional reference data
    }
  }

  Future<void> _loadWarehouses() async {
    try {
      final warehouses = await _warehouseService.listWarehouses(businessId: businessId);
      _warehouses = warehouses.map((w) => {
        'id': w.id,
        'code': w.code,
        'name': w.name,
        'is_default': w.isDefault,
      }).toList();
    } catch (_) {
      _warehouses = [];
    }
  }

  Future<void> _loadExistingPriceItems({required int productId}) async {
    _draftPriceItems.clear();
    // Iterate over price lists and collect items for this product
    for (final pl in _priceLists) {
      final plId = (pl['id'] as num?)?.toInt();
      if (plId == null) continue;
      try {
        final items = await _priceListService.listItems(
          businessId: businessId,
          priceListId: plId,
          productId: productId,
        );
        for (final it in items) {
          _draftPriceItems.add(Map<String, dynamic>.from(it));
        }
      } catch (_) {
        // skip this price list on error
      }
    }
  }

  // Update form data
  void updateFormData(ProductFormData newData) {
    _formData = newData;
    _clearError();
    
    // Auto-save (فقط برای فرم جدید)
    if (_autoSaveEnabled && _editingProductId == null) {
      _autoSave.saveFormData(businessId, null, newData);
    }
    
    notifyListeners();
  }

  // Validate form
  bool validateForm(GlobalKey<FormState> formKey) {
    final formState = formKey.currentState;
    if (formState == null) return false;
    
    // اعتبارسنجی فرم Flutter
    final isValid = formState.validate();
    
    // اعتبارسنجی اضافی با ProductFormValidator
    final validationErrors = ProductFormValidator.validateFormData(_formData);
    if (validationErrors.isNotEmpty) {
      // نمایش اولین خطا
      final firstError = validationErrors.values.first;
      _setError(firstError);
      return false;
    }
    
    return isValid;
  }

  // Submit form (create new product only). For editing, call updateProduct.
  Future<bool> submitForm() async {
    if (!_formData.name.trim().isNotEmpty) {
      _setError('نام کالا الزامی است');
      return false;
    }

    _setLoading(true);
    try {
      final payload = _formData.toPayload();
      // Check duplicate code if provided
      if (!_formData.autoGenerateCode) {
        final trimmedCode = _formData.code?.trim();
        if (trimmedCode != null && trimmedCode.isNotEmpty) {
          final exists = await _productService.codeExists(
            businessId: businessId,
            code: trimmedCode,
            excludeProductId: _editingProductId,
          );
          if (exists) {
            _setError('کد کالا/خدمت تکراری است. لطفاً کد دیگری انتخاب کنید.');
            return false;
          }
        }
      }

      // Always create in submitForm; editing handled by updateProduct
      final created = await _productService.createProduct(
        businessId: businessId,
        payload: payload,
        imageBytes: _selectedImageBytes,
        imageFilename: _selectedImageFilename,
      );
      final newId = (created['id'] as num?)?.toInt();
      _lastCreatedProductId = newId;
      if (newId != null) {
        await _saveDraftPriceItems(productId: newId);
      }
      
      // پاک کردن عکس انتخابی بعد از آپلود موفق
      _selectedImageBytes = null;
      _selectedImageFilename = null;
      
      // حذف draft ذخیره شده
      await _autoSave.clearFormData(businessId, null);
      
      _clearError();
      return true;
    } catch (e) {
      _setError(ErrorExtractor.userMessage(e));
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Update existing product
  Future<bool> updateProduct(int productId) async {
    if (!_formData.name.trim().isNotEmpty) {
      _setError('نام کالا الزامی است');
      return false;
    }

    _setLoading(true);
    try {
      // بررسی تغییر از bulk به unique
      final oldMode = _originalInventoryMode ?? 'bulk';
      final newMode = _formData.inventoryMode ?? 'bulk';
      final convertingToUnique = (oldMode != 'unique' && newMode == 'unique');
      
      if (convertingToUnique && _formData.trackInventory) {
        // بررسی موجودی فعلی
        try {
          final stockReport = await _warehouseService.getWarehouseStockReport(
            businessId: businessId,
            productIds: [productId],
          );
          final items = stockReport['items'] as List<dynamic>? ?? [];
          final totalStock = items.fold<int>(0, (sum, item) {
            final qty = (item as Map<String, dynamic>)['quantity'] as num? ?? 0;
            return sum + qty.toInt();
          });
          
          if (totalStock > 0) {
            // موجودی دارد - باید از endpoint تبدیل استفاده شود
            // این خطا را throw می‌کنیم تا در UI نمایش داده شود
            throw Exception('CONVERSION_REQUIRES_INSTANCES:$totalStock');
          }
        } catch (e) {
          if (e.toString().contains('CONVERSION_REQUIRES_INSTANCES')) {
            // این خطا را propagate می‌کنیم
            rethrow;
          }
          // خطاهای دیگر را ignore می‌کنیم و ادامه می‌دهیم
        }
      }
      
      final payload = _formData.toPayload();
      // Pre-check duplicate code before sending
      if (!_formData.autoGenerateCode) {
        final trimmedCode = _formData.code?.trim();
        if (trimmedCode != null && trimmedCode.isNotEmpty) {
          final exists = await _productService.codeExists(
            businessId: businessId,
            code: trimmedCode,
            excludeProductId: productId,
          );
          if (exists) {
            _setError('کد کالا/خدمت تکراری است. لطفاً کد دیگری انتخاب کنید.');
            return false;
          }
        }
      }
      await _productService.updateProduct(
        businessId: businessId,
        productId: productId,
        payload: payload,
        imageBytes: _selectedImageBytes,
        imageFilename: _selectedImageFilename,
      );
      await _saveDraftPriceItems(productId: productId);
      
      // پاک کردن عکس انتخابی بعد از آپلود موفق
      _selectedImageBytes = null;
      _selectedImageFilename = null;
      
      // به‌روزرسانی originalInventoryMode
      _originalInventoryMode = _formData.inventoryMode ?? 'bulk';
      
      // حذف draft ذخیره شده
      await _autoSave.clearFormData(businessId, productId);
      
      _clearError();
      return true;
    } catch (e) {
      _setError(ErrorExtractor.userMessage(e));
      return false;
    } finally {
      _setLoading(false);
    }
  }
  
  // تبدیل کالا از bulk به unique
  Future<bool> convertProductToUnique(int productId) async {
    _setLoading(true);
    try {
      final result = await _warehouseService.convertProductToUnique(
        businessId: businessId,
        productId: productId,
        autoGenerateSerial: true,
        serialPrefix: _formData.code,
        createForExistingStock: true,
        trackSerial: _formData.trackSerial,
        trackBarcode: _formData.trackBarcode,
      );
      
      // به‌روزرسانی formData با مقادیر جدید
      _formData = _formData.copyWith(
        inventoryMode: 'unique',
        trackSerial: result['track_serial'] ?? _formData.trackSerial,
        trackBarcode: result['track_barcode'] ?? _formData.trackBarcode,
      );
      _originalInventoryMode = 'unique';
      
      _clearError();
      notifyListeners();
      return true;
    } catch (e) {
      _setError(ErrorExtractor.userMessage(e));
      return false;
    } finally {
      _setLoading(false);
    }
  }
  
  // بررسی اینکه آیا تبدیل نیاز است یا نه
  bool get needsConversion {
    if (_editingProductId == null) return false;
    final oldMode = _originalInventoryMode ?? 'bulk';
    final newMode = _formData.inventoryMode ?? 'bulk';
    return (oldMode != 'unique' && newMode == 'unique' && _formData.trackInventory);
  }
  
  // دریافت موجودی فعلی (برای نمایش در UI)
  Future<int?> getCurrentStock(int productId) async {
    try {
      final stockReport = await _warehouseService.getWarehouseStockReport(
        businessId: businessId,
        productIds: [productId],
      );
      final items = stockReport['items'] as List<dynamic>? ?? [];
      final totalStock = items.fold<int>(0, (sum, item) {
        final qty = (item as Map<String, dynamic>)['quantity'] as num? ?? 0;
        return sum + qty.toInt();
      });
      return totalStock;
    } catch (_) {
      return null;
    }
  }
  
  
  // مدیریت عکس
  void setProductImage(List<int> imageBytes, String filename) {
    _selectedImageBytes = imageBytes;
    _selectedImageFilename = filename;
    notifyListeners();
  }
  
  void clearProductImage() {
    _selectedImageBytes = null;
    _selectedImageFilename = null;
    _formData = _formData.copyWith(imageFileId: null, imageUrl: null);
    notifyListeners();
  }
  
  bool get hasSelectedImage => _selectedImageBytes != null && _selectedImageBytes!.isNotEmpty;
  List<int>? get selectedImageBytes => _selectedImageBytes;
  String? get selectedImageFilename => _selectedImageFilename;

  Future<void> _saveDraftPriceItems({required int productId}) async {
    // Group by price_list_id and call upsert for each draft row
    for (final it in _draftPriceItems) {
      final plId = (it['price_list_id'] as num?)?.toInt();
      if (plId == null) continue;
      final payload = {
        'product_id': productId,
        'unit_id': it['unit_id'],
        'currency_id': it['currency_id'],
        'tier_name': it['tier_name'],
        'min_qty': it['min_qty'],
        'price': it['price'],
      }..removeWhere((k, v) => v == null);
      try {
        await _priceListService.upsertItem(
          businessId: businessId,
          priceListId: plId,
          payload: payload,
        );
      } catch (_) {
        // keep going for other items; errors can be surfaced later
      }
    }
  }

  // Reset form
  void resetForm() {
    _formData = ProductFormData();
    _clearError();
    // حذف draft ذخیره شده
    _autoSave.clearFormData(businessId, _editingProductId);
    notifyListeners();
  }
  
  // فعال/غیرفعال کردن auto-save
  void setAutoSaveEnabled(bool enabled) {
    _autoSaveEnabled = enabled;
  }
  
  bool get autoSaveEnabled => _autoSaveEnabled;

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }

}
