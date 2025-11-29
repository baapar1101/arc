import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../../services/warehouse_service.dart';
import '../../services/product_service.dart';
import '../../services/product_attribute_service.dart';
import '../../services/invoice_service.dart';
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
  final _invoiceService = InvoiceService();
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

  /// تعیین انبار پیش‌فرض بر اساس نوع حرکت
  /// 
  /// این تابع انبار پیش‌فرض را از سطح سند برمی‌گرداند:
  /// - برای حرکت 'out': انبار مبدا (_warehouseIdFrom)
  /// - برای حرکت 'in': انبار مقصد (_warehouseIdTo)
  /// - در غیر این صورت: null
  int? _defaultWarehouseForMovement(String? movement) {
    if (movement == 'out') return _warehouseIdFrom;
    if (movement == 'in') return _warehouseIdTo;
    return null;
  }

  /// تعیین انبار نهایی برای یک ردیف با استفاده از منطق fallback
  /// 
  /// منطق fallback:
  /// 1. اگر انبار در سطح ردیف مشخص شده باشد، از آن استفاده می‌شود
  /// 2. در غیر این صورت، از انبار پیش‌فرض سطح سند استفاده می‌شود
  /// 
  /// برای حواله انتقال (transfer):
  /// - انبار مبدا: line['warehouse_id_from'] ?? _warehouseIdFrom
  /// - انبار مقصد: line['warehouse_id_to'] ?? _warehouseIdTo
  /// 
  /// برای سایر انواع حواله:
  /// - انبار: line['warehouse_id'] ?? _defaultWarehouseForMovement(movement)
  /// 
  /// Returns: Map شامل warehouse_id (یا warehouse_id_from و warehouse_id_to برای transfer)
  /// و isFromDocumentLevel که نشان می‌دهد انبار از سطح سند آمده یا ردیف
  Map<String, dynamic> _resolveLineWarehouse(Map<String, dynamic> line, String? movement) {
    if (_docType == 'transfer') {
      final whFrom = line['warehouse_id_from'] as int?;
      final whTo = line['warehouse_id_to'] as int?;
      return {
        'warehouse_id_from': whFrom ?? _warehouseIdFrom,
        'warehouse_id_to': whTo ?? _warehouseIdTo,
        'is_from_document_level_from': whFrom == null,
        'is_from_document_level_to': whTo == null,
      };
    }
    
    final lineWarehouse = line['warehouse_id'] as int?;
    final resolvedWarehouse = lineWarehouse ?? _defaultWarehouseForMovement(movement);
    return {
      'warehouse_id': resolvedWarehouse,
      'is_from_document_level': lineWarehouse == null,
    };
  }

  /// بررسی اعتبارسنجی انبار برای یک ردیف
  /// 
  /// Returns: null اگر معتبر باشد، در غیر این صورت پیام خطا
  String? _validateLineWarehouse(Map<String, dynamic> line, int index) {
    final movement = (line['movement'] as String?) ?? _movementForDocType(_docType);
    
    if (_docType == 'transfer') {
      final resolved = _resolveLineWarehouse(line, movement);
      final whFrom = resolved['warehouse_id_from'] as int?;
      final whTo = resolved['warehouse_id_to'] as int?;
      
      if (whFrom == null) {
        return 'خط ${index + 1}: انبار مبدا الزامی است (در سطح سند یا ردیف)';
      }
      if (whTo == null) {
        return 'خط ${index + 1}: انبار مقصد الزامی است (در سطح سند یا ردیف)';
      }
      if (whFrom == whTo) {
        return 'خط ${index + 1}: انبار مبدا و مقصد نمی‌توانند یکسان باشند';
      }
      return null;
    }
    
    if (_docType == 'adjustment') {
      // برای adjustment، انبار باید حتماً در سطح ردیف مشخص شود
      if (line['warehouse_id'] == null) {
        return 'خط ${index + 1}: لطفاً انبار را انتخاب کنید';
      }
      return null;
    }
    
    // برای سایر انواع، بررسی می‌کنیم که یا در سطح سند یا ردیف انبار مشخص شده باشد
    final resolved = _resolveLineWarehouse(line, movement);
    final warehouseId = resolved['warehouse_id'] as int?;
    
    if (warehouseId == null) {
      return 'خط ${index + 1}: انبار الزامی است (در سطح سند یا ردیف)';
    }
    
    return null;
  }

  List<Map<String, dynamic>> _buildLinePayloads() {
    return _lines.map((line) {
      final movement = (line['movement'] as String?) ?? _movementForDocType(_docType);
      final extra = Map<String, dynamic>.from(line['extra_info'] ?? const {});
      if (!extra.containsKey('movement')) {
        extra['movement'] = movement;
      }
      
      // برای کالاهای یونیک، instance_data یا instance_ids را اضافه می‌کنیم
      final instanceData = line['instance_data'] as List<dynamic>?;
      final instanceIds = line['instance_ids'] as List<dynamic>?;
      
      // استفاده از تابع مرکزی برای تعیین انبار
      final warehouseResolved = _resolveLineWarehouse(line, movement);
      
      // برای transfer، از انبار سطح حواله استفاده می‌کنیم
      if (_docType == 'transfer') {
        return {
          'product_id': line['product_id'],
          'warehouse_id_from': warehouseResolved['warehouse_id_from'],
          'warehouse_id_to': warehouseResolved['warehouse_id_to'],
          'quantity': line['quantity'],
          'instance_data': instanceData, // برای حواله ورود
          'instance_ids': instanceIds, // برای حواله خروج
          'extra_info': extra,
        };
      }
      
      return {
        'product_id': line['product_id'],
        'warehouse_id': warehouseResolved['warehouse_id'],
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
      // بارگذاری اطلاعات کامل کالاها برای نمایش در کامبوباکس
      _loadInitialLinesProductInfo();
      // تکمیل خودکار انبار از فاکتور (فقط برای حواله‌های از فاکتور)
      if (_isFromInvoice) {
        _autoFillWarehouseFromInvoice(); // async - در پس‌زمینه اجرا می‌شود
      }
    }
    // بارگذاری اطلاعات مقادیر خطوط فاکتور
    if (_isFromInvoice && widget.sourceInvoiceId != null) {
      _loadLineQuantities();
    }
    // مقداردهی اولیه فیلدهای ارسال (در صورت ویرایش)
    // این فیلدها از extra_info در صورت ویرایش حواله موجود می‌آیند
  }

  /// بارگذاری اطلاعات کامل کالاها برای خطوط اولیه
  Future<void> _loadInitialLinesProductInfo() async {
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      final productId = line['product_id'] as int?;
      if (productId != null) {
        // بررسی اینکه آیا اطلاعات کامل (name و code) موجود است یا نه
        final hasName = line['product_name'] != null;
        final hasCode = line['product_code'] != null;
        
        // اگر اطلاعات کامل موجود نیست، از API بارگذاری کن
        if (!hasName || !hasCode) {
          try {
            await _loadProductInfo(productId);
            if (_productCache.containsKey(productId)) {
              final product = _productCache[productId]!;
              _updateLine(i, {
                'product_name': product['name'],
                'product_code': product['code'],
              });
            }
          } catch (e) {
            debugPrint('Error loading product info for line $i: $e');
          }
        }
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _autoFillWarehouseFromInvoice() async {
    // اگر انبار از قبل انتخاب شده، نیازی به تکمیل خودکار نیست
    if (_docType == 'transfer') {
      if (_warehouseIdFrom != null && _warehouseIdTo != null) return;
    } else if (_docType == 'issue' || _docType == 'production_out') {
      if (_warehouseIdFrom != null) return;
    } else if (_docType == 'receipt' || _docType == 'production_in') {
      if (_warehouseIdTo != null) return;
    }
    
    // اولویت 1: خواندن انبار از سطح سند فاکتور (extra_info.warehouse_id)
    int? invoiceDocumentWarehouseId;
    if (widget.sourceInvoiceId != null) {
      try {
        final invoiceData = await _invoiceService.getInvoice(
          businessId: widget.businessId,
          invoiceId: widget.sourceInvoiceId!,
        );
        final invoiceItem = invoiceData['item'] as Map<String, dynamic>?;
        if (invoiceItem != null) {
          final extraInfo = invoiceItem['extra_info'] as Map<String, dynamic>?;
          if (extraInfo != null) {
            final whId = extraInfo['warehouse_id'];
            if (whId != null) {
              invoiceDocumentWarehouseId = (whId is num) ? whId.toInt() : int.tryParse(whId.toString());
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading invoice warehouse: $e');
      }
    }
    
    // اولویت 2: استخراج انبار از خطوط فاکتور
    int? foundWarehouseId;
    if (invoiceDocumentWarehouseId != null) {
      foundWarehouseId = invoiceDocumentWarehouseId;
    } else {
      for (final line in _lines) {
        final warehouseId = line['warehouse_id'] as int?;
        if (warehouseId != null) {
          foundWarehouseId = warehouseId;
          break; // اولین انبار غیر null را می‌گیریم
        }
      }
    }
    
    if (foundWarehouseId == null) return;
    
    // تنظیم انبار بر اساس نوع حواله
    if (mounted) {
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

  List<Widget> _buildWarehouseFields({required bool isMobile}) {
    if (_docType == 'transfer') {
      if (isMobile) {
        return [
          WarehouseComboboxWidget(
            businessId: widget.businessId,
            selectedWarehouseId: _warehouseIdFrom,
            onChanged: (id) => setState(() => _warehouseIdFrom = id),
            label: 'انبار مبدا *',
          ),
          const SizedBox(height: 12),
          WarehouseComboboxWidget(
            businessId: widget.businessId,
            selectedWarehouseId: _warehouseIdTo,
            onChanged: (id) => setState(() => _warehouseIdTo = id),
            label: 'انبار مقصد *',
          ),
        ];
      }
      return [
        Row(
          children: [
            Expanded(
              child: WarehouseComboboxWidget(
                businessId: widget.businessId,
                selectedWarehouseId: _warehouseIdFrom,
                onChanged: (id) => setState(() => _warehouseIdFrom = id),
                label: 'انبار مبدا *',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: WarehouseComboboxWidget(
                businessId: widget.businessId,
                selectedWarehouseId: _warehouseIdTo,
                onChanged: (id) => setState(() => _warehouseIdTo = id),
                label: 'انبار مقصد *',
              ),
            ),
          ],
        ),
      ];
    } else if (_docType == 'issue' || _docType == 'production_out') {
      return [
        WarehouseComboboxWidget(
          businessId: widget.businessId,
          selectedWarehouseId: _warehouseIdFrom,
          onChanged: (id) => setState(() => _warehouseIdFrom = id),
          label: 'انبار *',
        ),
      ];
    } else if (_docType == 'receipt' || _docType == 'production_in') {
      return [
        WarehouseComboboxWidget(
          businessId: widget.businessId,
          selectedWarehouseId: _warehouseIdTo,
          onChanged: (id) => setState(() => _warehouseIdTo = id),
          label: 'انبار *',
        ),
      ];
    }
    return [];
  }

  Widget _buildShippingInfoSection() {
    return ExpansionTile(
      initiallyExpanded: false,
      tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      leading: Icon(Icons.local_shipping, size: 20, color: Theme.of(context).colorScheme.primary),
      title: Text(
        'اطلاعات ارسال (اختیاری)',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      children: [
        // شرح حواله
        TextFormField(
          initialValue: _description,
          decoration: const InputDecoration(
            labelText: 'شرح/توضیحات',
            border: OutlineInputBorder(),
            hintText: 'توضیحات اختیاری',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          maxLines: 2,
          onChanged: (value) => setState(() => _description = value.isEmpty ? null : value),
        ),
        const SizedBox(height: 12),
        // روش ارسال و نام باربری
        LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 600;
            if (isMobile) {
              return Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: _deliveryMethod,
                    decoration: const InputDecoration(
                      labelText: 'روش ارسال',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                  if (_showCarrierName) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: _carrierName,
                      decoration: const InputDecoration(
                        labelText: 'نام باربری',
                        border: OutlineInputBorder(),
                        hintText: 'مثال: باربری تهران',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      onChanged: (value) => setState(() => _carrierName = value.isEmpty ? null : value),
                    ),
                  ],
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _deliveryMethod,
                    decoration: const InputDecoration(
                      labelText: 'روش ارسال',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                ),
                if (_showCarrierName) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      initialValue: _carrierName,
                      decoration: const InputDecoration(
                        labelText: 'نام باربری',
                        border: OutlineInputBorder(),
                        hintText: 'مثال: باربری تهران',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      onChanged: (value) => setState(() => _carrierName = value.isEmpty ? null : value),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        // تحویل گیرنده و تلفن
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
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onChanged: (value) => setState(() => _recipientName = value.isEmpty ? null : value),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: _recipientPhone,
                    decoration: const InputDecoration(
                      labelText: 'تلفن',
                      border: OutlineInputBorder(),
                      hintText: '09123456789',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onChanged: (value) => setState(() => _recipientName = value.isEmpty ? null : value),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: _recipientPhone,
                    decoration: const InputDecoration(
                      labelText: 'تلفن',
                      border: OutlineInputBorder(),
                      hintText: '09123456789',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    keyboardType: TextInputType.phone,
                    onChanged: (value) => setState(() => _recipientPhone = value.isEmpty ? null : value),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        // شماره پیگیری
        TextFormField(
          initialValue: _trackingNumber,
          decoration: const InputDecoration(
            labelText: 'شماره پیگیری/بارنامه',
            border: OutlineInputBorder(),
            hintText: 'شماره پیگیری ارسال',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          onChanged: (value) => setState(() => _trackingNumber = value.isEmpty ? null : value),
        ),
      ],
    );
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
      // اعتبارسنجی انبار با استفاده از تابع مرکزی
      final warehouseError = _validateLineWarehouse(line, i);
      if (warehouseError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(warehouseError)),
        );
        return;
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
                  const SizedBox(height: 12),
                ],
                // Card تجمیعی برای اطلاعات اصلی
                Card(
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isMobile = constraints.maxWidth < 600;
                        if (isMobile) {
                          return Column(
                            children: [
                              // نوع حواله
                              DropdownButtonFormField<String>(
                                value: _docType,
                                decoration: const InputDecoration(
                                  labelText: 'نوع حواله *',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                              const SizedBox(height: 12),
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
                              const SizedBox(height: 12),
                              // انبارها
                              ..._buildWarehouseFields(isMobile: true),
                            ],
                          );
                        }
                        // دسکتاپ: چیدمان افقی
                        return Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: DropdownButtonFormField<String>(
                                    value: _docType,
                                    decoration: const InputDecoration(
                                      labelText: 'نوع حواله *',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: _calendarController != null
                                      ? DateInputField(
                                          value: _documentDate,
                                          calendarController: _calendarController!,
                                          onChanged: (date) => setState(() => _documentDate = date),
                                          labelText: 'تاریخ *',
                                          firstDate: DateTime(2000),
                                          lastDate: DateTime(2100),
                                        )
                                      : const Center(child: CircularProgressIndicator()),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // انبارها
                            ..._buildWarehouseFields(isMobile: false),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // بخش اطلاعات ارسال (collapsible)
                _buildShippingInfoSection(),
                const SizedBox(height: 12),
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
                                        ? {
                                            'id': line['product_id'],
                                            'name': line['product_name'],
                                            'code': line['product_code'],
                                          }
                                        : null,
                                    onChanged: (product) async {
                                      final productId = product?['id'];
                                      final productName = product?['name'];
                                      final productCode = product?['code'];
                                      
                                      _updateLine(index, {
                                        'product_id': productId,
                                        'product_name': productName,
                                        'product_code': productCode,
                                        'instance_data': null, // پاک کردن instance_data قبلی
                                      });
                                      
                                      // بارگذاری اطلاعات کالا برای بررسی یونیک بودن
                                      if (productId != null) {
                                        await _loadProductInfo(productId);
                                        // به‌روزرسانی اطلاعات کامل کالا از cache در صورت نیاز
                                        if (_productCache.containsKey(productId)) {
                                          final cachedProduct = _productCache[productId]!;
                                          _updateLine(index, {
                                            'product_name': cachedProduct['name'],
                                            'product_code': cachedProduct['code'],
                                          });
                                        }
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
                            // نمایش اطلاعات انبار (برای انواع غیر از adjustment و transfer)
                            if (_docType != 'adjustment' && _docType != 'transfer') ...[
                              const SizedBox(height: 8),
                              Builder(
                                builder: (context) {
                                  final movement = (line['movement'] as String?) ?? _movementForDocType(_docType);
                                  final resolved = _resolveLineWarehouse(line, movement);
                                  final warehouseId = resolved['warehouse_id'] as int?;
                                  final isFromDocumentLevel = resolved['is_from_document_level'] as bool? ?? false;
                                  
                                  if (warehouseId == null) {
                                    return Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: Theme.of(context).colorScheme.error.withOpacity(0.5),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.warning_amber_rounded,
                                            size: 16,
                                            color: Theme.of(context).colorScheme.error,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'انبار مشخص نشده (در سطح سند یا ردیف)',
                                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                color: Theme.of(context).colorScheme.error,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  
                                  return Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isFromDocumentLevel
                                          ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
                                          : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isFromDocumentLevel
                                            ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                                            : Theme.of(context).colorScheme.outline.withOpacity(0.3),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isFromDocumentLevel ? Icons.description : Icons.inventory_2,
                                          size: 16,
                                          color: isFromDocumentLevel
                                              ? Theme.of(context).colorScheme.primary
                                              : Theme.of(context).colorScheme.onSurface,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'انبار: #$warehouseId',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        Chip(
                                          label: Text(
                                            isFromDocumentLevel ? 'سطح سند' : 'سطح ردیف',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: isFromDocumentLevel
                                                  ? Theme.of(context).colorScheme.onPrimaryContainer
                                                  : Theme.of(context).colorScheme.onSurface,
                                            ),
                                          ),
                                          backgroundColor: isFromDocumentLevel
                                              ? Theme.of(context).colorScheme.primaryContainer
                                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                            // نمایش اطلاعات انبار برای transfer
                            if (_docType == 'transfer') ...[
                              const SizedBox(height: 8),
                              Builder(
                                builder: (context) {
                                  final movement = (line['movement'] as String?) ?? _movementForDocType(_docType);
                                  final resolved = _resolveLineWarehouse(line, movement);
                                  final whFrom = resolved['warehouse_id_from'] as int?;
                                  final whTo = resolved['warehouse_id_to'] as int?;
                                  final isFromDocLevelFrom = resolved['is_from_document_level_from'] as bool? ?? false;
                                  final isFromDocLevelTo = resolved['is_from_document_level_to'] as bool? ?? false;
                                  
                                  return Column(
                                    children: [
                                      if (whFrom != null)
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: isFromDocLevelFrom
                                                ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
                                                : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: isFromDocLevelFrom
                                                  ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                                                  : Theme.of(context).colorScheme.outline.withOpacity(0.3),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                isFromDocLevelFrom ? Icons.description : Icons.inventory_2,
                                                size: 16,
                                                color: isFromDocLevelFrom
                                                    ? Theme.of(context).colorScheme.primary
                                                    : Theme.of(context).colorScheme.onSurface,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'انبار مبدا: #$whFrom',
                                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                              Chip(
                                                label: Text(
                                                  isFromDocLevelFrom ? 'سطح سند' : 'سطح ردیف',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: isFromDocLevelFrom
                                                        ? Theme.of(context).colorScheme.onPrimaryContainer
                                                        : Theme.of(context).colorScheme.onSurface,
                                                  ),
                                                ),
                                                backgroundColor: isFromDocLevelFrom
                                                    ? Theme.of(context).colorScheme.primaryContainer
                                                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (whFrom != null && whTo != null) const SizedBox(height: 4),
                                      if (whTo != null)
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: isFromDocLevelTo
                                                ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
                                                : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: isFromDocLevelTo
                                                  ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                                                  : Theme.of(context).colorScheme.outline.withOpacity(0.3),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                isFromDocLevelTo ? Icons.description : Icons.inventory_2,
                                                size: 16,
                                                color: isFromDocLevelTo
                                                    ? Theme.of(context).colorScheme.primary
                                                    : Theme.of(context).colorScheme.onSurface,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'انبار مقصد: #$whTo',
                                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                              Chip(
                                                label: Text(
                                                  isFromDocLevelTo ? 'سطح سند' : 'سطح ردیف',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: isFromDocLevelTo
                                                        ? Theme.of(context).colorScheme.onPrimaryContainer
                                                        : Theme.of(context).colorScheme.onSurface,
                                                  ),
                                                ),
                                                backgroundColor: isFromDocLevelTo
                                                    ? Theme.of(context).colorScheme.primaryContainer
                                                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (whFrom == null || whTo == null)
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: Theme.of(context).colorScheme.error.withOpacity(0.5),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.warning_amber_rounded,
                                                size: 16,
                                                color: Theme.of(context).colorScheme.error,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  whFrom == null && whTo == null
                                                      ? 'انبار مبدا و مقصد مشخص نشده'
                                                      : whFrom == null
                                                          ? 'انبار مبدا مشخص نشده'
                                                          : 'انبار مقصد مشخص نشده',
                                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                    color: Theme.of(context).colorScheme.error,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  );
                                },
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

