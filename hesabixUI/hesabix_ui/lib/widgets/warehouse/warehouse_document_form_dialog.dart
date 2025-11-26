import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../../services/warehouse_service.dart';
import '../../services/product_service.dart';
import '../../services/product_attribute_service.dart';
import '../../widgets/invoice/product_combobox_widget.dart';
import '../../widgets/invoice/warehouse_combobox_widget.dart';
import '../../widgets/date_input_field.dart';
import '../../core/calendar_controller.dart';
import '../../utils/number_normalizer.dart' show parseFormattedNumber;
import '../../utils/responsive_helper.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;
import 'product_instance_form_dialog.dart';
import 'unique_product_selector_dialog.dart';

class WarehouseDocumentFormDialog extends StatefulWidget {
  final int businessId;
  final VoidCallback? onSuccess;
  final String? initialDocType;
  final DateTime? initialDocumentDate;
  final List<Map<String, dynamic>>? initialLines;
  final int? sourceInvoiceId;
  final String? sourceInvoiceCode;
  final String? sourceInvoiceType;
  final bool lockDocType;
  final CalendarController? calendarController;

  const WarehouseDocumentFormDialog({
    super.key,
    required this.businessId,
    this.onSuccess,
    this.initialDocType,
    this.initialDocumentDate,
    this.initialLines,
    this.sourceInvoiceId,
    this.sourceInvoiceCode,
    this.sourceInvoiceType,
    this.lockDocType = false,
    this.calendarController,
  });

  @override
  State<WarehouseDocumentFormDialog> createState() => _WarehouseDocumentFormDialogState();
}

class _WarehouseDocumentFormDialogState extends State<WarehouseDocumentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _svc = WarehouseService();
  final _productService = ProductService();
  final _attributeService = ProductAttributeService();
  CalendarController? _calendarController;
  
  // اطلاعات کالاها برای بررسی یونیک بودن
  final Map<int, Map<String, dynamic>> _productCache = {}; // product_id -> product data
  final Map<int, List<Map<String, dynamic>>> _productAttributesCache = {}; // product_id -> attributes
  
  String? _docType;
  DateTime? _documentDate;
  int? _warehouseIdFrom;
  int? _warehouseIdTo;
  final List<Map<String, dynamic>> _lines = [];
  bool _saving = false;
  // فیلدهای ارسال
  String? _description;
  String? _deliveryMethod;
  String? _carrierName;
  String? _recipientName;
  String? _recipientPhone;
  String? _trackingNumber;
  // اطلاعات مقادیر خطوط فاکتور (مورد نیاز، از قبل، باقی مانده)
  Map<int, Map<String, double>> _lineQuantities = {}; // product_id -> {required, processed, remaining}
  bool _loadingQuantities = false;
  bool get _isFromInvoice => widget.sourceInvoiceId != null;
  bool get _isDocTypeLocked => widget.lockDocType || _isFromInvoice;
  
  // بررسی نیاز به نمایش فیلد نام باربری
  bool get _showCarrierName => _deliveryMethod != null && 
    ['freight', 'bus', 'tipax', 'courier'].contains(_deliveryMethod);

  String _movementForDocType(String? docType) {
    if (docType == 'issue' || docType == 'production_out') {
      return 'out';
    }
    return 'in';
  }

  void _syncLineMovementsForDocType() {
    if (_docType == 'adjustment' || _docType == 'transfer') return;
    final movement = _movementForDocType(_docType);
    for (var i = 0; i < _lines.length; i++) {
      _lines[i] = {..._lines[i], 'movement': movement};
    }
  }

  int? _defaultWarehouseForMovement(String? movement) {
    if (movement == 'out') return _warehouseIdFrom;
    if (movement == 'in') return _warehouseIdTo;
    return null;
  }

  List<Map<String, dynamic>> _buildLinePayloads() {
    return _lines.map((line) {
      final movement = (line['movement'] as String?) ?? _movementForDocType(_docType);
      final lineWarehouse = line['warehouse_id'] ?? _defaultWarehouseForMovement(movement);
      final extra = Map<String, dynamic>.from(line['extra_info'] ?? const {});
      if (!extra.containsKey('movement')) {
        extra['movement'] = movement;
      }
      
      // برای کالاهای یونیک، instance_data یا instance_ids را اضافه می‌کنیم
      final instanceData = line['instance_data'] as List<dynamic>?;
      final instanceIds = line['instance_ids'] as List<dynamic>?;
      
      // برای transfer، از انبار سطح حواله استفاده می‌کنیم
      if (_docType == 'transfer') {
        return {
          'product_id': line['product_id'],
          'warehouse_id_from': line['warehouse_id_from'] ?? _warehouseIdFrom,
          'warehouse_id_to': line['warehouse_id_to'] ?? _warehouseIdTo,
          'quantity': line['quantity'],
          'instance_data': instanceData, // برای حواله ورود
          'instance_ids': instanceIds, // برای حواله خروج
          'extra_info': extra,
        };
      }
      
      return {
        'product_id': line['product_id'],
        'warehouse_id': lineWarehouse,
        'movement': movement,
        'quantity': line['quantity'],
        'instance_data': instanceData, // برای حواله ورود (receipt/production_in)
        'instance_ids': instanceIds, // برای حواله خروج (issue/production_out)
        'extra_info': extra,
      };
    }).toList();
  }

  Widget _buildQuantityRow(String label, double value, BuildContext context, {bool isRemaining = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          formatWithThousands(value, decimalPlaces: 2),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: isRemaining && value > 0
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildSourceBanner() {
    final theme = Theme.of(context);
    final invoiceLabel = widget.sourceInvoiceCode ?? '#${widget.sourceInvoiceId}';
    final typeLabel = widget.sourceInvoiceType ?? '';
    return Card(
      color: theme.colorScheme.primaryContainer.withOpacity(0.4),
      elevation: 0,
      child: ListTile(
        leading: Icon(Icons.receipt_long, color: theme.colorScheme.primary),
        title: Text('ایجاد حواله برای فاکتور $invoiceLabel'),
        subtitle: Text(
          typeLabel.isNotEmpty ? 'نوع فاکتور: $typeLabel' : 'شناسه: ${widget.sourceInvoiceId}',
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _docType = widget.initialDocType;
    _documentDate = widget.initialDocumentDate ?? DateTime.now();
    _loadCalendarController();
    if (widget.initialLines != null && widget.initialLines!.isNotEmpty) {
      for (final raw in widget.initialLines!) {
        final normalized = Map<String, dynamic>.from(raw);
        normalized['extra_info'] = Map<String, dynamic>.from(normalized['extra_info'] ?? const {});
        normalized['movement'] ??= _movementForDocType(_docType);
        _lines.add(normalized);
      }
      // تکمیل خودکار انبار از فاکتور (فقط برای حواله‌های از فاکتور)
      if (_isFromInvoice) {
        _autoFillWarehouseFromInvoice();
      }
    }
    // بارگذاری اطلاعات مقادیر خطوط فاکتور
    if (_isFromInvoice && widget.sourceInvoiceId != null) {
      _loadLineQuantities();
    }
    // مقداردهی اولیه فیلدهای ارسال (در صورت ویرایش)
    // این فیلدها از extra_info در صورت ویرایش حواله موجود می‌آیند
  }

  void _autoFillWarehouseFromInvoice() {
    // اگر انبار از قبل انتخاب شده، نیازی به تکمیل خودکار نیست
    if (_docType == 'transfer') {
      if (_warehouseIdFrom != null && _warehouseIdTo != null) return;
    } else if (_docType == 'issue' || _docType == 'production_out') {
      if (_warehouseIdFrom != null) return;
    } else if (_docType == 'receipt' || _docType == 'production_in') {
      if (_warehouseIdTo != null) return;
    }
    
    // استخراج انبار از خطوط فاکتور
    int? foundWarehouseId;
    for (final line in _lines) {
      final warehouseId = line['warehouse_id'] as int?;
      if (warehouseId != null) {
        foundWarehouseId = warehouseId;
        break; // اولین انبار غیر null را می‌گیریم
      }
    }
    
    if (foundWarehouseId == null) return;
    
    // تنظیم انبار بر اساس نوع حواله
    setState(() {
      if (_docType == 'transfer') {
        // برای انتقال، از انبار خط به عنوان مبدا استفاده می‌کنیم
        // مقصد باید توسط کاربر انتخاب شود
        if (_warehouseIdFrom == null) {
          _warehouseIdFrom = foundWarehouseId;
        }
      } else if (_docType == 'issue' || _docType == 'production_out') {
        // برای خروج: از انبار خط استفاده می‌کنیم
        _warehouseIdFrom = foundWarehouseId;
      } else if (_docType == 'receipt' || _docType == 'production_in') {
        // برای ورود: از انبار خط استفاده می‌کنیم
        _warehouseIdTo = foundWarehouseId;
      }
    });
  }

  Future<void> _loadLineQuantities() async {
    if (widget.sourceInvoiceId == null) return;
    setState(() => _loadingQuantities = true);
    try {
      final data = await _svc.getInvoiceLineQuantities(
        businessId: widget.businessId,
        invoiceId: widget.sourceInvoiceId!,
      );
      final lines = (data['lines'] as List<dynamic>? ?? []);
      final quantities = <int, Map<String, double>>{};
      for (final line in lines) {
        final map = Map<String, dynamic>.from(line as Map);
        final productId = map['product_id'] as int?;
        if (productId != null) {
          quantities[productId] = {
            'required': (map['required_quantity'] as num?)?.toDouble() ?? 0.0,
            'processed': (map['processed_quantity'] as num?)?.toDouble() ?? 0.0,
            'remaining': (map['remaining_quantity'] as num?)?.toDouble() ?? 0.0,
          };
        }
      }
      if (mounted) {
        setState(() {
          _lineQuantities = quantities;
          _loadingQuantities = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingQuantities = false);
      }
      debugPrint('Error loading line quantities: $e');
    }
  }

  Future<void> _loadCalendarController() async {
    if (widget.calendarController != null) {
      _calendarController = widget.calendarController;
    } else {
      _calendarController = await CalendarController.load();
    }
    if (mounted) {
      setState(() {});
    }
  }


  void _addLine() {
    setState(() {
      _lines.add({
        'product_id': null,
        'warehouse_id': null,
        'movement': _movementForDocType(_docType),
        'quantity': 0.0,
        'extra_info': <String, dynamic>{},
      });
    });
  }

  void _removeLine(int index) {
    setState(() {
      _lines.removeAt(index);
    });
  }

  void _updateLine(int index, Map<String, dynamic> updates) {
    setState(() {
      _lines[index] = {..._lines[index], ...updates};
    });
  }

  Future<void> _loadProductInfo(int productId) async {
    if (_productCache.containsKey(productId)) return;
    
    try {
      final product = await _productService.getProduct(
        businessId: widget.businessId,
        productId: productId,
      );
      _productCache[productId] = product;
      
      // بارگذاری ویژگی‌های کالا
      if (product['attribute_ids'] != null) {
        final attrIds = (product['attribute_ids'] as List<dynamic>?) ?? [];
        if (attrIds.isNotEmpty) {
          try {
            final result = await _attributeService.search(
              businessId: widget.businessId,
              limit: 1000, // دریافت همه ویژگی‌ها
            );
            final allAttributes = (result['items'] as List<dynamic>?) ?? [];
            final productAttrs = allAttributes.where((attr) {
              final attrId = attr['id'] as int?;
              return attrId != null && attrIds.contains(attrId);
            }).map((attr) => Map<String, dynamic>.from(attr as Map)).toList();
            _productAttributesCache[productId] = productAttrs;
          } catch (e) {
            debugPrint('Error loading product attributes: $e');
            _productAttributesCache[productId] = [];
          }
        } else {
          _productAttributesCache[productId] = [];
        }
      } else {
        _productAttributesCache[productId] = [];
      }
    } catch (e) {
      debugPrint('Error loading product info: $e');
    }
  }

  bool _isProductUnique(int productId) {
    final product = _productCache[productId];
    if (product == null) return false;
    return product['inventory_mode'] == 'unique';
  }

  Future<void> _registerUniqueProductInstances(int lineIndex) async {
    final line = _lines[lineIndex];
    final productId = line['product_id'] as int?;
    if (productId == null) return;
    
    // بارگذاری اطلاعات کالا
    await _loadProductInfo(productId);
    
    if (!_isProductUnique(productId)) return;
    
    final product = _productCache[productId]!;
    final productName = product['name']?.toString() ?? 'کالا';
    final trackSerial = product['track_serial'] == true;
    final trackBarcode = product['track_barcode'] == true;
    final attributes = _productAttributesCache[productId] ?? [];
    
    final quantity = (line['quantity'] as num?)?.toInt() ?? 0;
    if (quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لطفاً ابتدا تعداد را وارد کنید')),
      );
      return;
    }
    
    // لیست instance های ثبت شده
    final List<Map<String, dynamic>> instances = [];
    
    // ثبت اطلاعات برای هر واحد
    for (int i = 0; i < quantity; i++) {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => ProductInstanceFormDialog(
          businessId: widget.businessId,
          productId: productId,
          productName: productName,
          trackSerial: trackSerial,
          trackBarcode: trackBarcode,
          productAttributes: attributes,
        ),
      );
      
      if (result == null) {
        // کاربر انصراف داد
        return;
      }
      
      instances.add(result);
    }
    
    // ذخیره instance_data در خط
    _updateLine(lineIndex, {
      'instance_data': instances,
      'quantity': quantity.toDouble(),
    });
  }

  Future<void> _selectUniqueProductInstances(int lineIndex) async {
    final line = _lines[lineIndex];
    final productId = line['product_id'] as int?;
    if (productId == null) return;
    
    // بارگذاری اطلاعات کالا
    await _loadProductInfo(productId);
    
    if (!_isProductUnique(productId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('این کالا در حالت یونیک نیست')),
      );
      return;
    }
    
    final product = _productCache[productId]!;
    final productName = product['name']?.toString() ?? 'کالا';
    final quantity = (line['quantity'] as num?)?.toInt();
    final warehouseId = _warehouseIdFrom ?? line['warehouse_id'] as int?;
    
    // نمایش دیالوگ انتخاب
    final selectedIds = await showDialog<List<int>>(
      context: context,
      builder: (context) => UniqueProductSelectorDialog(
        businessId: widget.businessId,
        productId: productId,
        productName: productName,
        warehouseId: warehouseId,
        selectedInstanceIds: line['instance_ids'] as List<int>?,
        requiredQuantity: quantity,
      ),
    );
    
    if (selectedIds != null && selectedIds.isNotEmpty) {
      _updateLine(lineIndex, {
        'instance_ids': selectedIds,
        'quantity': selectedIds.length.toDouble(),
      });
    }
  }

  void _autoCompleteLine(int index) {
    final line = _lines[index];
    final productId = line['product_id'] as int?;
    if (productId == null) return;
    
    final quantities = _lineQuantities[productId];
    if (quantities == null) return;
    
    final remaining = quantities['remaining'] ?? 0.0;
    if (remaining > 0) {
      _updateLine(index, {'quantity': remaining});
    }
  }

  void _autoCompleteAllLines() {
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      final productId = line['product_id'] as int?;
      if (productId == null) continue;
      
      final quantities = _lineQuantities[productId];
      if (quantities == null) continue;
      
      final remaining = quantities['remaining'] ?? 0.0;
      if (remaining > 0) {
        _updateLine(i, {'quantity': remaining});
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_docType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لطفاً نوع حواله را انتخاب کنید')),
      );
      return;
    }
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لطفاً حداقل یک خط اضافه کنید')),
      );
      return;
    }

    // اعتبارسنجی انبارها
    if (_docType == 'transfer') {
      if (_warehouseIdFrom == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لطفاً انبار مبدا را انتخاب کنید')),
        );
        return;
      }
      if (_warehouseIdTo == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لطفاً انبار مقصد را انتخاب کنید')),
        );
        return;
      }
    } else if (_docType == 'issue' || _docType == 'production_out') {
      if (_warehouseIdFrom == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لطفاً انبار را انتخاب کنید')),
        );
        return;
      }
    } else if (_docType == 'receipt' || _docType == 'production_in') {
      if (_warehouseIdTo == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لطفاً انبار را انتخاب کنید')),
        );
        return;
      }
    }

    // اعتبارسنجی خطوط
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      if (line['product_id'] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خط ${i + 1}: لطفاً محصول را انتخاب کنید')),
        );
        return;
      }
      if ((line['quantity'] as num?) == null || (line['quantity'] as num) <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خط ${i + 1}: تعداد باید مثبت باشد')),
        );
        return;
      }
      // اعتبارسنجی انبار در خط (فقط برای adjustment)
      if (_docType == 'adjustment') {
        if (line['warehouse_id'] == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خط ${i + 1}: لطفاً انبار را انتخاب کنید')),
          );
          return;
        }
      }
    }

    setState(() => _saving = true);
    try {
      if (_isFromInvoice) {
        await _saveFromInvoice();
      } else {
        await _saveManual();
      }
    } catch (e) {
      if (!mounted) return;
      final errorMessage = e.toString().contains('Exception:')
          ? e.toString().split('Exception:').last.trim()
          : 'خطا در ذخیره حواله. لطفاً دوباره تلاش کنید.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _saveManual() async {
    final payload = {
      'doc_type': _docType,
      'document_date': _documentDate?.toIso8601String().split('T')[0],
      'warehouse_id_from': _warehouseIdFrom,
      'warehouse_id_to': _warehouseIdTo,
      'lines': _buildLinePayloads(),
      // فیلدهای ارسال
      if (_description != null && _description!.isNotEmpty) 'description': _description,
      if (_deliveryMethod != null && _deliveryMethod!.isNotEmpty) 'delivery_method': _deliveryMethod,
      if (_carrierName != null && _carrierName!.isNotEmpty) 'carrier_name': _carrierName,
      if (_recipientName != null && _recipientName!.isNotEmpty) 'recipient_name': _recipientName,
      if (_recipientPhone != null && _recipientPhone!.isNotEmpty) 'recipient_phone': _recipientPhone,
      if (_trackingNumber != null && _trackingNumber!.isNotEmpty) 'tracking_number': _trackingNumber,
    };

    await _svc.createManual(businessId: widget.businessId, payload: payload);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('حواله ایجاد شد')),
    );
    Navigator.of(context).pop();
    widget.onSuccess?.call();
  }

  Future<void> _saveFromInvoice() async {
    final payload = {
      'doc_type': _docType,
      'lines': _buildLinePayloads(),
      // فیلدهای ارسال
      if (_description != null && _description!.isNotEmpty) 'description': _description,
      if (_deliveryMethod != null && _deliveryMethod!.isNotEmpty) 'delivery_method': _deliveryMethod,
      if (_carrierName != null && _carrierName!.isNotEmpty) 'carrier_name': _carrierName,
      if (_recipientName != null && _recipientName!.isNotEmpty) 'recipient_name': _recipientName,
      if (_recipientPhone != null && _recipientPhone!.isNotEmpty) 'recipient_phone': _recipientPhone,
      if (_trackingNumber != null && _trackingNumber!.isNotEmpty) 'tracking_number': _trackingNumber,
    };

    await _svc.createFromInvoice(
      businessId: widget.businessId,
      invoiceId: widget.sourceInvoiceId!,
      body: payload,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('حواله از فاکتور ثبت شد')),
    );
    Navigator.of(context).pop();
    widget.onSuccess?.call();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final screenHeight = media.size.height;
    final isMobile = ResponsiveHelper.isMobile(context);
    final isTablet = screenWidth >= 600 && screenWidth < 1024;

    final dialogWidth = isMobile
        ? screenWidth * 0.95
        : isTablet
            ? screenWidth * 0.85
            : screenWidth > 1400
                ? 1200.0
                : screenWidth > 1200
                    ? 1100.0
                    : screenWidth * 0.85;

    final dialogHeight = isMobile ? screenHeight * 0.9 : 850.0;

    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: EdgeInsets.all(isMobile ? 8 : 16),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: dialogWidth,
            maxHeight: screenHeight * 0.9,
          ),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isFromInvoice ? 'ایجاد حواله از فاکتور' : 'ایجاد حواله دستی',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    tooltip: 'بستن',
                  ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: dialogHeight,
                  minHeight: isMobile ? 300 : 500,
                ),
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                if (_isFromInvoice) ...[
                  _buildSourceBanner(),
                  const SizedBox(height: 16),
                ],
                // نوع حواله
                DropdownButtonFormField<String>(
                  value: _docType,
                  decoration: const InputDecoration(
                    labelText: 'نوع حواله *',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'receipt', child: Text('حواله ورود')),
                    DropdownMenuItem(value: 'issue', child: Text('حواله خروج')),
                    DropdownMenuItem(value: 'transfer', child: Text('انتقال بین انبارها')),
                    DropdownMenuItem(value: 'adjustment', child: Text('تعدیل موجودی')),
                    DropdownMenuItem(value: 'production_in', child: Text('ورود تولید')),
                    DropdownMenuItem(value: 'production_out', child: Text('خروج تولید')),
                  ],
                  onChanged: _isDocTypeLocked
                      ? null
                      : (value) {
                          setState(() {
                            _docType = value;
                            _syncLineMovementsForDocType();
                          });
                        },
                  validator: (value) => value == null ? 'لطفاً نوع حواله را انتخاب کنید' : null,
                ),
                const SizedBox(height: 16),
                // تاریخ
                if (_calendarController != null)
                  DateInputField(
                    value: _documentDate,
                    calendarController: _calendarController!,
                    onChanged: (date) => setState(() => _documentDate = date),
                    labelText: 'تاریخ *',
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  )
                else
                  const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 16),
                // انبارها بر اساس نوع حواله
                if (_docType == 'transfer') ...[
                  WarehouseComboboxWidget(
                    businessId: widget.businessId,
                    selectedWarehouseId: _warehouseIdFrom,
                    onChanged: (id) => setState(() => _warehouseIdFrom = id),
                    label: 'انبار مبدا *',
                  ),
                  const SizedBox(height: 16),
                  WarehouseComboboxWidget(
                    businessId: widget.businessId,
                    selectedWarehouseId: _warehouseIdTo,
                    onChanged: (id) => setState(() => _warehouseIdTo = id),
                    label: 'انبار مقصد *',
                  ),
                ] else if (_docType == 'issue' || _docType == 'production_out') ...[
                  WarehouseComboboxWidget(
                    businessId: widget.businessId,
                    selectedWarehouseId: _warehouseIdFrom,
                    onChanged: (id) => setState(() => _warehouseIdFrom = id),
                    label: 'انبار *',
                  ),
                ] else if (_docType == 'receipt' || _docType == 'production_in') ...[
                  WarehouseComboboxWidget(
                    businessId: widget.businessId,
                    selectedWarehouseId: _warehouseIdTo,
                    onChanged: (id) => setState(() => _warehouseIdTo = id),
                    label: 'انبار *',
                  ),
                ],
                const SizedBox(height: 16),
                // بخش اطلاعات ارسال
                Card(
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.local_shipping, size: 20, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'اطلاعات ارسال',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // شرح حواله
                        TextFormField(
                          initialValue: _description,
                          decoration: const InputDecoration(
                            labelText: 'شرح/توضیحات حواله',
                            border: OutlineInputBorder(),
                            hintText: 'توضیحات اختیاری درباره حواله',
                          ),
                          maxLines: 2,
                          onChanged: (value) => setState(() => _description = value.isEmpty ? null : value),
                        ),
                        const SizedBox(height: 16),
                        // روش ارسال
                        DropdownButtonFormField<String>(
                          value: _deliveryMethod,
                          decoration: const InputDecoration(
                            labelText: 'روش ارسال',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'warehouse_door', child: Text('تحویل درب انبار')),
                            DropdownMenuItem(value: 'post_regular', child: Text('پست عادی')),
                            DropdownMenuItem(value: 'post_express', child: Text('پست پیشتاز')),
                            DropdownMenuItem(value: 'freight', child: Text('باربری')),
                            DropdownMenuItem(value: 'bus', child: Text('اتوبوس')),
                            DropdownMenuItem(value: 'tipax', child: Text('تیپاکس')),
                            DropdownMenuItem(value: 'courier', child: Text('پیک')),
                          ],
                          onChanged: (value) => setState(() => _deliveryMethod = value),
                        ),
                        // نام باربری (فقط برای روش‌های خاص)
                        if (_showCarrierName) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            initialValue: _carrierName,
                            decoration: const InputDecoration(
                              labelText: 'نام باربری/حمل و نقل',
                              border: OutlineInputBorder(),
                              hintText: 'مثال: باربری تهران',
                            ),
                            onChanged: (value) => setState(() => _carrierName = value.isEmpty ? null : value),
                          ),
                        ],
                        const SizedBox(height: 16),
                        // تحویل گیرنده و تلفن در یک ردیف (در دسکتاپ)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isMobile = constraints.maxWidth < 600;
                            if (isMobile) {
                              return Column(
                                children: [
                                  TextFormField(
                                    initialValue: _recipientName,
                                    decoration: const InputDecoration(
                                      labelText: 'تحویل گیرنده',
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (value) => setState(() => _recipientName = value.isEmpty ? null : value),
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    initialValue: _recipientPhone,
                                    decoration: const InputDecoration(
                                      labelText: 'تلفن تحویل گیرنده',
                                      border: OutlineInputBorder(),
                                      hintText: '09123456789',
                                    ),
                                    keyboardType: TextInputType.phone,
                                    onChanged: (value) => setState(() => _recipientPhone = value.isEmpty ? null : value),
                                  ),
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: _recipientName,
                                    decoration: const InputDecoration(
                                      labelText: 'تحویل گیرنده',
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (value) => setState(() => _recipientName = value.isEmpty ? null : value),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: _recipientPhone,
                                    decoration: const InputDecoration(
                                      labelText: 'تلفن تحویل گیرنده',
                                      border: OutlineInputBorder(),
                                      hintText: '09123456789',
                                    ),
                                    keyboardType: TextInputType.phone,
                                    onChanged: (value) => setState(() => _recipientPhone = value.isEmpty ? null : value),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        // شماره پیگیری/بارنامه/قبض
                        TextFormField(
                          initialValue: _trackingNumber,
                          decoration: const InputDecoration(
                            labelText: 'شماره پیگیری/بارنامه/قبض',
                            border: OutlineInputBorder(),
                            hintText: 'شماره پیگیری ارسال',
                          ),
                          onChanged: (value) => setState(() => _trackingNumber = value.isEmpty ? null : value),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // خطوط
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'خطوط حواله',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Row(
                      children: [
                        // دکمه تکمیل خودکار کلیه سطوح (فقط برای حواله از فاکتور)
                        if (_isFromInvoice)
                          TextButton.icon(
                            onPressed: _loadingQuantities ? null : _autoCompleteAllLines,
                            icon: _loadingQuantities
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.auto_fix_high, size: 18),
                            label: const Text('تکمیل خودکار همه'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        if (_isFromInvoice) const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: _addLine,
                          tooltip: 'افزودن خط',
                        ),
                      ],
                    ),
                  ],
                ),
                if (_lines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: Text('هیچ خطی وجود ندارد')),
                  )
                else
                  ...List.generate(_lines.length, (index) {
                    final line = _lines[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: ProductComboboxWidget(
                                    businessId: widget.businessId,
                                    selectedProduct: line['product_id'] != null
                                        ? {'id': line['product_id']}
                                        : null,
                                    onChanged: (product) async {
                                      final productId = product?['id'];
                                      _updateLine(index, {
                                        'product_id': productId,
                                        'instance_data': null, // پاک کردن instance_data قبلی
                                      });
                                      
                                      // بارگذاری اطلاعات کالا برای بررسی یونیک بودن
                                      if (productId != null) {
                                        await _loadProductInfo(productId);
                                        setState(() {}); // به‌روزرسانی UI
                                      }
                                    },
                                  ),
                                ),
                                // دکمه ثبت اطلاعات یونیک (فقط برای حواله ورود و کالاهای یونیک)
                                if ((_docType == 'receipt' || _docType == 'production_in') &&
                                    line['product_id'] != null &&
                                    _isProductUnique(line['product_id'] as int))
                                  IconButton(
                                    icon: const Icon(Icons.qr_code_scanner, size: 20),
                                    onPressed: () => _registerUniqueProductInstances(index),
                                    tooltip: 'ثبت اطلاعات کالاهای یونیک',
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                // دکمه انتخاب کالاهای یونیک (فقط برای حواله خروج و کالاهای یونیک)
                                if ((_docType == 'issue' || _docType == 'production_out') &&
                                    line['product_id'] != null &&
                                    _isProductUnique(line['product_id'] as int))
                                  IconButton(
                                    icon: const Icon(Icons.checklist, size: 20),
                                    onPressed: () => _selectUniqueProductInstances(index),
                                    tooltip: 'انتخاب کالاهای یونیک',
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                // دکمه تکمیل خودکار سطح (فقط برای حواله از فاکتور)
                                if (_isFromInvoice && line['product_id'] != null)
                                  IconButton(
                                    icon: const Icon(Icons.auto_fix_high, size: 20),
                                    onPressed: () => _autoCompleteLine(index),
                                    tooltip: 'تکمیل خودکار این خط',
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _removeLine(index),
                                  color: Colors.red,
                                ),
                              ],
                            ),
                            // نمایش اطلاعات مقادیر (فقط برای حواله از فاکتور)
                            if (_isFromInvoice && line['product_id'] != null)
                              Builder(
                                builder: (context) {
                                  final productId = line['product_id'] as int?;
                                  final quantities = productId != null ? _lineQuantities[productId] : null;
                                  if (quantities == null) return const SizedBox.shrink();
                                  
                                  final required = quantities['required'] ?? 0.0;
                                  final processed = quantities['processed'] ?? 0.0;
                                  final remaining = quantities['remaining'] ?? 0.0;
                                  
                                  return Container(
                                    margin: const EdgeInsets.only(top: 8, bottom: 8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: remaining > 0 
                                            ? Theme.of(context).colorScheme.error.withOpacity(0.3)
                                            : Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                        width: 1,
                                      ),
                                    ),
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final isMobile = constraints.maxWidth < 600;
                                        if (isMobile) {
                                          return Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              _buildQuantityRow('مورد نیاز', required, context),
                                              const SizedBox(height: 4),
                                              _buildQuantityRow('از قبل', processed, context),
                                              const SizedBox(height: 4),
                                              _buildQuantityRow('باقی مانده', remaining, context, isRemaining: true),
                                            ],
                                          );
                                        }
                                        return Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                                          children: [
                                            _buildQuantityRow('مورد نیاز', required, context),
                                            _buildQuantityRow('از قبل', processed, context),
                                            _buildQuantityRow('باقی مانده', remaining, context, isRemaining: true),
                                          ],
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                            // نمایش اطلاعات ثبت شده کالاهای یونیک
                            if (line['instance_data'] != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle,
                                          size: 18,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'اطلاعات ${line['instance_data'].length} کالای یونیک ثبت شده',
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context).colorScheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    ...(line['instance_data'] as List<dynamic>).take(3).map((inst) {
                                      final instMap = Map<String, dynamic>.from(inst as Map);
                                      final serial = instMap['serial_number']?.toString();
                                      final barcode = instMap['barcode']?.toString();
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: Text(
                                          '${serial != null ? "سریال: $serial" : ""}${serial != null && barcode != null ? " | " : ""}${barcode != null ? "بارکد: $barcode" : ""}',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      );
                                    }).toList(),
                                    if ((line['instance_data'] as List<dynamic>).length > 3)
                                      Text(
                                        'و ${(line['instance_data'] as List<dynamic>).length - 3} مورد دیگر...',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final isMobile = constraints.maxWidth < 600;
                                if (isMobile) {
                                  return Column(
                                    children: [
                                      if (_docType == 'adjustment') ...[
                                        DropdownButtonFormField<String>(
                                          value: line['movement'] as String?,
                                          decoration: const InputDecoration(
                                            labelText: 'نوع حرکت',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                          items: const [
                                            DropdownMenuItem(value: 'in', child: Text('ورود')),
                                            DropdownMenuItem(value: 'out', child: Text('خروج')),
                                          ],
                                          onChanged: (value) {
                                            if (value != null) {
                                              _updateLine(index, {'movement': value});
                                            }
                                          },
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                      // نمایش فیلد انبار فقط برای adjustment
                                      if (_docType == 'adjustment') ...[
                                        WarehouseComboboxWidget(
                                          businessId: widget.businessId,
                                          selectedWarehouseId: line['warehouse_id'] as int?,
                                          onChanged: (id) => _updateLine(index, {'warehouse_id': id}),
                                          label: 'انبار',
                                          isRequired: true,
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                      TextFormField(
                                        decoration: const InputDecoration(
                                          labelText: 'تعداد *',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        initialValue: line['quantity'].toString(),
                                        onChanged: (value) {
                                          final qty = parseFormattedNumber(value) ?? 0.0;
                                          _updateLine(index, {'quantity': qty});
                                        },
                                        validator: (value) {
                                          final qty = parseFormattedNumber(value) ?? 0.0;
                                          return qty <= 0 ? 'تعداد باید مثبت باشد' : null;
                                        },
                                      ),
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    if (_docType == 'adjustment')
                                      Expanded(
                                        child: DropdownButtonFormField<String>(
                                          value: line['movement'] as String?,
                                          decoration: const InputDecoration(
                                            labelText: 'نوع حرکت',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                          items: const [
                                            DropdownMenuItem(value: 'in', child: Text('ورود')),
                                            DropdownMenuItem(value: 'out', child: Text('خروج')),
                                          ],
                                          onChanged: (value) {
                                            if (value != null) {
                                              _updateLine(index, {'movement': value});
                                            }
                                          },
                                        ),
                                      ),
                                    if (_docType == 'adjustment') const SizedBox(width: 8),
                                    // نمایش فیلد انبار فقط برای adjustment
                                    if (_docType == 'adjustment') ...[
                                      Expanded(
                                        child: WarehouseComboboxWidget(
                                          businessId: widget.businessId,
                                          selectedWarehouseId: line['warehouse_id'] as int?,
                                          onChanged: (id) => _updateLine(index, {'warehouse_id': id}),
                                          label: 'انبار',
                                          isRequired: true,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Expanded(
                                      child: TextFormField(
                                        decoration: const InputDecoration(
                                          labelText: 'تعداد *',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        initialValue: line['quantity'].toString(),
                                        onChanged: (value) {
                                          final qty = parseFormattedNumber(value) ?? 0.0;
                                          _updateLine(index, {'quantity': qty});
                                        },
                                        validator: (value) {
                                          final qty = parseFormattedNumber(value) ?? 0.0;
                                          return qty <= 0 ? 'تعداد باید مثبت باشد' : null;
                                        },
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 600;
                  if (isMobile) {
                    return Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _saving ? null : _save,
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('ذخیره'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: _saving ? null : () => Navigator.of(context).pop(),
                            child: const Text('انصراف'),
                          ),
                        ),
                      ],
                    );
                  }
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _saving ? null : () => Navigator.of(context).pop(),
                        child: const Text('انصراف'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('ذخیره'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

