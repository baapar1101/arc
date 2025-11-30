import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../services/quick_sales_service.dart';
import '../../services/invoice_service.dart';
import '../../services/product_service.dart';
import '../../services/warehouse_service.dart';
import '../../services/price_list_service.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/web/web_utils.dart' as web_utils;
import '../../utils/number_normalizer.dart' as number_utils;
import '../../utils/number_formatters.dart';
import '../../models/invoice_line_item.dart';
import '../../models/invoice_transaction.dart';
import '../../widgets/invoice/product_combobox_widget.dart';
import '../../widgets/invoice/customer_combobox_widget.dart';
import '../../widgets/invoice/cash_register_combobox_widget.dart';
import '../../widgets/product/product_form_dialog.dart';
import '../../models/customer_model.dart';
import '../../models/cash_register.dart';
import 'package:go_router/go_router.dart';

class QuickSalesPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const QuickSalesPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<QuickSalesPage> createState() => _QuickSalesPageState();
}

class _QuickSalesPageState extends State<QuickSalesPage> {
  final QuickSalesService _quickSalesService = QuickSalesService();
  final InvoiceService _invoiceService = InvoiceService();
  final ProductService _productService = ProductService();
  final WarehouseService _warehouseService = WarehouseService();
  final PriceListService _priceListService = PriceListService(apiClient: ApiClient());
  
  bool _loading = true;
  bool _saving = false;
  Map<String, dynamic>? _settings;
  Customer? _anonymousCustomer;
  
  // سبد خرید
  List<InvoiceLineItem> _cartItems = [];
  
  // موجودی محصولات (productId -> stock)
  Map<int, num> _productStocks = {};
  bool _loadingStocks = false;
  
  // تاریخچه محصولات اخیر
  List<Map<String, dynamic>> _recentProducts = [];
  static const String _recentProductsKey = 'quick_sales_recent_products';
  static const int _maxRecentProducts = 10;
  
  // مشتری
  Customer? _selectedCustomer;
  
  // پرداخت
  InvoiceTransaction? _payment;
  String? _selectedCashRegisterId;
  
  // تنظیمات
  int? _defaultWarehouseId;
  int? _defaultCurrencyId;
  int? _defaultPriceListId;
  bool _autoPrint = false;
  bool _autoPostWarehouse = true;
  bool _showInventory = true;
  bool _showPurchasePrice = false;
  int? _printTemplateId;
  
  // جستجوی محصول
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocus = FocusNode();
  final FocusNode _keyboardListenerFocus = FocusNode();
  Timer? _searchDebounce;
  String? _lastFailedSearchQuery; // آخرین جستجوی ناموفق برای نمایش دکمه افزودن کالا

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadRecentProducts();
    // فوکوس خودکار روی فیلد بارکد
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _barcodeFocus.requestFocus();
      _keyboardListenerFocus.requestFocus();
    });
  }
  
  Future<void> _loadRecentProducts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${_recentProductsKey}_${widget.businessId}';
      final jsonString = prefs.getString(key);
      if (jsonString != null) {
        final List<dynamic> decoded = jsonDecode(jsonString);
        if (mounted) {
          setState(() {
            _recentProducts = decoded
                .map((e) => Map<String, dynamic>.from(e))
                .take(_maxRecentProducts)
                .toList();
          });
        }
      }
    } catch (e) {
      // خطا در خواندن تاریخچه، ادامه می‌دهیم
    }
  }
  
  Future<void> _saveRecentProduct(Map<String, dynamic> product) async {
    try {
      final productId = (product['id'] as num?)?.toInt();
      if (productId == null) return;
      
      // حذف محصول اگر قبلاً وجود داشته
      _recentProducts.removeWhere((p) => (p['id'] as num?)?.toInt() == productId);
      
      // اضافه کردن به ابتدا
      _recentProducts.insert(0, {
        'id': productId,
        'code': product['code']?.toString(),
        'name': product['name']?.toString(),
        'sales_price': _toNum(product['base_sales_price'] ?? product['sales_price']),
        'tax_rate': _toNum(product['sales_tax_rate'] ?? product['tax_rate']),
        'track_inventory': product['track_inventory'] ?? false,
        'added_at': DateTime.now().millisecondsSinceEpoch,
      });
      
      // محدود کردن به حداکثر تعداد
      if (_recentProducts.length > _maxRecentProducts) {
        _recentProducts = _recentProducts.take(_maxRecentProducts).toList();
      }
      
      // ذخیره در SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final key = '${_recentProductsKey}_${widget.businessId}';
      await prefs.setString(key, jsonEncode(_recentProducts));
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      // خطا در ذخیره، ادامه می‌دهیم
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _barcodeController.dispose();
    _barcodeFocus.dispose();
    _keyboardListenerFocus.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
    });
    try {
      final settings = await _quickSalesService.getSettings(businessId: widget.businessId);
      final customer = await _quickSalesService.getAnonymousCustomer(businessId: widget.businessId);
      
      final previousShowInventory = _showInventory;
      
      setState(() {
        _settings = settings;
        _anonymousCustomer = Customer(
          id: customer['id'] as int,
          name: customer['name'] as String,
        );
        _selectedCustomer = _anonymousCustomer;
        _defaultWarehouseId = settings['default_warehouse_id'];
        // اگر ارز پیش‌فرض در تنظیمات فروش سریع تنظیم نشده باشد، از ارز پیش‌فرض کسب‌وکار استفاده می‌کنیم
        _defaultCurrencyId = settings['default_currency_id'] ?? widget.authStore.currentBusiness?.defaultCurrency?.id;
        _defaultPriceListId = settings['default_price_list_id'];
        _selectedCashRegisterId = settings['default_cash_register_id']?.toString();
        _autoPrint = settings['auto_print'] ?? false;
        _autoPostWarehouse = settings['auto_post_warehouse'] ?? true;
        _showInventory = settings['show_inventory'] ?? true;
        _showPurchasePrice = settings['show_purchase_price'] ?? false;
        _printTemplateId = settings['print_template_id'];
      });
      
      // اگر نمایش موجودی فعال شد و قبلاً غیرفعال بود، موجودی‌ها را بارگذاری کن
      if (_showInventory && !previousShowInventory && _cartItems.isNotEmpty) {
        _refreshAllStocks();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: 'خطا در بارگذاری تنظیمات: $e', isError: true);
      }
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _searchByBarcode(String code) async {
    if (code.trim().isEmpty) return;
    
    try {
      // جستجو در کالاهای یونیک
      final instanceData = await _warehouseService.searchInstanceByCode(
        businessId: widget.businessId,
        code: code.trim(),
      );
      
      // بررسی اینکه آیا چند نتیجه برگردانده شده یا نه
      final multipleResults = instanceData['multiple_results'] == true;
      final items = instanceData['items'] as List?;
      
      if (multipleResults && items != null && items.isNotEmpty) {
        // اگر چند نتیجه پیدا شد، دیالوگ انتخاب نمایش بده
        if (!mounted) return;
        final selected = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (context) => _InstanceSelectionDialog(
            instances: items,
            searchCode: code.trim(),
          ),
        );
        
        if (selected != null) {
          final productId = selected['product_id'] as int?;
          if (productId != null) {
            final product = await _productService.getProduct(
              businessId: widget.businessId,
              productId: productId,
            );
            final instanceId = (selected['id'] as num?)?.toInt();
            await _addToCart(product, instanceId: instanceId);
            await _saveRecentProduct(product);
            _barcodeController.clear();
            _barcodeFocus.requestFocus();
            // پاک کردن جستجوی ناموفق قبلی
            if (mounted) {
              setState(() {
                _lastFailedSearchQuery = null;
              });
            }
            if (mounted) {
              SnackBarHelper.show(
                context,
                message: '${product['name'] ?? 'محصول'} به سبد اضافه شد',
              );
            }
            return;
          }
        }
        // اگر دیالوگ انتخاب بسته شد بدون انتخاب، جستجوی ناموفق را ثبت کن
        if (mounted) {
          setState(() {
            _lastFailedSearchQuery = code.trim();
          });
        }
        return;
      }
      
      // اگر یک نتیجه یا نتیجه مستقیم برگردانده شد
      final productId = instanceData['product_id'] as int?;
      if (productId != null) {
        // دریافت اطلاعات محصول
        final product = await _productService.getProduct(
          businessId: widget.businessId,
          productId: productId,
        );
        
        // افزودن به سبد
        final instanceId = (instanceData['id'] as num?)?.toInt();
        await _addToCart(product, instanceId: instanceId);
        await _saveRecentProduct(product);
        _barcodeController.clear();
        _barcodeFocus.requestFocus();
        // پاک کردن جستجوی ناموفق قبلی
        if (mounted) {
          setState(() {
            _lastFailedSearchQuery = null;
          });
        }
        // فیدبک بصری
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: '${product['name'] ?? 'محصول'} به سبد اضافه شد',
          );
        }
        return;
      }
    } catch (e) {
      // اگر کالای یونیک پیدا نشد، در محصولات عادی جستجو می‌کنیم
    }
    
      // جستجو در محصولات عادی (از طریق کد، بارکد یا نام)
    try {
      final products = await _productService.searchProducts(
        businessId: widget.businessId,
        searchQuery: code.trim(),
        limit: 1,
        searchFields: const ['code', 'barcode', 'name'],
      );
      
      if (products.isNotEmpty) {
        final product = products.first;
        await _addToCart(product);
        await _saveRecentProduct(product);
        _barcodeController.clear();
        _barcodeFocus.requestFocus();
        // پاک کردن جستجوی ناموفق قبلی
        if (mounted) {
          setState(() {
            _lastFailedSearchQuery = null;
          });
        }
        // فیدبک بصری
        if (mounted) {
          SnackBarHelper.show(
            context,
            message: '${product['name'] ?? 'محصول'} به سبد اضافه شد',
          );
        }
      } else {
        if (mounted) {
          setState(() {
            _lastFailedSearchQuery = code.trim();
          });
          SnackBarHelper.show(context, message: 'محصولی یافت نشد', isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: 'خطا در جستجو: $e', isError: true);
      }
    }
  }

  /// باز کردن دیالوگ افزودن کالا با نام پیش‌فرض و افزودن به سبد بعد از ثبت
  Future<void> _openAddProductDialog(String productName) async {
    if (productName.trim().isEmpty) return;
    
    try {
      // باز کردن دیالوگ با نام پیش‌فرض
      final result = await showDialog<dynamic>(
        context: context,
        builder: (context) => ProductFormDialog(
          businessId: widget.businessId,
          authStore: widget.authStore,
          product: {'name': productName.trim()}, // پاس دادن نام به عنوان product برای پیش‌پردازش
          onSuccess: () {},
        ),
      );
      
      if (!mounted) return;
      
      // اگر کالا با موفقیت ثبت شد
      if (result != null && result != false) {
        int? newProductId;
        
        // استخراج product_id از نتیجه
        if (result is int) {
          newProductId = result;
        } else if (result is Map) {
          newProductId = result['id'] as int?;
        }
        
        // اگر product_id را داریم، کالا را دریافت و به سبد اضافه کن
        if (newProductId != null) {
          try {
            final product = await _productService.getProduct(
              businessId: widget.businessId,
              productId: newProductId,
            );
            
            await _addToCart(product);
            await _saveRecentProduct(product);
            
            // پاک کردن جستجوی ناموفق و فیلد جستجو
            setState(() {
              _lastFailedSearchQuery = null;
            });
            _barcodeController.clear();
            _barcodeFocus.requestFocus();
            
            SnackBarHelper.show(
              context,
              message: '${product['name'] ?? 'محصول'} با موفقیت اضافه شد و به سبد خرید اضافه گردید',
            );
          } catch (e) {
            SnackBarHelper.show(
              context,
              message: 'کالا ثبت شد اما خطا در افزودن به سبد: $e',
              isError: true,
            );
          }
        } else {
          // اگر product_id را نداریم، فقط پیام موفقیت نمایش بده
          setState(() {
            _lastFailedSearchQuery = null;
          });
          _barcodeController.clear();
          _barcodeFocus.requestFocus();
          SnackBarHelper.show(
            context,
            message: 'کالا با موفقیت ثبت شد',
          );
        }
      } else {
        // اگر دیالوگ بسته شد بدون ثبت، جستجوی ناموفق را نگه دار
        // تا کاربر بتواند دوباره روی دکمه + کلیک کند
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: 'خطا در باز کردن دیالوگ افزودن کالا: $e',
          isError: true,
        );
      }
    }
  }

  /// تبدیل مقدار به num (پشتیبانی از String و num)
  num _toNum(dynamic value, {num defaultValue = 0.0}) {
    if (value == null) return defaultValue;
    if (value is num) return value;
    if (value is String) {
      return num.tryParse(value) ?? defaultValue;
    }
    return num.tryParse(value.toString()) ?? defaultValue;
  }

  Future<num> _getPriceFromPriceList(int productId) async {
    // اگر لیست قیمت پیش‌فرض وجود ندارد یا ارز مشخص نشده، null برگردان
    if (_defaultPriceListId == null || _defaultCurrencyId == null) {
      return 0;
    }
    
    try {
      final items = await _priceListService.listItems(
        businessId: widget.businessId,
        priceListId: _defaultPriceListId!,
        productId: productId,
        currencyId: _defaultCurrencyId,
      );
      
      // جستجوی قیمت برای واحد اصلی (unit_id == null)
      for (final item in items) {
        final unitId = item['unit_id'] as int?;
        final priceValue = item['price'];
        num? price;
        
        // تبدیل قیمت به num
        if (priceValue == null) {
          price = null;
        } else if (priceValue is num) {
          price = priceValue;
        } else if (priceValue is String) {
          price = num.tryParse(priceValue);
        } else {
          price = num.tryParse(priceValue.toString());
        }
        
        // اگر unit_id null باشد، یعنی قیمت برای واحد اصلی است
        if (unitId == null && price != null && price > 0) {
          return price;
        }
      }
    } catch (e) {
      // در صورت خطا، 0 برگردان تا از قیمت پایه استفاده شود
      debugPrint('خطا در دریافت قیمت از لیست قیمت: $e');
    }
    
    return 0;
  }

  Future<void> _addToCart(Map<String, dynamic> product, {int? instanceId}) async {
    final productId = (product['id'] as num?)?.toInt();
    if (productId == null) return;
    
    final trackInventory = product['track_inventory'] == true;
    
    // بررسی اینکه آیا محصول در سبد وجود دارد (فقط برای محصولات غیر یونیک)
    if (instanceId == null) {
      final existingIndex = _cartItems.indexWhere(
        (item) => item.productId == productId && item.extraInfo?['instance_id'] == null,
      );
      
      if (existingIndex != -1) {
        // افزایش تعداد محصول موجود
        setState(() {
          final existingItem = _cartItems[existingIndex];
          _cartItems[existingIndex] = existingItem.copyWith(
            quantity: existingItem.quantity + 1,
          );
        });
        // بارگذاری موجودی اگر لازم باشد و نمایش موجودی فعال باشد
        if (trackInventory && _showInventory) {
          _loadProductStock(productId);
        }
        return;
      }
    }
    
    // تلاش برای دریافت قیمت از لیست قیمت
    num unitPrice = 0.0;
    String unitPriceSource = 'base';
    
    if (_defaultPriceListId != null && _defaultCurrencyId != null) {
      final priceFromList = await _getPriceFromPriceList(productId);
      if (priceFromList > 0) {
        unitPrice = priceFromList;
        unitPriceSource = 'priceList';
      }
    }
    
    // اگر قیمت از لیست قیمت پیدا نشد یا صفر بود، از قیمت پایه استفاده کن
    if (unitPrice == 0) {
      unitPrice = _toNum(product['base_sales_price'] ?? product['sales_price']);
      unitPriceSource = 'base';
    }
    
    final lineItem = InvoiceLineItem(
      productId: productId,
      productCode: product['code']?.toString(),
      productName: product['name']?.toString(),
      quantity: instanceId != null ? 1 : 1, // برای کالاهای یونیک همیشه 1
      unitPrice: unitPrice,
      unitPriceSource: unitPriceSource,
      discountType: 'amount',
      discountValue: 0,
      taxRate: _toNum(product['sales_tax_rate'] ?? product['tax_rate']),
      trackInventory: trackInventory,
      warehouseId: _defaultWarehouseId,
      basePurchasePriceMainUnit: _toNum(product['base_purchase_price']),
      extraInfo: instanceId != null ? {'instance_id': instanceId} : null,
    );
    
    setState(() {
      _cartItems.add(lineItem);
    });
    
    // بارگذاری موجودی اگر لازم باشد و نمایش موجودی فعال باشد
    if (trackInventory && instanceId == null && _showInventory) {
      _loadProductStock(productId);
    }
  }
  
  Future<void> _loadProductStock(int productId) async {
    // اگر نمایش موجودی غیرفعال باشد، موجودی را بارگذاری نکن
    if (!_showInventory) {
      return;
    }
    
    // جلوگیری از درخواست‌های تکراری
    if (_productStocks.containsKey(productId) || _loadingStocks) {
      return;
    }
    
    if (_defaultWarehouseId == null) {
      return; // بدون انبار، موجودی قابل محاسبه نیست
    }
    
    setState(() {
      _loadingStocks = true;
    });
    
    try {
      final stockReport = await _warehouseService.getStockReport(
        businessId: widget.businessId,
        query: {
          'product_ids': [productId],
          'warehouse_ids': [_defaultWarehouseId],
          'as_of_date': DateTime.now().toIso8601String().split('T')[0],
          'include_zero': true,
        },
      );
      
      final items = List<dynamic>.from(stockReport['items'] ?? []);
      if (items.isNotEmpty) {
        final stock = (items.first['quantity'] as num?) ?? 0;
        if (mounted) {
          setState(() {
            _productStocks[productId] = stock;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _productStocks[productId] = 0;
          });
        }
      }
    } catch (e) {
      // در صورت خطا، موجودی را null نگه دار (نمایش داده نمی‌شود)
    } finally {
      if (mounted) {
        setState(() {
          _loadingStocks = false;
        });
      }
    }
  }
  
  Future<void> _refreshAllStocks() async {
    // اگر نمایش موجودی غیرفعال باشد، موجودی را به‌روزرسانی نکن
    if (!_showInventory) {
      return;
    }
    
    final trackInventoryProductIds = _cartItems
        .where((item) => item.trackInventory && item.productId != null && item.extraInfo?['instance_id'] == null)
        .map((item) => item.productId!)
        .toSet()
        .toList();
    
    if (trackInventoryProductIds.isEmpty || _defaultWarehouseId == null) {
      return;
    }
    
    setState(() {
      _loadingStocks = true;
    });
    
    try {
      final stockReport = await _warehouseService.getStockReport(
        businessId: widget.businessId,
        query: {
          'product_ids': trackInventoryProductIds,
          'warehouse_ids': [_defaultWarehouseId],
          'as_of_date': DateTime.now().toIso8601String().split('T')[0],
          'include_zero': true,
        },
      );
      
      final items = List<dynamic>.from(stockReport['items'] ?? []);
      final stocksMap = <int, num>{};
      
      for (final item in items) {
        final pid = (item['product_id'] as num?)?.toInt();
        if (pid != null) {
          stocksMap[pid] = (item['quantity'] as num?) ?? 0;
        }
      }
      
      if (mounted) {
        setState(() {
          _productStocks = stocksMap;
        });
      }
    } catch (e) {
      // در صورت خطا، موجودی‌های قبلی باقی می‌مانند
    } finally {
      if (mounted) {
        setState(() {
          _loadingStocks = false;
        });
      }
    }
  }
  
  num? _getProductStock(int? productId) {
    if (productId == null) return null;
    return _productStocks[productId];
  }
  
  bool _hasInsufficientStock(InvoiceLineItem item) {
    if (!item.trackInventory || item.productId == null || item.extraInfo?['instance_id'] != null) {
      return false; // کالاهای یونیک یا بدون کنترل موجودی
    }
    final stock = _getProductStock(item.productId);
    if (stock == null) return false; // موجودی هنوز لود نشده
    return stock < item.quantity;
  }

  void _removeFromCart(int index) {
    setState(() {
      final item = _cartItems[index];
      _cartItems.removeAt(index);
      
      // اگر آخرین مورد از این محصول حذف شد، موجودی را هم حذف کن
      final hasMoreOfProduct = _cartItems.any(
        (cartItem) => cartItem.productId == item.productId && 
                     cartItem.extraInfo?['instance_id'] == null,
      );
      if (!hasMoreOfProduct && item.productId != null) {
        _productStocks.remove(item.productId);
      }
    });
  }
  
  Future<void> _clearCart() async {
    if (_cartItems.isEmpty) return;
    
    // نمایش دیالوگ تأیید
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('پاک کردن سبد'),
        content: Text('آیا مطمئن هستید که می‌خواهید همه ${_cartItems.length} محصول را از سبد حذف کنید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('انصراف'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('پاک کردن'),
          ),
        ],
      ),
    );
    
    if (confirmed == true && mounted) {
      setState(() {
        _cartItems.clear();
        _productStocks.clear();
        _payment = null;
      });
      _barcodeFocus.requestFocus();
      SnackBarHelper.show(context, message: 'سبد خرید پاک شد');
    }
  }

  void _updateCartItem(int index, InvoiceLineItem item) {
    setState(() {
      _cartItems[index] = item;
    });
    
    // به‌روزرسانی موجودی در صورت تغییر تعداد (اگر نمایش موجودی فعال باشد)
    if (item.trackInventory && item.productId != null && item.extraInfo?['instance_id'] == null && _showInventory) {
      _loadProductStock(item.productId!);
    }
  }

  num get _subtotalAmount {
    return _cartItems.fold<num>(0, (sum, item) => sum + item.subtotal);
  }

  num get _totalDiscount {
    return _cartItems.fold<num>(0, (sum, item) => sum + item.discountAmount);
  }

  num get _totalTax {
    return _cartItems.fold<num>(0, (sum, item) => sum + item.taxAmount);
  }

  num get _totalAmount {
    return _cartItems.fold<num>(0, (sum, item) => sum + item.total);
  }

  Future<void> _saveInvoice({bool print = false}) async {
    // اعتبارسنجی سبد خرید
    if (_cartItems.isEmpty) {
      SnackBarHelper.show(context, message: 'سبد خرید خالی است', isError: true);
      return;
    }
    
    // اعتبارسنجی ارز
    if (_defaultCurrencyId == null) {
      SnackBarHelper.show(context, message: 'ارز پیش‌فرض تنظیم نشده است. لطفاً در تنظیمات فاکتور سریع تنظیم کنید.', isError: true);
      return;
    }
    
    // اعتبارسنجی صندوق (برای پرداخت)
    if (_payment != null && _selectedCashRegisterId == null) {
      SnackBarHelper.show(context, message: 'لطفاً صندوق را انتخاب کنید', isError: true);
      return;
    }
    
    // اعتبارسنجی مبلغ پرداخت
    if (_payment != null && _payment!.amount != _totalAmount) {
      SnackBarHelper.show(
        context, 
        message: 'مبلغ پرداخت (${_formatNumber(_payment!.amount)}) باید برابر با مبلغ فاکتور (${_formatNumber(_totalAmount)}) باشد',
        isError: true,
      );
      return;
    }
    
    setState(() {
      _saving = true;
    });
    
    try {
      // ساخت payload
      final lines = _cartItems.map((item) {
        // محاسبه مقادیر
        final lineDiscount = item.discountAmount;
        final taxAmount = item.taxAmount;
        final lineTotal = item.total;
        
        // ساختن extra_info با تمام اطلاعات قیمت (مثل new_invoice_page)
        final extraInfoMap = <String, dynamic>{
          'unit_price': item.unitPrice,
          'line_discount': lineDiscount,
          'tax_amount': taxAmount,
          'line_total': lineTotal,
          'unit_price_source': item.unitPriceSource,
          'discount_type': item.discountType,
          'discount_value': item.discountValue,
          'tax_rate': item.taxRate,
          if (item.warehouseId != null) 'warehouse_id': item.warehouseId,
          if (item.extraInfo != null) ...item.extraInfo!,
        };
        
        final lineData = <String, dynamic>{
          'product_id': item.productId,
          'quantity': item.quantity,
          'unit_price': item.unitPrice, // برای سازگاری با API قدیمی
          'tax_rate': item.taxRate,
          'discount_type': item.discountType,
          'discount_value': item.discountValue,
          if (item.description != null) 'description': item.description,
          'extra_info': extraInfoMap,
        };
        return lineData;
      }).toList();
      
      final payments = <Map<String, dynamic>>[];
      if (_payment != null && _selectedCashRegisterId != null) {
        payments.add({
          'transaction_type': 'cash_register',
          'cash_register_id': int.tryParse(_selectedCashRegisterId!),
          'amount': _payment!.amount,
          'transaction_date': _payment!.transactionDate.toIso8601String(),
        });
      }
      
      // تعیین person_id: اگر مشتری انتخاب شده باشد از آن استفاده می‌کنیم، وگرنه از مشتری ناشناس
      int? personId;
      if (_selectedCustomer != null && _selectedCustomer != _anonymousCustomer) {
        personId = _selectedCustomer!.id;
      } else if (_anonymousCustomer != null) {
        personId = _anonymousCustomer!.id;
      } else if (_selectedCustomer != null) {
        // fallback: اگر مشتری ناشناس null باشد اما مشتری انتخاب شده باشد
        personId = _selectedCustomer!.id;
      }
      
      if (personId == null) {
        SnackBarHelper.show(
          context,
          message: 'خطا: مشتری ناشناس تنظیم نشده است. لطفاً در تنظیمات فروش سریع یک مشتری پیش‌فرض انتخاب کنید.',
          isError: true,
        );
        setState(() {
          _saving = false;
        });
        return;
      }
      
      // دریافت تنظیمات auto_create_payment_document
      final autoCreatePaymentDoc = _settings?['auto_create_payment_document'] ?? true;
      
      // ساخت extra_info با person_id
      final extraInfo = <String, dynamic>{
        'quick_sale': true,
        'person_id': personId, // همیشه person_id را اضافه می‌کنیم
        'post_inventory': true,
        'auto_post_warehouse': _autoPostWarehouse,
        'auto_create_payment_document': autoCreatePaymentDoc,
      };
      
      if (_defaultWarehouseId != null) {
        extraInfo['warehouse_id'] = _defaultWarehouseId;
      }
      
      final payload = <String, dynamic>{
        'invoice_type': 'invoice_sales',
        'document_date': DateTime.now().toIso8601String().split('T')[0],
        'currency_id': _defaultCurrencyId,
        'is_proforma': false,
        'extra_info': extraInfo,
        'lines': lines,
        if (payments.isNotEmpty) 'payments': payments,
      };
      
      final result = await _invoiceService.createInvoice(
        businessId: widget.businessId,
        payload: payload,
      );
      
      if (!mounted) return;
      
      // استخراج invoice_id و invoice_code
      final invoiceId = (result['id'] as num?)?.toInt();
      final invoiceCode = result['code']?.toString();
      
      // چاپ در صورت نیاز
      if (print || _autoPrint) {
        if (invoiceId != null) {
          await _printInvoice(invoiceId: invoiceId, invoiceCode: invoiceCode);
        } else {
          SnackBarHelper.show(
            context, 
            message: 'فاکتور ثبت شد اما شناسه فاکتور برای چاپ در دسترس نیست',
            isError: true,
          );
        }
      }
      
      // پاک کردن سبد و موجودی‌ها
      setState(() {
        _cartItems.clear();
        _payment = null;
        _productStocks.clear();
      });
      
      _barcodeFocus.requestFocus();
      
      SnackBarHelper.show(context, message: 'فاکتور با موفقیت ثبت شد${invoiceCode != null ? ' (${invoiceCode})' : ''}');
      
      // به‌روزرسانی موجودی بعد از ثبت موفق (برای دفعه بعد)
      if (_defaultWarehouseId != null) {
        _refreshAllStocks();
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'خطا در ثبت فاکتور';
        if (e.toString().contains('INSUFFICIENT_STOCK')) {
          errorMessage = 'موجودی کافی برای برخی محصولات وجود ندارد';
        } else if (e.toString().contains('CURRENCY')) {
          errorMessage = 'خطا در تنظیمات ارز';
        } else {
          errorMessage = 'خطا در ثبت فاکتور: ${e.toString().replaceAll('Exception: ', '')}';
        }
        SnackBarHelper.show(context, message: errorMessage, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }
  
  Future<void> _printInvoice({required int invoiceId, String? invoiceCode}) async {
    try {
      // استفاده از قالب چاپ پیش‌فرض اگر تنظیم شده باشد
      final query = <String, dynamic>{};
      if (_printTemplateId != null) {
        query['template_id'] = _printTemplateId;
      }
      
      final bytes = await _invoiceService.downloadInvoicePdf(
        businessId: widget.businessId,
        invoiceId: invoiceId,
        query: query.isNotEmpty ? query : null,
      );
      
      if (!mounted) return;
      
      if (kIsWeb) {
        final filename = invoiceCode ?? 'invoice_$invoiceId';
        final safeName = filename.trim().isEmpty ? 'invoice.pdf' : filename;
        final finalName = safeName.toLowerCase().endsWith('.pdf') ? safeName : '$safeName.pdf';
        
        await web_utils.saveBytesAsFileWeb(
          bytes,
          finalName,
          mimeType: 'application/pdf',
        );
        
        SnackBarHelper.show(context, message: 'فایل PDF فاکتور دانلود شد');
      } else {
        SnackBarHelper.show(
          context, 
          message: 'چاپ فاکتور فعلاً فقط در نسخه وب در دسترس است',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context, 
          message: 'خطا در چاپ فاکتور: ${e.toString().replaceAll('Exception: ', '')}',
          isError: true,
        );
      }
    }
  }

  Future<void> _editCartItem(int index) async {
    final item = _cartItems[index];
    final result = await showDialog<InvoiceLineItem>(
      context: context,
      builder: (context) => _CartItemEditDialog(
        item: item,
      ),
    );
    
    if (result != null) {
      _updateCartItem(index, result);
    }
  }

  void _increaseQuantity(int index) {
    setState(() {
      final item = _cartItems[index];
      
      // بررسی موجودی قبل از افزایش
      if (item.trackInventory && item.productId != null && item.extraInfo?['instance_id'] == null) {
        final stock = _getProductStock(item.productId);
        if (stock != null && stock <= item.quantity) {
          SnackBarHelper.show(
            context,
            message: 'موجودی کافی نیست. موجودی: ${_formatNumber(stock)}',
            isError: true,
          );
          return;
        }
      }
      
      _cartItems[index] = item.copyWith(quantity: item.quantity + 1);
    });
  }

  void _decreaseQuantity(int index) {
    setState(() {
      final item = _cartItems[index];
      if (item.quantity > 1) {
        _cartItems[index] = item.copyWith(quantity: item.quantity - 1);
      }
    });
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final isControlPressed = HardwareKeyboard.instance.isControlPressed;
      final isMetaPressed = HardwareKeyboard.instance.isMetaPressed;
      
      // Enter: ثبت فاکتور
      if (event.logicalKey == LogicalKeyboardKey.enter &&
          !isControlPressed &&
          !isMetaPressed) {
        if (!_saving && _cartItems.isNotEmpty) {
          _saveInvoice(print: false);
          return true;
        }
      }
      
      // Ctrl/Cmd + P: ثبت و چاپ
      if ((isControlPressed || isMetaPressed) &&
          event.logicalKey == LogicalKeyboardKey.keyP) {
        if (!_saving && _cartItems.isNotEmpty) {
          _saveInvoice(print: true);
          return true;
        }
      }
      
      // +: افزایش تعداد آخرین محصول
      if (event.logicalKey == LogicalKeyboardKey.equal ||
          event.logicalKey == LogicalKeyboardKey.numpadAdd) {
        if (_cartItems.isNotEmpty) {
          _increaseQuantity(_cartItems.length - 1);
          return true;
        }
      }
      
      // -: کاهش تعداد آخرین محصول
      if (event.logicalKey == LogicalKeyboardKey.minus ||
          event.logicalKey == LogicalKeyboardKey.numpadSubtract) {
        if (_cartItems.isNotEmpty) {
          _decreaseQuantity(_cartItems.length - 1);
          return true;
        }
      }
      
      // Delete: حذف آخرین محصول
      if (event.logicalKey == LogicalKeyboardKey.delete ||
          event.logicalKey == LogicalKeyboardKey.backspace) {
        if (_cartItems.isNotEmpty && _barcodeFocus.hasFocus) {
          _removeFromCart(_cartItems.length - 1);
          return true;
        }
      }
      
      // Ctrl/Cmd + K: پاک کردن همه سبد
      if ((isControlPressed || isMetaPressed) &&
          event.logicalKey == LogicalKeyboardKey.keyK) {
        _clearCart();
        return true;
      }
      
      // Escape: پاک کردن فیلد جستجو
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_barcodeFocus.hasFocus && _barcodeController.text.isNotEmpty) {
          _barcodeController.clear();
          return true;
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('فروش سریع')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    
    return KeyboardListener(
      focusNode: _keyboardListenerFocus,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('فروش سریع'),
            if (_cartItems.isNotEmpty) ...[
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_cartItems.length} قلم',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatNumber(_totalAmount),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                ),
              ),
            ],
          ],
        ),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        actions: [
          if (_cartItems.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'پاک کردن سبد (Ctrl+K)',
              onPressed: _clearCart,
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'تنظیمات',
            onPressed: () {
              context.push('/business/${widget.businessId}/settings/quick-sales');
            },
          ),
        ],
      ),
      body: Row(
        children: [
          // ستون چپ: سبد خرید
          Expanded(
            flex: 7,
            child: Column(
              children: [
                // جستجوی بارکد
                Container(
                  padding: const EdgeInsets.all(16),
                  color: cs.surfaceContainerHighest,
                  child: Row(
                    children: [
                      // دکمه refresh موجودی (فقط اگر نمایش موجودی فعال باشد)
                      if (_showInventory && _cartItems.any((item) => item.trackInventory && item.productId != null))
                        IconButton(
                          icon: _loadingStocks 
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                          onPressed: _loadingStocks ? null : () => _refreshAllStocks(),
                          tooltip: 'به‌روزرسانی موجودی',
                        ),
                      Expanded(
                        child: TextField(
                          controller: _barcodeController,
                          focusNode: _barcodeFocus,
                          decoration: InputDecoration(
                            labelText: 'بارکد / کد / نام محصول',
                            hintText: 'اسکن یا وارد کردن بارکد، کد یا نام',
                            prefixIcon: const Icon(Icons.qr_code_scanner),
                            border: const OutlineInputBorder(),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // دکمه افزودن کالا (فقط وقتی جستجو ناموفق باشد)
                                if (_lastFailedSearchQuery != null && _lastFailedSearchQuery!.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.add_circle, color: Colors.green),
                                    tooltip: 'افزودن کالای جدید: $_lastFailedSearchQuery',
                                    onPressed: () => _openAddProductDialog(_lastFailedSearchQuery!),
                                  ),
                                // دکمه جستجو
                                IconButton(
                                  icon: const Icon(Icons.search),
                                  onPressed: () => _searchByBarcode(_barcodeController.text),
                                  tooltip: 'جستجو',
                                ),
                              ],
                            ),
                          ),
                          onSubmitted: _searchByBarcode,
                          onChanged: (value) {
                            // پاک کردن جستجوی ناموفق وقتی کاربر شروع به تایپ می‌کند
                            if (_lastFailedSearchQuery != null && value != _lastFailedSearchQuery) {
                              setState(() {
                                _lastFailedSearchQuery = null;
                              });
                            }
                          },
                          textInputAction: TextInputAction.search,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // جستجوی مشتری
                      SizedBox(
                        width: 200,
                        child: CustomerComboboxWidget(
                          selectedCustomer: _selectedCustomer,
                          onCustomerChanged: (customer) {
                            setState(() {
                              _selectedCustomer = customer ?? _anonymousCustomer;
                            });
                          },
                          businessId: widget.businessId,
                          authStore: widget.authStore,
                          isRequired: false,
                          label: 'مشتری',
                          hintText: 'مشتری ناشناس',
                        ),
                      ),
                    ],
                  ),
                ),
                // تاریخچه محصولات اخیر
                if (_recentProducts.isNotEmpty && _cartItems.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: cs.surfaceContainerHighest,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.history, size: 18, color: cs.onSurface.withOpacity(0.7)),
                            const SizedBox(width: 8),
                            Text(
                              'محصولات اخیر',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: cs.onSurface.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 60,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _recentProducts.length,
                            itemBuilder: (context, index) {
                              final product = _recentProducts[index];
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: InkWell(
                                  onTap: () async {
                                    try {
                                      final productId = (product['id'] as num?)?.toInt();
                                      if (productId != null) {
                                        final fullProduct = await _productService.getProduct(
                                          businessId: widget.businessId,
                                          productId: productId,
                                        );
                                        await _addToCart(fullProduct);
                                        await _saveRecentProduct(fullProduct);
                                        if (mounted) {
                                          SnackBarHelper.show(
                                            context,
                                            message: '${product['name'] ?? 'محصول'} به سبد اضافه شد',
                                          );
                                        }
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        SnackBarHelper.show(
                                          context,
                                          message: 'خطا در افزودن محصول: $e',
                                          isError: true,
                                        );
                                      }
                                    }
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: cs.surface,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: cs.outline.withOpacity(0.3)),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          product['name']?.toString() ?? 'نامشخص',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${_formatNumber(_toNum(product['base_sales_price'] ?? product['sales_price']))}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: cs.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                // لیست سبد خرید
                Expanded(
                  child: _cartItems.isEmpty
                      ? Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: Column(
                              key: ValueKey(_recentProducts.isEmpty),
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.shopping_cart_outlined, size: 64, color: cs.outline),
                                const SizedBox(height: 16),
                                Text('سبد خرید خالی است', style: TextStyle(color: cs.outline)),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _cartItems.length,
                          itemBuilder: (context, index) {
                            final item = _cartItems[index];
                            final hasInsufficientStock = _hasInsufficientStock(item);
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: Card(
                                color: hasInsufficientStock ? cs.errorContainer.withOpacity(0.3) : null,
                                child: InkWell(
                                onTap: () => _editCartItem(index),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // هشدار موجودی ناکافی (فقط اگر نمایش موجودی فعال باشد)
                                      if (_showInventory && hasInsufficientStock)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          margin: const EdgeInsets.only(bottom: 8),
                                          decoration: BoxDecoration(
                                            color: cs.errorContainer,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.warning_amber_rounded, size: 16, color: cs.onErrorContainer),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'موجودی کافی نیست! موجودی: ${_formatNumber(_getProductStock(item.productId) ?? 0)}، درخواست: ${_formatNumber(item.quantity)}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: cs.onErrorContainer,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.productName ?? 'نامشخص',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'کد: ${item.productCode ?? '-'}',
                                                  style: TextStyle(
                                                    color: cs.onSurface.withOpacity(0.7),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                // نمایش قیمت خرید (فقط اگر تنظیمات نمایش قیمت خرید فعال باشد)
                                                if (_showPurchasePrice && item.basePurchasePriceMainUnit != null)
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 4),
                                                    child: Text(
                                                      'قیمت خرید: ${_formatNumber(item.basePurchasePriceMainUnit!)}',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: cs.onSurface.withOpacity(0.6),
                                                        fontStyle: FontStyle.italic,
                                                      ),
                                                    ),
                                                  ),
                                                // نمایش موجودی (فقط اگر تنظیمات نمایش موجودی فعال باشد)
                                                if (_showInventory && item.trackInventory && item.productId != null && item.extraInfo?['instance_id'] == null)
                                                  Builder(
                                                    builder: (context) {
                                                      final stock = _getProductStock(item.productId);
                                                      // اگر موجودی null است و در حال بارگذاری نیست، سعی کن بارگذاری کن
                                                      if (stock == null && !_loadingStocks && _defaultWarehouseId != null) {
                                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                                          if (mounted && _showInventory) {
                                                            _loadProductStock(item.productId!);
                                                          }
                                                        });
                                                      }
                                                      final hasInsufficientStock = stock != null && stock < item.quantity;
                                                      return Padding(
                                                        padding: const EdgeInsets.only(top: 4),
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                              hasInsufficientStock ? Icons.warning : Icons.inventory_2,
                                                              size: 14,
                                                              color: hasInsufficientStock ? cs.error : cs.onSurface.withOpacity(0.6),
                                                            ),
                                                            const SizedBox(width: 4),
                                                            Text(
                                                              stock != null 
                                                                ? 'موجودی: ${_formatNumber(stock)}'
                                                                : 'در حال بررسی موجودی...',
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                color: hasInsufficientStock ? cs.error : cs.onSurface.withOpacity(0.6),
                                                                fontWeight: hasInsufficientStock ? FontWeight.bold : FontWeight.normal,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.edit, size: 20),
                                            onPressed: () => _editCartItem(index),
                                            tooltip: 'ویرایش',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete, size: 20),
                                            onPressed: () => _removeFromCart(index),
                                            tooltip: 'حذف',
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          // دکمه‌های افزایش/کاهش تعداد
                                          Container(
                                            decoration: BoxDecoration(
                                              border: Border.all(color: cs.outline),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                                IconButton(
                                                  icon: const Icon(Icons.remove, size: 18),
                                                  onPressed: () => _decreaseQuantity(index),
                                                  padding: const EdgeInsets.all(4),
                                                  constraints: const BoxConstraints(
                                                    minWidth: 32,
                                                    minHeight: 32,
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: 50,
                                                  child: Text(
                                                    item.quantity.toStringAsFixed(0),
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.add, size: 18),
                                                  onPressed: () => _increaseQuantity(index),
                                                  padding: const EdgeInsets.all(4),
                                                  constraints: const BoxConstraints(
                                                    minWidth: 32,
                                                    minHeight: 32,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  '${_formatNumber(item.quantity)} × ${_formatNumber(item.unitPrice)}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: cs.onSurface.withOpacity(0.7),
                                                  ),
                                                ),
                                                if (item.discountValue > 0)
                                                  Text(
                                                    'تخفیف: ${item.discountType == 'percent' ? '${item.discountValue}%' : _formatNumber(item.discountValue)}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: cs.error,
                                                    ),
                                                  ),
                                                if (item.taxRate > 0)
                                                  Text(
                                                    'مالیات: ${item.taxRate}%',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: cs.onSurface.withOpacity(0.6),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                    Text(
                                      _formatNumber(item.total),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                        color: cs.primary,
                                      ),
                                    ),
                                        ],
                                    ),
                                  ],
                                  ),
                                ),
                              ),
                            ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          // ستون راست: خلاصه و پرداخت
          Container(
            width: 350,
            color: cs.surfaceContainerHighest,
            child: Column(
              children: [
                // خلاصه فاکتور
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'خلاصه فاکتور',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildSummaryRow('تعداد اقلام', '${_cartItems.length}'),
                      _buildSummaryRow('جمع کل', _formatNumber(_subtotalAmount)),
                      if (_totalDiscount > 0)
                        _buildSummaryRow('تخفیف', '-${_formatNumber(_totalDiscount)}'),
                      if (_totalTax > 0)
                        _buildSummaryRow('مالیات', _formatNumber(_totalTax)),
                      const Divider(),
                      _buildSummaryRow(
                        'مبلغ نهایی',
                        _formatNumber(_totalAmount),
                        isTotal: true,
                      ),
                      if (_payment != null && _payment!.amount < _totalAmount) ...[
                        const SizedBox(height: 8),
                        _buildSummaryRow(
                          'مبلغ پرداخت شده',
                          _formatNumber(_payment!.amount),
                          isWarning: true,
                        ),
                        _buildSummaryRow(
                          'باقیمانده',
                          _formatNumber(_totalAmount - _payment!.amount),
                          isWarning: true,
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(),
                // پرداخت
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'پرداخت',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      CashRegisterComboboxWidget(
                        businessId: widget.businessId,
                        selectedRegisterId: _selectedCashRegisterId,
                        onChanged: (option) {
                          setState(() {
                            _selectedCashRegisterId = option?.id;
                            if (option != null && _totalAmount > 0) {
                              _payment = InvoiceTransaction(
                                id: DateTime.now().millisecondsSinceEpoch.toString(),
                                type: TransactionType.cashRegister,
                                cashRegisterId: option.id,
                                cashRegisterName: option.name,
                                transactionDate: DateTime.now(),
                                amount: _totalAmount, // همیشه برابر با مبلغ کل فاکتور
                              );
                            } else {
                              _payment = null;
                            }
                          });
                        },
                        label: 'صندوق',
                        hintText: 'انتخاب صندوق',
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // دکمه‌های ثبت
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : () => _saveInvoice(print: true),
                          icon: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.print),
                          label: const Text('ثبت و چاپ'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : () => _saveInvoice(print: false),
                          icon: const Icon(Icons.save),
                          label: const Text('ثبت'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isTotal = false, bool isWarning = false}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isWarning ? cs.error : null,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: FontWeight.bold,
              color: isTotal ? cs.primary : (isWarning ? cs.error : cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(num value) {
    return value.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
}

/// Dialog برای ویرایش اقلام سبد خرید
class _CartItemEditDialog extends StatefulWidget {
  final InvoiceLineItem item;

  const _CartItemEditDialog({
    required this.item,
  });

  @override
  State<_CartItemEditDialog> createState() => _CartItemEditDialogState();
}

class _CartItemEditDialogState extends State<_CartItemEditDialog> {
  late TextEditingController _quantityController;
  late TextEditingController _priceController;
  late TextEditingController _discountController;
  late String _discountType;
  late TextEditingController _taxRateController;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(
      text: number_utils.formatNumberForInput(widget.item.quantity),
    );
    _priceController = TextEditingController(
      text: number_utils.formatNumberForInput(widget.item.unitPrice),
    );
    _discountController = TextEditingController(
      text: number_utils.formatNumberForInput(widget.item.discountValue),
    );
    _discountType = widget.item.discountType;
    _taxRateController = TextEditingController(
      text: number_utils.formatNumberForInput(widget.item.taxRate),
    );
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _discountController.dispose();
    _taxRateController.dispose();
    super.dispose();
  }

  InvoiceLineItem _buildUpdatedItem() {
    final quantityValue = number_utils.parseFormattedNumber(_quantityController.text);
    final priceValue = number_utils.parseFormattedNumber(_priceController.text);
    final discountValue = number_utils.parseFormattedNumber(_discountController.text);
    final taxRateValue = number_utils.parseFormattedNumber(_taxRateController.text);
    
    final quantity = (quantityValue != null && quantityValue > 0) ? quantityValue : widget.item.quantity;
    final price = (priceValue != null && priceValue >= 0) ? priceValue : widget.item.unitPrice;
    final discount = (discountValue != null && discountValue >= 0) ? discountValue : widget.item.discountValue;
    final taxRate = (taxRateValue != null && taxRateValue >= 0) ? taxRateValue : widget.item.taxRate;

    return widget.item.copyWith(
      quantity: quantity > 0 ? quantity : 1,
      unitPrice: price,
      discountType: _discountType,
      discountValue: discount,
      taxRate: taxRate,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final updatedItem = _buildUpdatedItem();

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // هدر دیالوگ
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit, color: cs.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ویرایش محصول',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                        if (widget.item.productName != null)
                          Text(
                            widget.item.productName!,
                            style: TextStyle(
                              fontSize: 14,
                              color: cs.onPrimaryContainer.withOpacity(0.8),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // محتوای دیالوگ
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // تعداد
                    TextField(
                      controller: _quantityController,
                      decoration: InputDecoration(
                        labelText: 'تعداد',
                        hintText: 'مثال: 5',
                        prefixIcon: const Icon(Icons.numbers),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        number_utils.EnglishDigitsFormatter(),
                        const number_utils.ThousandsSeparatorInputFormatter(allowDecimal: true),
                      ],
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    // قیمت واحد
                    TextField(
                      controller: _priceController,
                      decoration: InputDecoration(
                        labelText: 'قیمت واحد',
                        hintText: 'مثال: 100,000',
                        prefixIcon: const Icon(Icons.attach_money),
                        suffixText: 'ریال',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        number_utils.EnglishDigitsFormatter(),
                        const number_utils.ThousandsSeparatorInputFormatter(allowDecimal: false),
                      ],
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    // نوع تخفیف و مبلغ تخفیف
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: _discountType,
                            decoration: InputDecoration(
                              labelText: 'نوع تخفیف',
                              prefixIcon: const Icon(Icons.percent),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: cs.surfaceContainerHighest,
                            ),
                            items: const [
                              DropdownMenuItem(value: 'amount', child: Text('مبلغی')),
                              DropdownMenuItem(value: 'percent', child: Text('درصدی')),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _discountType = value;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _discountController,
                            decoration: InputDecoration(
                              labelText: _discountType == 'percent' ? 'درصد تخفیف' : 'مبلغ تخفیف',
                              hintText: _discountType == 'percent' ? 'مثال: 10' : 'مثال: 5,000',
                              prefixIcon: Icon(_discountType == 'percent' ? Icons.percent : Icons.discount),
                              suffixText: _discountType == 'percent' ? '%' : 'ریال',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: cs.surfaceContainerHighest,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              number_utils.EnglishDigitsFormatter(),
                              number_utils.ThousandsSeparatorInputFormatter(
                                allowDecimal: _discountType == 'percent' ? false : true,
                              ),
                            ],
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // نرخ مالیات
                    TextField(
                      controller: _taxRateController,
                      decoration: InputDecoration(
                        labelText: 'نرخ مالیات',
                        hintText: 'مثال: 9',
                        prefixIcon: const Icon(Icons.receipt_long),
                        suffixText: '%',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        number_utils.EnglishDigitsFormatter(),
                        const number_utils.ThousandsSeparatorInputFormatter(allowDecimal: false),
                      ],
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 24),
                    // خلاصه محاسبات
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: cs.outline.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.calculate, size: 20, color: cs.primary),
                              const SizedBox(width: 8),
                              Text(
                                'خلاصه محاسبات',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildSummaryRow(
                            'جمع کل',
                            formatWithThousands(updatedItem.subtotal),
                            icon: Icons.summarize,
                          ),
                          if (updatedItem.discountValue > 0) ...[
                            const SizedBox(height: 8),
                            _buildSummaryRow(
                              'تخفیف',
                              '-${formatWithThousands(updatedItem.discountAmount)}',
                              icon: Icons.discount,
                              isDiscount: true,
                            ),
                          ],
                          if (updatedItem.taxRate > 0) ...[
                            const SizedBox(height: 8),
                            _buildSummaryRow(
                              'مالیات',
                              formatWithThousands(updatedItem.taxAmount),
                              icon: Icons.receipt,
                            ),
                          ],
                          const Divider(height: 24),
                          _buildSummaryRow(
                            'مبلغ نهایی',
                            formatWithThousands(updatedItem.total),
                            icon: Icons.payments,
                            isTotal: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // دکمه‌های پایین
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('انصراف'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop(_buildUpdatedItem());
                    },
                    icon: const Icon(Icons.check),
                    label: const Text('ذخیره تغییرات'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    IconData? icon,
    bool isTotal = false,
    bool isDiscount = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 18,
                color: isTotal
                    ? cs.primary
                    : (isDiscount ? cs.error : cs.onSurface.withOpacity(0.7)),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: isTotal ? 15 : 13,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
                color: isTotal
                    ? cs.primary
                    : (isDiscount ? cs.error : cs.onSurface),
              ),
            ),
          ],
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isTotal
                ? cs.primary
                : (isDiscount ? cs.error : cs.onSurface),
            fontSize: isTotal ? 18 : 14,
          ),
        ),
      ],
    );
  }
}

/// Dialog برای انتخاب instance از بین چند نتیجه
class _InstanceSelectionDialog extends StatelessWidget {
  final List<dynamic> instances;
  final String searchCode;

  const _InstanceSelectionDialog({
    required this.instances,
    required this.searchCode,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // هدر
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, color: cs.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'چند نتیجه پیدا شد',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'برای "$searchCode"',
                          style: TextStyle(
                            fontSize: 14,
                            color: cs.onPrimaryContainer.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: cs.onPrimaryContainer),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // لیست نتایج
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: instances.length,
                itemBuilder: (context, index) {
                  final instance = Map<String, dynamic>.from(instances[index] as Map);
                  final serialNumber = instance['serial_number']?.toString() ?? '-';
                  final barcode = instance['barcode']?.toString() ?? '-';
                  final productName = instance['product_name']?.toString() ?? 'نامشخص';
                  final warehouseName = instance['warehouse_name']?.toString();
                  
                  return ListTile(
                    leading: const Icon(Icons.inventory_2),
                    title: Text(productName),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (serialNumber != '-') 
                          Text('سریال: $serialNumber'),
                        if (barcode != '-') 
                          Text('بارکد: $barcode'),
                        if (warehouseName != null)
                          Text('انبار: $warehouseName'),
                      ],
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.of(context).pop(instance);
                    },
                  );
                },
              ),
            ),
            // دکمه انصراف
            Container(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('انصراف'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

