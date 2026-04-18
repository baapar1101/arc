import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/utils/web/web_utils.dart' as web_utils;
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
import '../../widgets/project/project_selector_widget.dart';
import '../../models/invoice_type_model.dart';
import '../../models/customer_model.dart';
import '../../models/person_model.dart';
import '../../widgets/invoice/line_items_table.dart';
import '../../widgets/invoice/invoice_transactions_widget.dart';
import '../../widgets/invoice/bom_explosion_widget.dart';
import '../../services/bom_service.dart';
import '../../widgets/invoice/warehouse_combobox_widget.dart';
import '../../utils/number_formatters.dart';
import '../../utils/number_normalizer.dart';
import '../../services/currency_service.dart';
import '../../core/api_client.dart';
import '../../utils/responsive_helper.dart';
import '../../services/business_api_service.dart';
import '../../services/person_service.dart';
import '../../services/report_template_service.dart';
import '../../models/invoice_transaction.dart';
import '../../models/invoice_line_item.dart';
import '../../services/invoice_service.dart';
import '../../services/credit_api_service.dart';
import '../../models/credit_models.dart';import '../../utils/snackbar_helper.dart';


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
  // تنظیمات انبار / حواله (none | draft | posted)
  String _invoiceWarehouseReleaseMode = 'draft';
  bool _warehouseReleaseModeFromLocal = false;
  int? _documentWarehouseId; // انبار کلی در سطح سند (برای استفاده در حواله‌های انبار)

  bool get _postInventory => _invoiceWarehouseReleaseMode != 'none';
  late TabController _tabController;
  // نادیده گرفتن اعتبار مشتری برای این فاکتور
  bool _ignoreCreditCheck = false;
  
  InvoiceType? _selectedInvoiceType;
  bool _isDraft = false;
  bool _isSaving = false;
  String? _invoiceNumber;
  final bool _autoGenerateInvoiceNumber = true;
  Customer? _selectedCustomer;
  Person? _selectedSeller;
  Person? _selectedSupplier; // برای فاکتورهای خرید
  double? _customerBalance;
  String? _customerStatus;
  Map<String, dynamic>? _customerCreditInfo; // credit_limit, effective_credit_limit, credit_check_enabled
  double? _commissionPercentage;
  double? _commissionAmount;
  CommissionType? _commissionType;
  DateTime? _invoiceDate;
  DateTime? _dueDate;
  int? _selectedCurrencyId;
  int? _selectedProjectId;
  String? _invoiceTitle;
  String? _invoiceReference;
  // جمع‌های محاسباتی ردیف‌ها
  num _sumSubtotal = 0;
  num _sumDiscount = 0;
  num _sumTax = 0;
  num _sumTotal = 0;
  
  // تنظیمات چاپ و ارسال
  bool _printAfterSave = false;
  String? _selectedPaperSize;
  bool _showStampOnPrint = true;
  String? _selectedPrintTemplate;
  String? _selectedPaperOrientation = 'landscape';
  bool _sendToTaxFolder = false;
  bool _hasUserCustomizedSettings = false;
  Map<String, dynamic>? _businessPrintSettingsDefault;
  Map<String, Map<String, dynamic>> _businessPrintSettingsPerType = {};
  List<Map<String, dynamic>> _availablePrintTemplates = const [];
  bool _isLoadingPrintTemplates = false;
  
  // تراکنش‌های فاکتور
  List<InvoiceTransaction> _transactions = [];
  // ردیف‌های فاکتور برای ساخت payload
  List<InvoiceLineItem> _lineItems = <InvoiceLineItem>[];
  // لیست شناسه فرمول‌های تولید استفاده شده در این فاکتور
  Set<int> _bomIds = <int>{};
  // هزینه عملیات/سربار تولید
  double? _productionOperationsTotal;
  
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
  
  // Controller های فیلدهای اقساطی برای جلوگیری از از دست رفتن فوکوس
  late final TextEditingController _numInstallmentsController;
  late final TextEditingController _downPaymentController;
  late final TextEditingController _interestRateController;
  late final TextEditingController _installmentPeriodDaysController;
  // Controller های فیلدهای جدول اقساط دستی (key: index)
  final Map<int, TextEditingController> _installmentPrincipalControllers = {};
  final Map<int, TextEditingController> _installmentInterestControllers = {};
  final Map<int, TextEditingController> _installmentTotalControllers = {};

  // خلاصه محاسبات اقساط
  double get _installmentsPrincipalTotal {
    double sum = 0;
    for (final r in _installmentRows) {
      sum += (r['principal'] as num?)?.toDouble() ?? 0.0;
    }
    return sum;
  }

  double get _installmentsInterestTotal {
    double sum = 0;
    for (final r in _installmentRows) {
      sum += (r['interest'] as num?)?.toDouble() ?? 0.0;
    }
    return sum;
  }

  double get _installmentsTotal {
    double sum = 0;
    for (final r in _installmentRows) {
      sum += (r['total'] as num?)?.toDouble() ?? 0.0;
    }
    return sum;
  }

  bool get _isSalesOrReturn =>
      _selectedInvoiceType == InvoiceType.sales || _selectedInvoiceType == InvoiceType.salesReturn;

  bool get _isCreditLimitExceededApprox {
    if (!_isSalesOrReturn) return false;
    if (_customerCreditInfo == null || _customerBalance == null) return false;
    final effectiveLimit = (_customerCreditInfo!['effective_credit_limit'] as num?)?.toDouble();
    if (effectiveLimit == null) return false;
    // بدهی فعلی (تراز منفی یعنی بدهکار)
    double currentDebt = 0;
    final bal = _customerBalance!;
    if (bal < 0) {
      currentDebt = -bal;
    }
    // مبلغ فاکتور (با مالیات)
    final gross = _sumSubtotal.toDouble();
    final discount = _sumDiscount.toDouble();
    final tax = _sumTax.toDouble();
    final totalWithTax = gross - discount + tax;
    // پرداخت‌های برنامه‌ریزی‌شده
    double plannedPaid = 0;
    for (final p in _transactions) {
      plannedPaid += (p.amount).toDouble();
    }
    double invoiceEffect = totalWithTax - plannedPaid;
    if (invoiceEffect < 0) invoiceEffect = 0;
    final newDebt = currentDebt + invoiceEffect;
    return newDebt > effectiveLimit + 0.01;
  }

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
    // افزودن یک ردیف پیش‌فرض کالا
    _lineItems = [
      InvoiceLineItem(
        quantity: 1,
        unitPrice: 0,
        unitPriceSource: 'manual',
        discountType: 'amount',
        discountValue: 0,
        taxRate: 0,
      ),
    ];
    // مقداردهی اولیه Controller های اقساطی
    _numInstallmentsController = TextEditingController();
    _downPaymentController = TextEditingController();
    _interestRateController = TextEditingController();
    _installmentPeriodDaysController = TextEditingController();
    // بارگذاری پلن‌های فعال اقساط
    _loadInstallmentPlans();
    _loadLocalSettingsForCurrentType();
    // بارگذاری تنظیمات چاپ کسب‌وکار
    _loadPrintSettings();
    _loadPrintTemplates();
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

  Future<void> _loadPrintTemplates() async {
    setState(() {
      _isLoadingPrintTemplates = true;
    });
    try {
      final service = ReportTemplateService(ApiClient());
      final templates = await service.listTemplates(
        businessId: widget.businessId,
        moduleKey: 'invoices',
        subtype: 'detail',
        status: 'published',
      );
      if (!mounted) return;
      setState(() {
        _availablePrintTemplates = templates;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _availablePrintTemplates = const [];
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPrintTemplates = false;
        });
      }
    }
  }

  Future<void> _loadPrintSettings() async {
    try {
      final data = await BusinessApiService.getPrintSettings(widget.businessId);
      final defaultSettings = (data['default'] as Map?)?.cast<String, dynamic>();
      final perTypeRaw = (data['per_type'] as Map?)?.cast<String, dynamic>();
      final perType = <String, Map<String, dynamic>>{};
      perTypeRaw?.forEach((key, value) {
        if (value is Map) {
          perType[key] = value.cast<String, dynamic>();
        }
      });
      if (!mounted) return;
      setState(() {
        _businessPrintSettingsDefault = defaultSettings;
        _businessPrintSettingsPerType = perType;
      });
      _applyPrintSettingsForCurrentType();
    } catch (e) {
      if (mounted) {
        _showError('خطا در دریافت تنظیمات چاپ: $e');
      }
    } finally {
      // no-op
    }
  }

  void _applyPrintSettingsForCurrentType() {
    if (_hasUserCustomizedSettings) {
      return;
    }
    final selectedType = _selectedInvoiceType;
    Map<String, dynamic>? target;
    if (selectedType != null) {
      final key = _convertInvoiceTypeToApi(selectedType);
      target = _businessPrintSettingsPerType[key];
    }
    target ??= _businessPrintSettingsDefault;
    if (target == null) {
      return;
    }
    final showStamp = target['show_stamp'];
    if (showStamp is bool) {
      setState(() {
        _showStampOnPrint = showStamp;
      });
    }
    _loadLocalSettingsForCurrentType();
  }

  void _loadLocalSettingsForCurrentType() {
    _warehouseReleaseModeFromLocal = false;
    void scheduleBusinessDefault() {
      if (!_warehouseReleaseModeFromLocal) {
        Future.microtask(() => _loadBusinessInvoiceWarehouseDefaults());
      }
    }

    if (!kIsWeb) {
      scheduleBusinessDefault();
      return;
    }
    final key = _currentSettingsStorageKey();
    if (key == null) {
      scheduleBusinessDefault();
      return;
    }
    final raw = web_utils.getLocalStorageValue(key);
    if (raw == null || raw.isEmpty) {
      scheduleBusinessDefault();
      return;
    }
    try {
      final Map<String, dynamic> data = jsonDecode(raw);
      setState(() {
        final savedPrintAfterSave = _parseBool(data['print_after_save']);
        if (savedPrintAfterSave != null) {
          _printAfterSave = savedPrintAfterSave;
        }
        _selectedPaperSize = data['paper_size']?.toString();
        _selectedPrintTemplate = data['print_template']?.toString();
        final orientation = data['orientation']?.toString();
        if (orientation != null && orientation.isNotEmpty) {
          _selectedPaperOrientation = orientation;
        }
        final showStamp = _parseBool(data['show_stamp']);
        if (showStamp != null) {
          _showStampOnPrint = showStamp;
        }
        final sendTax = _parseBool(data['send_to_tax_folder']);
        if (sendTax != null) {
          _sendToTaxFolder = sendTax;
        }
        final modeRaw = data['invoice_warehouse_release_mode']?.toString().trim().toLowerCase();
        if (modeRaw != null && (modeRaw == 'none' || modeRaw == 'draft' || modeRaw == 'posted')) {
          _invoiceWarehouseReleaseMode = modeRaw;
          _warehouseReleaseModeFromLocal = true;
        } else {
          final postInventory = _parseBool(data['post_inventory']);
          if (postInventory != null) {
            _warehouseReleaseModeFromLocal = true;
            _invoiceWarehouseReleaseMode = postInventory ? 'draft' : 'none';
          }
        }
        final documentWarehouseId = data['document_warehouse_id'];
        if (documentWarehouseId != null) {
          _documentWarehouseId = (documentWarehouseId is num) ? documentWarehouseId.toInt() : int.tryParse(documentWarehouseId.toString());
        }
        final ignoreCredit = _parseBool(data['ignore_credit_check']);
        if (ignoreCredit != null) {
          _ignoreCreditCheck = ignoreCredit;
        }
        final useInstallments = _parseBool(data['use_installments']);
        if (useInstallments != null) {
          _useInstallments = useInstallments;
        }
      });
      _hasUserCustomizedSettings = true;
      scheduleBusinessDefault();
    } catch (_) {
      scheduleBusinessDefault();
    }
  }

  Future<void> _loadBusinessInvoiceWarehouseDefaults() async {
    if (_warehouseReleaseModeFromLocal) return;
    try {
      final b = await BusinessApiService.getBusiness(widget.businessId);
      if (!mounted) return;
      setState(() {
        _invoiceWarehouseReleaseMode = b.invoiceWarehouseReleaseMode;
      });
    } catch (_) {
      // نادیده گرفتن؛ پیش‌فرض draft روی UI باقی می‌ماند
    }
  }

  void _saveLocalSettings() {
    if (!kIsWeb) return;
    final key = _currentSettingsStorageKey();
    if (key == null) return;
    final data = jsonEncode({
      'print_after_save': _printAfterSave,
      'paper_size': _selectedPaperSize,
      'print_template': _selectedPrintTemplate,
      'orientation': _selectedPaperOrientation,
      'show_stamp': _showStampOnPrint,
      'send_to_tax_folder': _sendToTaxFolder,
      'invoice_warehouse_release_mode': _invoiceWarehouseReleaseMode,
      'document_warehouse_id': _documentWarehouseId,
      'ignore_credit_check': _ignoreCreditCheck,
      'use_installments': _useInstallments,
    });
    web_utils.setLocalStorageValue(key, data);
  }

  bool? _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty) return null;
      if (normalized == 'true' || normalized == '1' || normalized == 'yes' || normalized == 'on') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no' || normalized == 'off') {
        return false;
      }
    }
    return null;
  }

  String? _currentSettingsStorageKey() {
    final type = _selectedInvoiceType;
    if (type == null) {
      return null;
    }
    return 'invoice_settings_${widget.businessId}_${type.value}';
  }

  Future<void> _loadCustomerCreditIfNeeded() async {
    if (_selectedCustomer == null) return;
    try {
      final data = await CreditApiService.getPersonCredit(widget.businessId, _selectedCustomer!.id);
      setState(() {
        _customerCreditInfo = data;
      });
    } catch (_) {
      // در صورت خطا، فقط نادیده بگیر
    }
  }

  // متد helper برای ایجاد یا دریافت Controller برای فیلدهای جدول اقساط
  TextEditingController _getInstallmentController(Map<int, TextEditingController> controllers, int index, double value, {bool updateIfChanged = true}) {
    if (!controllers.containsKey(index)) {
      controllers[index] = TextEditingController(
        text: formatNumberForInput(value, decimalPlaces: 0),
      );
    } else if (updateIfChanged) {
      // به‌روزرسانی مقدار Controller اگر تغییر کرده باشد
      final currentText = formatNumberForInput(value, decimalPlaces: 0);
      final controller = controllers[index]!;
      // فقط اگر مقدار واقعاً تغییر کرده باشد، به‌روز کن
      // توجه: این ممکن است مقدار تایپ شده توسط کاربر را بازنویسی کند
      // بنابراین فقط در autoDistribute استفاده می‌شود (updateIfChanged: false)
      if (controller.text != currentText) {
        controller.text = currentText;
      }
    }
    return controllers[index]!;
  }

  // پاک کردن Controller های اضافی وقتی ردیف‌ها حذف می‌شوند
  void _cleanupInstallmentControllers() {
    final maxIndex = _installmentRows.length - 1;
    // حذف Controller های مربوط به ردیف‌های حذف شده
    _installmentPrincipalControllers.removeWhere((key, _) => key > maxIndex);
    _installmentInterestControllers.removeWhere((key, _) => key > maxIndex);
    _installmentTotalControllers.removeWhere((key, _) => key > maxIndex);
  }

  Widget _buildInstallmentsTab() {
    // ابزارها: تولید خودکار، افزودن/حذف ردیف
    void autoDistribute() {
      final n = _numInstallments ?? 0;
      if (n <= 0) return;
      final start = _firstInstallmentDueDate ?? _invoiceDate ?? DateTime.now();
      final periodDays = (_installmentPeriod == 'monthly') ? 30 : (_installmentPeriodDays ?? 30);
      // محاسبه اصل با لحاظ پیش‌پرداخت
      final totalNet = _sumTotal.toDouble();
      final principalTarget = (totalNet - (_downPayment ?? 0)).clamp(0, double.infinity);
      final principalTotal = principalTarget;

      final method = _selectedInstallmentPlan?.method ?? 'flat';
      final rate = (_interestRate ?? 0.0);

      final rows = <Map<String, dynamic>>[];

      if (method == 'amortized' && rate > 0) {
        // قسط ثابت بر اساس نرخ سود هر دوره (rate درصد به‌ازای هر قسط)
        final i = rate / 100.0;
        final nDouble = n.toDouble();
        double installmentAmount;
        if (i == 0) {
          installmentAmount = principalTotal / nDouble;
        } else {
          final powFactor = math.pow(1 + i, nDouble) as double;
          installmentAmount = principalTotal * i * powFactor / (powFactor - 1);
        }
        double remainingPrincipal = principalTotal.toDouble();
        for (int k = 0; k < n; k++) {
          final due = start.add(Duration(days: periodDays * k));
          double interest = remainingPrincipal * i;
          double principalPay = installmentAmount - interest;
          if (k == n - 1) {
            // آخرین قسط: تسویه باقیمانده برای جلوگیری از خطای اعشاری
            principalPay = remainingPrincipal;
            interest = installmentAmount - principalPay;
          }
          if (principalPay < 0) principalPay = 0;
          remainingPrincipal -= principalPay;
          // رند کردن به مبلغ بدون اعشار
          final principalInt = principalPay.round();
          final interestInt = interest.round();
          rows.add({
            'seq': k + 1,
            'due_date': due,
            'principal': principalInt.toDouble(),
            'interest': interestInt.toDouble(),
            'total': (principalInt + interestInt).toDouble(),
          });
        }
        setState(() {
          _installmentRows = rows;
          // به‌روزرسانی Controller ها بعد از تغییر ردیف‌ها
          for (int idx = 0; idx < rows.length; idx++) {
            final principal = rows[idx]['principal'] as double? ?? 0.0;
            final interest = rows[idx]['interest'] as double? ?? 0.0;
            final total = rows[idx]['total'] as double? ?? 0.0;
            _getInstallmentController(_installmentPrincipalControllers, idx, principal, updateIfChanged: false);
            _getInstallmentController(_installmentInterestControllers, idx, interest, updateIfChanged: false);
            _getInstallmentController(_installmentTotalControllers, idx, total, updateIfChanged: false);
          }
          _cleanupInstallmentControllers();
        });
      } else {
        // روش ساده flat: تقسیم مساوی اصل و سود کل
        final principalTotalRounded = principalTotal.round(); // کل اصل بدون اعشار
        final basePrincipal = principalTotalRounded ~/ n;
        int remainderPrincipal = principalTotalRounded - (basePrincipal * n);
        final interestTotal = ((principalTotal * (rate / 100.0))).round();
        final baseInterest = interestTotal ~/ n;
        int remainderInterest = interestTotal - (baseInterest * n);
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
        setState(() {
          _installmentRows = rows;
          // به‌روزرسانی Controller ها بعد از تغییر ردیف‌ها
          for (int idx = 0; idx < rows.length; idx++) {
            final principal = rows[idx]['principal'] as double? ?? 0.0;
            final interest = rows[idx]['interest'] as double? ?? 0.0;
            final total = rows[idx]['total'] as double? ?? 0.0;
            _getInstallmentController(_installmentPrincipalControllers, idx, principal, updateIfChanged: false);
            _getInstallmentController(_installmentInterestControllers, idx, interest, updateIfChanged: false);
            _getInstallmentController(_installmentTotalControllers, idx, total, updateIfChanged: false);
          }
          _cleanupInstallmentControllers();
        });
      }
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
                        // به‌روزرسانی Controller ها
                        _numInstallmentsController.text = formatNumberForInput(_numInstallments, decimalPlaces: 0);
                        _downPaymentController.text = formatNumberForInput(_downPayment);
                        _interestRateController.text = formatNumberForInput(_interestRate);
                        _installmentPeriodDaysController.text = formatNumberForInput(_installmentPeriodDays, decimalPlaces: 0);
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
                    // به‌روزرسانی Controller ها
                    _numInstallmentsController.text = formatNumberForInput(_numInstallments, decimalPlaces: 0);
                    _downPaymentController.text = formatNumberForInput(_downPayment);
                    _interestRateController.text = formatNumberForInput(_interestRate);
                    _installmentPeriodDaysController.text = formatNumberForInput(_installmentPeriodDays, decimalPlaces: 0);
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
                          controller: _numInstallmentsController,
                          decoration: InputDecoration(labelText: AppLocalizations.of(context).installmentsCount, border: const OutlineInputBorder()),
                          keyboardType: TextInputType.number,
                          inputFormatters: const [
                            EnglishDigitsFormatter(),
                            ThousandsSeparatorInputFormatter(allowDecimal: false),
                          ],
                          onChanged: (v) {
                            final n = parseFormattedInt(v);
                            _numInstallments = n;
                            // بدون setState برای جلوگیری از rebuild
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _downPaymentController,
                          decoration: InputDecoration(labelText: AppLocalizations.of(context).downPayment, border: const OutlineInputBorder()),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: const [
                            EnglishDigitsFormatter(),
                            ThousandsSeparatorInputFormatter(allowDecimal: true),
                          ],
                          onChanged: (v) {
                            final d = parseFormattedDouble(v);
                            _downPayment = d;
                            // بدون setState برای جلوگیری از rebuild
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
                          controller: _interestRateController,
                          decoration: InputDecoration(labelText: AppLocalizations.of(context).interestRatePercent, border: const OutlineInputBorder()),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: const [
                            EnglishDigitsFormatter(),
                            ThousandsSeparatorInputFormatter(allowDecimal: true),
                          ],
                          onChanged: (v) {
                            final r = parseFormattedDouble(v);
                            _interestRate = r;
                            // بدون setState برای جلوگیری از rebuild
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
                      controller: _installmentPeriodDaysController,
                      decoration: InputDecoration(labelText: AppLocalizations.of(context).installmentDaysLength, border: const OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                      inputFormatters: const [
                        EnglishDigitsFormatter(),
                        ThousandsSeparatorInputFormatter(allowDecimal: false),
                      ],
                      onChanged: (v) {
                        final d = parseFormattedInt(v);
                        _installmentPeriodDays = d;
                        // بدون setState برای جلوگیری از rebuild
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('مشتری: ${_selectedCustomer!.name}'),
                          if (_customerCreditInfo != null) ...[
                            const SizedBox(height: 4),
                            Builder(builder: (context) {
                              final effectiveLimit = (_customerCreditInfo!['effective_credit_limit'] as num?)?.toDouble();
                              final used = (_customerBalance ?? 0) < 0 ? -_customerBalance! : 0;
                              final remaining = effectiveLimit != null ? (effectiveLimit - used) : null;
                              final creditEnabled = _customerCreditInfo!['credit_check_enabled'];
                              final enabledText = (creditEnabled == null)
                                  ? 'پیروی از تنظیمات سیستم'
                                  : (creditEnabled == true ? 'کنترل اعتبار فعال' : 'کنترل اعتبار غیرفعال');
                              final limitExceeded = _isCreditLimitExceededApprox;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (effectiveLimit != null)
                                    Text('سقف اعتبار مؤثر: ${effectiveLimit.toStringAsFixed(0)}'),
                                  if (remaining != null)
                                    Text('اعتبار باقیمانده تقریبی: ${remaining.toStringAsFixed(0)}'),
                                  Text(enabledText, style: Theme.of(context).textTheme.bodySmall),
                                  if (limitExceeded && !_ignoreCreditCheck)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'ثبت این فاکتور احتمالاً از سقف اعتبار عبور می‌کند و توسط سیستم رد می‌شود مگر این‌که گزینه نادیده گرفتن اعتبار را فعال کنید.',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red),
                                      ),
                                    ),
                                  if (limitExceeded && _ignoreCreditCheck)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'هشدار: این فاکتور با وجود عبور از سقف اعتبار، به دلیل فعال بودن نادیده گرفتن اعتبار ثبت خواهد شد.',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orange),
                                      ),
                                    ),
                                ],
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
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
                    final newIndex = _installmentRows.length;
                    _installmentRows.add({
                      'seq': idx,
                      'due_date': _firstInstallmentDueDate ?? _invoiceDate ?? DateTime.now(),
                      'principal': 0.0,
                      'interest': 0.0,
                      'total': 0.0,
                    });
                    // ایجاد Controller های جدید برای ردیف اضافه شده
                    _getInstallmentController(_installmentPrincipalControllers, newIndex, 0.0);
                    _getInstallmentController(_installmentInterestControllers, newIndex, 0.0);
                    _getInstallmentController(_installmentTotalControllers, newIndex, 0.0);
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
                  SnackBarHelper.show(context, message: 'اختلاف اصل اقساط تراز شد');
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
                      SizedBox(width: 50, child: Text('ردیف', textAlign: TextAlign.center)),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 50,
                            child: Center(
                              child: Text(
                                '#$seq',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ),
                          Expanded(
                            child: DateInputField(
                              value: due,
                              calendarController: widget.calendarController,
                              labelText: 'تاریخ',
                              isDense: true,
                              onChanged: (d) {
                                setState(() => _installmentRows[i]['due_date'] = d ?? due);
                              },
                            ),
                          ),
                          Expanded(
                            child: TextFormField(
                              controller: _getInstallmentController(_installmentPrincipalControllers, i, principal),
                              keyboardType: TextInputType.number,
                              inputFormatters: const [
                                EnglishDigitsFormatter(),
                                ThousandsSeparatorInputFormatter(allowDecimal: false),
                              ],
                              onChanged: (v) {
                                final pInt = parseFormattedInt(v) ?? 0;
                                final p = pInt.toDouble();
                                _installmentRows[i]['principal'] = p;
                                _installmentRows[i]['total'] = p + (( _installmentRows[i]['interest'] as num?)?.toDouble() ?? 0.0);
                                // به‌روزرسانی Controller جمع
                                final newTotal = _installmentRows[i]['total'] as double? ?? 0.0;
                                _getInstallmentController(_installmentTotalControllers, i, newTotal);
                                // بدون setState برای جلوگیری از rebuild
                              },
                              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                            ),
                          ),
                          Expanded(
                            child: TextFormField(
                              controller: _getInstallmentController(_installmentInterestControllers, i, interest),
                              keyboardType: TextInputType.number,
                              inputFormatters: const [
                                EnglishDigitsFormatter(),
                                ThousandsSeparatorInputFormatter(allowDecimal: false),
                              ],
                              onChanged: (v) {
                                final sInt = parseFormattedInt(v) ?? 0;
                                final s = sInt.toDouble(); // سود بدون اعشار
                                _installmentRows[i]['interest'] = s;
                                _installmentRows[i]['total'] = s + (( _installmentRows[i]['principal'] as num?)?.toDouble() ?? 0.0);
                                // به‌روزرسانی Controller جمع
                                final newTotal = _installmentRows[i]['total'] as double? ?? 0.0;
                                _getInstallmentController(_installmentTotalControllers, i, newTotal);
                                // بدون setState برای جلوگیری از rebuild
                              },
                              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                            ),
                          ),
                          Expanded(
                            child: TextFormField(
                              controller: _getInstallmentController(_installmentTotalControllers, i, total),
                              keyboardType: TextInputType.number,
                              inputFormatters: const [
                                EnglishDigitsFormatter(),
                                ThousandsSeparatorInputFormatter(allowDecimal: false),
                              ],
                              onChanged: (v) {
                                final totInt = parseFormattedInt(v) ?? 0;
                                final tot = totInt.toDouble();
                                _installmentRows[i]['total'] = tot;
                                // بدون setState برای جلوگیری از rebuild
                              },
                              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                // Dispose و حذف Controller های ردیف حذف شده
                                _installmentPrincipalControllers[i]?.dispose();
                                _installmentInterestControllers[i]?.dispose();
                                _installmentTotalControllers[i]?.dispose();
                                _installmentPrincipalControllers.remove(i);
                                _installmentInterestControllers.remove(i);
                                _installmentTotalControllers.remove(i);
                                
                                // حذف ردیف
                                _installmentRows.removeAt(i);
                                
                                // بازسازی Controller ها برای ردیف‌های باقی‌مانده با index جدید
                                // ابتدا همه Controller های بعدی را dispose کن
                                for (int idx = i; idx < _installmentRows.length + 10; idx++) {
                                  if (_installmentPrincipalControllers.containsKey(idx)) {
                                    _installmentPrincipalControllers[idx]?.dispose();
                                    _installmentInterestControllers[idx]?.dispose();
                                    _installmentTotalControllers[idx]?.dispose();
                                    _installmentPrincipalControllers.remove(idx);
                                    _installmentInterestControllers.remove(idx);
                                    _installmentTotalControllers.remove(idx);
                                  }
                                }
                                
                                // حالا Controller های جدید برای ردیف‌های باقی‌مانده بساز
                                for (int idx = 0; idx < _installmentRows.length; idx++) {
                                  final principal = (_installmentRows[idx]['principal'] as num?)?.toDouble() ?? 0.0;
                                  final interest = (_installmentRows[idx]['interest'] as num?)?.toDouble() ?? 0.0;
                                  final total = (_installmentRows[idx]['total'] as num?)?.toDouble() ?? 0.0;
                                  _getInstallmentController(_installmentPrincipalControllers, idx, principal, updateIfChanged: false);
                                  _getInstallmentController(_installmentInterestControllers, idx, interest, updateIfChanged: false);
                                  _getInstallmentController(_installmentTotalControllers, idx, total, updateIfChanged: false);
                                }
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
                      final sumPrincipal = _installmentsPrincipalTotal;
                      final sumInterest = _installmentsInterestTotal;
                      final sumTotal = _installmentsTotal;
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
                              backgroundColor: diffColor.withValues(alpha: 0.12),
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
    // اگر پیش‌فاکتور است، تب تراکنش‌ها نمایش داده نمی‌شود
    if (_isDraft) return false;
    return _selectedInvoiceType != InvoiceType.waste && 
           _selectedInvoiceType != InvoiceType.directConsumption && 
           _selectedInvoiceType != InvoiceType.production;
  }

  @override
  void dispose() {
    _tabController.dispose();
    // Dispose کردن Controller های اقساطی
    _numInstallmentsController.dispose();
    _downPaymentController.dispose();
    _interestRateController.dispose();
    _installmentPeriodDaysController.dispose();
    // Dispose کردن Controller های جدول اقساط دستی
    for (final controller in _installmentPrincipalControllers.values) {
      controller.dispose();
    }
    for (final controller in _installmentInterestControllers.values) {
      controller.dispose();
    }
    for (final controller in _installmentTotalControllers.values) {
      controller.dispose();
    }
    _installmentPrincipalControllers.clear();
    _installmentInterestControllers.clear();
    _installmentTotalControllers.clear();
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
              onPressed: _isSaving ? null : _saveInvoice,
              icon: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
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
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
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
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.isDesktop(context) ? 1600 : double.infinity,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // فیلدهای اصلی - responsive layout
              LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = ResponsiveHelper.isMobile(context);
                  // اگر عرض صفحه کمتر از 768 پیکسل باشد، تک ستونه
                  if (isMobile) {
                    return Column(
                      children: [
                        // نوع فاکتور
                        InvoiceTypeCombobox(
                          selectedType: _selectedInvoiceType,
                          onTypeChanged: (type) {
                            _handleInvoiceTypeChange(type);
                          },
                          isDraft: _isDraft,
                          onDraftChanged: (isDraft) {
                            setState(() {
                              _isDraft = isDraft;
                              // اگر پیش‌فاکتور فعال شد، اقساط را غیرفعال کن
                              if (isDraft && _useInstallments) {
                                _useInstallments = false;
                                _hasUserCustomizedSettings = true;
                                _numInstallments = null;
                                _downPayment = null;
                                _interestRate = null;
                                _firstInstallmentDueDate = null;
                                _installmentRows = [];
                                // همگام‌سازی TabController
                                final newTabCount = _getTabCountForType(_selectedInvoiceType);
                                if (newTabCount != _tabController.length) {
                                  _tabController.dispose();
                                  _tabController = TabController(length: newTabCount, vsync: this);
                                  _attachTabListener();
                                }
                              }
                            });
                            _saveLocalSettings();
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
                          invoiceDocumentCode: true,
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
                                _customerCreditInfo = null;
                              });
                              _loadCustomerBalance();
                              _loadCustomerCreditIfNeeded();
                            },
                            businessId: widget.businessId,
                            authStore: widget.authStore,
                            isRequired: false,
                            label: 'طرف حساب',
                            hintText: 'انتخاب طرف حساب',
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
                        
                        // پروژه
                        ProjectSelectorWidget(
                          businessId: widget.businessId,
                          apiClient: ApiClient(),
                          selectedProjectId: _selectedProjectId,
                          onChanged: (projectId) {
                            setState(() {
                              _selectedProjectId = projectId;
                            });
                          },
                          allowNull: true,
                          labelText: 'پروژه (اختیاری)',
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
                                  _handleInvoiceTypeChange(type);
                                },
                                isDraft: _isDraft,
                                onDraftChanged: (isDraft) {
                                  setState(() {
                                    _isDraft = isDraft;
                                    // اگر پیش‌فاکتور فعال شد، اقساط را غیرفعال کن
                                    if (isDraft && _useInstallments) {
                                      _useInstallments = false;
                                      _numInstallments = null;
                                      _downPayment = null;
                                      _interestRate = null;
                                      _firstInstallmentDueDate = null;
                                      _installmentRows = [];
                                      // همگام‌سازی TabController
                                      final newTabCount = _getTabCountForType(_selectedInvoiceType);
                                      if (newTabCount != _tabController.length) {
                                        _tabController.dispose();
                                        _tabController = TabController(length: newTabCount, vsync: this);
                                        _attachTabListener();
                                      }
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
                                onChanged: (number) {
                                  setState(() {
                                    _invoiceNumber = number;
                                  });
                                },
                                isRequired: true,
                                label: 'شماره فاکتور',
                                hintText: 'مثال: INV-2024-001',
                                autoGenerateCode: _autoGenerateInvoiceNumber,
                                invoiceDocumentCode: true,
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
                                          label: 'طرف حساب',
                                          hintText: 'انتخاب طرف حساب',
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
                            Expanded(
                              child: ProjectSelectorWidget(
                                businessId: widget.businessId,
                                apiClient: ApiClient(),
                                selectedProjectId: _selectedProjectId,
                                onChanged: (projectId) {
                                  setState(() {
                                    _selectedProjectId = projectId;
                                  });
                                },
                                allowNull: true,
                                labelText: 'پروژه (اختیاری)',
                              ),
                            ),
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

  Future<String?> _validateBomOutputs() async {
    if (_selectedInvoiceType != InvoiceType.production || _bomIds.isEmpty) {
      return null; // اعتبارسنجی BOM فقط برای فاکتور تولید لازم است
    }

    // جمع‌آوری product_id های موجود در ردیف‌های فاکتور با movement='in'
    final outputProductIdsInInvoice = <int>{};
    for (final line in _lineItems) {
      final movement = line.extraInfo?['movement']?.toString();
      if (movement == 'in' && line.productId != null) {
        outputProductIdsInInvoice.add(line.productId!);
      }
    }

    final bomService = BomService();
    
    // بررسی برای هر فرمول تولید
    for (final bomId in _bomIds) {
      try {
        final bom = await bomService.getById(
          businessId: widget.businessId,
          bomId: bomId,
        );

        if (bom.outputs.isEmpty) {
          // اگر فرمول خروجی ندارد، هشدار می‌دهیم اما خطا نمی‌دهیم
          continue;
        }

        // بررسی اینکه product_id فرمول در خروجی‌ها باشد (هشدار)
        final bomProductInOutputs = bom.outputs.any(
          (output) => output.outputProductId == bom.productId,
        );
        if (!bomProductInOutputs) {
          // این یک هشدار است، نه خطا - در لاگ ثبت می‌شود
          debugPrint(
            'هشدار: کالای فرمول تولید ${bom.name} (product_id: ${bom.productId}) '
            'در خروجی‌های فرمول تعریف نشده است.',
          );
        }

        // بررسی اینکه همه خروجی‌های فرمول در فاکتور وجود داشته باشند
        final missingOutputs = <String>[];
        for (final output in bom.outputs) {
          if (!outputProductIdsInInvoice.contains(output.outputProductId)) {
            final productName = output.outputProductName ?? 
                               output.outputProductCode ?? 
                               'کالا #${output.outputProductId}';
            missingOutputs.add(productName);
          }
        }

        if (missingOutputs.isNotEmpty) {
          final missingNames = missingOutputs.join('، ');
          return 'خروجی‌های فرمول تولید "${bom.name}" (نسخه: ${bom.version}) '
                 'که در فاکتور وجود ندارند: $missingNames. '
                 'لطفاً همه خروجی‌های فرمول تولید را در فاکتور شامل کنید.';
        }
      } catch (e) {
        // در صورت خطا در دریافت فرمول، ادامه می‌دهیم (اعتبارسنجی در بک‌اند انجام می‌شود)
        debugPrint('خطا در دریافت فرمول تولید $bomId: $e');
      }
    }

    return null; // همه چیز درست است
  }

  Future<void> _saveInvoice() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    final t = AppLocalizations.of(context);
    try {
      // اعتبارسنجی BOM outputs (async)
      if (_selectedInvoiceType == InvoiceType.production) {
        final bomValidation = await _validateBomOutputs();
        if (bomValidation != null) {
          _showError(bomValidation);
          return;
        }
      }

      final validation = _validateAndBuildPayload(t);
      if (validation is String) {
        _showError(validation);
        return;
      }
      final payload = validation as Map<String, dynamic>;

      // بررسی مبلغ صفر فاکتور
      if (_sumTotal == 0) {
        final confirmed = await _showZeroAmountWarning();
        if (!confirmed) {
          return; // کاربر انصراف داد
        }
      }

      try {
        final service = InvoiceService(apiClient: ApiClient());
        final result = await service.createInvoice(businessId: widget.businessId, payload: payload);
        final invoiceId = (result['id'] as num?)?.toInt();
        final invoiceCode = result['code']?.toString();

        if (!mounted) {
          return;
        }

        SnackBarHelper.show(context, message: t.invoiceCreatedSuccess);

        if (_printAfterSave) {
          if (invoiceId == null) {
            _showError('شناسه فاکتور برای چاپ در دسترس نیست');
          } else {
            await _printInvoiceAfterSave(
              service: service,
              invoiceId: invoiceId,
              invoiceCode: invoiceCode,
            );
          }
        }

        // هدایت به لیست فاکتورها بعد از ثبت موفق
        if (mounted) {
          context.goNamed(
            'business_invoice',
            pathParameters: {
              'business_id': widget.businessId.toString(),
            },
          );
        }
      } catch (e) {
        _showError(t.saveInvoiceErrorWithMessage(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _printInvoiceAfterSave({
    required InvoiceService service,
    required int invoiceId,
    String? invoiceCode,
  }) async {
    try {
      final query = <String, dynamic>{};
      final paperSize = _selectedPaperSize;
      if (paperSize != null && paperSize.isNotEmpty) {
        query['paper_size'] = paperSize;
      }
      final orientation = _selectedPaperOrientation;
      if (orientation != null && orientation.isNotEmpty) {
        query['orientation'] = orientation;
      }
      final templateId = int.tryParse(_selectedPrintTemplate ?? '');
      if (templateId != null) {
        query['template_id'] = templateId;
      }
      query['show_stamp'] = _showStampOnPrint ? 'true' : 'false';

      final bytes = await service.downloadInvoicePdf(
        businessId: widget.businessId,
        invoiceId: invoiceId,
        query: query.isEmpty ? null : query,
      );
      await _saveInvoicePdf(bytes, invoiceCode ?? 'invoice_$invoiceId');

      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: 'فایل PDF فاکتور دانلود شد');
    } catch (e) {
      if (!mounted) return;
      _showError('خطا در چاپ فاکتور: $e');
    }
  }

  Future<void> _saveInvoicePdf(List<int> bytes, String filename) async {
    if (!kIsWeb) {
      throw UnsupportedError('چاپ فاکتور فعلاً فقط در نسخه وب در دسترس است');
    }
    final trimmed = filename.trim();
    final safeName = trimmed.isEmpty ? 'invoice.pdf' : trimmed;
    final finalName = safeName.toLowerCase().endsWith('.pdf') ? safeName : '$safeName.pdf';
    await web_utils.saveBytesAsFileWeb(
      bytes,
      finalName,
      mimeType: 'application/pdf',
    );
  }

  String _convertInvoiceTypeToApi(InvoiceType type) {
    return 'invoice_${type.value}';
  }

  /// نمایش هشدار برای فاکتور با مبلغ صفر
  Future<bool> _showZeroAmountWarning() async {
    final theme = Theme.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: theme.colorScheme.error,
          size: 48,
        ),
        title: const Text('هشدار: مبلغ فاکتور صفر است'),
        content: const Text(
          'مبلغ کل فاکتور شما صفر است. این می‌تواند به دلایل زیر باشد:\n\n'
          '• کالای رایگان یا نمونه\n'
          '• تخفیف ۱۰۰٪\n'
          '• کالای تبلیغاتی\n\n'
          'آیا مطمئن هستید که می‌خواهید این فاکتور را ثبت کنید؟\n\n'
          'توجه: فاکتور با مبلغ صفر در گزارش‌های مالی نمایش داده می‌شود و ممکن است ثبت‌های حسابداری با مبلغ صفر ایجاد شود.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            child: const Text('بله، ثبت کن'),
          ),
        ],
      ),
    );
    return result ?? false;
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
    
    // اعتبارسنجی ویژه برای فاکتور تولید
    if (_selectedInvoiceType == InvoiceType.production) {
      // بررسی اینکه حداقل یک فرمول منفجر شده باشد
      if (_bomIds.isEmpty) {
        return 'برای فاکتور تولید، باید حداقل یک فرمول تولید را منفجر کنید';
      }
      
      // بررسی وجود movement در تمام ردیف‌ها
      int hasOutCount = 0;
      int hasInCount = 0;
      for (int i = 0; i < _lineItems.length; i++) {
        final r = _lineItems[i];
        final movement = r.extraInfo?['movement']?.toString();
        
        if (movement == null || (movement != 'in' && movement != 'out')) {
          return 'ردیف ${i + 1} باید movement مشخص داشته باشد (in یا out)';
        }
        
        if (movement == 'out') {
          hasOutCount++;
        } else if (movement == 'in') {
          hasInCount++;
        }
      }
      
      // بررسی وجود حداقل یک ردیف با movement: "out" (مواد اولیه)
      if (hasOutCount == 0) {
        return 'فاکتور تولید باید حداقل یک ردیف با movement: "out" داشته باشد (مواد اولیه)';
      }
      
      // بررسی وجود حداقل یک ردیف با movement: "in" (محصول نهایی)
      if (hasInCount == 0) {
        return 'فاکتور تولید باید حداقل یک ردیف با movement: "in" داشته باشد (محصول نهایی)';
      }
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
                      _selectedInvoiceType == InvoiceType.waste ||
                      (_selectedInvoiceType == InvoiceType.production && (r.extraInfo?['movement']?.toString() == 'out'));
        final isIn = _selectedInvoiceType == InvoiceType.purchase ||
                     _selectedInvoiceType == InvoiceType.salesReturn ||
                     (_selectedInvoiceType == InvoiceType.production && (r.extraInfo?['movement']?.toString() == 'in'));
        if ((isOut || isIn) && r.warehouseId == null) {
          return 'انبار ردیف ${i + 1} الزامی است';
        }
      }
    }

    final isSalesOrReturn = _selectedInvoiceType == InvoiceType.sales || _selectedInvoiceType == InvoiceType.salesReturn;
    final isPurchaseOrReturn = _selectedInvoiceType == InvoiceType.purchase || _selectedInvoiceType == InvoiceType.purchaseReturn;
    
    // اعتبارسنجی طرف حساب برای فروش
    if (isSalesOrReturn && _selectedCustomer == null) {
      return 'انتخاب طرف حساب الزامی است';
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

    // ساخت extra_info با person_id و totals
    final extraInfo = <String, dynamic>{
      'totals': {
        'gross': _sumSubtotal,
        'discount': _sumDiscount,
        'tax': _sumTax,
        'net': _sumTotal,
      },
    };
    extraInfo['post_inventory'] = _invoiceWarehouseReleaseMode != 'none';
    extraInfo['auto_post_warehouse'] = _invoiceWarehouseReleaseMode == 'posted';
    // انبار کلی در سطح سند (برای استفاده در حواله‌های انبار)
    if (_documentWarehouseId != null) {
      extraInfo['warehouse_id'] = _documentWarehouseId;
    }
    // نادیده گرفتن اعتبار مشتری (فقط در فروش معنادار است؛ اما در payload همیشه ارسال می‌شود)
    extraInfo['ignore_credit_check'] = _ignoreCreditCheck;
    // تاریخ سررسید سند (YYYY-MM-DD در extra_info)
    final dueForDoc = _dueDate ?? _invoiceDate;
    if (dueForDoc != null) {
      extraInfo['due_date'] = dueForDoc.toIso8601String().split('T').first;
    }

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
    
    // افزودن bom_ids برای فاکتور تولید
    if (_selectedInvoiceType == InvoiceType.production && _bomIds.isNotEmpty) {
      extraInfo['bom_ids'] = _bomIds.toList();
    }
    
    // افزودن هزینه عملیات/سربار تولید
    if (_selectedInvoiceType == InvoiceType.production && 
        _productionOperationsTotal != null && 
        _productionOperationsTotal! > 0) {
      extraInfo['production_operations_total'] = _productionOperationsTotal;
    }
    
    // ساخت payload
    final payload = <String, dynamic>{
      'invoice_type': _convertInvoiceTypeToApi(_selectedInvoiceType!),
      'document_date': _invoiceDate!.toIso8601String().split('T')[0], // فقط تاریخ بدون زمان
      'currency_id': _selectedCurrencyId,
      'is_proforma': _isDraft,
      'extra_info': extraInfo,
      if (_invoiceTitle != null && _invoiceTitle!.isNotEmpty) 'description': _invoiceTitle,
      if (_selectedProjectId != null) 'project_id': _selectedProjectId,
      'lines': _lineItems.map((e) => _serializeLineItem(e)).toList(),
    };
    
    // افزودن payments اگر وجود دارد
    if (_transactions.isNotEmpty) {
      payload['payments'] = _transactions.map((t) => t.toJson()).toList();
    }
    
    return payload;
  }

  Map<String, dynamic> _serializeLineItem(InvoiceLineItem e) {
    // تعیین movement بر اساس نوع فاکتور یا از extra_info
    String? movement;
    
    // اول از extra_info استفاده می‌کنیم (اگر از BOM آمده باشد)
    if (e.extraInfo != null && e.extraInfo!['movement'] != null) {
      movement = e.extraInfo!['movement'].toString();
    } else {
      // در غیر این صورت از نوع فاکتور تعیین می‌کنیم
      if (_selectedInvoiceType == InvoiceType.sales || 
          _selectedInvoiceType == InvoiceType.purchaseReturn ||
          _selectedInvoiceType == InvoiceType.directConsumption ||
          _selectedInvoiceType == InvoiceType.waste) {
        movement = 'out';
      } else if (_selectedInvoiceType == InvoiceType.purchase || 
                 _selectedInvoiceType == InvoiceType.salesReturn) {
        movement = 'in';
      }
    }
    // برای production، movement باید در extra_info تعیین شده باشد
    
    // محاسبه مقادیر
    final lineDiscount = e.discountAmount;
    final taxAmount = e.taxAmount;
    final lineTotal = e.total;
    
    // ساختن extra_info با ترکیب اطلاعات موجود و extra_info از InvoiceLineItem
    final extraInfo = <String, dynamic>{
      'unit_price': e.unitPrice,
      'line_discount': lineDiscount,
      'tax_amount': taxAmount,
      'line_total': lineTotal,
      // اطلاعات اضافی برای ردیابی
      'unit': e.selectedUnit ?? e.mainUnit,
      'unit_price_source': e.unitPriceSource,
      'discount_type': e.discountType,
      'discount_value': e.discountValue,
      'tax_rate': e.taxRate,
    };
    
    // اضافه کردن movement اگر وجود دارد
    if (movement != null) {
      extraInfo['movement'] = movement;
    }
    
    // اضافه کردن اطلاعات از extra_info InvoiceLineItem (مانند bom_id)
    if (e.extraInfo != null) {
      extraInfo.addAll(_stripLocalExtraInfo(e.extraInfo!));
    }
    
    // اضافه کردن warehouse_id به extra_info اگر وجود دارد
    if (e.warehouseId != null) {
      extraInfo['warehouse_id'] = e.warehouseId;
    }
    
    // اضافه کردن selected_instance_ids به extra_info برای کالاهای یونیک
    if (e.selectedInstanceIds != null && e.selectedInstanceIds!.isNotEmpty) {
      extraInfo['selected_instance_ids'] = e.selectedInstanceIds;
    }
    
    return <String, dynamic>{
      'product_id': e.productId,
      'quantity': e.quantity,
      if ((e.description ?? '').isNotEmpty) 'description': e.description,
      'extra_info': extraInfo,
    };
  }

  Map<String, dynamic> _stripLocalExtraInfo(Map<String, dynamic> source) {
    final sanitized = <String, dynamic>{};
    source.forEach((key, value) {
      if (key.toString().startsWith('_local_')) {
        return;
      }
      sanitized[key] = value;
    });
    return sanitized;
  }

  void _showError(String message) {
    SnackBarHelper.showError(context, message: message);
  }

  /// مدیریت تغییر نوع فاکتور و پاک کردن ردیف‌های BOM
  void _handleInvoiceTypeChange(InvoiceType? newType) {
    // اگر نوع جدید null باشد، کاری نکن
    if (newType == null) return;
    
    final oldType = _selectedInvoiceType;
    final hasBomLines = _lineItems.any((item) => 
      item.extraInfo?['bom_id'] != null || 
      item.extraInfo?['movement'] == 'out' || 
      item.extraInfo?['movement'] == 'in'
    );
    
    setState(() {
      _selectedInvoiceType = newType;
      _hasUserCustomizedSettings = false;
      
      // اگر نوع فاکتور از تولید به نوع دیگری تغییر می‌کند
      if (oldType == InvoiceType.production && newType != InvoiceType.production) {
        // پاک کردن bom_ids
        _bomIds.clear();
        
        // پاک کردن هزینه عملیات/سربار تولید
        _productionOperationsTotal = null;
        
        // پاک کردن ردیف‌هایی که از BOM آمده‌اند یا movement دارند
        _lineItems.removeWhere((item) {
          final extraInfo = item.extraInfo;
          if (extraInfo == null) return false;
          
          // حذف ردیف‌هایی که bom_id دارند
          if (extraInfo['bom_id'] != null) return true;
          
          // حذف ردیف‌هایی که movement دارند (مخصوص فاکتور تولید)
          final movement = extraInfo['movement'];
          if (movement == 'out' || movement == 'in') return true;
          
          return false;
        });
        
        // محاسبه مجدد جمع‌ها پس از حذف ردیف‌ها
        _sumSubtotal = _lineItems.fold<num>(0, (acc, e) => acc + e.subtotal);
        _sumDiscount = _lineItems.fold<num>(0, (acc, e) => acc + e.discountAmount);
        _sumTax = _lineItems.fold<num>(0, (acc, e) => acc + e.taxAmount);
        _sumTotal = _lineItems.fold<num>(0, (acc, e) => acc + e.total);
        
        // اگر هیچ ردیفی باقی نماند، یک ردیف پیش‌فرض اضافه کن
        if (_lineItems.isEmpty) {
          _lineItems = [
            InvoiceLineItem(
              quantity: 1,
              unitPrice: 0,
              unitPriceSource: 'manual',
              discountType: 'amount',
              discountValue: 0,
              taxRate: 0,
            ),
          ];
        }
      } else if (newType != InvoiceType.production) {
        // اگر نوع جدید تولید نیست، bom_ids را پاک کن (برای اطمینان)
        _bomIds.clear();
        _productionOperationsTotal = null;
      }
      
      // پاک کردن انتخاب‌های قبلی هنگام تغییر نوع فاکتور
      if (newType == InvoiceType.purchase || newType == InvoiceType.purchaseReturn) {
        _selectedCustomer = null;
        _selectedSeller = null;
      } else if (newType == InvoiceType.sales || newType == InvoiceType.salesReturn) {
        _selectedSupplier = null;
      } else {
        _selectedCustomer = null;
        _selectedSupplier = null;
        _selectedSeller = null;
      }
      
      // به‌روزرسانی TabController اگر تعداد تب‌ها تغییر کرده
      final newTabCount = _getTabCountForType(newType);
      if (newTabCount != _tabController.length) {
        _tabController.dispose();
        _tabController = TabController(length: newTabCount, vsync: this);
        _attachTabListener();
      }
    });
    
    // نمایش هشدار به کاربر در صورت وجود ردیف‌های BOM
    if (hasBomLines && newType != InvoiceType.production) {
      SnackBarHelper.showInfo(
        context,
        message: 'ردیف‌های مربوط به فرمول تولید حذف شدند زیرا نوع فاکتور تغییر کرد.',
      );
    }
    
    _applyPrintSettingsForCurrentType();
  }

  Widget _buildProductsTab() {
    return SingleChildScrollView(
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
                  productionOperationsTotal: _productionOperationsTotal,
                  onExploded: (newItems, bomId) {
                    setState(() {
                      // افزودن ردیف‌های جدید به لیست موجود
                      _lineItems = [..._lineItems, ...newItems];
                      // افزودن bom_id به لیست
                      _bomIds.add(bomId);
                      // محاسبه مجدد جمع‌ها
                      _sumSubtotal = _lineItems.fold<num>(0, (acc, e) => acc + e.subtotal);
                      _sumDiscount = _lineItems.fold<num>(0, (acc, e) => acc + e.discountAmount);
                      _sumTax = _lineItems.fold<num>(0, (acc, e) => acc + e.taxAmount);
                      _sumTotal = _lineItems.fold<num>(0, (acc, e) => acc + e.total);
                    });
                  },
                ),
                // نمایش هشدار در صورت عدم وجود انفجار فرمول
                if (_bomIds.isEmpty && _lineItems.isEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.error,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'برای فاکتور تولید، باید حداقل یک فرمول تولید را منفجر کنید',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
              ],
              InvoiceLineItemsTable(
                businessId: widget.businessId,
                authStore: widget.authStore,
                selectedCurrencyId: _selectedCurrencyId,
                invoiceType: (_selectedInvoiceType?.value ?? 'sales'),
                postInventory: _postInventory,
                initialRows: _lineItems,
                calendarController: widget.calendarController,
                onChanged: (rows) {
                  setState(() {
                    // بررسی bom_id های موجود در ردیف‌های جدید
                    final bomIdsInRows = <int>{};
                    for (final row in rows) {
                      final bomId = row.extraInfo?['bom_id'];
                      if (bomId is int) {
                        bomIdsInRows.add(bomId);
                      }
                    }
                    
                    // حذف bom_id هایی که دیگر در ردیف‌ها نیستند
                    _bomIds.removeWhere((bomId) => !bomIdsInRows.contains(bomId));
                    
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
            authStore: widget.authStore,
            invoiceTotal: _sumTotal, // ارسال مبلغ کل فاکتور
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
    final t = AppLocalizations.of(context);
    
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
                          // غیرفعال در حالت پیش‌فاکتور (onChanged: null باعث غیرفعال شدن می‌شود)
                          onChanged: _isDraft ? null : (value) {
                            setState(() {
                              _useInstallments = value;
                              _firstInstallmentDueDate ??= _invoiceDate ?? DateTime.now();
                              _hasUserCustomizedSettings = true;
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
                            _saveLocalSettings();
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
                      Text(
                        t.invoiceWarehouseReleaseSectionTitle,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t.invoiceWarehouseReleaseSectionSubtitle,
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: <ButtonSegment<String>>[
                          ButtonSegment<String>(value: 'none', label: Text(t.invoiceWarehouseReleaseNone)),
                          ButtonSegment<String>(value: 'draft', label: Text(t.invoiceWarehouseReleaseDraft)),
                          ButtonSegment<String>(value: 'posted', label: Text(t.invoiceWarehouseReleasePosted)),
                        ],
                        selected: <String>{_invoiceWarehouseReleaseMode},
                        onSelectionChanged: (Set<String> next) {
                          setState(() {
                            _invoiceWarehouseReleaseMode = next.first;
                            _warehouseReleaseModeFromLocal = true;
                            _hasUserCustomizedSettings = true;
                          });
                          _saveLocalSettings();
                        },
                      ),
                      // فیلد انتخاب انبار کلی در سطح سند (برای استفاده در حواله‌های انبار)
                      if (_postInventory) ...[
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: WarehouseComboboxWidget(
                            businessId: widget.businessId,
                            selectedWarehouseId: _documentWarehouseId,
                            onChanged: (id) {
                              setState(() {
                                _documentWarehouseId = id;
                              });
                            },
                            label: 'انبار کلی (سطح سند)',
                            hintText: 'انتخاب انبار (اختیاری)',
                            isRequired: false,
                            selectDefaultWhenUnset: true,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: Text(
                            'این انبار در سطح سند حواله انبار استفاده می‌شود. اگر ردیف‌ها انبار نداشته باشند، از این انبار استفاده می‌شود.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                      const Divider(),
                      // نادیده گرفتن اعتبار مشتری (فقط برای فاکتور فروش)
                      if (_selectedInvoiceType == InvoiceType.sales)
                        SwitchListTile(
                          title: const Text('نادیده گرفتن اعتبار مشتری'),
                          subtitle: const Text('در صورت فعال بودن، محدودیت اعتبار برای این فاکتور اعمال نمی‌شود'),
                          value: _ignoreCreditCheck,
                            onChanged: (value) {
                            setState(() {
                              _ignoreCreditCheck = value;
                              _hasUserCustomizedSettings = true;
                            });
                              _saveLocalSettings();
                            },
                        ),
                    ],
                  ),
                ),
              ),

              // هزینه عملیات/سربار تولید (فقط برای فاکتور تولید)
              if (_selectedInvoiceType == InvoiceType.production) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'هزینه عملیات/سربار تولید',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: _productionOperationsTotal?.toString(),
                          decoration: InputDecoration(
                            labelText: 'مبلغ هزینه عملیات (ریال)',
                            hintText: 'مثال: 50000',
                            prefixIcon: const Icon(Icons.attach_money),
                            border: const OutlineInputBorder(),
                            helperText: 'هزینه عملیات و سربار تولید که به هزینه تمام‌شده محصول اضافه می‌شود',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (value) {
                            setState(() {
                              _productionOperationsTotal = double.tryParse(value);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

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
                            _hasUserCustomizedSettings = true;
                          });
                          _saveLocalSettings();
                        },
                      ),
                      
                      // تنظیمات چاپ (فقط اگر چاپ فعال باشد)
                      if (_printAfterSave) ...[
                        const Divider(),
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
                              _hasUserCustomizedSettings = true;
                            });
                            _saveLocalSettings();
                          },
                        ),
                        const SizedBox(height: 16),

                        DropdownButtonFormField<String>(
                          value: _selectedPaperOrientation,
                          decoration: const InputDecoration(
                            labelText: 'جهت چاپ',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'portrait', child: Text('عمودی (Portrait)')),
                            DropdownMenuItem(value: 'landscape', child: Text('افقی (Landscape)')),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedPaperOrientation = value;
                              _hasUserCustomizedSettings = true;
                            });
                            _saveLocalSettings();
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // فاکتور رسمی
                        SwitchListTile(
                          title: const Text('نمایش مهر و امضا'),
                          subtitle: const Text('در صورت غیرفعال بودن، مهر و امضا در PDF نمایش داده نمی‌شود'),
                          value: _showStampOnPrint,
                          onChanged: (value) {
                            setState(() {
                              _showStampOnPrint = value;
                              _hasUserCustomizedSettings = true;
                            });
                            _saveLocalSettings();
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // انتخاب قالب چاپ
                        if (_isLoadingPrintTemplates) ...[
                          const Center(child: CircularProgressIndicator()),
                        ] else ...[
                          DropdownButtonFormField<String?>(
                            value: _selectedPrintTemplate,
                            decoration: InputDecoration(
                              labelText: t.printTemplate,
                              border: const OutlineInputBorder(),
                            ),
                            items: [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text(t.noCustomTemplate),
                              ),
                              ..._availablePrintTemplates.map(
                                (tpl) => DropdownMenuItem<String?>(
                                  value: tpl['id']?.toString(),
                                  child: Text(tpl['name']?.toString() ?? 'Template ${tpl['id']}'),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedPrintTemplate = value;
                                _hasUserCustomizedSettings = true;
                              });
                              _saveLocalSettings();
                            },
                          ),
                        ],
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
                              _hasUserCustomizedSettings = true;
                            });
                            _saveLocalSettings();
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