import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../widgets/permission/access_denied_page.dart';
import '../../widgets/invoice/invoice_type_combobox.dart';
import '../../widgets/invoice/code_field_widget.dart';
import '../../widgets/invoice/customer_combobox_widget.dart';
import '../../widgets/invoice/seller_picker_widget.dart';
import '../../widgets/invoice/commission_percentage_field.dart';
import '../../widgets/invoice/commission_type_selector.dart';
import '../../widgets/invoice/commission_amount_field.dart';
import '../../widgets/date_input_field.dart';
import '../../widgets/banking/currency_picker_widget.dart';
import '../../core/date_utils.dart';
import '../../models/invoice_type_model.dart';
import '../../models/customer_model.dart';
import '../../models/person_model.dart';
import '../../widgets/invoice/line_items_table.dart';
import '../../utils/number_formatters.dart';
import '../../services/currency_service.dart';
import '../../core/api_client.dart';

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
  late TabController _tabController;
  
  InvoiceType? _selectedInvoiceType;
  bool _isDraft = false;
  String? _invoiceNumber;
  bool _autoGenerateInvoiceNumber = true;
  Customer? _selectedCustomer;
  Person? _selectedSeller;
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
                        
                        // مشتری
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
                                        if (seller.commissionSalePercent != null) {
                                          _commissionType = CommissionType.percentage;
                                          _commissionPercentage = seller.commissionSalePercent;
                                          _commissionAmount = null;
                                        } else if (seller.commissionSalesAmount != null) {
                                          _commissionType = CommissionType.amount;
                                          _commissionAmount = seller.commissionSalesAmount;
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
                              child: CustomerComboboxWidget(
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
                                        if (seller.commissionSalePercent != null) {
                                          _commissionType = CommissionType.percentage;
                                          _commissionPercentage = seller.commissionSalePercent;
                                          _commissionAmount = null;
                                        } else if (seller.commissionSalesAmount != null) {
                                          _commissionType = CommissionType.amount;
                                          _commissionAmount = seller.commissionSalesAmount;
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
              
              // دکمه ادامه
              Center(
                child: ElevatedButton.icon(
                  onPressed: (_selectedInvoiceType != null && _invoiceDate != null) ? _continueToInvoiceForm : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text('ادامه ایجاد فاکتور'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    minimumSize: const Size(200, 48),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // نمایش اطلاعات انتخاب شده
              if (_selectedInvoiceType != null || _invoiceDate != null || _dueDate != null)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'اطلاعات انتخاب شده:',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // نمایش اطلاعات در دو ستون
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_selectedInvoiceType != null)
                                  _buildInfoItem('نوع فاکتور', _selectedInvoiceType!.label),
                                if (_invoiceDate != null)
                                  _buildInfoItem('تاریخ فاکتور', HesabixDateUtils.formatForDisplay(_invoiceDate, widget.calendarController.isJalali == true)),
                                if (_dueDate != null)
                                  _buildInfoItem('تاریخ سررسید', HesabixDateUtils.formatForDisplay(_dueDate, widget.calendarController.isJalali == true)),
                                if (_selectedCurrencyId != null)
                                  _buildInfoItem('ارز فاکتور', 'انتخاب شده'),
                              ],
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_selectedSeller != null)
                                  _buildInfoItem('فروشنده/بازاریاب', '${_selectedSeller!.displayName} (${_selectedSeller!.personTypes.isNotEmpty ? _selectedSeller!.personTypes.first.persianName : 'نامشخص'})'),
                                if (_commissionType != null)
                                  _buildInfoItem('نوع کارمزد', _commissionType!.label),
                                if (_commissionPercentage != null)
                                  _buildInfoItem('درصد کارمزد', '${_commissionPercentage!.toStringAsFixed(1)}%'),
                                if (_commissionAmount != null)
                                  _buildInfoItem('مبلغ کارمزد', '${_commissionAmount!.toStringAsFixed(0)} ریال'),
                                if (_invoiceTitle != null)
                                  _buildInfoItem('عنوان فاکتور', _invoiceTitle!),
                                if (_invoiceReference != null)
                                  _buildInfoItem('ارجاع', _invoiceReference!),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  void _continueToInvoiceForm() {
    if (_selectedInvoiceType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لطفا نوع فاکتور را انتخاب کنید'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    final invoiceNumberText = _autoGenerateInvoiceNumber
        ? 'شماره فاکتور: اتوماتیک\n'
        : (_invoiceNumber != null 
            ? 'شماره فاکتور: $_invoiceNumber\n'
            : 'شماره فاکتور: انتخاب نشده\n');
    
    final customerText = _selectedCustomer != null
        ? 'مشتری: ${_selectedCustomer!.name}\n'
        : 'مشتری: خویشتنفروش\n';

    final sellerText = _selectedSeller != null
        ? 'فروشنده/بازاریاب: ${_selectedSeller!.displayName} (${_selectedSeller!.personTypes.isNotEmpty ? _selectedSeller!.personTypes.first.persianName : 'نامشخص'})\n'
        : '';

    final commissionText = _commissionPercentage != null
        ? 'درصد کارمزد: ${_commissionPercentage!.toStringAsFixed(1)}%\n'
        : '';

    final invoiceDateText = _invoiceDate != null
        ? 'تاریخ فاکتور: ${HesabixDateUtils.formatForDisplay(_invoiceDate, widget.calendarController.isJalali == true)}\n'
        : 'تاریخ فاکتور: انتخاب نشده\n';

    final dueDateText = _dueDate != null
        ? 'تاریخ سررسید: ${HesabixDateUtils.formatForDisplay(_dueDate, widget.calendarController.isJalali == true)}\n'
        : 'تاریخ سررسید: انتخاب نشده\n';

    final currencyText = _selectedCurrencyId != null
        ? 'ارز فاکتور: انتخاب شده\n'
        : 'ارز فاکتور: انتخاب نشده\n';

    final titleText = _invoiceTitle != null
        ? 'عنوان فاکتور: $_invoiceTitle\n'
        : 'عنوان فاکتور: انتخاب نشده\n';

    final referenceText = _invoiceReference != null
        ? 'ارجاع: $_invoiceReference\n'
        : 'ارجاع: انتخاب نشده\n';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('نوع فاکتور: ${_selectedInvoiceType!.label}\n$invoiceNumberText$customerText$sellerText$commissionText$invoiceDateText$dueDateText$currencyText$titleText$referenceText\nفرم کامل فاکتور به زودی اضافه خواهد شد'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 5),
      ),
    );
    
    // TODO: در آینده می‌توانید به صفحه فرم کامل فاکتور بروید
    // Navigator.push(
    //   context,
    //   MaterialPageRoute(
    //     builder: (context) => InvoiceFormPage(
    //       businessId: widget.businessId,
    //       authStore: widget.authStore,
    //       invoiceType: _selectedInvoiceType!,
    //       invoiceNumber: _invoiceNumber,
    //     ),
    //   ),
    // );
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
                onChanged: (rows) {
                  setState(() {
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
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 64,
            color: Colors.grey,
          ),
          SizedBox(height: 16),
          Text(
            'تراکنش‌ها',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'این بخش در آینده پیاده‌سازی خواهد شد',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.settings_outlined,
            size: 64,
            color: Colors.grey,
          ),
          SizedBox(height: 16),
          Text(
            'تنظیمات',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'این بخش در آینده پیاده‌سازی خواهد شد',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}