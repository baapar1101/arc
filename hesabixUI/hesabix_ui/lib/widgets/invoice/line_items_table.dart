import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../models/invoice_line_item.dart';
import '../../utils/number_formatters.dart';
import './product_combobox_widget.dart';
// import './price_list_combobox_widget.dart';
import '../../services/price_list_service.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import './warehouse_combobox_widget.dart';
import '../../utils/number_normalizer.dart' show EnglishDigitsFormatter, formatNumberForInput, parseFormattedNumber, parseFormattedDouble, ThousandsSeparatorInputFormatter;
import '../../core/calendar_controller.dart';
import './unique_product_instance_selector_dialog.dart';
import './invoice_line_attributes_dialog.dart';
import '../../services/product_service.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/responsive_helper.dart';
import 'package:reorderables/reorderables.dart';


class InvoiceLineItemsTable extends StatefulWidget {
  final int businessId;
  final int? selectedCurrencyId; // از تب ارز فاکتور
  final ValueChanged<List<InvoiceLineItem>>? onChanged;
  final String invoiceType; // sales | purchase | sales_return | purchase_return | ...
  final bool postInventory;
  final List<InvoiceLineItem>? initialRows; // برای مقداردهی اولیه (ویرایش فاکتور)
  final AuthStore? authStore;
  final CalendarController? calendarController; // برای فرمت تاریخ در دیالوگ انتخاب instance

  const InvoiceLineItemsTable({
    super.key,
    required this.businessId,
    this.selectedCurrencyId,
    this.onChanged,
    this.invoiceType = 'sales',
    this.postInventory = true,
    this.initialRows,
    this.authStore,
    this.calendarController,
  });

  @override
  State<InvoiceLineItemsTable> createState() => _InvoiceLineItemsTableState();
}

class _InvoiceLineItemsTableState extends State<InvoiceLineItemsTable> {
  final List<InvoiceLineItem> _rows = <InvoiceLineItem>[];
  final PriceListService _priceListService = PriceListService(apiClient: ApiClient());
  final ProductService _productService = ProductService();
  Map<String, dynamic>? _inlinePriceList; // کش لیست قیمت برای آیکون انتخاب قیمت
  final Map<int, Map<String, dynamic>> _productCache = {}; // کش اطلاعات کالاها برای بررسی یونیک بودن
  final Map<int, Map<String, FocusNode>> _focusNodes = {}; // مدیریت فوکوس برای navigation

  void _notify() => widget.onChanged?.call(List<InvoiceLineItem>.from(_rows));
  
  /// دریافت ارتفاع فیلد بر اساس اندازه صفحه
  double _getFieldHeight(BuildContext context) {
    return ResponsiveHelper.responsiveValue(
      context,
      mobile: 56.0,    // موبایل: 56px (حداقل برای لمس)
      tablet: 52.0,    // تبلت: 52px
      desktop: 48.0,   // دسکتاپ: 48px
    );
  }
  
  /// دریافت padding داخلی فیلدها
  EdgeInsets _getFieldPadding(BuildContext context) {
    return ResponsiveHelper.isMobile(context)
        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 10);
  }
  
  /// ایجاد FocusNode برای یک ردیف
  void _ensureFocusNodes(int index) {
    if (!_focusNodes.containsKey(index)) {
      _focusNodes[index] = {
        'product': FocusNode(),
        'quantity': FocusNode(),
        'warehouse': FocusNode(),
        'unitPrice': FocusNode(),
        'description': FocusNode(),
        'discount': FocusNode(),
        'tax': FocusNode(),
      };
    }
  }
  
  /// پاک کردن FocusNode های یک ردیف
  void _disposeFocusNodes(int index) {
    final nodes = _focusNodes.remove(index);
    if (nodes != null) {
      for (final node in nodes.values) {
        node.dispose();
      }
    }
  }
  
  /// پاک کردن همه FocusNode ها
  void _disposeAllFocusNodes() {
    for (final nodes in _focusNodes.values) {
      for (final node in nodes.values) {
        node.dispose();
      }
    }
    _focusNodes.clear();
  }
  
  /// حرکت به فیلد بعدی
  void _moveToNextField(int index, String currentField) {
    final nodes = _focusNodes[index];
    if (nodes == null) return;
    
    final fieldOrder = ['product', 'quantity', 'warehouse', 'unitPrice', 'description', 'discount', 'tax'];
    final currentIndex = fieldOrder.indexOf(currentField);
    if (currentIndex >= 0 && currentIndex < fieldOrder.length - 1) {
      final nextField = fieldOrder[currentIndex + 1];
      final nextNode = nodes[nextField];
      if (nextNode != null && mounted) {
        nextNode.requestFocus();
      }
    } else if (currentIndex == fieldOrder.length - 1 && index < _rows.length - 1) {
      // اگر آخرین فیلد آخرین ردیف بود، به ردیف بعدی برو
      _ensureFocusNodes(index + 1);
      final nextRowNodes = _focusNodes[index + 1];
      if (nextRowNodes != null) {
        nextRowNodes['product']?.requestFocus();
      }
    }
  }
  
  bool _shouldShowLineAttributesButton(InvoiceLineItem item) {
    if (item.productId == null) return false;
    final product = _productCache[item.productId];
    if (product == null) return false;
    if ((product['inventory_mode']?.toString() ?? '') == 'unique') return false;
    final ids = product['attribute_ids'];
    return ids is List && ids.isNotEmpty;
  }

  Map<String, dynamic>? _lineAttributesMap(InvoiceLineItem item) {
    final raw = item.extraInfo?['line_custom_attributes'];
    if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
    if (raw is Map) return Map<String, dynamic>.from(raw.map((k, v) => MapEntry(k.toString(), v)));
    return null;
  }

  String _lineAttributesSummary(InvoiceLineItem item) {
    final m = _lineAttributesMap(item);
    if (m == null || m.isEmpty) return '';
    return m.entries.map((e) => '${e.key}: ${e.value}').join('، ');
  }

  Future<void> _editLineAttributes(int index, InvoiceLineItem item) async {
    if (item.productId == null) return;
    await _loadProductInfo(item.productId!, force: true);
    if (!mounted) return;
    final product = _productCache[item.productId];
    if (product == null || !_shouldShowLineAttributesButton(item)) {
      SnackBarHelper.show(context, message: 'این کالا ویژگی قابل ویرایش در سطح ردیف ندارد');
      return;
    }
    final result = await showInvoiceLineAttributesEditor(
      context: context,
      businessId: widget.businessId,
      productId: item.productId!,
      productName: item.productName ?? '',
      productMap: product,
      initialLineAttributes: _lineAttributesMap(item),
      calendarController: widget.calendarController,
    );
    if (!mounted || result == null) return;
    final ei = Map<String, dynamic>.from(item.extraInfo ?? {});
    if (result.isEmpty) {
      ei.remove('line_custom_attributes');
    } else {
      ei['line_custom_attributes'] = result;
    }
    _updateRow(index, item.copyWith(extraInfo: ei.isEmpty ? null : ei));
  }

  Widget _lineAttributesRow(BuildContext context, int index, InvoiceLineItem item) {
    final summary = _lineAttributesSummary(item);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal[50],
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.teal[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.tune, size: 20, color: Colors.teal[800]),
          const SizedBox(width: 8),
          Expanded(
            child: summary.isEmpty
                ? Text(
                    'ویژگی‌های کالا (اختیاری)',
                    style: TextStyle(fontSize: 13, color: Colors.teal[900], fontStyle: FontStyle.italic),
                  )
                : Text(
                    summary,
                    style: TextStyle(fontSize: 13, color: Colors.teal[900], fontWeight: FontWeight.w500),
                  ),
          ),
          TextButton.icon(
            onPressed: () => _editLineAttributes(index, item),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(summary.isEmpty ? 'تعیین' : 'ویرایش'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  /// بررسی اینکه آیا باید قابلیت انتخاب instance نمایش داده شود
  bool _shouldShowInstanceSelector(InvoiceLineItem item) {
    // فقط برای فاکتور فروش و برگشت از خرید
    if (widget.invoiceType != 'sales' && widget.invoiceType != 'purchase_return') {
      return false;
    }
    
    // باید کالا انتخاب شده باشد
    if (item.productId == null) {
      return false;
    }
    
    // بررسی اینکه کالا یونیک است
    final product = _productCache[item.productId];
    if (product == null) return false;
    
    return product['inventory_mode'] == 'unique';
  }
  
  /// بارگذاری اطلاعات کالا برای بررسی یونیک بودن و ویژگی‌ها
  Future<void> _loadProductInfo(int productId, {bool force = false}) async {
    if (!force && _productCache.containsKey(productId)) {
      return;
    }
    
    try {
      final product = await _productService.getProduct(
        businessId: widget.businessId,
        productId: productId,
      );
      if (mounted) {
        setState(() {
          _productCache[productId] = product;
        });
      }
    } catch (e) {
      // خطا در بارگذاری - نادیده می‌گیریم
    }
  }
  
  /// باز کردن دیالوگ انتخاب instance ها
  Future<void> _selectUniqueProductInstances(int index, InvoiceLineItem item) async {
    if (item.productId == null) return;
    
    // بارگذاری اطلاعات کالا
    await _loadProductInfo(item.productId!);
    
    if (!_shouldShowInstanceSelector(item)) {
      SnackBarHelper.show(context, message: 'این کالا در حالت یونیک نیست');
      return;
    }
    
    if (widget.calendarController == null) {
      SnackBarHelper.show(context, message: 'خطا: CalendarController در دسترس نیست');
      return;
    }
    
    final product = _productCache[item.productId!]!;
    final quantity = item.quantity.toInt();
    
    if (quantity <= 0) {
      SnackBarHelper.show(context, message: 'لطفاً ابتدا تعداد را وارد کنید');
      return;
    }
    
    final selectedIds = await showDialog<List<int>>(
      context: context,
      builder: (context) => UniqueProductInstanceSelectorDialog(
        businessId: widget.businessId,
        productId: item.productId!,
        productName: item.productName ?? 'کالا',
        warehouseId: item.warehouseId,
        selectedInstanceIds: item.selectedInstanceIds,
        requiredQuantity: quantity,
        calendarController: widget.calendarController!,
      ),
    );
    
    if (selectedIds != null && mounted) {
      setState(() {
        _rows[index] = item.copyWith(selectedInstanceIds: selectedIds);
      });
      _notify();
    }
  }

  void _updateRow(int index, InvoiceLineItem updated) {
    setState(() {
      _rows[index] = updated;
    });
    _notify();
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  num _toNum(dynamic value, {num fallback = 0}) {
    if (value == null) return fallback;
    if (value is num) return value;
    return num.tryParse(value.toString()) ?? fallback;
  }

  void _addRow() {
    setState(() {
      final newIndex = _rows.length;
      _rows.add(InvoiceLineItem(
        taxRate: _getDefaultTaxRateForInvoiceType(),
      ));
      _ensureFocusNodes(newIndex);
      // فوکوس به فیلد کالای ردیف جدید
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nodes = _focusNodes[newIndex];
        if (nodes != null && mounted) {
          nodes['product']?.requestFocus();
        }
      });
    });
    _notify();
  }

  void _removeRow(int index) {
    setState(() {
      _disposeFocusNodes(index);
      _rows.removeAt(index);
      // به‌روزرسانی index های focus nodes
      final keysToUpdate = _focusNodes.keys.where((k) => k > index).toList()..sort();
      final newFocusNodes = <int, Map<String, FocusNode>>{};
      for (final oldKey in _focusNodes.keys) {
        if (oldKey < index) {
          newFocusNodes[oldKey] = _focusNodes[oldKey]!;
        } else if (oldKey > index) {
          newFocusNodes[oldKey - 1] = _focusNodes[oldKey]!;
        }
      }
      _focusNodes.clear();
      _focusNodes.addAll(newFocusNodes);
    });
    _notify();
  }
  
  /// جابجایی ردیف‌ها (برای drag & drop)
  void _reorderRows(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final item = _rows.removeAt(oldIndex);
      _rows.insert(newIndex, item);
      
      // به‌روزرسانی focus nodes
      final newFocusNodes = <int, Map<String, FocusNode>>{};
      for (final entry in _focusNodes.entries) {
        int newKey = entry.key;
        if (entry.key == oldIndex) {
          newKey = newIndex;
        } else if (entry.key > oldIndex && entry.key <= newIndex) {
          newKey = entry.key - 1;
        } else if (entry.key < oldIndex && entry.key >= newIndex) {
          newKey = entry.key + 1;
        }
        newFocusNodes[newKey] = entry.value;
      }
      _focusNodes.clear();
      _focusNodes.addAll(newFocusNodes);
    });
    _notify();
  }

  @override
  void initState() {
    super.initState();
    if ((widget.initialRows ?? const <InvoiceLineItem>[]).isNotEmpty) {
      _rows.clear();
      _rows.addAll(widget.initialRows!);
      // ایجاد focus nodes برای ردیف‌های اولیه
      for (int i = 0; i < _rows.length; i++) {
        _ensureFocusNodes(i);
      }
      // بارگذاری اطلاعات کالاها برای بررسی یونیک بودن
      _loadProductInfosForInitialRows();
      _notify();
    }
  }
  
  @override
  void dispose() {
    _disposeAllFocusNodes();
    super.dispose();
  }
  
  /// بارگذاری اطلاعات کالاهای موجود در ردیف‌های اولیه
  Future<void> _loadProductInfosForInitialRows() async {
    for (var item in _rows) {
      if (item.productId != null && !_productCache.containsKey(item.productId)) {
        await _loadProductInfo(item.productId!);
      }
    }
  }

  @override
  void didUpdateWidget(covariant InvoiceLineItemsTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCurrencyId != widget.selectedCurrencyId) {
      // ارز تغییر کرده: لازم است قیمت‌های بر اساس لیست قیمت مجدد ارزیابی شوند
      _recalculateAllUnitPrices();
      // invalidate inline price list cache if currency changed
      _inlinePriceList = null;
    }

    // اگر والد پس از لود اولیه، ردیف‌های اولیه را فراهم کرد و جدول خالی است، آن‌ها را ست کن
    // یا اگر تعداد ردیف‌های initialRows بیشتر از ردیف‌های فعلی است (ردیف‌های جدید اضافه شده)
    if (widget.initialRows != null && widget.initialRows!.isNotEmpty) {
      if (_rows.isEmpty) {
        // اگر جدول خالی است، همه ردیف‌ها را اضافه کن
        _rows.clear();
        _rows.addAll(widget.initialRows!);
        _notify();
      } else if (widget.initialRows!.length > _rows.length) {
        // اگر ردیف‌های جدید اضافه شده، همه ردیف‌ها را جایگزین کن
        // (کاربر می‌تواند بعداً ردیف‌ها را ویرایش کند)
        _rows.clear();
        _rows.addAll(widget.initialRows!);
        _notify();
      }
    }

    if (oldWidget.invoiceType != widget.invoiceType) {
      if (_applyInvoiceTypeDescriptionAdjustments()) {
        setState(() {});
        _notify();
      }
    }
  }

  // لیست قیمت سراسری حذف شده است؛ انتخاب قیمت از داخل سلول انجام می‌شود

  Future<void> _recalculateAllUnitPrices() async {
    // برای هر ردیف، اگر منبع قیمت «priceList» است سعی کن قیمت مناسب را بارگذاری/تبدیل کنی
    for (int i = 0; i < _rows.length; i++) {
      final it = _rows[i];
      final updated = await _resolveUnitPrice(it, preferManual: false);
      setState(() => _rows[i] = updated);
    }
    _notify();
  }

  Future<InvoiceLineItem> _resolveUnitPrice(InvoiceLineItem item, {bool preferManual = true}) async {
    // اگر کاربر دستی وارد کرده، همان را نگه داریم (در مدل جدید، فیلد همیشه قابل ویرایش است)
    if (preferManual && item.unitPriceSource == 'manual') return item;

    // تلاش بر اساس لیست قیمت (در مدل جدید از انتخاب داخل سلول استفاده می‌کنیم،
    // این تابع همچنان fallback قیمت پایه را فراهم می‌کند.)
    final currencyId = widget.selectedCurrencyId;
    final pl = _inlinePriceList; // اگر از پیکر انتخاب قیمت ست شده باشد
    if (pl != null && currencyId != null && item.productId != null) {
      try {
        final items = await _priceListService.listItems(
          businessId: widget.businessId,
          priceListId: (pl['id'] as int),
          productId: item.productId,
          currencyId: currencyId,
        );
        num? priceOnMainUnit;
        for (final pi in items) {
          final unitId = pi['unit_id'] as int?; // ممکن است null باشد (یعنی بر واحد اصلی)
          final price = (pi['price'] as num?) ?? 0;
          if (unitId == null) {
            // قیمت بر اساس واحد اصلی
            priceOnMainUnit = price;
          }
        }
        if (priceOnMainUnit != null) {
          // تبدیل به واحد انتخابی
          final converted = _convertFromMain(priceOnMainUnit, item);
          return item.copyWith(unitPriceSource: 'priceList', unitPrice: converted);
        }
      } catch (_) {
        // ignore
      }
    }

    // fallback: قیمت پایه محصول بر اساس نوع فاکتور (فرض: روی واحد اصلی)
    final basePrice = _basePriceOfProduct(item);
    final converted = _convertFromMain(basePrice, item);
    return item.copyWith(unitPriceSource: 'base', unitPrice: converted);
  }

  num _basePriceOfProduct(InvoiceLineItem item) {
    // انتخاب قیمت پایه متناسب با نوع فاکتور: فروش/خرید
    // قیمت‌های پایه فرضاً بر واحد اصلی هستند
    if (widget.invoiceType == 'purchase' || widget.invoiceType == 'purchase_return') {
      return item.basePurchasePriceMainUnit ?? 0;
    }
    return item.baseSalesPriceMainUnit ?? 0;
  }

  String? _noteForInvoiceType(String invoiceType, {String? salesNote, String? purchaseNote}) {
    final trimmedSales = salesNote?.trim();
    final trimmedPurchase = purchaseNote?.trim();
    if (invoiceType == 'purchase' || invoiceType == 'purchase_return') {
      return (trimmedPurchase != null && trimmedPurchase.isNotEmpty) ? trimmedPurchase : null;
    }
    return (trimmedSales != null && trimmedSales.isNotEmpty) ? trimmedSales : null;
  }

  String? _cleanNote(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  bool _shouldReplaceDescription(String? current, String? previousAuto) {
    final trimmed = current?.trim() ?? '';
    if (trimmed.isEmpty) return true;
    if (previousAuto == null || previousAuto.isEmpty) return false;
    return trimmed == previousAuto;
  }

  Map<String, dynamic> _mergeExtraInfoWithNotes(
    InvoiceLineItem item, {
    String? salesNote,
    String? purchaseNote,
  }) {
    final metadata = Map<String, dynamic>.from(item.extraInfo ?? const {});
    if (salesNote != null) {
      metadata['_local_sales_note'] = salesNote;
    } else {
      metadata.remove('_local_sales_note');
    }
    if (purchaseNote != null) {
      metadata['_local_purchase_note'] = purchaseNote;
    } else {
      metadata.remove('_local_purchase_note');
    }
    return metadata;
  }

  bool _applyInvoiceTypeDescriptionAdjustments() {
    bool changed = false;
    for (var i = 0; i < _rows.length; i++) {
      final item = _rows[i];
      final metadata = Map<String, dynamic>.from(item.extraInfo ?? const {});
      final salesNote = metadata['_local_sales_note']?.toString();
      final purchaseNote = metadata['_local_purchase_note']?.toString();
      final previousAuto = metadata['_local_auto_description']?.toString();
      final newAuto = _noteForInvoiceType(
        widget.invoiceType,
        salesNote: salesNote,
        purchaseNote: purchaseNote,
      );

      bool metadataChanged = false;
      if (newAuto?.isNotEmpty == true) {
        if (previousAuto != newAuto) {
          metadata['_local_auto_description'] = newAuto;
          metadataChanged = true;
        }
      } else if (previousAuto != null) {
        metadata.remove('_local_auto_description');
        metadataChanged = true;
      }

      final currentDesc = item.description?.trim() ?? '';
      final shouldReplace = _shouldReplaceDescription(currentDesc, previousAuto);
      InvoiceLineItem updated = item;
      if (shouldReplace && currentDesc != (newAuto ?? '')) {
        updated = updated.copyWith(description: newAuto);
        changed = true;
      }
      if (metadataChanged) {
        final cleaned = metadata.isEmpty ? null : metadata;
        updated = updated.copyWith(extraInfo: cleaned);
        changed = true;
      }
      if (!identical(updated, item)) {
        _rows[i] = updated;
      }
    }
    return changed;
  }

  num _convertFromMain(num priceOnMainUnit, InvoiceLineItem item) {
    final rawFactor = item.unitConversionFactor;
    final factor = (rawFactor == null || rawFactor <= 0) ? 1 : rawFactor;
    final isMainSelected = (item.selectedUnit == item.mainUnit) || (item.selectedUnit == null);
    if (isMainSelected) {
      return priceOnMainUnit;
    }
    // در حالت انتخاب واحد فرعی: قیمت واحد باید در ضریب تبدیل ضرب شود
    // تعریف: 1 main = factor * secondary  => price(secondary) = price(main) * factor
    return priceOnMainUnit * factor;
  }

  num _defaultTaxRateFromProduct(Map<String, dynamic> p) {
    if (widget.invoiceType == 'purchase' || widget.invoiceType == 'purchase_return') {
      // برای فاکتور خرید و برگشت از خرید: از نرخ مالیات خرید استفاده کن
      final isTaxable = p['is_purchase_taxable'] == true;
      if (!isTaxable) return 0;
      
      final v = p['purchase_tax_rate'];
      final rate = _toNum(v);
      if (rate > 0) return rate;
      // اگر محصول نرخ مالیات خرید نداشته باشد، از نرخ پیش‌فرض استفاده کن
      return _getDefaultTaxRateForInvoiceType();
    }
    
    // برای فاکتور فروش و برگشت از فروش: از نرخ مالیات فروش استفاده کن
    final isTaxable = p['is_sales_taxable'] == true;
    if (!isTaxable) return 0;
    
    final v = p['sales_tax_rate'];
    final rate = _toNum(v);
    if (rate > 0) return rate;
    // اگر محصول نرخ مالیات فروش نداشته باشد، از نرخ پیش‌فرض استفاده کن
    return _getDefaultTaxRateForInvoiceType();
  }

  num _getDefaultTaxRateForInvoiceType() {
    // نرخ پیش‌فرض مالیات بر اساس نوع فاکتور
    switch (widget.invoiceType) {
      case 'sales':
      case 'sales_return':
        return 9; // نرخ پیش‌فرض مالیات بر ارزش افزوده فروش (برای فروش و برگشت از فروش)
      case 'purchase':
      case 'purchase_return':
        return 9; // نرخ پیش‌فرض مالیات بر ارزش افزوده خرید (برای خرید و برگشت از خرید)
      default:
        return 0; // سایر انواع فاکتور بدون مالیات
    }
  }

  String _unitTitle(InvoiceLineItem item, String? unit) {
    if (unit == null) return '';
    return unit;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outline.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _buildHeader(context),
                  const Divider(height: 1),
                  if (_rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        t.noRowsAdded,
                        style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    )
                  else
                    _buildRowsList(context),
                ],
              ),
            ),
            // فضای خالی برای دکمه شناور (فقط زمانی که خطوط وجود دارند)
            if (_rows.isNotEmpty) const SizedBox(height: 80),
          ],
        ),
        // دکمه شناور در پایین (فقط زمانی که خطوط وجود دارند)
        if (_rows.isNotEmpty)
          Positioned(
            bottom: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: FloatingActionButton.extended(
                onPressed: _addRow,
                icon: const Icon(Icons.add),
                label: Text(t.add),
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                elevation: 4,
              ),
            ),
          )
        else
          // اگر خطوطی وجود ندارد، دکمه را در بالای جدول نمایش بده
          Positioned(
            top: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.only(top: 0, right: 0),
              child: ElevatedButton.icon(
                onPressed: _addRow,
                icon: const Icon(Icons.add),
                label: Text(t.add),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          _h('#', 36, style),
          Expanded(
            flex: 4,
            child: Tooltip(
              message: t.productsAndServices,
              child: Text(t.productsAndServices, style: style),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Tooltip(
              message: t.quantityUnit,
              child: Text(t.quantityUnit, style: style),
            ),
          ),
          const SizedBox(width: 8),
          if (widget.postInventory)
            Expanded(
              flex: 2,
              child: Tooltip(
                message: t.warehouse,
                child: Text(t.warehouse, style: style),
              ),
            ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Tooltip(
              message: t.unitPrice,
              child: Text(t.unitPrice, style: style),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Tooltip(
                message: t.totalAmount,
                child: Text(t.totalAmount, style: style, textAlign: TextAlign.end),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _h(String text, double width, TextStyle? style, {bool alignEnd = false}) {
    return SizedBox(
      width: width,
      child: Tooltip(
        message: text,
        child: Text(text, style: style, textAlign: alignEnd ? TextAlign.end : TextAlign.start),
      ),
    );
  }
  
  /// ساخت لیست ردیف‌ها با قابلیت drag & drop
  Widget _buildRowsList(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    
    // استفاده از ReorderableListView برای هر دو حالت
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      onReorder: _reorderRows,
      children: _rows.asMap().entries.map((e) {
        if (isMobile) {
          return _buildMobileRow(context, e.key, e.value);
        } else {
          return _buildDesktopRow(context, e.key, e.value);
        }
      }).toList(),
    );
  }
  
  /// ساخت ردیف برای موبایل (با Card)
  Widget _buildMobileRow(BuildContext context, int index, InvoiceLineItem item) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final fieldHeight = _getFieldHeight(context);
    _ensureFocusNodes(index);
    
    return Card(
      key: ValueKey('row_$index'),
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12, left: 8, right: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // هدر ردیف با شماره و دکمه‌های جابجایی
            Row(
              children: [
                Icon(Icons.drag_handle, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  'ردیف ${index + 1}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                // دکمه‌های جابجایی
                if (index > 0)
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_up),
                    onPressed: () => _reorderRows(index, index - 1),
                    tooltip: 'جابجایی به بالا',
                    iconSize: 20,
                  ),
                if (index < _rows.length - 1)
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down),
                    onPressed: () => _reorderRows(index, index + 1),
                    tooltip: 'جابجایی به پایین',
                    iconSize: 20,
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeRow(index),
                  tooltip: 'حذف',
                  iconSize: 20,
                  color: Colors.red,
                ),
              ],
            ),
            const Divider(height: 24),
            // کالا/خدمت
            Text(
              t.productsAndServices,
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: fieldHeight,
              child: ProductComboboxWidget(
                businessId: widget.businessId,
                authStore: widget.authStore,
                selectedProduct: item.productId != null
                    ? {
                        'id': item.productId,
                        'code': item.productCode,
                        'name': item.productName,
                        'main_unit': item.mainUnit,
                        'secondary_unit': item.secondaryUnit,
                        'unit_conversion_factor': item.unitConversionFactor,
                      }
                    : null,
                onChanged: (p) async {
                  await _handleProductChange(index, item, p);
                  // بعد از انتخاب کالا، فوکوس به تعداد
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final nodes = _focusNodes[index];
                    if (nodes != null && mounted) {
                      nodes['quantity']?.requestFocus();
                    }
                  });
                },
              ),
            ),
            const SizedBox(height: 12),
            // تعداد و واحد
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.quantityUnit,
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: fieldHeight,
                        child: _buildQuantityWithUnitField(
                          item,
                          (qty) {
                            _updateRow(index, item.copyWith(quantity: qty));
                          },
                          (unit) async {
                            final changed = item.copyWith(selectedUnit: unit);
                            final priced = await _resolveUnitPrice(changed, preferManual: item.unitPriceSource == 'manual');
                            setState(() => _rows[index] = priced);
                            _notify();
                          },
                          focusNode: _focusNodes[index]?['quantity'],
                          onFieldSubmitted: () => _moveToNextField(index, 'quantity'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.postInventory) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.warehouse,
                          style: theme.textTheme.labelMedium,
                        ),
                        const SizedBox(height: 4),
                        WarehouseComboboxWidget(
                          businessId: widget.businessId,
                          selectedWarehouseId: item.warehouseId,
                          onChanged: (wid) {
                            _updateRow(index, item.copyWith(warehouseId: wid));
                          },
                          label: 'انبار',
                          hintText: 'انتخاب انبار',
                          isRequired: item.trackInventory,
                          height: fieldHeight,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            // قیمت واحد
            Text(
              t.unitPrice,
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: fieldHeight,
              child: Tooltip(
                message: t.unitPricePickHint,
                child: _UnitPriceCell(
                  businessId: widget.businessId,
                  invoiceType: widget.invoiceType,
                  currencyId: widget.selectedCurrencyId,
                  item: item,
                  onChanged: (src, price) {
                    final validatedPrice = price < 0 ? 0 : price;
                    _updateRow(index, item.copyWith(unitPriceSource: src, unitPrice: validatedPrice));
                  },
                  resolver: () => _resolveUnitPrice(item, preferManual: true),
                  unitTitleResolver: (u) => _unitTitle(item, u),
                  focusNode: _focusNodes[index]?['unitPrice'],
                  onFieldSubmitted: () => _moveToNextField(index, 'unitPrice'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // مبلغ کل
            Container(
              padding: _getFieldPadding(context),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(4),
                color: theme.colorScheme.surfaceContainerHighest,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    t.totalAmount,
                    style: theme.textTheme.labelMedium,
                  ),
                  Text(
                    formatWithThousands(item.total, decimalPlaces: 0),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // شرح
            Text(
              t.lineDescription,
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: fieldHeight,
              child: TextFormField(
                focusNode: _focusNodes[index]?['description'],
                initialValue: item.description ?? '',
                onChanged: (v) {
                  _updateRow(index, item.copyWith(description: v));
                },
                onFieldSubmitted: (_) => _moveToNextField(index, 'description'),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  contentPadding: _getFieldPadding(context),
                  hintText: t.descriptionOptional,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // تخفیف و مالیات
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.discountTypeAndValue,
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: fieldHeight,
                        child: _DiscountCell(
                          value: item.discountValue,
                          type: item.discountType,
                          onChanged: (type, value) {
                            _updateRow(index, item.copyWith(discountType: type, discountValue: value));
                          },
                          focusNode: _focusNodes[index]?['discount'],
                          onFieldSubmitted: () => _moveToNextField(index, 'discount'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.taxPercentAndAmount,
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: fieldHeight,
                        child: _TaxCell(
                          rate: item.taxRate,
                          taxAmount: item.taxAmount,
                          onRateChanged: (r) {
                            _updateRow(index, item.copyWith(taxRate: r));
                          },
                          focusNode: _focusNodes[index]?['tax'],
                          onFieldSubmitted: () => _moveToNextField(index, 'tax'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // سطر سوم: نمایش instance های انتخاب شده (فقط برای کالاهای یونیک)
            if (_shouldShowInstanceSelector(item)) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.qr_code_scanner, size: 20, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: item.selectedInstanceIds != null && item.selectedInstanceIds!.isNotEmpty
                          ? Text(
                              '${item.selectedInstanceIds!.length} کالای یونیک انتخاب شده',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.blue[900],
                                fontWeight: FontWeight.w500,
                              ),
                            )
                          : Text(
                              'برای انتخاب کالاهای یونیک کلیک کنید',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.blue[700],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                    ),
                    TextButton.icon(
                      onPressed: () => _selectUniqueProductInstances(index, item),
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      label: Text(
                        item.selectedInstanceIds != null && item.selectedInstanceIds!.isNotEmpty
                            ? 'ویرایش'
                            : 'انتخاب',
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_shouldShowLineAttributesButton(item)) ...[
              const SizedBox(height: 12),
              _lineAttributesRow(context, index, item),
            ],
          ],
        ),
      ),
    );
  }
  
  /// ساخت ردیف برای دسکتاپ
  Widget _buildDesktopRow(BuildContext context, int index, InvoiceLineItem item) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final fieldHeight = _getFieldHeight(context);
    _ensureFocusNodes(index);
    
    return Container(
      key: ValueKey('row_$index'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        children: [
          // سطر اول: شماره، کالا/خدمت، تعداد+واحد، انبار، قیمت واحد، مبلغ کل، عملیات
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle و شماره
              SizedBox(
                width: 48,
                child: Row(
                  children: [
                    Icon(Icons.drag_handle, size: 20, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text('${index + 1}', style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // کالا/خدمت
              Expanded(
                flex: 4,
                child: SizedBox(
                  height: fieldHeight,
                  child: ProductComboboxWidget(
                    businessId: widget.businessId,
                    authStore: widget.authStore,
                    selectedProduct: item.productId != null
                        ? {
                            'id': item.productId,
                            'code': item.productCode,
                            'name': item.productName,
                            'main_unit': item.mainUnit,
                            'secondary_unit': item.secondaryUnit,
                            'unit_conversion_factor': item.unitConversionFactor,
                          }
                        : null,
                    onChanged: (p) async {
                      await _handleProductChange(index, item, p);
                      // بعد از انتخاب کالا، فوکوس به تعداد
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final nodes = _focusNodes[index];
                        if (nodes != null && mounted) {
                          nodes['quantity']?.requestFocus();
                        }
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // تعداد+واحد
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: fieldHeight,
                  child: _buildQuantityWithUnitField(
                    item,
                    (qty) {
                      _updateRow(index, item.copyWith(quantity: qty));
                    },
                    (unit) async {
                      final changed = item.copyWith(selectedUnit: unit);
                      final priced = await _resolveUnitPrice(changed, preferManual: item.unitPriceSource == 'manual');
                      setState(() => _rows[index] = priced);
                      _notify();
                    },
                    focusNode: _focusNodes[index]?['quantity'],
                    onFieldSubmitted: () => _moveToNextField(index, 'quantity'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // انبار
              if (widget.postInventory)
                Expanded(
                  flex: 2,
                  child: WarehouseComboboxWidget(
                    businessId: widget.businessId,
                    selectedWarehouseId: item.warehouseId,
                    onChanged: (wid) {
                      _updateRow(index, item.copyWith(warehouseId: wid));
                    },
                    label: 'انبار',
                    hintText: 'انتخاب انبار',
                    isRequired: item.trackInventory,
                    height: fieldHeight,
                  ),
                ),
              if (widget.postInventory) const SizedBox(width: 8),
              // قیمت واحد
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: fieldHeight,
                  child: Tooltip(
                    message: t.unitPricePickHint,
                    child: _UnitPriceCell(
                      businessId: widget.businessId,
                      invoiceType: widget.invoiceType,
                      currencyId: widget.selectedCurrencyId,
                      item: item,
                      onChanged: (src, price) {
                        final validatedPrice = price < 0 ? 0 : price;
                        _updateRow(index, item.copyWith(unitPriceSource: src, unitPrice: validatedPrice));
                      },
                      resolver: () => _resolveUnitPrice(item, preferManual: true),
                      unitTitleResolver: (u) => _unitTitle(item, u),
                      focusNode: _focusNodes[index]?['unitPrice'],
                      onFieldSubmitted: () => _moveToNextField(index, 'unitPrice'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // مبلغ کل
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: fieldHeight,
                  child: Tooltip(
                    message: t.lineTotalAmount,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        contentPadding: _getFieldPadding(context),
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          formatWithThousands(item.total, decimalPlaces: 0),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // دکمه حذف
              IconButton(
                onPressed: () => _removeRow(index),
                icon: const Icon(Icons.delete_outline),
                color: Colors.red,
                tooltip: 'حذف',
                iconSize: 24,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // سطر دوم: شرح، تخفیف، مالیات
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 48),
              // شرح
              Expanded(
                child: SizedBox(
                  height: fieldHeight,
                  child: TextFormField(
                    focusNode: _focusNodes[index]?['description'],
                    initialValue: item.description ?? '',
                    onChanged: (v) {
                      _updateRow(index, item.copyWith(description: v));
                    },
                    onFieldSubmitted: (_) => _moveToNextField(index, 'description'),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      contentPadding: _getFieldPadding(context),
                      hintText: t.descriptionOptional,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // تخفیف
              SizedBox(
                width: 200,
                child: SizedBox(
                  height: fieldHeight,
                  child: _DiscountCell(
                    value: item.discountValue,
                    type: item.discountType,
                    onChanged: (type, value) {
                      _updateRow(index, item.copyWith(discountType: type, discountValue: value));
                    },
                    focusNode: _focusNodes[index]?['discount'],
                    onFieldSubmitted: () => _moveToNextField(index, 'discount'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // مالیات
              SizedBox(
                width: 200,
                child: SizedBox(
                  height: fieldHeight,
                  child: _TaxCell(
                    rate: item.taxRate,
                    taxAmount: item.taxAmount,
                    onRateChanged: (r) {
                      _updateRow(index, item.copyWith(taxRate: r));
                    },
                    focusNode: _focusNodes[index]?['tax'],
                    onFieldSubmitted: () => _moveToNextField(index, 'tax'),
                  ),
                ),
              ),
            ],
          ),
          // سطر سوم: نمایش instance های انتخاب شده (فقط برای کالاهای یونیک)
          if (_shouldShowInstanceSelector(item)) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 48),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.qr_code_scanner, size: 18, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: item.selectedInstanceIds != null && item.selectedInstanceIds!.isNotEmpty
                              ? Text(
                                  '${item.selectedInstanceIds!.length} کالای یونیک انتخاب شده',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.blue[900],
                                    fontWeight: FontWeight.w500,
                                  ),
                                )
                              : Text(
                                  'برای انتخاب کالاهای یونیک کلیک کنید',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.blue[700],
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                        ),
                        TextButton.icon(
                          onPressed: () => _selectUniqueProductInstances(index, item),
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          label: Text(
                            item.selectedInstanceIds != null && item.selectedInstanceIds!.isNotEmpty
                                ? 'ویرایش'
                                : 'انتخاب',
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_shouldShowLineAttributesButton(item)) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: 48),
                  Expanded(child: _lineAttributesRow(context, index, item)),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
  
  /// مدیریت تغییر کالا
  Future<void> _handleProductChange(int index, InvoiceLineItem item, Map<String, dynamic>? p) async {
    if (p == null) {
      setState(() {
        final cleanedExtra = Map<String, dynamic>.from(item.extraInfo ?? {});
        cleanedExtra.remove('line_custom_attributes');
        cleanedExtra.removeWhere((key, value) => key.toString().startsWith('_local_'));
        _rows[index] = item.copyWith(
          productId: null,
          productCode: null,
          productName: null,
          mainUnit: null,
          secondaryUnit: null,
          unitConversionFactor: null,
          selectedUnit: null,
          unitPriceSource: 'base',
          unitPrice: 0,
          extraInfo: cleanedExtra.isEmpty ? null : cleanedExtra,
        );
      });
      _notify();
      return;
    }
    
    final mainUnit = p['main_unit']?.toString();
    final secondaryUnit = p['secondary_unit']?.toString();
    final taxRate = _defaultTaxRateFromProduct(p);
    final defaultWarehouseId = _toInt(p['default_warehouse_id']);
    final salesNote = _cleanNote(p['base_sales_note']);
    final purchaseNote = _cleanNote(p['base_purchase_note']);
    final previousAuto = item.extraInfo?['_local_auto_description']?.toString();
    final autoDescription = _noteForInvoiceType(
      widget.invoiceType,
      salesNote: salesNote,
      purchaseNote: purchaseNote,
    );
    final metadata = _mergeExtraInfoWithNotes(
      item,
      salesNote: salesNote,
      purchaseNote: purchaseNote,
    );
    if (autoDescription?.isNotEmpty == true) {
      metadata['_local_auto_description'] = autoDescription;
    } else {
      metadata.remove('_local_auto_description');
    }
    final shouldReplaceDescription = _shouldReplaceDescription(item.description, previousAuto);

    final productId = _toInt(p['id']);
    if (productId != null && productId != item.productId) {
      metadata.remove('line_custom_attributes');
    }

    // ذخیره اطلاعات کالا در cache برای بررسی یونیک بودن
    if (productId != null) {
      _productCache[productId] = Map<String, dynamic>.from(p);
      await _loadProductInfo(productId, force: true);
    }
    
    final updated = item.copyWith(
      productId: productId,
      productCode: p['code']?.toString(),
      productName: p['name']?.toString(),
      mainUnit: mainUnit,
      secondaryUnit: secondaryUnit,
      unitConversionFactor: _toNum(p['unit_conversion_factor'], fallback: 1),
      selectedUnit: mainUnit,
      baseSalesPriceMainUnit: _toNum(p['base_sales_price']),
      basePurchasePriceMainUnit: _toNum(p['base_purchase_price']),
      taxRate: taxRate,
      minOrderQty: _toInt(p['min_order_qty']),
      trackInventory: p['track_inventory'] == true,
      warehouseId: item.warehouseId ?? defaultWarehouseId,
      extraInfo: metadata.isEmpty ? null : metadata,
      description: shouldReplaceDescription ? autoDescription : item.description,
    );
    final priced = await _resolveUnitPrice(updated, preferManual: false);
    setState(() => _rows[index] = priced);
    _notify();
  }

  Widget _buildQuantityWithUnitField(
    InvoiceLineItem item,
    ValueChanged<num> onQuantityChanged,
    ValueChanged<String?> onUnitChanged, {
    FocusNode? focusNode,
    VoidCallback? onFieldSubmitted,
  }) {
    return _QuantityWithUnitField(
      item: item,
      onQuantityChanged: onQuantityChanged,
      onUnitChanged: onUnitChanged,
      onShowUnitSelector: () => _showUnitSelectorDialog(item, onUnitChanged),
      focusNode: focusNode,
      onFieldSubmitted: onFieldSubmitted,
    );
  }


  // فوتر جمع‌ها حذف شد؛ جمع‌ها در صفحهٔ والد نمایش داده می‌شوند

  void _showUnitSelectorDialog(InvoiceLineItem item, ValueChanged<String?> onChanged) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).selectUnitTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.mainUnit?.isNotEmpty == true)
              ListTile(
                leading: const Icon(Icons.straighten),
                title: Text(item.mainUnit!),
                subtitle: Text(AppLocalizations.of(context).mainUnitLabel),
                trailing: (item.selectedUnit == item.mainUnit) ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () {
                  onChanged(item.mainUnit);
                  Navigator.of(context).pop();
                },
              ),
            if (item.secondaryUnit?.isNotEmpty == true)
              ListTile(
                leading: const Icon(Icons.inventory_2),
                title: Text(item.secondaryUnit!),
                subtitle: Text(AppLocalizations.of(context).secondaryUnitLabel),
                trailing: (item.selectedUnit == item.secondaryUnit) ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () {
                  onChanged(item.secondaryUnit);
                  Navigator.of(context).pop();
                },
              ),
            if (item.mainUnit?.isEmpty != false && item.secondaryUnit?.isEmpty != false)
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(AppLocalizations.of(context).noUnitsDefined),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context).cancel),
          ),
        ],
      ),
    );
  }

  // اعتبارسنجی تعداد مستقیماً داخل ویجت مقداردهی می‌شود؛ نیاز به تابع مجزا نیست
}

class _DiscountCell extends StatefulWidget {
  final String type; // percent | amount
  final num value;
  final void Function(String type, num value) onChanged;
  final FocusNode? focusNode;
  final VoidCallback? onFieldSubmitted;

  const _DiscountCell({
    required this.type,
    required this.value,
    required this.onChanged,
    this.focusNode,
    this.onFieldSubmitted,
  });

  @override
  State<_DiscountCell> createState() => _DiscountCellState();
}

class _DiscountCellState extends State<_DiscountCell> {
  late String _type;
  late TextEditingController _ctrl;
  num _lastSentValue = 0;

  String _formatDisplayValue(num value, String type) {
    if (type == 'amount') {
      return formatNumberForInput(value);
    }
    return value.toString();
  }

  @override
  void initState() {
    super.initState();
    _type = widget.type;
    _lastSentValue = widget.value;
    _ctrl = TextEditingController(text: _formatDisplayValue(widget.value, widget.type));
  }

  @override
  void didUpdateWidget(covariant _DiscountCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _type = widget.type;
    // فقط وقتی مقدار از بیرون عوض شده (نه نتیجهٔ تایپ کاربر) متن فیلد را همگام کن
    if (widget.value != _lastSentValue) {
      _lastSentValue = widget.value;
      _ctrl.text = _formatDisplayValue(widget.value, _type);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDiscountChanged(String v) {
    num parsed = parseFormattedNumber(v) ?? 0;
    if (_type == 'percent') {
      parsed = parsed.clamp(0, 100);
      if (parsed != (parseFormattedNumber(v) ?? 0)) {
        _ctrl.text = _formatDisplayValue(parsed, _type);
        _lastSentValue = parsed;
        widget.onChanged(_type, parsed);
        return;
      }
    }
    _lastSentValue = parsed;
    widget.onChanged(_type, parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);
    final fieldHeight = ResponsiveHelper.responsiveValue(
      context,
      mobile: 56.0,
      tablet: 52.0,
      desktop: 48.0,
    );
    final fieldPadding = ResponsiveHelper.isMobile(context)
        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 10);
    String typeLabel(String tp) => tp == 'percent' ? t.percent : t.amount;
    return SizedBox(
      height: fieldHeight,
      child: TextFormField(
        focusNode: widget.focusNode,
        controller: _ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          EnglishDigitsFormatter(),
          ThousandsSeparatorInputFormatter(allowDecimal: _type != 'percent'),
          FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
        ],
        onChanged: _onDiscountChanged,
        onFieldSubmitted: (_) => widget.onFieldSubmitted?.call(),
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          contentPadding: fieldPadding,
          suffix: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_type == 'percent')
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: Text('%', style: theme.textTheme.bodySmall),
                )
              else
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: Text(typeLabel(_type), style: theme.textTheme.bodySmall),
                ),
              PopupMenuButton<String>(
                tooltip: t.discountType,
                padding: EdgeInsets.zero,
                itemBuilder: (c) => [
                  PopupMenuItem<String>(
                    value: 'amount',
                    child: Text(t.amount),
                  ),
                  PopupMenuItem<String>(
                    value: 'percent',
                    child: Text(t.percent),
                  ),
                ],
                onSelected: (nv) {
                  final parsed = parseFormattedNumber(_ctrl.text) ?? 0;
                  final value = nv == 'percent' ? parsed.clamp(0, 100) : parsed;
                  setState(() {
                    _type = nv;
                    _lastSentValue = value;
                    _ctrl.text = _formatDisplayValue(value, nv);
                  });
                  widget.onChanged(nv, value);
                },
                child: const Icon(Icons.arrow_drop_down, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaxCell extends StatefulWidget {
  final num rate; // editable percent
  final num taxAmount; // readonly
  final ValueChanged<num> onRateChanged;
  final FocusNode? focusNode;
  final VoidCallback? onFieldSubmitted;

  const _TaxCell({
    required this.rate,
    required this.taxAmount,
    required this.onRateChanged,
    this.focusNode,
    this.onFieldSubmitted,
  });

  @override
  State<_TaxCell> createState() => _TaxCellState();
}

class _TaxCellState extends State<_TaxCell> {
  late TextEditingController _controller;
  bool _isUserTyping = false;
  late TextEditingController _amountCtrl;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.rate.toString());
    _amountCtrl = TextEditingController(text: formatWithThousands(widget.taxAmount, decimalPlaces: 0));
  }

  @override
  void didUpdateWidget(_TaxCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // فقط اگر کاربر در حال تایپ نیست، مقدار را به‌روزرسانی کن
    if (oldWidget.rate != widget.rate && !_isUserTyping) {
      _controller.text = widget.rate.toString();
    }
    if (oldWidget.taxAmount != widget.taxAmount) {
      _amountCtrl.text = formatWithThousands(widget.taxAmount, decimalPlaces: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fieldHeight = ResponsiveHelper.responsiveValue(
      context,
      mobile: 56.0,
      tablet: 52.0,
      desktop: 48.0,
    );
    final fieldPadding = ResponsiveHelper.isMobile(context)
        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 10);
    
    return Row(
      children: [
        SizedBox(
          width: 70,
          height: fieldHeight,
          child: TextFormField(
            focusNode: widget.focusNode,
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              EnglishDigitsFormatter(),
              FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
            ],
            onChanged: (v) {
              _isUserTyping = true;
              widget.onRateChanged(num.tryParse(v) ?? 0);
              // بعد از یک فریم، فلگ را ریست کن
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _isUserTyping = false;
                }
              });
            },
            onFieldSubmitted: (_) => widget.onFieldSubmitted?.call(),
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              contentPadding: fieldPadding,
              suffixText: '%',
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: fieldHeight,
            child: TextFormField(
              controller: _amountCtrl,
              readOnly: true,
              enableInteractiveSelection: false,
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                contentPadding: fieldPadding,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UnitPriceCell extends StatefulWidget {
  final int businessId;
  final String invoiceType;
  final int? currencyId;
  final InvoiceLineItem item;
  final void Function(String source, num price) onChanged;
  final Future<InvoiceLineItem> Function() resolver;
  final String Function(String? unit) unitTitleResolver;
  final FocusNode? focusNode;
  final VoidCallback? onFieldSubmitted;

  const _UnitPriceCell({
    required this.businessId,
    required this.invoiceType,
    required this.currencyId,
    required this.item,
    required this.onChanged,
    required this.resolver,
    required this.unitTitleResolver,
    this.focusNode,
    this.onFieldSubmitted,
  });

  @override
  State<_UnitPriceCell> createState() => _UnitPriceCellState();
}

class _UnitPriceCellState extends State<_UnitPriceCell> {
  late TextEditingController _ctrl;
  final bool _loading = false;
  final PriceListService _pls = PriceListService(apiClient: ApiClient());
  late FocusNode _focusNode;
  bool _isUserTyping = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: formatNumberForInput(widget.item.unitPrice, decimalPlaces: 0));
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _UnitPriceCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // فقط اگر کاربر در حال تایپ نیست، مقدار را به‌روزرسانی کن
    if ((oldWidget.item.unitPrice != widget.item.unitPrice || oldWidget.item.unitPriceSource != widget.item.unitPriceSource) &&
        !_isUserTyping) {
      _ctrl.text = formatNumberForInput(widget.item.unitPrice, decimalPlaces: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // حذف شد: _applySource (مدل جدید نیازی ندارد)

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final fieldHeight = ResponsiveHelper.responsiveValue(
      context,
      mobile: 56.0,
      tablet: 52.0,
      desktop: 48.0,
    );
    final fieldPadding = ResponsiveHelper.isMobile(context)
        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 10);
    
    // استفاده از focusNode خارجی اگر موجود باشد، در غیر این صورت از داخلی
    final effectiveFocusNode = widget.focusNode ?? _focusNode;
    
    return SizedBox(
      height: fieldHeight,
      child: TextFormField(
        controller: _ctrl,
        focusNode: effectiveFocusNode,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: const [
          EnglishDigitsFormatter(),
          ThousandsSeparatorInputFormatter(allowDecimal: true),
        ],
        onChanged: (v) {
          _isUserTyping = true;
          final price = parseFormattedDouble(v) ?? 0;
          widget.onChanged('manual', price < 0 ? 0 : price);
          // بعد از یک فریم، فلگ را ریست کن
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _isUserTyping = false;
            }
          });
        },
        onFieldSubmitted: (_) => widget.onFieldSubmitted?.call(),
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          contentPadding: fieldPadding,
          suffixIcon: _loading
              ? const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(
                  tooltip: t.pricePickFromList,
                  icon: const Icon(Icons.list_alt_outlined),
                  onPressed: () => _openPricePicker(context),
                ),
        ),
      ),
    );
  }

  Future<void> _openPricePicker(BuildContext context) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final t = AppLocalizations.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _fetchPriceOptions(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
                }
                final options = snapshot.data ?? const <Map<String, dynamic>>[];
                if (options.isEmpty) {
                  return SizedBox(height: 200, child: Center(child: Text(t.noPricesFound)));
                }
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 400),
                  child: ListView.separated(
                    itemCount: options.length,
                    separatorBuilder: (separatorContext, separatorIndex) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final opt = options[index];
                      final price = (opt['price'] as num?) ?? 0;
                      final label = (opt['label'] as String?) ?? '';
                      return ListTile(
                        leading: const Icon(Icons.sell_outlined),
                        title: Text(formatWithThousands(price, decimalPlaces: 0)),
                        subtitle: label.isNotEmpty ? Text(label) : null,
                        onTap: () {
                          _ctrl.text = price.toString();
                          widget.onChanged('manual', price);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _fetchPriceOptions() async {
    final List<Map<String, dynamic>> result = <Map<String, dynamic>>[];
    
    // گزینه ۱: قیمت پایه (بر اساس نوع فاکتور و تبدیل واحد)
    if (!context.mounted) return result;
    final ctx = context;
    try {
      final resolved = await widget.resolver();
      if (!ctx.mounted) return result;
      result.add(<String, dynamic>{
        'label': AppLocalizations.of(ctx).baseEstimatedPrice,
        'price': resolved.unitPrice,
      });
    } catch (_) {}

    // گزینه‌های لیست قیمت (در صورت داشتن ارز و محصول)
    final productId = widget.item.productId;
    final currencyId = widget.currencyId;
    
    if (productId != null && currencyId != null) {
      if (!ctx.mounted) return result;
      try {
        final res = await _pls.listPriceLists(businessId: widget.businessId, limit: 50);
        if (!ctx.mounted) return result;
        final lists = (res['items'] as List?)?.cast<dynamic>().map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? const <Map<String, dynamic>>[];
        
        for (final pl in lists) {
          final plId = pl['id'] as int?;
          if (!ctx.mounted) return result;
          final plName = pl['name']?.toString() ?? AppLocalizations.of(ctx).priceListLabel;
          if (plId == null) continue;
          
          try {
            final items = await _pls.listItems(
              businessId: widget.businessId,
              priceListId: plId,
              productId: productId,
              currencyId: currencyId,
            );
            
            for (final pi in items) {
              final priceValue = pi['price'];
              num? price;
              
              // تبدیل قیمت از String به num
              if (priceValue is num) {
                price = priceValue;
              } else if (priceValue is String) {
                price = num.tryParse(priceValue);
              } else {
                price = 0;
              }
              
              if (price == null || price <= 0) continue;
              if (!ctx.mounted) return result;
              final unitLabel = AppLocalizations.of(ctx).mainUnitLabel; // چون unit_id null است، یعنی واحد اصلی
              result.add(<String, dynamic>{
                'label': '$plName - $unitLabel',
                'price': price,
              });
            }
          } catch (_) {
            // ignore per list errors
          }
        }
      } catch (_) {
        // ignore
      }
    }
    // مرتب‌سازی: نزدیک‌ترین قیمت به مقدار فعلی در ابتدای لیست
    final current = num.tryParse(_ctrl.text) ?? widget.item.unitPrice;
    result.sort((a, b) {
      final pa = (a['price'] as num?) ?? 0;
      final pb = (b['price'] as num?) ?? 0;
      return (pa - current).abs().compareTo((pb - current).abs());
    });
    return result;
  }

  // حذف شد: _unitLabelFor (با unitTitleResolver جایگزین شده)
}

class _QuantityWithUnitField extends StatefulWidget {
  final InvoiceLineItem item;
  final ValueChanged<num> onQuantityChanged;
  final ValueChanged<String?> onUnitChanged;
  final VoidCallback onShowUnitSelector;
  final FocusNode? focusNode;
  final VoidCallback? onFieldSubmitted;

  const _QuantityWithUnitField({
    required this.item,
    required this.onQuantityChanged,
    required this.onUnitChanged,
    required this.onShowUnitSelector,
    this.focusNode,
    this.onFieldSubmitted,
  });

  @override
  State<_QuantityWithUnitField> createState() => _QuantityWithUnitFieldState();
}

class _QuantityWithUnitFieldState extends State<_QuantityWithUnitField> {
  late TextEditingController _controller;
  String? _currentUnit;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _currentUnit = widget.item.selectedUnit ?? widget.item.mainUnit;
    _updateController();
  }

  @override
  void didUpdateWidget(_QuantityWithUnitField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.quantity != widget.item.quantity || 
        oldWidget.item.selectedUnit != widget.item.selectedUnit) {
      _currentUnit = widget.item.selectedUnit ?? widget.item.mainUnit;
      _updateController();
    }
  }

  void _updateController() {
    // فقط مقدار عددی را در فیلد نگه می‌داریم؛ واحد به‌صورت لیبل در suffix نمایش داده می‌شود
    // فقط اگر کاربر در حال تایپ نیست، کنترلر را به‌روزرسانی کن
    if (!_controller.text.isNotEmpty) {
      _controller.text = widget.item.quantity.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fieldHeight = ResponsiveHelper.responsiveValue(
      context,
      mobile: 56.0,
      tablet: 52.0,
      desktop: 48.0,
    );
    final fieldPadding = ResponsiveHelper.isMobile(context)
        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 10);
    
    return SizedBox(
      height: fieldHeight,
      child: TextFormField(
        focusNode: widget.focusNode,
        controller: _controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          EnglishDigitsFormatter(),
          FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
        ],
        onChanged: (v) {
          // فقط عدد ورودی کاربر را می‌خوانیم
          final cleaned = v.replaceAll(',', '');
          final q = num.tryParse(cleaned) ?? 0;
          widget.onQuantityChanged(q);
        },
        onFieldSubmitted: (_) => widget.onFieldSubmitted?.call(),
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          contentPadding: fieldPadding,
          // نمایش واحد به صورت لیبل غیرقابل ویرایش در کنار دکمه انتخاب
          suffix: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_currentUnit != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: Text(
                    _currentUnit!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.arrow_drop_down, size: 20),
                onPressed: widget.onShowUnitSelector,
                tooltip: 'انتخاب واحد',
              ),
            ],
          ),
        ),
      ),
    );
  }
}



