import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../widgets/permission/access_denied_page.dart';
import '../../widgets/invoice/invoice_type_combobox.dart';
import '../../widgets/invoice/code_field_widget.dart';
import '../../widgets/invoice/customer_combobox_widget.dart';
import '../../widgets/invoice/person_combobox_widget.dart';
import '../../widgets/date_input_field.dart';
import '../../widgets/banking/currency_picker_widget.dart';
import '../../widgets/invoice/line_items_table.dart';
import '../../widgets/invoice/invoice_transactions_widget.dart';
import '../../utils/number_formatters.dart';
import '../../models/invoice_type_model.dart';
import '../../models/customer_model.dart';
import '../../models/person_model.dart';
import '../../models/invoice_line_item.dart';
import '../../models/invoice_transaction.dart';
import '../../services/invoice_service.dart';
import '../../services/receipt_payment_service.dart';
import '../../core/api_client.dart';
import '../../services/person_service.dart';

class EditInvoicePage extends StatefulWidget {
  final int businessId;
  final int invoiceId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const EditInvoicePage({
    super.key,
    required this.businessId,
    required this.invoiceId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<EditInvoicePage> createState() => _EditInvoicePageState();
}

class _EditInvoicePageState extends State<EditInvoicePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _loading = true;
  String? _loadError;

  // Header state
  InvoiceType? _selectedInvoiceType;
  String? _invoiceNumber;
  DateTime? _invoiceDate;
  int? _selectedCurrencyId;
  String? _invoiceTitle;
  bool _isProforma = false; // وضعیت پیش‌فاکتور (قابل تغییر)
  bool _postInventory = true;

  // Party selections (اختیاری برای نمایش؛ هنگام ذخیره از extra_info اصلی نگهداری می‌شود)
  Customer? _selectedCustomer;
  Person? _selectedSupplier;

  // Lines
  List<InvoiceLineItem> _lineItems = <InvoiceLineItem>[];
  num _sumSubtotal = 0;
  num _sumDiscount = 0;
  num _sumTax = 0;
  num _sumTotal = 0;

  // تراکنش‌های پرداخت
  List<InvoiceTransaction> _transactions = [];

  // For preserving and merging extra_info
  Map<String, dynamic> _originalExtraInfo = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    // تعداد تب‌ها: اطلاعات، کالاها، تراکنش‌ها (اگر پیش‌فاکتور نباشد)، تنظیمات
    final tabCount = _isProforma ? 3 : 4;
    _tabController = TabController(length: tabCount, vsync: this);
    _loadInvoice();
  }

  // محاسبه تعداد تب‌ها بر اساس نوع فاکتور
  int _getTabCount() {
    if (_isProforma) return 3; // اطلاعات، کالاها، تنظیمات
    if (_selectedInvoiceType == InvoiceType.waste || 
        _selectedInvoiceType == InvoiceType.directConsumption || 
        _selectedInvoiceType == InvoiceType.production) {
      return 3; // اطلاعات، کالاها، تنظیمات (بدون تراکنش)
    }
    return 4; // اطلاعات، کالاها، تراکنش‌ها، تنظیمات
  }

  // بررسی اینکه آیا تب تراکنش‌ها باید نمایش داده شود
  bool get _shouldShowTransactionsTab {
    if (_isProforma) return false;
    return _selectedInvoiceType != InvoiceType.waste && 
           _selectedInvoiceType != InvoiceType.directConsumption && 
           _selectedInvoiceType != InvoiceType.production;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInvoice() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final service = InvoiceService(apiClient: ApiClient());
      final data = await service.getInvoice(businessId: widget.businessId, invoiceId: widget.invoiceId);
      final item = Map<String, dynamic>.from(data['item'] ?? const {});

      final String docType = (item['document_type']?.toString() ?? '');
      final String typeValue = docType.startsWith('invoice_') ? docType.substring('invoice_'.length) : docType;
      _selectedInvoiceType = InvoiceType.fromValue(typeValue) ?? InvoiceType.sales;

      _invoiceNumber = item['code']?.toString();
      _isProforma = item['is_proforma'] == true;
      _invoiceDate = DateTime.tryParse(item['document_date']?.toString() ?? '') ?? DateTime.now();
      _selectedCurrencyId = (item['currency_id'] as num?)?.toInt();
      _invoiceTitle = item['description']?.toString();

      // extra_info
      _originalExtraInfo = Map<String, dynamic>.from(item['extra_info'] ?? const {});
      _postInventory = (_originalExtraInfo['post_inventory'] is bool) ? _originalExtraInfo['post_inventory'] as bool : true;
      
      // بارگذاری تراکنش‌های پرداخت موجود
      await _loadPaymentTransactions();

      // lines
      final List<dynamic> lines = List<dynamic>.from(item['product_lines'] ?? const []);
      num _toNum(dynamic v, {num fallback = 0}) {
        if (v == null) return fallback;
        if (v is num) return v;
        return num.tryParse(v.toString()) ?? fallback;
      }
      int? _toInt(dynamic v) {
        if (v == null) return null;
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse(v.toString());
      }

      _lineItems = lines.map<InvoiceLineItem>((raw) {
        final Map<String, dynamic> r = Map<String, dynamic>.from(raw as Map);
        final Map<String, dynamic> info = Map<String, dynamic>.from(r['extra_info'] ?? const {});

        final num qty = _toNum(r['quantity']);
        final num unitPrice = _toNum(info['unit_price']);
        final num lineDiscount = _toNum(info['line_discount']);
        final num taxAmount = _toNum(info['tax_amount']);
        final String discountType = (info['discount_type']?.toString() ?? (info['discount_value'] != null ? 'amount' : 'amount'));
        final num discountValue = _toNum(info['discount_value'], fallback: lineDiscount);

        // اگر tax_rate موجود نبود، از نسبت tax_amount به مبلغ مشمول مالیات تخمین بزن
        num taxRate = _toNum(info['tax_rate']);
        if (taxRate <= 0) {
          final taxable = (qty * unitPrice) - discountValue;
          if (taxAmount > 0 && taxable > 0) {
            taxRate = (taxAmount / taxable) * 100;
          }
        }

        return InvoiceLineItem(
          productId: _toInt(r['product_id']),
          productName: r['product_name']?.toString(),
          selectedUnit: info['unit']?.toString(),
          quantity: qty,
          unitPriceSource: 'manual',
          unitPrice: unitPrice,
          discountType: discountType,
          discountValue: discountValue,
          taxRate: taxRate,
          description: r['description']?.toString(),
          trackInventory: false,
          warehouseId: null,
        );
      }).toList();

      _recalculateTotals();

      // تلاش برای مقداردهی اولیه طرف حساب بر اساس person_id (از سرویس اشخاص)
      try {
        final pid = (_originalExtraInfo['person_id'] as num?)?.toInt();
        if (pid != null) {
          final ps = PersonService(apiClient: ApiClient());
          final person = await ps.getPerson(pid);
          if (_selectedInvoiceType == InvoiceType.sales || _selectedInvoiceType == InvoiceType.salesReturn) {
            _selectedCustomer = Customer(
              id: person.id!,
              name: person.displayName,
              code: person.code?.toString(),
              phone: person.mobile ?? person.phone,
              email: person.email,
              address: person.address,
              isActive: person.isActive,
              createdAt: person.createdAt,
            );
          } else if (_selectedInvoiceType == InvoiceType.purchase || _selectedInvoiceType == InvoiceType.purchaseReturn) {
            _selectedSupplier = person;
          }
        }
      } catch (_) {}

      // به‌روزرسانی TabController بر اساس تعداد تب‌ها
      final newTabCount = _getTabCount();
      if (newTabCount != _tabController.length) {
        _tabController.dispose();
        _tabController = TabController(length: newTabCount, vsync: this);
      }

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// بارگذاری تراکنش‌های پرداخت موجود از اسناد دریافت/پرداخت مرتبط
  Future<void> _loadPaymentTransactions() async {
    if (_isProforma) return; // پیش‌فاکتورها تراکنش ندارند
    
    try {
      final links = _originalExtraInfo['links'] as Map<String, dynamic>?;
      if (links == null) return;
      
      final receiptPaymentIds = links['receipt_payment_document_ids'] as List<dynamic>?;
      if (receiptPaymentIds == null || receiptPaymentIds.isEmpty) return;
      
      final receiptPaymentService = ReceiptPaymentService(ApiClient());
      final List<InvoiceTransaction> transactions = [];
      
      for (final id in receiptPaymentIds) {
        try {
          final doc = await receiptPaymentService.getById(id as int);
          if (doc == null) continue;
          
          // تبدیل سند دریافت/پرداخت به InvoiceTransaction
          for (final accountLine in doc.accountLines) {
            if (accountLine.transactionType == null) continue;
            
            final transactionType = TransactionType.fromValue(accountLine.transactionType ?? '');
            if (transactionType == null) continue;
            
            final transaction = InvoiceTransaction(
              id: const Uuid().v4(), // ID موقت برای ویرایش
              type: transactionType,
              amount: accountLine.amount,
              transactionDate: accountLine.transactionDate ?? doc.documentDate,
              description: accountLine.description,
              commission: accountLine.commission,
              // استخراج اطلاعات اضافی (تبدیل int به String)
              bankId: accountLine.extraInfo?['bank_id']?.toString(),
              bankName: accountLine.extraInfo?['bank_name'] as String?,
              cashRegisterId: accountLine.extraInfo?['cash_register_id']?.toString(),
              cashRegisterName: accountLine.extraInfo?['cash_register_name'] as String?,
              pettyCashId: accountLine.extraInfo?['petty_cash_id']?.toString(),
              pettyCashName: accountLine.extraInfo?['petty_cash_name'] as String?,
              checkId: accountLine.extraInfo?['check_id']?.toString(),
              checkNumber: accountLine.extraInfo?['check_number'] as String?,
              personId: accountLine.extraInfo?['person_id']?.toString(),
              personName: accountLine.extraInfo?['person_name'] as String?,
              accountId: accountLine.accountId.toString(),
              accountName: accountLine.accountName,
            );
            transactions.add(transaction);
          }
        } catch (e) {
          // اگر خطا رخ داد، ادامه بده
          print('Error loading payment transaction from document $id: $e');
        }
      }
      
      if (mounted) {
        setState(() {
          _transactions = transactions;
        });
      }
    } catch (e) {
      print('Error loading payment transactions: $e');
    }
  }

  void _recalculateTotals() {
    _sumSubtotal = _lineItems.fold<num>(0, (acc, e) => acc + e.subtotal);
    _sumDiscount = _lineItems.fold<num>(0, (acc, e) => acc + e.discountAmount);
    _sumTax = _lineItems.fold<num>(0, (acc, e) => acc + e.taxAmount);
    _sumTotal = _lineItems.fold<num>(0, (acc, e) => acc + e.total);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    if (!widget.authStore.canWriteSection('invoices')) {
      return AccessDeniedPage(message: t.accessDenied);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('ویرایش فاکتور'),
        actions: [
          IconButton(
            tooltip: 'ذخیره تغییرات',
            onPressed: _loading ? null : _saveChanges,
            icon: const Icon(Icons.save),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(icon: Icon(Icons.info_outline), text: 'اطلاعات فاکتور'),
            const Tab(icon: Icon(Icons.inventory_2_outlined), text: 'کالاها و خدمات'),
            if (_shouldShowTransactionsTab)
              const Tab(icon: Icon(Icons.receipt_long_outlined), text: 'تراکنش‌ها'),
            const Tab(icon: Icon(Icons.settings_outlined), text: 'تنظیمات'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Text(_loadError!))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildInvoiceInfoTab(),
                    _buildProductsTab(),
                    if (_shouldShowTransactionsTab) _buildTransactionsTab(),
                    _buildSettingsTab(),
                  ],
                ),
    );
  }

  Widget _buildInvoiceInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  return Column(
                    children: [
                      // سطر اول
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: InvoiceTypeCombobox(
                              selectedType: _selectedInvoiceType,
                              onTypeChanged: (type) {
                                setState(() {
                                  _selectedInvoiceType = type;
                                });
                              },
                              isDraft: _isProforma,
                              onDraftChanged: (isDraft) {
                                setState(() {
                                  _isProforma = isDraft;
                                  // اگر پیش‌فاکتور فعال شد، تراکنش‌های پرداخت را پاک کن
                                  if (isDraft && _transactions.isNotEmpty) {
                                    _transactions = [];
                                  }
                                  // به‌روزرسانی TabController
                                  final newTabCount = _getTabCount();
                                  if (newTabCount != _tabController.length) {
                                    _tabController.dispose();
                                    _tabController = TabController(length: newTabCount, vsync: this);
                                  }
                                });
                              },
                              isRequired: true,
                              label: 'نوع فاکتور',
                              hintText: 'انتخاب نوع فاکتور',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CodeFieldWidget(
                              initialValue: _invoiceNumber,
                              onChanged: (_) {},
                              isRequired: true,
                              label: 'شماره فاکتور',
                              hintText: 'کد فاکتور',
                              autoGenerateCode: true, // فقط نمایشی در ویرایش
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DateInputField(
                              value: _invoiceDate,
                              labelText: 'تاریخ فاکتور *',
                              hintText: 'انتخاب تاریخ فاکتور',
                              calendarController: widget.calendarController,
                              onChanged: (date) {
                                setState(() {
                                  _invoiceDate = date;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CurrencyPickerWidget(
                              businessId: widget.businessId,
                              selectedCurrencyId: _selectedCurrencyId,
                              onChanged: (currencyId) {
                                setState(() {
                                  _selectedCurrencyId = currencyId;
                                });
                              },
                              label: 'ارز فاکتور',
                              hintText: 'انتخاب ارز فاکتور',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // طرف حساب فقط نمایشی در صورت امکان
                      if (_selectedInvoiceType == InvoiceType.sales || _selectedInvoiceType == InvoiceType.salesReturn)
                        CustomerComboboxWidget(
                          selectedCustomer: _selectedCustomer,
                          onCustomerChanged: (c) => setState(() => _selectedCustomer = c),
                          businessId: widget.businessId,
                          authStore: widget.authStore,
                          isRequired: false,
                          label: 'مشتری',
                          hintText: _selectedCustomer?.name ?? 'انتخاب مشتری',
                        ),
                      if (_selectedInvoiceType == InvoiceType.purchase || _selectedInvoiceType == InvoiceType.purchaseReturn) ...[
                        const SizedBox(height: 16),
                        PersonComboboxWidget(
                          businessId: widget.businessId,
                          selectedPerson: _selectedSupplier,
                          onChanged: (p) => setState(() => _selectedSupplier = p),
                          isRequired: false,
                          label: 'تامین‌کننده',
                          hintText: 'انتخاب تامین‌کننده',
                          personTypes: const ['تامین‌کننده', 'فروشنده'],
                          searchHint: 'جست‌وجو در تامین‌کنندگان...',
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: _invoiceTitle,
                        onChanged: (v) => setState(() => _invoiceTitle = v.trim().isEmpty ? null : v.trim()),
                        decoration: const InputDecoration(
                          labelText: 'توضیحات فاکتور',
                          hintText: 'مثال: فروش محصولات',
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                        maxLines: 3,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildProductsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InvoiceLineItemsTable(
                businessId: widget.businessId,
                selectedCurrencyId: _selectedCurrencyId,
                invoiceType: (_selectedInvoiceType?.value ?? 'sales'),
                postInventory: _postInventory,
                initialRows: _lineItems,
                onChanged: (rows) {
                  setState(() {
                    _lineItems = rows;
                    _recalculateTotals();
                  });
                },
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text('جمع مبلغ: ${formatWithThousands(_sumSubtotal, decimalPlaces: 0)}', style: Theme.of(context).textTheme.bodyLarge),
                    Text('جمع تخفیف: ${formatWithThousands(_sumDiscount, decimalPlaces: 0)}', style: Theme.of(context).textTheme.bodyLarge),
                    Text('جمع مالیات: ${formatWithThousands(_sumTax, decimalPlaces: 0)}', style: Theme.of(context).textTheme.bodyLarge),
                    Text('جمع کل: ${formatWithThousands(_sumTotal, decimalPlaces: 0)}', style: Theme.of(context).textTheme.bodyLarge),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionsTab() {
    if (!_shouldShowTransactionsTab) {
      return const Center(child: Text('تراکنش‌ها برای این نوع فاکتور در دسترس نیست'));
    }
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1600),
          child: InvoiceTransactionsWidget(
            transactions: _transactions,
            onChanged: (transactions) {
              setState(() {
                _transactions = transactions;
              });
            },
            businessId: widget.businessId,
            calendarController: widget.calendarController,
            invoiceType: _selectedInvoiceType ?? InvoiceType.sales,
            selectedCurrencyId: _selectedCurrencyId,
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        title: const Text('ثبت اسناد انبار'),
                        subtitle: const Text('در صورت غیرفعال‌سازی، حرکات موجودی ثبت نمی‌شوند و کنترل کسری انجام نمی‌گردد'),
                        value: _postInventory,
                        onChanged: (v) => setState(() => _postInventory = v),
                      ),
                      const SizedBox(height: 8),
                      const Text('توجه: در ویرایش فاکتور، حواله‌های انبار به صورت خودکار بازسازی نمی‌شوند. لطفاً پس از ذخیره تغییرات، حواله‌های مرتبط را بررسی کنید.'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveChanges() async {
    final payloadOrError = _validateAndBuildPayload();
    if (payloadOrError is String) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(payloadOrError)),
      );
      return;
    }
    final payload = payloadOrError as Map<String, dynamic>;

    try {
      final service = InvoiceService(apiClient: ApiClient());
      await service.updateInvoice(
        businessId: widget.businessId,
        invoiceId: widget.invoiceId,
        payload: payload,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تغییرات فاکتور با موفقیت ذخیره شد')),
      );
      // بازگشت به لیست فاکتورها بعد از ذخیره موفق
      if (mounted) {
        context.pop(true); // true به معنای موفقیت‌آمیز بودن ویرایش
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در ذخیره تغییرات: $e')),
      );
    }
  }

  dynamic _validateAndBuildPayload() {
    if (_selectedInvoiceType == null) {
      return 'نوع فاکتور نامعتبر است';
    }
    if (_invoiceDate == null) {
      return 'تاریخ فاکتور الزامی است';
    }
    if (_selectedCurrencyId == null) {
      return 'ارز فاکتور الزامی است';
    }
    if (_lineItems.isEmpty) {
      return 'حداقل یک ردیف کالا/خدمت وارد کنید';
    }

    // ساخت extra_info با حفظ اطلاعات قبلی
    final mergedExtra = <String, dynamic>{..._originalExtraInfo};
    mergedExtra['post_inventory'] = _postInventory;
    mergedExtra['totals'] = {
      'gross': _sumSubtotal,
      'discount': _sumDiscount,
      'tax': _sumTax,
      'net': _sumTotal,
    };

    String _convertInvoiceTypeToApi(InvoiceType type) => 'invoice_${type.value}';

    final payload = <String, dynamic>{
      'invoice_type': _convertInvoiceTypeToApi(_selectedInvoiceType!), // جهت سازگاری حساب‌ها
      'document_date': _invoiceDate!.toIso8601String().split('T')[0],
      'currency_id': _selectedCurrencyId,
      'is_proforma': _isProforma, // ارسال وضعیت پیش‌فاکتور
      'extra_info': mergedExtra,
      if ((_invoiceTitle ?? '').isNotEmpty) 'description': _invoiceTitle,
      'lines': _lineItems.map((e) => _serializeLineItem(e)).toList(),
    };
    
    // افزودن تراکنش‌های پرداخت (فقط برای فاکتورهای قطعی)
    if (!_isProforma && _transactions.isNotEmpty) {
      payload['payments'] = _transactions.map((t) => t.toJson()).toList();
    }

    return payload;
  }

  Map<String, dynamic> _serializeLineItem(InvoiceLineItem e) {
    String? movement;
    if (_selectedInvoiceType == InvoiceType.sales ||
        _selectedInvoiceType == InvoiceType.purchaseReturn ||
        _selectedInvoiceType == InvoiceType.directConsumption ||
        _selectedInvoiceType == InvoiceType.waste) {
      movement = 'out';
    } else if (_selectedInvoiceType == InvoiceType.purchase ||
        _selectedInvoiceType == InvoiceType.salesReturn) {
      movement = 'in';
    }

    final lineDiscount = e.discountAmount;
    final taxAmount = e.taxAmount;
    final lineTotal = e.total;

    return <String, dynamic>{
      'product_id': e.productId,
      'quantity': e.quantity,
      if ((e.description ?? '').isNotEmpty) 'description': e.description,
      'extra_info': {
        'unit_price': e.unitPrice,
        'line_discount': lineDiscount,
        'tax_amount': taxAmount,
        'line_total': lineTotal,
        if (movement != null) 'movement': movement,
        'unit': e.selectedUnit ?? e.mainUnit,
        'unit_price_source': e.unitPriceSource,
        'discount_type': e.discountType,
        'discount_value': e.discountValue,
        'tax_rate': e.taxRate,
      },
    };
  }
}


