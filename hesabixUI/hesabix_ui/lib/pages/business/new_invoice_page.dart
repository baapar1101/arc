import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../widgets/permission/access_denied_page.dart';
import '../../widgets/invoice/invoice_type_combobox.dart';
import '../../widgets/invoice/code_field_widget.dart';
import '../../widgets/invoice/customer_combobox_widget.dart';
import '../../widgets/invoice/seller_picker_widget.dart';
import '../../widgets/invoice/person_combobox_widget.dart';
import '../../widgets/invoice/commission_percentage_field.dart';
import '../../widgets/invoice/commission_type_selector.dart';
import '../../widgets/invoice/commission_amount_field.dart';
import '../../widgets/date_input_field.dart';
import '../../widgets/banking/currency_picker_widget.dart';
import '../../models/invoice_type_model.dart';
import '../../models/customer_model.dart';
import '../../models/person_model.dart';
import '../../widgets/invoice/line_items_table.dart';
import '../../widgets/invoice/invoice_transactions_widget.dart';
import '../../utils/number_formatters.dart';
import '../../services/currency_service.dart';
import '../../core/api_client.dart';
import '../../models/invoice_transaction.dart';
import '../../models/invoice_line_item.dart';
import '../../services/invoice_service.dart';

class NewInvoicePage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const NewInvoicePage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<NewInvoicePage> createState() => _NewInvoicePageState();
}

class _NewInvoicePageState extends State<NewInvoicePage> with SingleTickerProviderStateMixin {
  // تنظیمات انبار
  bool _postInventory = true; // ثبت اسناد انبار
  late TabController _tabController;
  
  InvoiceType? _selectedInvoiceType;
  bool _isDraft = false;
  String? _invoiceNumber;
  final bool _autoGenerateInvoiceNumber = true;
  Customer? _selectedCustomer;
  Person? _selectedSeller;
  Person? _selectedSupplier; // برای فاکتورهای خرید
  double? _commissionPercentage;
  double? _commissionAmount;
  CommissionType? _commissionType;
  DateTime? _invoiceDate;
  DateTime? _dueDate;
  int? _selectedCurrencyId;
  String? _invoiceTitle;
  String? _invoiceReference;
  // جمع‌های محاسباتی ردیف‌ها
  num _sumSubtotal = 0;
  num _sumDiscount = 0;
  num _sumTax = 0;
  num _sumTotal = 0;
  
  // تنظیمات چاپ و ارسال
  bool _printAfterSave = false;
  String? _selectedPrinter;
  String? _selectedPaperSize;
  bool _isOfficialInvoice = false;
  String? _selectedPrintTemplate;
  bool _sendToTaxFolder = false;
  
  // تراکنش‌های فاکتور
  List<InvoiceTransaction> _transactions = [];
  // ردیف‌های فاکتور برای ساخت payload
  List<InvoiceLineItem> _lineItems = <InvoiceLineItem>[];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this); // شروع با 4 تب
    // تنظیم نوع فاکتور پیش‌فرض
    _selectedInvoiceType = InvoiceType.sales;
    // تنظیم ارز پیش‌فرض از AuthStore
    _selectedCurrencyId = widget.authStore.selectedCurrencyId;
    // اگر ارز انتخاب نشده، ارز پیش‌فرض را بارگذاری کن
    if (_selectedCurrencyId == null) {
      _loadDefaultCurrency();
    }
    // تنظیم تاریخ‌های پیش‌فرض
    _invoiceDate = DateTime.now();
    _dueDate = DateTime.now();
  }

  Future<void> _loadDefaultCurrency() async {
    try {
      final currencyService = CurrencyService(ApiClient());
      final currencies = await currencyService.listBusinessCurrencies(businessId: widget.businessId);
      if (currencies.isNotEmpty) {
        // ارز پیش‌فرض را پیدا کن
        final defaultCurrency = currencies.firstWhere(
          (c) => c['is_default'] == true,
          orElse: () => currencies.first,
        );
        setState(() {
          _selectedCurrencyId = defaultCurrency['id'] as int;
        });
        // ارز پیش‌فرض بارگذاری شد
      }
    } catch (e) {
      // خطا در بارگذاری ارز پیش‌فرض
    }
  }


  // محاسبه تعداد تب‌ها بر اساس نوع فاکتور
  int _getTabCountForType(InvoiceType? type) {
    if (type == InvoiceType.waste || 
        type == InvoiceType.directConsumption || 
        type == InvoiceType.production) {
      return 3; // اطلاعات فاکتور، کالاها و خدمات، تنظیمات
    }
    return 4; // همه تب‌ها
  }


  // بررسی اینکه آیا تب تراکنش‌ها باید نمایش داده شود
  bool get _shouldShowTransactionsTab {
    return _selectedInvoiceType != InvoiceType.waste && 
           _selectedInvoiceType != InvoiceType.directConsumption && 
           _selectedInvoiceType != InvoiceType.production;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    if (!widget.authStore.canWriteSection('invoices')) {
      return AccessDeniedPage(message: t.accessDenied);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t.addInvoice),
        toolbarHeight: 56,
        actions: [
          Tooltip(
            message: 'ذخیره فاکتور',
            child: IconButton(
              onPressed: _saveInvoice,
              icon: const Icon(Icons.save),
              tooltip: 'ذخیره فاکتور',
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(
              icon: Icon(Icons.info_outline),
              text: 'اطلاعات فاکتور',
            ),
            const Tab(
              icon: Icon(Icons.inventory_2_outlined),
              text: 'کالاها و خدمات',
            ),
            if (_shouldShowTransactionsTab)
              const Tab(
                icon: Icon(Icons.receipt_long_outlined),
                text: 'تراکنش‌ها',
              ),
            const Tab(
              icon: Icon(Icons.settings_outlined),
              text: 'تنظیمات',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // تب اطلاعات فاکتور
          _buildInvoiceInfoTab(),
          // تب کالاها و خدمات
          _buildProductsTab(),
          // تب تراکنش‌ها (فقط اگر باید نمایش داده شود)
          if (_shouldShowTransactionsTab) _buildTransactionsTab(),
          // تب تنظیمات
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
              // فیلدهای اصلی - responsive layout
              LayoutBuilder(
                builder: (context, constraints) {
                  // اگر عرض صفحه کمتر از 768 پیکسل باشد، تک ستونه
                  if (constraints.maxWidth < 768) {
                    return Column(
                      children: [
                        // نوع فاکتور
                        InvoiceTypeCombobox(
                          selectedType: _selectedInvoiceType,
                          onTypeChanged: (type) {
                                  setState(() {
                                    _selectedInvoiceType = type;
                                    // پاک کردن انتخاب‌های قبلی هنگام تغییر نوع فاکتور
                                    if (type == InvoiceType.purchase || type == InvoiceType.purchaseReturn) {
                                      _selectedCustomer = null;
                                      _selectedSeller = null;
                                    } else if (type == InvoiceType.sales || type == InvoiceType.salesReturn) {
                                      _selectedSupplier = null;
                                    } else {
                                      _selectedCustomer = null;
                                      _selectedSupplier = null;
                                      _selectedSeller = null;
                                    }
                                    // به‌روزرسانی TabController اگر تعداد تب‌ها تغییر کرده
                                    final newTabCount = _getTabCountForType(type);
                                    if (newTabCount != _tabController.length) {
                                      _tabController.dispose();
                                      _tabController = TabController(length: newTabCount, vsync: this);
                                    }
                                  });
                                },
                          isDraft: _isDraft,
                          onDraftChanged: (isDraft) {
                            setState(() {
                              _isDraft = isDraft;
                            });
                          },
                          isRequired: true,
                          label: 'نوع فاکتور',
                          hintText: 'انتخاب نوع فاکتور',
                        ),
                        const SizedBox(height: 16),
                        
                        // شماره فاکتور
                        CodeFieldWidget(
                          initialValue: _invoiceNumber,
                          onChanged: (number) {
                            setState(() {
                              _invoiceNumber = number;
                            });
                          },
                          isRequired: true,
                          label: 'شماره فاکتور',
                          hintText: 'مثال: INV-2024-001',
                          autoGenerateCode: _autoGenerateInvoiceNumber,
                        ),
                        const SizedBox(height: 16),
                        
                        // تاریخ فاکتور
                        DateInputField(
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
                        const SizedBox(height: 16),
                        
                        // تاریخ سررسید
                        DateInputField(
                          value: _dueDate,
                          labelText: 'تاریخ سررسید',
                          hintText: 'انتخاب تاریخ سررسید',
                          calendarController: widget.calendarController,
                          onChanged: (date) {
                            setState(() {
                              _dueDate = date;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // مشتری (فقط برای فروش و برگشت از فروش)
                        if (_selectedInvoiceType == InvoiceType.sales || 
                            _selectedInvoiceType == InvoiceType.salesReturn)
                          CustomerComboboxWidget(
                            selectedCustomer: _selectedCustomer,
                            onCustomerChanged: (customer) {
                              setState(() {
                                _selectedCustomer = customer;
                              });
                            },
                            businessId: widget.businessId,
                            authStore: widget.authStore,
                            isRequired: false,
                            label: 'مشتری',
                            hintText: 'انتخاب مشتری',
                          ),
                        // تامین‌کننده (فقط برای خرید و برگشت از خرید)
                        if (_selectedInvoiceType == InvoiceType.purchase || 
                            _selectedInvoiceType == InvoiceType.purchaseReturn) ...[
                          const SizedBox(height: 16),
                          PersonComboboxWidget(
                            businessId: widget.businessId,
                            selectedPerson: _selectedSupplier,
                            onChanged: (person) {
                              setState(() {
                                _selectedSupplier = person;
                              });
                            },
                            isRequired: false,
                            label: 'تامین‌کننده',
                            hintText: 'انتخاب تامین‌کننده',
                            personTypes: ['تامین‌کننده', 'فروشنده'],
                            searchHint: 'جست‌وجو در تامین‌کنندگان...',
                          ),
                        ],
                        const SizedBox(height: 16),
                        
                        // ارز فاکتور
                        CurrencyPickerWidget(
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
                        const SizedBox(height: 16),
                        
                        // فروشنده و کارمزد (فقط برای فروش و برگشت فروش)
                        if (_selectedInvoiceType == InvoiceType.sales || _selectedInvoiceType == InvoiceType.salesReturn) ...[
                          Row(
                            children: [
                              Expanded(
                                child: SellerPickerWidget(
                                  selectedSeller: _selectedSeller,
                                  onSellerChanged: (seller) {
                                    setState(() {
                                      _selectedSeller = seller;
                                      // تنظیم خودکار نوع کارمزد و مقادیر بر اساس فروشنده
                                      if (seller != null) {
                                        final isSales = _selectedInvoiceType == InvoiceType.sales;
                                        final isSalesReturn = _selectedInvoiceType == InvoiceType.salesReturn;
                                        final percent = isSales ? seller.commissionSalePercent : (isSalesReturn ? seller.commissionSalesReturnPercent : null);
                                        final amount = isSales ? seller.commissionSalesAmount : (isSalesReturn ? seller.commissionSalesReturnAmount : null);
                                        if (percent != null) {
                                          _commissionType = CommissionType.percentage;
                                          _commissionPercentage = percent;
                                          _commissionAmount = null;
                                        } else if (amount != null) {
                                          _commissionType = CommissionType.amount;
                                          _commissionAmount = amount;
                                          _commissionPercentage = null;
                                        }
                                      } else {
                                        _commissionType = null;
                                        _commissionPercentage = null;
                                        _commissionAmount = null;
                                      }
                                    });
                                  },
                                  businessId: widget.businessId,
                                  authStore: widget.authStore,
                                  isRequired: false,
                                  label: 'فروشنده/بازاریاب',
                                  hintText: 'جست‌وجو و انتخاب فروشنده یا بازاریاب',
                                ),
                              ),
                              const SizedBox(width: 12),
                              // فیلدهای کارمزد (فقط اگر فروشنده انتخاب شده باشد)
                              if (_selectedSeller != null) ...[
                                Expanded(
                                  child: CommissionTypeSelector(
                                    selectedType: _commissionType,
                                    onTypeChanged: (type) {
                                      setState(() {
                                        _commissionType = type;
                                        // پاک کردن مقادیر قبلی هنگام تغییر نوع
                                        if (type == CommissionType.percentage) {
                                          _commissionAmount = null;
                                        } else if (type == CommissionType.amount) {
                                          _commissionPercentage = null;
                                        }
                                      });
                                    },
                                    isRequired: false,
                                    label: 'نوع کارمزد',
                                    hintText: 'انتخاب نوع کارمزد',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // فیلد درصد کارمزد (فقط اگر نوع درصدی انتخاب شده)
                                if (_commissionType == CommissionType.percentage)
                                  Expanded(
                                    child: CommissionPercentageField(
                                      initialValue: _commissionPercentage,
                                      onChanged: (percentage) {
                                        setState(() {
                                          _commissionPercentage = percentage;
                                        });
                                      },
                                      isRequired: false,
                                      label: 'درصد کارمزد',
                                      hintText: 'مثال: 5.5',
                                    ),
                                  )
                                // فیلد مبلغ کارمزد (فقط اگر نوع مبلغی انتخاب شده)
                                else if (_commissionType == CommissionType.amount)
                                  Expanded(
                                    child: CommissionAmountField(
                                      initialValue: _commissionAmount,
                                      onChanged: (amount) {
                                        setState(() {
                                          _commissionAmount = amount;
                                        });
                                      },
                                      isRequired: false,
                                      label: 'مبلغ کارمزد',
                                      hintText: 'مثال: 100000',
                                    ),
                                  ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                        
                        // عنوان فاکتور
                        TextFormField(
                          initialValue: _invoiceTitle,
                          onChanged: (value) {
                            setState(() {
                              _invoiceTitle = value.trim().isEmpty ? null : value.trim();
                            });
                          },
                          decoration: const InputDecoration(
                            labelText: 'عنوان فاکتور',
                            hintText: 'مثال: فروش محصولات',
                            border: OutlineInputBorder(),
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 16),
                        
                        // ارجاع
                        TextFormField(
                          initialValue: _invoiceReference,
                          onChanged: (value) {
                            setState(() {
                              _invoiceReference = value.trim().isEmpty ? null : value.trim();
                            });
                          },
                          decoration: const InputDecoration(
                            labelText: 'ارجاع',
                            hintText: 'مثال: PO-2024-001',
                            border: OutlineInputBorder(),
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                      ],
                    );
                  } else {
                    // برای دسکتاپ - چند ستونه
                    return Column(
                      children: [
                        // ردیف اول: 5 فیلد اصلی
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: InvoiceTypeCombobox(
                                selectedType: _selectedInvoiceType,
                                onTypeChanged: (type) {
                                  setState(() {
                                    _selectedInvoiceType = type;
                                    // پاک کردن انتخاب‌های قبلی هنگام تغییر نوع فاکتور
                                    if (type == InvoiceType.purchase || type == InvoiceType.purchaseReturn) {
                                      _selectedCustomer = null;
                                      _selectedSeller = null;
                                    } else if (type == InvoiceType.sales || type == InvoiceType.salesReturn) {
                                      _selectedSupplier = null;
                                    } else {
                                      _selectedCustomer = null;
                                      _selectedSupplier = null;
                                      _selectedSeller = null;
                                    }
                                    // به‌روزرسانی TabController اگر تعداد تب‌ها تغییر کرده
                                    final newTabCount = _getTabCountForType(type);
                                    if (newTabCount != _tabController.length) {
                                      _tabController.dispose();
                                      _tabController = TabController(length: newTabCount, vsync: this);
                                    }
                                  });
                                },
                                isDraft: _isDraft,
                                onDraftChanged: (isDraft) {
                                  setState(() {
                                    _isDraft = isDraft;
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
                                onChanged: (number) {
                                  setState(() {
                                    _invoiceNumber = number;
                                  });
                                },
                                isRequired: true,
                                label: 'شماره فاکتور',
                                hintText: 'مثال: INV-2024-001',
                                autoGenerateCode: _autoGenerateInvoiceNumber,
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
                              child: DateInputField(
                                value: _dueDate,
                                labelText: 'تاریخ سررسید',
                                hintText: 'انتخاب تاریخ سررسید',
                                calendarController: widget.calendarController,
                                onChanged: (date) {
                                  setState(() {
                                    _dueDate = date;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: (_selectedInvoiceType == InvoiceType.waste ||
                                      _selectedInvoiceType == InvoiceType.directConsumption ||
                                      _selectedInvoiceType == InvoiceType.production)
                                  ? const SizedBox()
                                  : (_selectedInvoiceType == InvoiceType.sales || 
                                      _selectedInvoiceType == InvoiceType.salesReturn)
                                      ? CustomerComboboxWidget(
                                          selectedCustomer: _selectedCustomer,
                                          onCustomerChanged: (customer) {
                                            setState(() {
                                              _selectedCustomer = customer;
                                            });
                                          },
                                          businessId: widget.businessId,
                                          authStore: widget.authStore,
                                          isRequired: false,
                                          label: 'مشتری',
                                          hintText: 'انتخاب مشتری',
                                        )
                                      : (_selectedInvoiceType == InvoiceType.purchase || 
                                          _selectedInvoiceType == InvoiceType.purchaseReturn)
                                          ? PersonComboboxWidget(
                                              businessId: widget.businessId,
                                              selectedPerson: _selectedSupplier,
                                              onChanged: (person) {
                                                setState(() {
                                                  _selectedSupplier = person;
                                                });
                                              },
                                              isRequired: false,
                                              label: 'تامین‌کننده',
                                              hintText: 'انتخاب تامین‌کننده',
                                              personTypes: ['تامین‌کننده', 'فروشنده'],
                                              searchHint: 'جست‌وجو در تامین‌کنندگان...',
                                            )
                                          : const SizedBox(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // ردیف دوم: ارز، عنوان فاکتور، ارجاع
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                initialValue: _invoiceTitle,
                                onChanged: (value) {
                                  setState(() {
                                    _invoiceTitle = value.trim().isEmpty ? null : value.trim();
                                  });
                                },
                                decoration: const InputDecoration(
                                  labelText: 'عنوان فاکتور',
                                  hintText: 'مثال: فروش محصولات',
                                  border: OutlineInputBorder(),
                                ),
                                textInputAction: TextInputAction.next,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                initialValue: _invoiceReference,
                                onChanged: (value) {
                                  setState(() {
                                    _invoiceReference = value.trim().isEmpty ? null : value.trim();
                                  });
                                },
                                decoration: const InputDecoration(
                                  labelText: 'ارجاع',
                                  hintText: 'مثال: PO-2024-001',
                                  border: OutlineInputBorder(),
                                ),
                                textInputAction: TextInputAction.next,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(child: SizedBox()), // جای خالی
                            const SizedBox(width: 12),
                            const Expanded(child: SizedBox()), // جای خالی
                          ],
                        ),
                        const SizedBox(height: 24),

                        // ردیف سوم: فروشنده و کارمزد (فقط برای فروش و برگشت فروش)
                        if (_selectedInvoiceType == InvoiceType.sales || _selectedInvoiceType == InvoiceType.salesReturn) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: SellerPickerWidget(
                                  selectedSeller: _selectedSeller,
                                  onSellerChanged: (seller) {
                                    setState(() {
                                      _selectedSeller = seller;
                                      // تنظیم خودکار نوع کارمزد و مقادیر بر اساس فروشنده
                                      if (seller != null) {
                                        final isSales = _selectedInvoiceType == InvoiceType.sales;
                                        final isSalesReturn = _selectedInvoiceType == InvoiceType.salesReturn;
                                        final percent = isSales ? seller.commissionSalePercent : (isSalesReturn ? seller.commissionSalesReturnPercent : null);
                                        final amount = isSales ? seller.commissionSalesAmount : (isSalesReturn ? seller.commissionSalesReturnAmount : null);
                                        if (percent != null) {
                                          _commissionType = CommissionType.percentage;
                                          _commissionPercentage = percent;
                                          _commissionAmount = null;
                                        } else if (amount != null) {
                                          _commissionType = CommissionType.amount;
                                          _commissionAmount = amount;
                                          _commissionPercentage = null;
                                        }
                                      } else {
                                        _commissionType = null;
                                        _commissionPercentage = null;
                                        _commissionAmount = null;
                                      }
                                    });
                                  },
                                  businessId: widget.businessId,
                                  authStore: widget.authStore,
                                  isRequired: false,
                                  label: 'فروشنده/بازاریاب',
                                  hintText: 'جست‌وجو و انتخاب فروشنده یا بازاریاب',
                                ),
                              ),
                              const SizedBox(width: 12),
                              // فیلدهای کارمزد (فقط اگر فروشنده انتخاب شده باشد)
                              if (_selectedSeller != null) ...[
                                Expanded(
                                  child: CommissionTypeSelector(
                                    selectedType: _commissionType,
                                    onTypeChanged: (type) {
                                      setState(() {
                                        _commissionType = type;
                                        // پاک کردن مقادیر قبلی هنگام تغییر نوع
                                        if (type == CommissionType.percentage) {
                                          _commissionAmount = null;
                                        } else if (type == CommissionType.amount) {
                                          _commissionPercentage = null;
                                        }
                                      });
                                    },
                                    isRequired: false,
                                    label: 'نوع کارمزد',
                                    hintText: 'انتخاب نوع کارمزد',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // فیلد درصد کارمزد (فقط اگر نوع درصدی انتخاب شده)
                                if (_commissionType == CommissionType.percentage)
                                  Expanded(
                                    child: CommissionPercentageField(
                                      initialValue: _commissionPercentage,
                                      onChanged: (percentage) {
                                        setState(() {
                                          _commissionPercentage = percentage;
                                        });
                                      },
                                      isRequired: false,
                                      label: 'درصد کارمزد',
                                      hintText: 'مثال: 5.5',
                                    ),
                                  )
                                // فیلد مبلغ کارمزد (فقط اگر نوع مبلغی انتخاب شده)
                                else if (_commissionType == CommissionType.amount)
                                  Expanded(
                                    child: CommissionAmountField(
                                      initialValue: _commissionAmount,
                                      onChanged: (amount) {
                                        setState(() {
                                          _commissionAmount = amount;
                                        });
                                      },
                                      isRequired: false,
                                      label: 'مبلغ کارمزد',
                                      hintText: 'مثال: 100000',
                                    ),
                                  )
                                else
                                  const Expanded(child: SizedBox()),
                                const SizedBox(width: 12),
                              ] else ...[
                                const Expanded(child: SizedBox()),
                                const SizedBox(width: 12),
                                const Expanded(child: SizedBox()),
                                const SizedBox(width: 12),
                              ],
                              const Expanded(child: SizedBox()), // جای خالی
                            ],
                          ),
                        ],
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 32),
              
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveInvoice() async {
    final validation = _validateAndBuildPayload();
    if (validation is String) {
      _showError(validation);
      return;
    }
    final payload = validation as Map<String, dynamic>;

    try {
      final service = InvoiceService(apiClient: ApiClient());
      await service.createInvoice(businessId: widget.businessId, payload: payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('فاکتور با موفقیت ثبت شد'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      _showError('خطا در ذخیره فاکتور: ${e.toString()}');
    }
  }

  dynamic _validateAndBuildPayload() {
    // اعتبارسنجی‌های پایه
    if (_selectedInvoiceType == null) {
      return 'نوع فاکتور الزامی است';
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
    // اعتبارسنجی ردیف‌ها
    for (int i = 0; i < _lineItems.length; i++) {
      final r = _lineItems[i];
      if (r.productId == null) {
        return 'محصول ردیف ${i + 1} انتخاب نشده است';
      }
      if ((r.quantity) <= 0) {
        return 'تعداد ردیف ${i + 1} باید بزرگ‌تر از صفر باشد';
      }
      if (r.unitPrice < 0) {
        return 'قیمت واحد ردیف ${i + 1} نمی‌تواند منفی باشد';
      }
      if (r.discountType == 'percent' && (r.discountValue < 0 || r.discountValue > 100)) {
        return 'درصد تخفیف ردیف ${i + 1} باید بین 0 تا 100 باشد';
      }
      if (r.taxRate < 0 || r.taxRate > 100) {
        return 'درصد مالیات ردیف ${i + 1} باید بین 0 تا 100 باشد';
      }
      // الزام انبار در حالت ثبت اسناد انبار و کالاهای تحت کنترل موجودی
      if (_postInventory && r.trackInventory) {
        final isOut = _selectedInvoiceType == InvoiceType.sales ||
                      _selectedInvoiceType == InvoiceType.purchaseReturn ||
                      _selectedInvoiceType == InvoiceType.directConsumption ||
                      _selectedInvoiceType == InvoiceType.waste;
        final isIn = _selectedInvoiceType == InvoiceType.purchase ||
                     _selectedInvoiceType == InvoiceType.salesReturn;
        if ((isOut || isIn) && r.warehouseId == null) {
          return 'انبار ردیف ${i + 1} الزامی است';
        }
      }
    }

    final isSalesOrReturn = _selectedInvoiceType == InvoiceType.sales || _selectedInvoiceType == InvoiceType.salesReturn;
    final isPurchaseOrReturn = _selectedInvoiceType == InvoiceType.purchase || _selectedInvoiceType == InvoiceType.purchaseReturn;
    
    // اعتبارسنجی مشتری برای فروش
    if (isSalesOrReturn && _selectedCustomer == null) {
      return 'انتخاب مشتری الزامی است';
    }
    
    // اعتبارسنجی تامین‌کننده برای خرید
    if (isPurchaseOrReturn && _selectedSupplier == null) {
      return 'انتخاب تامین‌کننده الزامی است';
    }

    // اعتبارسنجی کارمزد در حالت فروش
    if (isSalesOrReturn && _selectedSeller != null && _commissionType != null) {
      if (_commissionType == CommissionType.percentage) {
        final p = _commissionPercentage ?? 0;
        if (p < 0 || p > 100) return 'درصد کارمزد باید بین 0 تا 100 باشد';
      } else if (_commissionType == CommissionType.amount) {
        final a = _commissionAmount ?? 0;
        if (a < 0) return 'مبلغ کارمزد نمی‌تواند منفی باشد';
      }
    }

    // تبدیل نوع فاکتور به فرمت API
    String _convertInvoiceTypeToApi(InvoiceType type) {
      return 'invoice_${type.value}';
    }
    
    // ساخت extra_info با person_id و totals
    final extraInfo = <String, dynamic>{
      'totals': {
        'gross': _sumSubtotal,
        'discount': _sumDiscount,
        'tax': _sumTax,
        'net': _sumTotal,
      },
    };
    // سوییچ ثبت اسناد انبار
    extraInfo['post_inventory'] = _postInventory;
    
    // افزودن person_id بر اساس نوع فاکتور
    if (isSalesOrReturn && _selectedCustomer != null) {
      extraInfo['person_id'] = _selectedCustomer!.id;
    } else if (isPurchaseOrReturn && _selectedSupplier != null) {
      extraInfo['person_id'] = _selectedSupplier!.id;
    }
    
    // افزودن اطلاعات فروشنده و کارمزد (اختیاری)
    if (isSalesOrReturn && _selectedSeller != null) {
      extraInfo['seller_id'] = _selectedSeller!.id;
      if (_commissionType != null) {
        extraInfo['commission'] = {
          'type': _commissionType == CommissionType.percentage ? 'percentage' : 'amount',
          if (_commissionType == CommissionType.percentage && _commissionPercentage != null)
            'value': _commissionPercentage,
          if (_commissionType == CommissionType.amount && _commissionAmount != null)
            'value': _commissionAmount,
        };
      }
    }
    
    // ساخت payload
    final payload = <String, dynamic>{
      'invoice_type': _convertInvoiceTypeToApi(_selectedInvoiceType!),
      'document_date': _invoiceDate!.toIso8601String().split('T')[0], // فقط تاریخ بدون زمان
      'currency_id': _selectedCurrencyId,
      'is_proforma': _isDraft,
      'extra_info': extraInfo,
      if (_invoiceTitle != null && _invoiceTitle!.isNotEmpty) 'description': _invoiceTitle,
      'lines': _lineItems.map((e) => _serializeLineItem(e)).toList(),
    };
    
    // افزودن payments اگر وجود دارد
    if (_transactions.isNotEmpty) {
      payload['payments'] = _transactions.map((t) => t.toJson()).toList();
    }
    
    return payload;
  }

  Map<String, dynamic> _serializeLineItem(InvoiceLineItem e) {
    // تعیین movement بر اساس نوع فاکتور
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
    // برای production، movement باید در UI تعیین شود (می‌تواند out یا in باشد)
    
    // محاسبه مقادیر
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
        if (_postInventory && e.warehouseId != null) 'warehouse_id': e.warehouseId,
        // اطلاعات اضافی برای ردیابی
        'unit': e.selectedUnit ?? e.mainUnit,
        'unit_price_source': e.unitPriceSource,
        'discount_type': e.discountType,
        'discount_value': e.discountValue,
        'tax_rate': e.taxRate,
      },
    };
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
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
                onChanged: (rows) {
                  setState(() {
                    _lineItems = rows;
                    _sumSubtotal = rows.fold<num>(0, (acc, e) => acc + e.subtotal);
                    _sumDiscount = rows.fold<num>(0, (acc, e) => acc + e.discountAmount);
                    _sumTax = rows.fold<num>(0, (acc, e) => acc + e.taxAmount);
                    _sumTotal = rows.fold<num>(0, (acc, e) => acc + e.total);
                  });
                },
              ),
              const SizedBox(height: 12),
              // نوار خلاصه جمع‌ها در والد (برای همگام‌سازی با سایر بخش‌ها)
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: InvoiceTransactionsWidget(
            transactions: _transactions,
            businessId: widget.businessId,
            calendarController: widget.calendarController,
            invoiceType: _selectedInvoiceType ?? InvoiceType.sales,
            onChanged: (transactions) {
              setState(() {
                _transactions = transactions;
              });
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsTab() {
    final theme = Theme.of(context);
    
    // بررسی اینکه آیا فاکتور فروش یا برگشت از فروش است و پیش‌نویس نیست
    final isSalesOrReturn = _selectedInvoiceType == InvoiceType.sales || 
                           _selectedInvoiceType == InvoiceType.salesReturn;
    final showTaxFolderOption = isSalesOrReturn && !_isDraft;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // عنوان بخش
              Text(
                'تنظیمات فاکتور',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),

              // تنظیمات انبار
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
                        onChanged: (value) {
                          setState(() {
                            _postInventory = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              
              // چاپ فاکتور بعد از صدور
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        title: const Text('چاپ فاکتور بعد از صدور'),
                        subtitle: const Text('فاکتور بلافاصله پس از ذخیره چاپ شود'),
                        value: _printAfterSave,
                        onChanged: (value) {
                          setState(() {
                            _printAfterSave = value;
                          });
                        },
                      ),
                      
                      // تنظیمات چاپ (فقط اگر چاپ فعال باشد)
                      if (_printAfterSave) ...[
                        const Divider(),
                        const SizedBox(height: 16),
                        
                        // انتخاب پرینتر
                        DropdownButtonFormField<String>(
                          initialValue: _selectedPrinter,
                          decoration: const InputDecoration(
                            labelText: 'پرینتر',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'default', child: Text('پرینتر پیش‌فرض')),
                            DropdownMenuItem(value: 'printer1', child: Text('پرینتر 1')),
                            DropdownMenuItem(value: 'printer2', child: Text('پرینتر 2')),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedPrinter = value;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // انتخاب سایز کاغذ
                        DropdownButtonFormField<String>(
                          initialValue: _selectedPaperSize,
                          decoration: const InputDecoration(
                            labelText: 'سایز کاغذ',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'A4', child: Text('A4')),
                            DropdownMenuItem(value: 'A5', child: Text('A5')),
                            DropdownMenuItem(value: 'A6', child: Text('A6')),
                            DropdownMenuItem(value: '80mm', child: Text('80mm (فیش)')),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedPaperSize = value;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // فاکتور رسمی
                        SwitchListTile(
                          title: const Text('فاکتور رسمی'),
                          subtitle: const Text('فاکتور با مهر و امضا رسمی چاپ شود'),
                          value: _isOfficialInvoice,
                          onChanged: (value) {
                            setState(() {
                              _isOfficialInvoice = value;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // انتخاب قالب چاپ
                        DropdownButtonFormField<String>(
                          initialValue: _selectedPrintTemplate,
                          decoration: const InputDecoration(
                            labelText: 'قالب چاپ',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'standard', child: Text('قالب استاندارد')),
                            DropdownMenuItem(value: 'compact', child: Text('قالب فشرده')),
                            DropdownMenuItem(value: 'detailed', child: Text('قالب تفصیلی')),
                            DropdownMenuItem(value: 'custom', child: Text('قالب سفارشی')),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedPrintTemplate = value;
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // ارسال به کارپوشه مودیان
              if (showTaxFolderOption) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          title: const Text('ارسال به کارپوشه مودیان'),
                          subtitle: const Text('فاکتور پس از ثبت به کارپوشه مودیان مالیاتی ارسال شود'),
                          value: _sendToTaxFolder,
                          onChanged: (value) {
                            setState(() {
                              _sendToTaxFolder = value;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              
              const SizedBox(height: 24),
              
              // اطلاعات اضافی
              Card(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: theme.colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'اطلاعات',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '• تنظیمات چاپ فقط برای فاکتورهای نهایی اعمال می‌شود\n'
                        '• ارسال به کارپوشه مودیان فقط برای فاکتورهای فروش و برگشت از فروش فعال است\n'
                        '• فاکتورهای پیش‌نویس به کارپوشه مودیان ارسال نمی‌شوند',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
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
}