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

  // Initialize form with existing product data
  Future<void> initializeWithProduct(Map<String, dynamic>? product) async {
    _setLoading(true);
    try {
      await _loadReferenceData();
      await _loadPriceListsAndCurrencies();
      await _loadWarehouses();
      
      if (product != null) {
        _editingProductId = product['id'] as int?;
        _formData = ProductFormData.fromProduct(product);
        if (_editingProductId != null) {
          await _loadExistingPriceItems(productId: _editingProductId!);
        }
      } else {
        _formData = ProductFormData(
          baseSalesPrice: 0,
          basePurchasePrice: 0,
          unitConversionFactor: 1,
        );
        // پیش‌فرض انتخاب اولین نوع مالیات و واحد مالیاتی اگر موجود باشد
        if (_taxTypes.isNotEmpty && _formData.taxTypeId == null) {
          final firstTaxTypeId = (_taxTypes.first['id'] as num?)?.toInt();
          if (firstTaxTypeId != null) {
            _formData = _formData.copyWith(taxTypeId: firstTaxTypeId);
          }
        }
        if (_taxUnits.isNotEmpty && _formData.taxUnitId == null) {
          final firstTaxUnitId = (_taxUnits.first['id'] as num?)?.toInt();
          if (firstTaxUnitId != null) {
            _formData = _formData.copyWith(taxUnitId: firstTaxUnitId);
          }
        }
      }
      // دیگر واحد اصلی را به‌صورت خودکار مقداردهی نکن؛
      // کاربر می‌تواند عنوان واحد را در فرم وارد کند و در صورت تطبیق با لیست، آیدی ست می‌شود
      
      _clearError();
      notifyListeners();
    } catch (e) {
      _setError('خطا در بارگذاری اطلاعات: $e');
    } finally {
      _setLoading(false);
    }
  }

  // Load all reference data
  Future<void> _loadReferenceData() async {
    try {
      // Load categories
      _categories = await _categoryService.getTree(businessId: businessId);
      
      // Load attributes
      try {
        final attrsRes = await _attributeService.search(businessId: businessId, limit: 100);
        final items = List<Map<String, dynamic>>.from(attrsRes['items'] ?? const []);
        _attributes = items;
      } catch (_) {
        _attributes = [];
      }
      
      
      // Load tax types
      try {
        _taxTypes = await _taxService.getTaxTypes();
      } catch (_) {
        _taxTypes = [];
      }
      
      // Load tax units
      try {
        _taxUnits = await _taxService.getTaxUnits();
      } catch (_) {
        _taxUnits = [];
      }
    } catch (e) {
      throw Exception('خطا در بارگذاری اطلاعات مرجع: $e');
    }
  }

  Future<void> _loadPriceListsAndCurrencies() async {
    try {
      // Price lists (first page only for selection)
      try {
        final res = await _priceListService.listPriceLists(businessId: businessId, page: 1, limit: 100);
        _priceLists = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      } catch (_) {
        _priceLists = [];
      }
      // Currencies: load only business default + active currencies
      try {
        _currencies = await _currencyService.listBusinessCurrencies(businessId: businessId);
      } catch (_) {
        _currencies = [];
      }
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
    notifyListeners();
  }

  // Validate form
  bool validateForm(GlobalKey<FormState> formKey) {
    return formKey.currentState?.validate() ?? false;
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
      
      // Always create in submitForm; editing handled by updateProduct
      final created = await _productService.createProduct(
        businessId: businessId,
        payload: payload,
        imageBytes: _selectedImageBytes,
        imageFilename: _selectedImageFilename,
      );
      final newId = (created['id'] as num?)?.toInt();
      if (newId != null) {
        await _saveDraftPriceItems(productId: newId);
      }
      
      // پاک کردن عکس انتخابی بعد از آپلود موفق
      _selectedImageBytes = null;
      _selectedImageFilename = null;
      
      _clearError();
      return true;
    } catch (e) {
      _setError('خطا در ذخیره اطلاعات: $e');
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
      final payload = _formData.toPayload();
      // Pre-check duplicate code before sending
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
      
      _clearError();
      return true;
    } catch (e) {
      _setError('خطا در به‌روزرسانی اطلاعات: $e');
      return false;
    } finally {
      _setLoading(false);
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
    notifyListeners();
  }

  // Save form data to local storage (for auto-save)
  void saveToLocalStorage() {
    // Implementation for local storage persistence
    // This could use SharedPreferences or similar
  }

  // Load form data from local storage
  void loadFromLocalStorage() {
    // Implementation for loading from local storage
  }

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
