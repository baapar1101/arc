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
import '../../widgets/invoice/bom_explosion_widget.dart';
import '../../utils/number_formatters.dart';
import '../../utils/number_normalizer.dart';
import '../../services/currency_service.dart';
import '../../core/api_client.dart';
import '../../services/person_service.dart';
import '../../models/invoice_transaction.dart';
import '../../models/invoice_line_item.dart';
import '../../services/invoice_service.dart';
import '../../services/credit_api_service.dart';
import '../../models/credit_models.dart';

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
  // نادیده گرفتن اعتبار مشتری برای این فاکتور
  bool _ignoreCreditCheck = false;
  
  InvoiceType? _selectedInvoiceType;
  bool _isDraft = false;
  String? _invoiceNumber;
  final bool _autoGenerateInvoiceNumber = true;
  Customer? _selectedCustomer;
  Person? _selectedSeller;
  Person? _selectedSupplier; // برای فاکتورهای خرید
  double? _customerBalance;
  String? _customerStatus;
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
  
  // فروش اقساطی (MVP)
  bool _useInstallments = false;
  int? _numInstallments;
  double? _downPayment;
  double? _interestRate; // درصد کل دوره
  DateTime? _firstInstallmentDueDate;
  String _installmentPeriod = 'monthly'; // monthly | days
  int? _installmentPeriodDays; // در صورت انتخاب days
  // برنامه اقساط دستی
  List<Map<String, dynamic>> _installmentRows = <Map<String, dynamic>>[];
  // پلن‌های اقساط
  List<InstallmentPlan> _installmentPlans = <InstallmentPlan>[];
  InstallmentPlan? _selectedInstallmentPlan;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this); // شروع با 4 تب
    _attachTabListener();
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
    // بارگذاری پلن‌های فعال اقساط
    _loadInstallmentPlans();
  }

  void _attachTabListener() {
    _tabController.addListener(() {
      try {
        final isSettingsSelected = _tabController.index == (_tabController.length - 1);
        if (isSettingsSelected) {
          // بارگذاری تازه پلن‌ها هنگام ورود به تب تنظیمات
          _loadInstallmentPlans();
        }
      } catch (_) {}
    });
  }

  Future<void> _loadInstallmentPlans() async {
    try {
      final items = await CreditApiService.listInstallmentPlans(widget.businessId, onlyActive: true);
      setState(() {
        _installmentPlans = items;
      });
    } catch (_) {}
  }

  Widget _buildInstallmentsTab() {
    // ابزارها: تولید خودکار، افزودن/حذف ردیف
    void autoDistribute() {
      final n = _numInstallments ?? 0;
      if (n <= 0) return;
      final start = _firstInstallmentDueDate ?? _invoiceDate ?? DateTime.now();
      final periodDays = (_installmentPeriod == 'monthly') ? 30 : (_installmentPeriodDays ?? 30);
      // محاسبه اصل با لحاظ پیش‌پرداخت، بدون اعشار
      final totalNet = _sumTotal.toDouble();
      final principalTarget = (totalNet - (_downPayment ?? 0)).clamp(0, double.infinity);
      final principalTotal = principalTarget.round(); // کل اصل بدون اعشار
      // توزیع یکنواخت اصل بدون اعشار
      final basePrincipal = principalTotal ~/ n;
      int remainderPrincipal = principalTotal - (basePrincipal * n);
      // محاسبه سود کل و توزیع بدون اعشار
      final rate = (_interestRate ?? 0.0);
      final interestTotal = ((principalTotal * (rate / 100.0))).round();
      final baseInterest = interestTotal ~/ n;
      int remainderInterest = interestTotal - (baseInterest * n);
      final rows = <Map<String, dynamic>>[];
      for (int i = 0; i < n; i++) {
        final due = start.add(Duration(days: periodDays * i));
        final principal = basePrincipal + (remainderPrincipal > 0 ? 1 : 0);
        if (remainderPrincipal > 0) remainderPrincipal -= 1;
        final interest = baseInterest + (remainderInterest > 0 ? 1 : 0);
        if (remainderInterest > 0) remainderInterest -= 1;
        rows.add({
          'seq': i + 1,
          'due_date': due,
          'principal': principal.toDouble(),
          'interest': interest.toDouble(),
          'total': (principal + interest).toDouble(),
        });
      }
      setState(() => _installmentRows = rows);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // انتخاب پلن اقساط و اعمال خودکار
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<InstallmentPlan>(
                  value: _selectedInstallmentPlan,
                  items: _installmentPlans.map((p) {
                    return DropdownMenuItem(
                      value: p,
                      child: Text('${p.name} • ${p.numInstallments} ${AppLocalizations.of(context).installmentsCount} / ${p.periodDays} ${AppLocalizations.of(context).installmentDaysLength}'),
                    );
                  }).toList(),
                  onChanged: (v) {
                    setState(() {
                      _selectedInstallmentPlan = v;
                      final plan = v;
                      if (plan != null) {
                        _useInstallments = true;
                        _numInstallments = plan.numInstallments;
                        _installmentPeriod = 'days';
                        _installmentPeriodDays = plan.periodDays;
                        _interestRate = plan.interestRate ?? 0.0;
                        final dpPercent = plan.downPaymentPercent ?? 0.0;
                        _downPayment = (_sumTotal.toDouble() * dpPercent / 100.0);
                      }
                    });
                    autoDistribute();
                  },
                  decoration: InputDecoration(labelText: AppLocalizations.of(context).selectInstallmentPlan),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  final plan = _selectedInstallmentPlan;
                  if (plan == null) return;
                  setState(() {
                    _useInstallments = true;
                    _numInstallments = plan.numInstallments;
                    _installmentPeriod = 'days';
                    _installmentPeriodDays = plan.periodDays;
                    _interestRate = plan.interestRate ?? 0.0;
                    // محاسبه پیش‌پرداخت از درصد پلن بر اساس جمع کنونی
                    final dpPercent = plan.downPaymentPercent ?? 0.0;
                    _downPayment = (_sumTotal.toDouble() * dpPercent / 100.0);
                    _firstInstallmentDueDate = _invoiceDate ?? DateTime.now();
                  });
                  autoDistribute();
                },
                icon: const Icon(Icons.playlist_add_check),
                label: Text(AppLocalizations.of(context).applyPlan),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // تنظیمات پلن و پارامترها (تجمیع‌شده)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // تعداد اقساط و پیش‌پرداخت
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('num_${_numInstallments ?? 0}'),
                          initialValue: formatNumberForInput(_numInstallments, decimalPlaces: 0),
                          decoration: InputDecoration(labelText: AppLocalizations.of(context).installmentsCount, border: const OutlineInputBorder()),
                          keyboardType: TextInputType.number,
                          inputFormatters: const [
                            EnglishDigitsFormatter(),
                            ThousandsSeparatorInputFormatter(allowDecimal: false),
                          ],
                          onChanged: (v) {
                            final n = parseFormattedInt(v);
                            setState(() => _numInstallments = n);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('down_${_downPayment ?? 0}'),
                          initialValue: formatNumberForInput(_downPayment),
                          decoration: InputDecoration(labelText: AppLocalizations.of(context).downPayment, border: const OutlineInputBorder()),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: const [
                            EnglishDigitsFormatter(),
                            ThousandsSeparatorInputFormatter(allowDecimal: true),
                          ],
                          onChanged: (v) {
                            final d = parseFormattedDouble(v);
                            setState(() => _downPayment = d);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // نرخ سود و دوره‌بندی
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('rate_${_interestRate ?? 0}'),
                          initialValue: formatNumberForInput(_interestRate),
                          decoration: InputDecoration(labelText: AppLocalizations.of(context).interestRatePercent, border: const OutlineInputBorder()),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: const [
                            EnglishDigitsFormatter(),
                            ThousandsSeparatorInputFormatter(allowDecimal: true),
                          ],
                          onChanged: (v) {
                            final r = parseFormattedDouble(v);
                            setState(() => _interestRate = r);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _installmentPeriod,
                          decoration: InputDecoration(labelText: AppLocalizations.of(context).installmentsPeriod, border: const OutlineInputBorder()),
                          items: [
                            DropdownMenuItem(value: 'monthly', child: Text(AppLocalizations.of(context).installmentsMonthly)),
                            DropdownMenuItem(value: 'days', child: Text(AppLocalizations.of(context).installmentsDaysBased)),
                          ],
                          onChanged: (v) {
                            setState(() {
                              _installmentPeriod = v ?? 'monthly';
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_installmentPeriod == 'days')
                    TextFormField(
                      key: ValueKey('days_${_installmentPeriodDays ?? 0}'),
                      initialValue: formatNumberForInput(_installmentPeriodDays, decimalPlaces: 0),
                      decoration: InputDecoration(labelText: AppLocalizations.of(context).installmentDaysLength, border: const OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                      inputFormatters: const [
                        EnglishDigitsFormatter(),
                        ThousandsSeparatorInputFormatter(allowDecimal: false),
                      ],
                      onChanged: (v) {
                        final d = parseFormattedInt(v);
                        setState(() => _installmentPeriodDays = d);
                      },
                    ),
                  if (_installmentPeriod == 'days') const SizedBox(height: 12),
                  // تاریخ سررسید اولین قسط
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 320,
                      child: DateInputField(
                        labelText: AppLocalizations.of(context).firstInstallmentDueDate,
                        value: _firstInstallmentDueDate ?? _invoiceDate ?? DateTime.now(),
                        onChanged: (d) {
                          setState(() => _firstInstallmentDueDate = d);
                        },
                        calendarController: widget.calendarController,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_selectedCustomer != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.person),
                    const SizedBox(width: 8),
                    Expanded(child: Text('مشتری: ${_selectedCustomer!.name}')),
                    if (_customerBalance != null) Text('تراز: ${_customerBalance!.toStringAsFixed(0)}'),
                    const SizedBox(width: 8),
                    if (_customerStatus != null) Chip(label: Text(_customerStatus!)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: autoDistribute,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('تولید خودکار اقساط'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    final idx = _installmentRows.length + 1;
                    _installmentRows.add({
                      'seq': idx,
                      'due_date': _firstInstallmentDueDate ?? _invoiceDate ?? DateTime.now(),
                      'principal': 0.0,
                      'interest': 0.0,
                      'total': 0.0,
                    });
                  });
                },
                icon: const Icon(Icons.add),
                label: const Text('افزودن قسط'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  // تراز اختلاف
                  final n = _installmentRows.length;
                  if (n == 0) return;
                  final totalNet = _sumTotal.toDouble();
                  final principalTarget = (totalNet - (_downPayment ?? 0)).clamp(0, double.infinity);
                  double sumPrincipal = 0;
                  for (final r in _installmentRows) {
                    sumPrincipal += (r['principal'] as num?)?.toDouble() ?? 0.0;
                  }
                  double remaining = sumPrincipal - principalTarget;
                  for (int idx = n - 1; idx >= 0 && remaining.abs() > 0.0001; idx--) {
                    final current = (_installmentRows[idx]['principal'] as num?)?.toDouble() ?? 0.0;
                    double newPrincipal;
                    if (remaining > 0) {
                      final canReduce = current;
                      final reduce = remaining > canReduce ? canReduce : remaining;
                      newPrincipal = (current - reduce).clamp(0, double.infinity);
                      remaining -= reduce;
                    } else {
                      newPrincipal = current + (-remaining);
                      remaining = 0;
                    }
                    _installmentRows[idx]['principal'] = newPrincipal;
                    _installmentRows[idx]['total'] =
                        newPrincipal + ((_installmentRows[idx]['interest'] as num?)?.toDouble() ?? 0.0);
                  }
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('اختلاف اصل اقساط تراز شد')),
                  );
                },
                icon: const Icon(Icons.tune),
                label: const Text('تراز اختلاف اصل'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: const [
                      Expanded(child: Text('ردیف')),
                      Expanded(child: Text('تاریخ سررسید')),
                      Expanded(child: Text('اصل')),
                      Expanded(child: Text('سود')),
                      Expanded(child: Text('جمع')),
                      SizedBox(width: 40),
                    ],
                  ),
                  const Divider(),
                  ..._installmentRows.asMap().entries.map((entry) {
                    final i = entry.key;
                    final r = entry.value;
                    final seq = (r['seq'] as int?) ?? (i + 1);
                    final due = (r['due_date'] as DateTime?) ?? DateTime.now();
                    final principal = (r['principal'] as num?)?.toDouble() ?? 0.0;
                    final interest = (r['interest'] as num?)?.toDouble() ?? 0.0;
                    final total = (r['total'] as num?)?.toDouble() ?? (principal + interest);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(child: Text('#$seq')),
                          Expanded(
                            child: DateInputField(
                              value: due,
                              calendarController: widget.calendarController,
                              labelText: 'تاریخ',
                              onChanged: (d) {
                                setState(() => _installmentRows[i]['due_date'] = d ?? due);
                              },
                            ),
                          ),
                          Expanded(
                            child: TextFormField(
                              initialValue: formatNumberForInput(principal, decimalPlaces: 0),
                              keyboardType: TextInputType.number,
                              inputFormatters: const [
                                EnglishDigitsFormatter(),
                                ThousandsSeparatorInputFormatter(allowDecimal: false),
                              ],
                              onChanged: (v) {
                                final pInt = parseFormattedInt(v) ?? 0;
                                final p = pInt.toDouble();
                                setState(() {
                                  _installmentRows[i]['principal'] = p;
                                  _installmentRows[i]['total'] = p + (( _installmentRows[i]['interest'] as num?)?.toDouble() ?? 0.0);
                                });
                              },
                              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                            ),
                          ),
                          Expanded(
                            child: TextFormField(
                              initialValue: formatNumberForInput(interest, decimalPlaces: 0),
                              keyboardType: TextInputType.number,
                              inputFormatters: const [
                                EnglishDigitsFormatter(),
                                ThousandsSeparatorInputFormatter(allowDecimal: false),
                              ],
                              onChanged: (v) {
                                final sInt = parseFormattedInt(v) ?? 0;
                                final s = sInt.toDouble(); // سود بدون اعشار
                                setState(() {
                                  _installmentRows[i]['interest'] = s;
                                  _installmentRows[i]['total'] = s + (( _installmentRows[i]['principal'] as num?)?.toDouble() ?? 0.0);
                                });
                              },
                              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                            ),
                          ),
                          Expanded(
                            child: TextFormField(
                              initialValue: formatNumberForInput(total, decimalPlaces: 0),
                              keyboardType: TextInputType.number,
                              inputFormatters: const [
                                EnglishDigitsFormatter(),
                                ThousandsSeparatorInputFormatter(allowDecimal: false),
                              ],
                              onChanged: (v) {
                                final totInt = parseFormattedInt(v) ?? 0;
                                final tot = totInt.toDouble();
                                setState(() {
                                  _installmentRows[i]['total'] = tot;
                                });
                              },
                              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _installmentRows.removeAt(i);
                              });
                            },
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'حذف',
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(),
                  // خلاصه اقساط
                  Builder(
                    builder: (context) {
                      double sumPrincipal = 0;
                      double sumInterest = 0;
                      double sumTotal = 0;
                      for (final r in _installmentRows) {
                        sumPrincipal += (r['principal'] as num?)?.toDouble() ?? 0.0;
                        sumInterest += (r['interest'] as num?)?.toDouble() ?? 0.0;
                        sumTotal += (r['total'] as num?)?.toDouble() ?? 0.0;
                      }
                      final targetPrincipal = (_sumTotal.toDouble() - (_downPayment ?? 0)).clamp(0, double.infinity);
                      final diff = sumPrincipal - targetPrincipal;
                      final diffColor = diff.abs() <= 1 ? Colors.green : Colors.orange;
                      return Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Chip(label: Text('جمع اصل: ${formatWithThousands(sumPrincipal, decimalPlaces: 0)}')),
                            Chip(label: Text('جمع سود: ${formatWithThousands(sumInterest, decimalPlaces: 0)}')),
                            Chip(label: Text('جمع اقساط: ${formatWithThousands(sumTotal, decimalPlaces: 0)}')),
                            Chip(
                              label: Text('اختلاف اصل: ${formatWithThousands(diff, decimalPlaces: 0)}'),
                              backgroundColor: diffColor.withOpacity(0.12),
                              labelStyle: TextStyle(color: diffColor),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
    // اگر فروش اقساطی فعال باشد، تب اقساط اضافه می‌شود
    final base = 4;
    final addInstallmentsTab = (_useInstallments && (type == InvoiceType.sales || type == InvoiceType.salesReturn));
    return base + (addInstallmentsTab ? 1 : 0);
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

  Future<void> _loadCustomerBalance() async {
    try {
      if (_selectedCustomer == null) return;
      final svc = PersonService(apiClient: ApiClient());
      final p = await svc.getPerson(_selectedCustomer!.id);
      setState(() {
        _customerBalance = p.balance;
        _customerStatus = p.status;
      });
    } catch (_) {
      // ignore failures silently
    }
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
            message: t.saveInvoice,
            child: IconButton(
              onPressed: _saveInvoice,
              icon: const Icon(Icons.save),
              tooltip: t.saveInvoice,
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(icon: const Icon(Icons.info_outline), text: t.invoiceInfoTab),
            Tab(icon: const Icon(Icons.inventory_2_outlined), text: t.productsServicesTab),
            if (_shouldShowTransactionsTab)
              Tab(icon: const Icon(Icons.receipt_long_outlined), text: t.transactionsTab),
            if (_useInstallments && (_selectedInvoiceType == InvoiceType.sales || _selectedInvoiceType == InvoiceType.salesReturn))
              const Tab(icon: Icon(Icons.payments_outlined), text: 'اقساط'),
            Tab(icon: const Icon(Icons.settings_outlined), text: t.settingsTab),
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
          // تب اقساط (در صورت فعال بودن)
          if (_useInstallments && (_selectedInvoiceType == InvoiceType.sales || _selectedInvoiceType == InvoiceType.salesReturn)) _buildInstallmentsTab(),
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
                                      _attachTabListener();
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
                                _customerBalance = null;
                                _customerStatus = null;
                              });
                              _loadCustomerBalance();
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
                                      _attachTabListener();
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
                                              _customerBalance = null;
                                              _customerStatus = null;
                                            });
                                            _loadCustomerBalance();
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
    final t = AppLocalizations.of(context);
    final validation = _validateAndBuildPayload(t);
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
          content: Text(t.invoiceCreatedSuccess),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      _showError(t.saveInvoiceErrorWithMessage(e.toString()));
    }
  }

  dynamic _validateAndBuildPayload(AppLocalizations t) {
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
    // نادیده گرفتن اعتبار مشتری (فقط در فروش معنادار است؛ اما در payload همیشه ارسال می‌شود)
    extraInfo['ignore_credit_check'] = _ignoreCreditCheck;
    
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
    // افزودن طرح اقساط (در صورت فعال بودن)
    if (isSalesOrReturn && _useInstallments) {
      if ((_numInstallments ?? 0) <= 0) {
        return t.invalidInstallmentsCount;
      }
      // اگر برنامه اقساط دستی است، مجموع اصل اقساط باید با (جمع فاکتور - پیش‌پرداخت) برابر باشد
      if (_installmentRows.isNotEmpty) {
        final totalNet = _sumTotal.toDouble();
        final principalTarget = (totalNet - (_downPayment ?? 0)).clamp(0, double.infinity);
        double sumPrincipal = 0;
        for (final r in _installmentRows) {
          sumPrincipal += (r['principal'] as num?)?.toDouble() ?? 0.0;
        }
        // تلورانس 1 ریال
        if ((sumPrincipal - principalTarget).abs() > 1) {
          return 'جمع اصل اقساط (${sumPrincipal.toStringAsFixed(0)}) با مبلغ قابل دریافت (${principalTarget.toStringAsFixed(0)}) برابر نیست';
        }
      }
      final due0 = (_firstInstallmentDueDate ?? _invoiceDate ?? DateTime.now())
          .toIso8601String()
          .split('T')
          .first;
      final plan = <String, dynamic>{
        'down_payment': _downPayment ?? 0,
        'num_installments': _numInstallments,
        'first_due_date': due0,
        if (_installmentPeriod == 'monthly') 'period': 'monthly',
        if (_installmentPeriod == 'days') 'period_days': _installmentPeriodDays ?? 30,
        if (_interestRate != null && _installmentRows.isEmpty) 'interest_rate': _interestRate,
        'method': 'flat',
      };
      // اگر برنامه دستی تعریف شده، اضافه کن
      if (_installmentRows.isNotEmpty) {
        final rows = <Map<String, dynamic>>[];
        double interestTotal = 0;
        for (var i = 0; i < _installmentRows.length; i++) {
          final r = _installmentRows[i];
          final dueDate = (r['due_date'] as DateTime? ?? _firstInstallmentDueDate ?? _invoiceDate ?? DateTime.now())
              .toIso8601String()
              .split('T')
              .first;
          final principal = (r['principal'] as num?)?.toDouble() ?? 0.0;
          final interest = (r['interest'] as num?)?.toDouble() ?? 0.0;
          final total = (r['total'] as num?)?.toDouble() ?? (principal + interest);
          interestTotal += interest;
          rows.add({
            'seq': (r['seq'] as int?) ?? (i + 1),
            'due_date': dueDate,
            'principal': principal,
            'interest': interest,
            'total': total,
          });
        }
        plan['schedule'] = rows;
        plan['interest_total'] = interestTotal;
      }
      extraInfo['installment_plan'] = plan;
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
              // ویجت انفجار فرمول (فقط برای فاکتور تولید)
              if (_selectedInvoiceType == InvoiceType.production) ...[
                BomExplosionWidget(
                  businessId: widget.businessId,
                  onExploded: (newItems) {
                    setState(() {
                      // افزودن ردیف‌های جدید به لیست موجود
                      _lineItems = [..._lineItems, ...newItems];
                      // محاسبه مجدد جمع‌ها
                      _sumSubtotal = _lineItems.fold<num>(0, (acc, e) => acc + e.subtotal);
                      _sumDiscount = _lineItems.fold<num>(0, (acc, e) => acc + e.discountAmount);
                      _sumTax = _lineItems.fold<num>(0, (acc, e) => acc + e.taxAmount);
                      _sumTotal = _lineItems.fold<num>(0, (acc, e) => acc + e.total);
                    });
                  },
                ),
                const SizedBox(height: 16),
              ],
              InvoiceLineItemsTable(
                businessId: widget.businessId,
                selectedCurrencyId: _selectedCurrencyId,
                invoiceType: (_selectedInvoiceType?.value ?? 'sales'),
                postInventory: _postInventory,
                initialRows: _lineItems,
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
            selectedCurrencyId: _selectedCurrencyId,
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

              // فروش اقساطی
              if (isSalesOrReturn) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          title: Text(AppLocalizations.of(context).installmentsTitle),
                          subtitle: Text(AppLocalizations.of(context).installmentsSubtitle),
                          value: _useInstallments,
                          onChanged: (value) {
                            setState(() {
                              _useInstallments = value;
                              _firstInstallmentDueDate ??= _invoiceDate ?? DateTime.now();
                              // همگام‌سازی TabController با تعداد تب‌ها پس از تغییر وضعیت اقساط
                              final newTabCount = _getTabCountForType(_selectedInvoiceType);
                              if (newTabCount != _tabController.length) {
                                _tabController.dispose();
                                _tabController = TabController(length: newTabCount, vsync: this);
                                _attachTabListener();
                              }
                              if (value == true) {
                                // در صورت فعال‌سازی فروش اقساطی، پلن‌ها را تازه‌سازی کن
                                _loadInstallmentPlans();
                                // انتقال خودکار به تب اقساط (در صورت وجود)
                                if (_selectedInvoiceType == InvoiceType.sales || _selectedInvoiceType == InvoiceType.salesReturn) {
                                  try {
                                    // تب اقساط همیشه قبل از تب تنظیمات قرار می‌گیرد
                                    final installmentsTabIndex = _tabController.length - 2;
                                    if (installmentsTabIndex >= 0 && installmentsTabIndex < _tabController.length) {
                                      _tabController.index = installmentsTabIndex;
                                    }
                                  } catch (_) {}
                                }
                              }
                            });
                          },
                        ),
                        // سایر تنظیمات اقساط به تب «اقساط» منتقل شد
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

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
                      const Divider(),
                      // نادیده گرفتن اعتبار مشتری (فقط برای فاکتور فروش)
                      if (_selectedInvoiceType == InvoiceType.sales)
                        SwitchListTile(
                          title: const Text('نادیده گرفتن اعتبار مشتری'),
                          subtitle: const Text('در صورت فعال بودن، محدودیت اعتبار برای این فاکتور اعمال نمی‌شود'),
                          value: _ignoreCreditCheck,
                          onChanged: (value) => setState(() => _ignoreCreditCheck = value),
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
                          decoration: InputDecoration(
                            labelText: AppLocalizations.of(context).printTemplate,
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem(value: 'standard', child: Text(AppLocalizations.of(context).templateStandard)),
                            DropdownMenuItem(value: 'compact', child: Text(AppLocalizations.of(context).templateCompact)),
                            DropdownMenuItem(value: 'detailed', child: Text(AppLocalizations.of(context).templateDetailed)),
                            DropdownMenuItem(value: 'custom', child: Text(AppLocalizations.of(context).templateCustom)),
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