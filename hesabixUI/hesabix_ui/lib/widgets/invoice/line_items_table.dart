import 'package:flutter/material.dart';
import '../../models/invoice_line_item.dart';
import '../../utils/number_formatters.dart';
import './product_combobox_widget.dart';
// import './price_list_combobox_widget.dart';
import '../../services/price_list_service.dart';
import '../../core/api_client.dart';

class InvoiceLineItemsTable extends StatefulWidget {
  final int businessId;
  final int? selectedCurrencyId; // از تب ارز فاکتور
  final ValueChanged<List<InvoiceLineItem>>? onChanged;
  final String invoiceType; // sales | purchase | sales_return | purchase_return | ...

  const InvoiceLineItemsTable({
    super.key,
    required this.businessId,
    this.selectedCurrencyId,
    this.onChanged,
    this.invoiceType = 'sales',
  });

  @override
  State<InvoiceLineItemsTable> createState() => _InvoiceLineItemsTableState();
}

class _InvoiceLineItemsTableState extends State<InvoiceLineItemsTable> {
  final List<InvoiceLineItem> _rows = <InvoiceLineItem>[];
  final PriceListService _priceListService = PriceListService(apiClient: ApiClient());
  Map<String, dynamic>? _inlinePriceList; // کش لیست قیمت برای آیکون انتخاب قیمت

  void _notify() => widget.onChanged?.call(List<InvoiceLineItem>.from(_rows));

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
      _rows.add(InvoiceLineItem(
        taxRate: _getDefaultTaxRateForInvoiceType(),
      ));
    });
    _notify();
  }

  void _removeRow(int index) {
    setState(() {
      _rows.removeAt(index);
    });
    _notify();
  }

  @override
  void initState() {
    super.initState();
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _addRow,
              icon: const Icon(Icons.add),
              label: const Text('افزودن ردیف'),
            ),
            const SizedBox(width: 12),
            // لیست قیمت از بالای جدول حذف شد
            const Spacer(),
            // حالت فشرده به صورت پیش‌فرض و تنها حالت است
            if (widget.selectedCurrencyId != null)
              Chip(label: Text('ارز: ${widget.selectedCurrencyId}')),
          ],
        ),
        const SizedBox(height: 12),
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
                    'ردیفی افزوده نشده است',
                    style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                )
              else
                ..._rows.asMap().entries.map((e) => _buildCompactRow(context, e.key, e.value)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          _h('#', 36, style),
          Expanded(
            flex: 4,
            child: Tooltip(
              message: 'کالا/خدمت',
              child: Text('کالا/خدمت', style: style),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Tooltip(
              message: 'تعداد/واحد',
              child: Text('تعداد/واحد', style: style),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Tooltip(
              message: 'قیمت واحد',
              child: Text('قیمت واحد', style: style),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Tooltip(
                message: 'مبلغ کل',
                child: Text('مبلغ کل', style: style, textAlign: TextAlign.end),
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


  Widget _buildCompactRow(BuildContext context, int index, InvoiceLineItem item) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: [
          // سطر اول: شماره، کالا/خدمت، تعداد+واحد، قیمت واحد، مبلغ کل، حذف
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 36, child: Text('${index + 1}')),
              Flexible(
                flex: 4,
                child: SizedBox(
                  height: 36,
                  child: ProductComboboxWidget(
                  businessId: widget.businessId,
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
                    if (p == null) {
                      setState(() {
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
                        );
                      });
                      _notify();
                      return;
                    }
                    
                    final mainUnit = p['main_unit']?.toString();
                    final secondaryUnit = p['secondary_unit']?.toString();
                    final taxRate = _defaultTaxRateFromProduct(p);
                    
                    final updated = item.copyWith(
                      productId: _toInt(p['id']),
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
                    );
                    final priced = await _resolveUnitPrice(updated, preferManual: false);
                    setState(() => _rows[index] = priced);
                    _notify();
                  },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 2,
                child: _buildQuantityWithUnitField(item, (qty) {
                  _updateRow(index, item.copyWith(quantity: qty));
                }, (unit) async {
                  final changed = item.copyWith(selectedUnit: unit);
                  final priced = await _resolveUnitPrice(changed, preferManual: item.unitPriceSource == 'manual');
                  setState(() => _rows[index] = priced);
                  _notify();
                }),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 3,
                child: SizedBox(
                  height: 36,
                  child: Tooltip(
                    message: 'قیمت واحد (انتخاب از لیست یا ورود دستی)',
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
                  ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 2,
                child: SizedBox(
                  height: 36,
                  child: Tooltip(
                    message: 'مبلغ کل این ردیف',
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          formatWithThousands(item.total, decimalPlaces: 0),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(onPressed: () => _removeRow(index), icon: const Icon(Icons.delete, color: Colors.red)),
            ],
          ),
          const SizedBox(height: 6),
          // سطر دوم: شرح، تخفیف، مالیات
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 36),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: Tooltip(
                    message: 'شرح ردیف',
                    child: TextFormField(
                  initialValue: item.description ?? '',
                  onChanged: (v) {
                    _updateRow(index, item.copyWith(description: v));
                  },
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        hintText: 'شرح (اختیاری)'
                        ),
                  ),
                ),
              ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 200,
                child: SizedBox(
                  height: 36,
                  child: Tooltip(
                    message: 'تخفیف (نوع و مقدار)',
                    child: _DiscountCell(
                  value: item.discountValue,
                  type: item.discountType,
                  onChanged: (type, value) {
                    _updateRow(index, item.copyWith(discountType: type, discountValue: value));
                  },
                  ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 200,
                child: SizedBox(
                  height: 36,
                  child: Tooltip(
                    message: 'مالیات (درصد و مبلغ)',
                    child: _TaxCell(
                  rate: item.taxRate,
                  taxAmount: item.taxAmount,
                  onRateChanged: (r) {
                    _updateRow(index, item.copyWith(taxRate: r));
                  },
                  ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityWithUnitField(InvoiceLineItem item, ValueChanged<num> onQuantityChanged, ValueChanged<String?> onUnitChanged) {
    return _QuantityWithUnitField(
      item: item,
      onQuantityChanged: onQuantityChanged,
      onUnitChanged: onUnitChanged,
      onShowUnitSelector: () => _showUnitSelectorDialog(item, onUnitChanged),
    );
  }


  // فوتر جمع‌ها حذف شد؛ جمع‌ها در صفحهٔ والد نمایش داده می‌شوند

  void _showUnitSelectorDialog(InvoiceLineItem item, ValueChanged<String?> onChanged) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('انتخاب واحد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.mainUnit?.isNotEmpty == true)
              ListTile(
                leading: const Icon(Icons.straighten),
                title: Text(item.mainUnit!),
                subtitle: const Text('واحد اصلی'),
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
                subtitle: const Text('واحد فرعی'),
                trailing: (item.selectedUnit == item.secondaryUnit) ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () {
                  onChanged(item.secondaryUnit);
                  Navigator.of(context).pop();
                },
              ),
            if (item.mainUnit?.isEmpty != false && item.secondaryUnit?.isEmpty != false)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('واحدی برای این محصول تعریف نشده است'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('انصراف'),
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

  const _DiscountCell({
    required this.type,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_DiscountCell> createState() => _DiscountCellState();
}

class _DiscountCellState extends State<_DiscountCell> {
  late String _type;
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _type = widget.type;
    _ctrl = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(covariant _DiscountCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // فقط اگر مقدار واقعاً تغییر کرده و کاربر در حال تایپ نیست، کنترلر را به‌روزرسانی کن
    if (oldWidget.value != widget.value && !_ctrl.text.isNotEmpty) {
      _ctrl.text = widget.value.toString();
    }
    _type = widget.type;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String typeLabel(String t) => t == 'percent' ? 'درصد' : 'مبلغ';
    return SizedBox(
      height: 36,
      child: TextFormField(
        controller: _ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (v) => widget.onChanged(_type, num.tryParse(v) ?? 0),
        decoration: InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                tooltip: 'نوع تخفیف',
                padding: EdgeInsets.zero,
                itemBuilder: (c) => [
                  PopupMenuItem<String>(
                    value: 'amount',
                    child: const Text('مبلغ'),
                  ),
                  PopupMenuItem<String>(
                    value: 'percent',
                    child: const Text('درصد'),
                  ),
                ],
                onSelected: (nv) {
                  setState(() => _type = nv);
                  widget.onChanged(nv, num.tryParse(_ctrl.text) ?? 0);
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

  const _TaxCell({
    required this.rate,
    required this.taxAmount,
    required this.onRateChanged,
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
    return Row(
      children: [
        SizedBox(
          width: 70,
          height: 36,
          child: TextFormField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              suffixText: '%',
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 36,
            child: TextFormField(
              controller: _amountCtrl,
              readOnly: true,
              enableInteractiveSelection: false,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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

  const _UnitPriceCell({
    required this.businessId,
    required this.invoiceType,
    required this.currencyId,
    required this.item,
    required this.onChanged,
    required this.resolver,
    required this.unitTitleResolver,
  });

  @override
  State<_UnitPriceCell> createState() => _UnitPriceCellState();
}

class _UnitPriceCellState extends State<_UnitPriceCell> {
  late TextEditingController _ctrl;
  final bool _loading = false;
  final PriceListService _pls = PriceListService(apiClient: ApiClient());
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.item.unitPrice.toString());
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _UnitPriceCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // اگر مقدار از بیرون تغییر کرد و فیلد در فوکوس نیست، متن را همگام کن
    if ((oldWidget.item.unitPrice != widget.item.unitPrice || oldWidget.item.unitPriceSource != widget.item.unitPriceSource) &&
        !_focusNode.hasFocus) {
      _ctrl.text = widget.item.unitPrice.toString();
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
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _ctrl,
            focusNode: _focusNode,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) {
              final cleaned = v.replaceAll(',', '');
              final price = num.tryParse(cleaned) ?? 0;
              widget.onChanged('manual', price < 0 ? 0 : price);
            },
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              suffixIcon: _loading
                  ? const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(
                      tooltip: 'انتخاب از لیست قیمت',
                      icon: const Icon(Icons.list_alt_outlined),
                      onPressed: () => _openPricePicker(context),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openPricePicker(BuildContext context) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
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
                  return const SizedBox(height: 200, child: Center(child: Text('قیمتی برای نمایش یافت نشد')));
                }
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 400),
                  child: ListView.separated(
                    itemCount: options.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (c, i) {
                      final opt = options[i];
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
    try {
      final resolved = await widget.resolver();
      result.add(<String, dynamic>{
        'label': 'قیمت پایه تخمینی',
        'price': resolved.unitPrice,
      });
    } catch (_) {}

    // گزینه‌های لیست قیمت (در صورت داشتن ارز و محصول)
    final productId = widget.item.productId;
    final currencyId = widget.currencyId;
    
    if (productId != null && currencyId != null) {
      try {
        final res = await _pls.listPriceLists(businessId: widget.businessId, limit: 50);
        final lists = (res['items'] as List?)?.cast<dynamic>().map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? const <Map<String, dynamic>>[];
        
        for (final pl in lists) {
          final plId = pl['id'] as int?;
          final plName = pl['name']?.toString() ?? 'لیست قیمت';
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
              final unitLabel = 'واحد اصلی'; // چون unit_id null است، یعنی واحد اصلی
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

  const _QuantityWithUnitField({
    required this.item,
    required this.onQuantityChanged,
    required this.onUnitChanged,
    required this.onShowUnitSelector,
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
    return SizedBox(
      height: 36,
      child: TextFormField(
        controller: _controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (v) {
          // فقط عدد ورودی کاربر را می‌خوانیم
          final cleaned = v.replaceAll(',', '');
          final q = num.tryParse(cleaned) ?? 0;
          widget.onQuantityChanged(q);
        },
        decoration: InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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



