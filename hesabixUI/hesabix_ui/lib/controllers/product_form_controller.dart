import 'package:flutter/material.dart';
import '../models/product_form_data.dart';
import '../services/product_service.dart';
import '../services/category_service.dart';
import '../services/product_attribute_service.dart';
import '../services/unit_service.dart';
import '../services/tax_service.dart';
import '../core/api_client.dart';

class ProductFormController extends ChangeNotifier {
  final int businessId;
  final ApiClient _apiClient;
  
  late final ProductService _productService;
  late final CategoryService _categoryService;
  late final ProductAttributeService _attributeService;
  late final UnitService _unitService;
  late final TaxService _taxService;

  ProductFormData _formData = ProductFormData();
  bool _isLoading = false;
  String? _errorMessage;
  int? _editingProductId;
  
  // Reference data
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _attributes = [];
  List<Map<String, dynamic>> _units = [];
  List<Map<String, dynamic>> _taxTypes = [];
  List<Map<String, dynamic>> _taxUnits = [];

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
    _unitService = UnitService(apiClient: _apiClient);
    _taxService = TaxService(apiClient: _apiClient);
  }

  // Getters
  ProductFormData get formData => _formData;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<Map<String, dynamic>> get categories => _categories;
  List<Map<String, dynamic>> get attributes => _attributes;
  List<Map<String, dynamic>> get units => _units;
  List<Map<String, dynamic>> get taxTypes => _taxTypes;
  List<Map<String, dynamic>> get taxUnits => _taxUnits;

  // Initialize form with existing product data
  Future<void> initializeWithProduct(Map<String, dynamic>? product) async {
    _setLoading(true);
    try {
      await _loadReferenceData();
      
      if (product != null) {
        _editingProductId = product['id'] as int?;
        _formData = ProductFormData.fromProduct(product);
      } else {
        _formData = ProductFormData(
          baseSalesPrice: 0,
          basePurchasePrice: 0,
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
      // Default main unit id: prefer unit titled "عدد", then first available, else 1
      if (_formData.mainUnitId == null) {
        int? unitId;
        try {
          final numberUnit = _units.firstWhere(
            (e) => ((e['title'] ?? e['name'])?.toString().trim() ?? '') == 'عدد',
          );
          unitId = (numberUnit['id'] as num?)?.toInt();
        } catch (_) {
          // ignore
        }
        unitId ??= _units.isNotEmpty ? (_units.first['id'] as num).toInt() : 1;
        _formData = _formData.copyWith(mainUnitId: unitId);
      }
      
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
      
      // Load units
      try {
        _units = await _unitService.getUnits(businessId: businessId);
      } catch (_) {
        _units = [];
      }
      
      // Load tax types
      try {
        _taxTypes = await _taxService.getTaxTypes(businessId: businessId);
      } catch (_) {
        _taxTypes = [];
      }
      
      // Load tax units
      try {
        _taxUnits = await _taxService.getTaxUnits(businessId: businessId);
      } catch (_) {
        _taxUnits = [];
      }
    } catch (e) {
      throw Exception('خطا در بارگذاری اطلاعات مرجع: $e');
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

  // Submit form
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
      
      // Check if this is an update or create
      final isUpdate = _formData.code != null; // Assuming code indicates existing product
      
      if (isUpdate) {
        // For update, we need the product ID - this should be passed from the calling widget
        throw UnimplementedError('Update functionality needs product ID');
      } else {
        await _productService.createProduct(businessId: businessId, payload: payload);
      }
      
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
      );
      
      _clearError();
      return true;
    } catch (e) {
      _setError('خطا در به‌روزرسانی اطلاعات: $e');
      return false;
    } finally {
      _setLoading(false);
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

  @override
  void dispose() {
    super.dispose();
  }
}
