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
import '../../widgets/project/project_selector_widget.dart';
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
import '../../utils/responsive_helper.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/invoice_global_discount_calculator.dart';
import '../../services/business_api_service.dart';
import '../../services/currency_service.dart';
import '../../services/business_currency_rate_service.dart';
import '../../widgets/invoice/invoice_fx_rate_field.dart';
import '../../widgets/invoice/invoice_installments_editor.dart';
import '../../widgets/invoice/keep_alive_tab_child.dart';


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
  bool _isSaving = false;
  String? _loadError;

  // Header state
  InvoiceType? _selectedInvoiceType;
  String? _invoiceNumber;
  DateTime? _invoiceDate;
  DateTime? _dueDate;
  int? _selectedCurrencyId;
  int? _defaultBusinessCurrencyId;
  int? _manualFxRateId;
  List<Map<String, dynamic>> _fxRateRows = [];
  bool _loadingFxRates = false;
  List<Map<String, dynamic>>? _businessCurrenciesCache;
  int _invoiceCurrencyDecimalPlaces = 2;
  bool _invoiceCurrencyRoundMonetary = true;
  int? _selectedProjectId;
  String? _invoiceTitle;
  bool _isProforma = false; // وضعیت پیش‌فاکتور (قابل تغییر)
  /// none | draft | posted
  String _invoiceWarehouseReleaseMode = 'draft';

  // طرف حساب (فروش/برگشت فروش: مشتری؛ خرید/برگشت خرید: تامین‌کننده)
  Customer? _selectedCustomer;
  Person? _selectedSupplier;

  // Lines
  List<InvoiceLineItem> _lineItems = <InvoiceLineItem>[];
  num _sumSubtotal = 0;
  num _sumDiscount = 0;
  num _sumTax = 0;
  num _sumTotal = 0;
  InvoiceGlobalDiscountPolicy _globalDiscountPolicy = const InvoiceGlobalDiscountPolicy();
  String _globalDiscountType = 'percent';
  late final TextEditingController _globalDiscountValueController;

  // تراکنش‌های پرداخت
  List<InvoiceTransaction> _transactions = [];

  // For preserving and merging extra_info
  Map<String, dynamic> _originalExtraInfo = <String, dynamic>{};

  /// در زمان بارگذاری سند، آیا طرح اقساط داشت (برای پر کردن اولیهٔ ویرایشگر)
  bool _documentHadInstallmentPlanAtLoad = false;
  Map<String, dynamic>? _initialInstallmentPlanCopy;

  /// فروش اقساطی فعال (مثل صفحهٔ افزودن؛ حتی اگر بار اول بدون طرح بوده باشد)
  bool _useInstallments = false;
  final GlobalKey<InvoiceInstallmentsEditorState> _installmentsEditorKey =
      GlobalKey<InvoiceInstallmentsEditorState>();

  bool get _canPickFxRate =>
      widget.authStore.hasBusinessPermission('currency_revaluation', 'view');

  bool get _showInvoiceFxField {
    if (!_canPickFxRate) return false;
    final b = _defaultBusinessCurrencyId;
    final c = _selectedCurrencyId;
    if (b == null || c == null) return false;
    return c != b;
  }

  @override
  void initState() {
    super.initState();
    _globalDiscountValueController = TextEditingController();
    _globalDiscountValueController.addListener(() {
      if (mounted) setState(_recalculateTotals);
    });
    _tabController = TabController(length: _getTabCount(), vsync: this);
    _loadInvoice();
  }

  bool _extraInfoHasInstallmentPlan(Map<String, dynamic> extra) {
    final p = extra['installment_plan'];
    if (p is! Map) return false;
    final sch = p['schedule'];
    if (sch is List && sch.isNotEmpty) return true;
    final n = p['num_installments'];
    if (n is int && n > 0) return true;
    if (n is num && n.toInt() > 0) return true;
    return false;
  }

  /// تب اقساط: فروش/برگشت از فروش قطعی وقتی کاربر فروش اقساطی را فعال کرده باشد
  bool get _shouldShowInstallmentsTab {
    if (_isProforma) return false;
    if (_selectedInvoiceType != InvoiceType.sales && _selectedInvoiceType != InvoiceType.salesReturn) {
      return false;
    }
    return _useInstallments;
  }

  Map<String, dynamic>? get _installmentPlanForEditor =>
      _documentHadInstallmentPlanAtLoad ? _initialInstallmentPlanCopy : null;

  int _installmentsSlotIndex() => 2 + (_shouldShowTransactionsTab ? 1 : 0);

  int _mapTabIndexAfterInstallmentsToggle({
    required int oldIndex,
    required int oldLength,
    required int newLength,
    required bool addedInstallments,
    required int installmentsSlot,
  }) {
    if (oldLength == newLength) {
      return oldIndex.clamp(0, newLength - 1);
    }
    if (addedInstallments && newLength == oldLength + 1) {
      if (oldIndex >= installmentsSlot) return oldIndex + 1;
      return oldIndex;
    }
    if (!addedInstallments && oldLength == newLength + 1) {
      if (oldIndex > installmentsSlot) return oldIndex - 1;
      return oldIndex;
    }
    return oldIndex.clamp(0, newLength - 1);
  }

  void _syncTabControllerLength() {
    final newTabCount = _getTabCount();
    if (newTabCount == _tabController.length) return;
    final prevIdx = _tabController.index;
    _tabController.dispose();
    _tabController = TabController(
      length: newTabCount,
      vsync: this,
      initialIndex: prevIdx.clamp(0, newTabCount - 1),
    );
  }

  void _onUseInstallmentsChanged(bool value) {
    final oldIdx = _tabController.index;
    final oldLen = _tabController.length;
    final slot = _installmentsSlotIndex();
    setState(() {
      _useInstallments = value;
      final newLen = _getTabCount();
      if (newLen != oldLen) {
        final newIdx = _mapTabIndexAfterInstallmentsToggle(
          oldIndex: oldIdx,
          oldLength: oldLen,
          newLength: newLen,
          addedInstallments: value,
          installmentsSlot: slot,
        );
        _tabController.dispose();
        _tabController = TabController(
          length: newLen,
          vsync: this,
          initialIndex: newIdx.clamp(0, newLen - 1),
        );
      }
    });
    if (value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final instIdx = _installmentsSlotIndex();
        if (instIdx >= 0 && instIdx < _tabController.length) {
          _tabController.animateTo(instIdx);
        }
      });
    }
  }

  void _handleInvoiceTypeChanged(InvoiceType? type) {
    setState(() {
      _selectedInvoiceType = type;
      if (type != null && !invoiceTypeSupportsGlobalDiscount(type.value)) {
        _globalDiscountValueController.clear();
      }
      if (_isProforma ||
          (type != InvoiceType.sales && type != InvoiceType.salesReturn)) {
        _useInstallments = false;
      }
      _syncTabControllerLength();
      _recalculateTotals();
    });
  }

  void _handleDraftChanged(bool isDraft) {
    setState(() {
      _isProforma = isDraft;
      if (isDraft && _transactions.isNotEmpty) {
        _transactions = [];
      }
      if (isDraft) {
        _useInstallments = false;
      }
      _syncTabControllerLength();
    });
  }

  // محاسبه تعداد تب‌ها بر اساس نوع فاکتور
  int _getTabCount() {
    if (_isProforma) return 3; // اطلاعات، کالاها، تنظیمات
    if (_selectedInvoiceType == InvoiceType.waste ||
        _selectedInvoiceType == InvoiceType.directConsumption ||
        _selectedInvoiceType == InvoiceType.production) {
      return 3; // اطلاعات، کالاها، تنظیمات (بدون تراکنش)
    }
    var n = 4; // اطلاعات، کالاها، تراکنش‌ها، تنظیمات
    if (_shouldShowInstallmentsTab) n += 1; // اقساط بین تراکنش‌ها و تنظیمات
    return n;
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
    _globalDiscountValueController.dispose();
    super.dispose();
  }

  DateTime? _parseDueDateFromExtra(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    if (s.isEmpty) return null;
    final head = s.length >= 10 ? s.substring(0, 10) : s;
    return DateTime.tryParse(head);
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
      _selectedProjectId = (item['project_id'] as num?)?.toInt();
      _invoiceTitle = item['description']?.toString();

      // extra_info
      _originalExtraInfo = Map<String, dynamic>.from(item['extra_info'] ?? const {});
      _manualFxRateId = null;
      final fxx0 = _originalExtraInfo['fx'];
      if (fxx0 is Map && fxx0['mode']?.toString() == 'selected') {
        final rrid = fxx0['rate_row_id'];
        if (rrid != null) {
          _manualFxRateId = (rrid as num).toInt();
        }
      }
      _documentHadInstallmentPlanAtLoad = _extraInfoHasInstallmentPlan(_originalExtraInfo);
      if (_documentHadInstallmentPlanAtLoad && _originalExtraInfo['installment_plan'] is Map) {
        _initialInstallmentPlanCopy =
            Map<String, dynamic>.from(_originalExtraInfo['installment_plan'] as Map);
      } else {
        _initialInstallmentPlanCopy = null;
      }
      _useInstallments = _documentHadInstallmentPlanAtLoad;
      final pi = _originalExtraInfo['post_inventory'];
      final ap = _originalExtraInfo['auto_post_warehouse'];
      final postOn = (pi is bool) ? pi : true;
      final autoPost = (ap is bool) ? ap : false;
      if (!postOn) {
        _invoiceWarehouseReleaseMode = 'none';
      } else if (autoPost) {
        _invoiceWarehouseReleaseMode = 'posted';
      } else {
        _invoiceWarehouseReleaseMode = 'draft';
      }
      _dueDate = _parseDueDateFromExtra(_originalExtraInfo['due_date']);
      
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

        // بارگذاری selected_instance_ids از extra_info
        List<int>? selectedInstanceIds;
        if (info['selected_instance_ids'] != null) {
          final ids = info['selected_instance_ids'];
          if (ids is List) {
            selectedInstanceIds = ids
                .map((id) => _toInt(id))
                .where((id) => id != null)
                .cast<int>()
                .toList();
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
          warehouseId: _toInt(info['warehouse_id']),
          selectedInstanceIds: selectedInstanceIds,
          extraInfo: info.isNotEmpty ? Map<String, dynamic>.from(info) : null,
        );
      }).toList();

      try {
        final b = await BusinessApiService.getBusiness(widget.businessId);
        if (mounted) {
          _globalDiscountPolicy = InvoiceGlobalDiscountPolicy.fromBusiness(b);
        }
      } catch (_) {}

      try {
        final cs = CurrencyService(ApiClient());
        final curList = await cs.listBusinessCurrencies(businessId: widget.businessId);
        if (mounted) {
          int? defId;
          for (final raw in curList) {
            final c = Map<String, dynamic>.from(raw as Map);
            if (c['is_default'] == true) {
              defId = (c['id'] as num?)?.toInt();
              break;
            }
          }
          _businessCurrenciesCache = curList;
          _defaultBusinessCurrencyId = defId;
          _applyCurrencyMetaFromCache();
        }
      } catch (_) {}

      final gd = _originalExtraInfo['global_discount'];
      if (gd is Map) {
        final tt = gd['type']?.toString() ?? 'amount';
        if (tt == 'percent' || tt == 'amount') {
          _globalDiscountType = tt;
        }
        final v = gd['value'];
        if (v != null) {
          _globalDiscountValueController.text = v.toString();
        }
      }

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
        final prevIdx = _tabController.index;
        _tabController.dispose();
        _tabController = TabController(
          length: newTabCount,
          vsync: this,
          initialIndex: prevIdx.clamp(0, newTabCount - 1),
        );
      }

      await _reloadFxRates();
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
      final receiptPaymentService = ReceiptPaymentService(ApiClient());
      final List<InvoiceTransaction> transactions = [];
      final Set<int> processedDocIds = {}; // برای جلوگیری از تکرار
      
      // 1. بارگذاری از لینک‌های مستقیم (receipt_payment_document_ids)
      final links = _originalExtraInfo['links'] as Map<String, dynamic>?;
      if (links != null) {
        final receiptPaymentIds = links['receipt_payment_document_ids'] as List<dynamic>?;
        if (receiptPaymentIds != null && receiptPaymentIds.isNotEmpty) {
          for (final id in receiptPaymentIds) {
            try {
              final docId = id is int ? id : int.tryParse(id.toString());
              if (docId == null || processedDocIds.contains(docId)) continue;
              
              final doc = await receiptPaymentService.getById(docId);
              if (doc == null) continue;
              
              processedDocIds.add(docId);
              
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
            }
          }
        }
      }
      
      // 2. جستجوی اسناد دریافت/پرداخت که به این فاکتور لینک شده‌اند
      // (از طریق extra_info.invoice_id در person_lines)
      try {
        final receiptPaymentList = await receiptPaymentService.listReceiptsPayments(
          businessId: widget.businessId,
          skip: 0,
          take: 1000, // محدود کردن به 1000 رکورد
        );
        
        final items = (receiptPaymentList['items'] as List<dynamic>?) ?? [];
        for (final item in items) {
          try {
            final docId = (item['id'] as num?)?.toInt();
            if (docId == null || processedDocIds.contains(docId)) continue;
            
            // بررسی person_lines برای invoice_id
            final personLines = item['person_lines'] as List<dynamic>?;
            if (personLines == null) continue;
            
            bool hasInvoiceLink = false;
            for (final pl in personLines) {
              final extraInfo = pl['extra_info'] as Map<String, dynamic>?;
              if (extraInfo != null) {
                final invoiceId = extraInfo['invoice_id'];
                if (invoiceId is int && invoiceId == widget.invoiceId) {
                  hasInvoiceLink = true;
                  break;
                } else if (invoiceId is num && invoiceId.toInt() == widget.invoiceId) {
                  hasInvoiceLink = true;
                  break;
                }
              }
            }
            
            if (!hasInvoiceLink) continue;
            
            // دریافت جزئیات کامل سند
            final doc = await receiptPaymentService.getById(docId);
            if (doc == null) continue;
            
            processedDocIds.add(docId);
            
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
          }
        }
      } catch (e) {
      }
      
      if (mounted) {
        setState(() {
          _transactions = transactions;
        });
      }
    } catch (e) {
    }
  }

  void _applyCurrencyMetaFromCache() {
    final id = _selectedCurrencyId;
    var dp = 2;
    var rm = true;
    final cache = _businessCurrenciesCache;
    if (id != null && cache != null) {
      for (final raw in cache) {
        final c = Map<String, dynamic>.from(raw as Map);
        if ((c['id'] as num?)?.toInt() == id) {
          dp = (c['decimal_places'] as num?)?.toInt() ?? 2;
          rm = c['round_monetary_amounts'] != false;
          break;
        }
      }
    }
    _invoiceCurrencyDecimalPlaces = dp;
    _invoiceCurrencyRoundMonetary = rm;
  }

  Future<void> _reloadFxRates() async {
    if (!mounted) return;
    if (!_canPickFxRate) {
      setState(() {
        _fxRateRows = [];
        _loadingFxRates = false;
      });
      return;
    }
    final def = _defaultBusinessCurrencyId;
    final cur = _selectedCurrencyId;
    if (def == null || cur == null || cur == def) {
      setState(() {
        _fxRateRows = [];
        _manualFxRateId = null;
        _loadingFxRates = false;
      });
      return;
    }
    setState(() {
      _loadingFxRates = true;
    });
    try {
      final svc = BusinessCurrencyRateService(ApiClient());
      final res = await svc.list(
        businessId: widget.businessId,
        take: 100,
        currencyId: cur,
      );
      final items = (res['items'] as List<dynamic>?) ?? const [];
      if (!mounted) return;
      setState(() {
        _fxRateRows = items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loadingFxRates = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _fxRateRows = [];
          _loadingFxRates = false;
        });
      }
    }
  }

  void _recalculateTotals() {
    final type = _selectedInvoiceType?.value;
    final raw = _globalDiscountValueController.text.replaceAll(',', '').trim();
    num gv = 0;
    if (raw.isNotEmpty) {
      gv = num.tryParse(raw) ?? 0;
    }
    if (!invoiceTypeSupportsGlobalDiscount(type) || gv <= 0) {
      _sumSubtotal = _lineItems.fold<num>(0, (acc, e) => acc + e.subtotal);
      _sumDiscount = _lineItems.fold<num>(0, (acc, e) => acc + e.discountAmount);
      _sumTax = _lineItems.fold<num>(0, (acc, e) => acc + e.taxAmount);
      _sumTotal = _lineItems.fold<num>(0, (acc, e) => acc + e.total);
      return;
    }
    if (_globalDiscountType == 'percent' && gv > 100) {
      gv = 100;
    }
    final r = computeInvoiceTotalsWithGlobalDiscount(
      lines: _lineItems,
      globalType: _globalDiscountType,
      globalValue: gv,
      policy: _globalDiscountPolicy,
      decimalPlaces: _invoiceCurrencyDecimalPlaces,
      roundMonetaryAmounts: _invoiceCurrencyRoundMonetary,
    );
    _sumSubtotal = r.sumSubtotal;
    _sumDiscount = r.sumLineDiscount + r.globalDiscountAmount;
    _sumTax = r.sumTax;
    _sumTotal = r.sumTotal;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    if (!widget.authStore.canWriteSection('invoices')) {
      return AccessDeniedPage(message: t.accessDenied);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t.editInvoiceTitle),
        actions: [
          IconButton(
            tooltip: t.saveChangesTooltip,
            onPressed: (_loading || _isSaving) ? null : _saveChanges,
            icon: _isSaving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(icon: const Icon(Icons.info_outline), text: t.invoiceInfoTab),
            Tab(icon: const Icon(Icons.inventory_2_outlined), text: t.invoiceProductsTab),
            if (_shouldShowTransactionsTab)
              Tab(icon: const Icon(Icons.receipt_long_outlined), text: t.invoiceTransactionsTab),
            if (_shouldShowInstallmentsTab)
              Tab(icon: const Icon(Icons.payments_outlined), text: t.invoiceInstallmentsTab),
            Tab(icon: const Icon(Icons.settings_outlined), text: t.invoiceSettingsTab),
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
                    if (_shouldShowInstallmentsTab)
                      KeepAliveTabChild(
                        child: InvoiceInstallmentsEditor(
                          key: _installmentsEditorKey,
                          businessId: widget.businessId,
                          calendarController: widget.calendarController,
                          sumTotal: _sumTotal,
                          invoiceDate: _invoiceDate,
                          initialInstallmentPlan: _installmentPlanForEditor,
                        ),
                      ),
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
                  final isMobile = ResponsiveHelper.isMobile(context);
                  if (isMobile) {
                    // موبایل: Column layout
                    return Column(
                      children: [
                        InvoiceTypeCombobox(
                          selectedType: _selectedInvoiceType,
                          onTypeChanged: _handleInvoiceTypeChanged,
                          isDraft: _isProforma,
                          onDraftChanged: _handleDraftChanged,
                          isRequired: true,
                          label: 'نوع فاکتور',
                          hintText: 'انتخاب نوع فاکتور',
                        ),
                        const SizedBox(height: 12),
                        CodeFieldWidget(
                          initialValue: _invoiceNumber,
                          onChanged: (number) {
                            setState(() {
                              _invoiceNumber = number;
                            });
                          },
                          isRequired: true,
                          label: 'شماره فاکتور',
                          hintText: 'مثال: INV-20240410-0001',
                          autoGenerateCode: false,
                          invoiceDocumentCode: true,
                        ),
                        const SizedBox(height: 12),
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
                        const SizedBox(height: 12),
                        DateInputField(
                          value: _dueDate ?? _invoiceDate,
                          labelText: 'تاریخ سررسید',
                          hintText: 'انتخاب تاریخ سررسید',
                          calendarController: widget.calendarController,
                          onChanged: (date) {
                            setState(() {
                              _dueDate = date;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        InvoiceFxRateField(
                          show: _showInvoiceFxField,
                          loading: _loadingFxRates,
                          manualRateId: _manualFxRateId,
                          rateRows: _fxRateRows,
                          onChanged: (v) => setState(() => _manualFxRateId = v),
                        ),
                        const SizedBox(height: 16),
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
                      ],
                    );
                  } else {
                    // دسکتاپ/تبلت: Row layout
                    return Column(
                      children: [
                        // سطر اول
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: InvoiceTypeCombobox(
                                selectedType: _selectedInvoiceType,
                                onTypeChanged: _handleInvoiceTypeChanged,
                                isDraft: _isProforma,
                                onDraftChanged: _handleDraftChanged,
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
                                hintText: 'مثال: INV-20240410-0001',
                                autoGenerateCode: false,
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
                              child: CurrencyPickerWidget(
                                businessId: widget.businessId,
                                selectedCurrencyId: _selectedCurrencyId,
                                onChanged: (currencyId) {
                                  setState(() {
                                    _selectedCurrencyId = currencyId;
                                    _manualFxRateId = null;
                                    _applyCurrencyMetaFromCache();
                                    _recalculateTotals();
                                  });
                                  _reloadFxRates();
                                },
                                label: 'ارز فاکتور',
                                hintText: 'انتخاب ارز فاکتور',
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
                          ],
                        ),
                        const SizedBox(height: 8),
                        InvoiceFxRateField(
                          show: _showInvoiceFxField,
                          loading: _loadingFxRates,
                          manualRateId: _manualFxRateId,
                          rateRows: _fxRateRows,
                          onChanged: (v) => setState(() => _manualFxRateId = v),
                        ),
                        const SizedBox(height: 16),
                        DateInputField(
                          value: _dueDate ?? _invoiceDate,
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
                        // طرف حساب فقط نمایشی در صورت امکان
                        if (_selectedInvoiceType == InvoiceType.sales || _selectedInvoiceType == InvoiceType.salesReturn)
                          CustomerComboboxWidget(
                            selectedCustomer: _selectedCustomer,
                            onCustomerChanged: (c) => setState(() => _selectedCustomer = c),
                            businessId: widget.businessId,
                            authStore: widget.authStore,
                            isRequired: false,
                            label: 'طرف حساب',
                            hintText: _selectedCustomer?.name ?? 'انتخاب طرف حساب',
                            showFinancialBalance: true,
                          ),
                        if (_selectedInvoiceType == InvoiceType.purchase || _selectedInvoiceType == InvoiceType.purchaseReturn) ...[
                          const SizedBox(height: 16),
                          PersonComboboxWidget(
                            businessId: widget.businessId,
                            showFinancialBalance: true,
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
                          maxLines: 3,
                        ),
                      ],
                    );
                  }
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
    final t = AppLocalizations.of(context);
    final showGlobalDisc = invoiceTypeSupportsGlobalDiscount(_selectedInvoiceType?.value);
    final lineDiscOnly = _lineItems.fold<num>(0, (acc, e) => acc + e.discountAmount);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InvoiceLineItemsTable(
                businessId: widget.businessId,
                authStore: widget.authStore,
                selectedCurrencyId: _selectedCurrencyId,
                currencyDecimalPlaces: _invoiceCurrencyDecimalPlaces,
                invoiceType: (_selectedInvoiceType?.value ?? 'sales'),
                postInventory: _invoiceWarehouseReleaseMode != 'none',
                initialRows: _lineItems,
                calendarController: widget.calendarController,
                onChanged: (rows) {
                  setState(() {
                    _lineItems = rows;
                    _recalculateTotals();
                  });
                },
              ),
              if (showGlobalDisc) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.invoiceGlobalDiscountSection, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        SegmentedButton<String>(
                          segments: [
                            ButtonSegment<String>(
                              value: 'percent',
                              label: Text(t.invoiceGlobalDiscountTypePercent),
                            ),
                            ButtonSegment<String>(
                              value: 'amount',
                              label: Text(t.invoiceGlobalDiscountTypeAmount),
                            ),
                          ],
                          selected: {_globalDiscountType},
                          onSelectionChanged: (s) {
                            setState(() {
                              _globalDiscountType = s.first;
                              _recalculateTotals();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _globalDiscountValueController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: t.invoiceGlobalDiscountValueLabel,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t.invoiceGlobalDiscountLineDiscountHint(
                            formatWithThousands(lineDiscOnly, decimalPlaces: _invoiceCurrencyDecimalPlaces),
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (_sumDiscount > lineDiscOnly)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              t.invoiceGlobalDiscountAmountComputedHint(
                                formatWithThousands(_sumDiscount - lineDiscOnly, decimalPlaces: _invoiceCurrencyDecimalPlaces),
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text('${t.invoiceSummarySubtotal}: ${formatWithThousands(_sumSubtotal, decimalPlaces: _invoiceCurrencyDecimalPlaces)}', style: Theme.of(context).textTheme.bodyLarge),
                    Text('${t.invoiceSummaryDiscount}: ${formatWithThousands(_sumDiscount, decimalPlaces: _invoiceCurrencyDecimalPlaces)}', style: Theme.of(context).textTheme.bodyLarge),
                    Text('${t.invoiceSummaryTax}: ${formatWithThousands(_sumTax, decimalPlaces: _invoiceCurrencyDecimalPlaces)}', style: Theme.of(context).textTheme.bodyLarge),
                    Text('${t.invoiceSummaryTotal}: ${formatWithThousands(_sumTotal, decimalPlaces: _invoiceCurrencyDecimalPlaces)}', style: Theme.of(context).textTheme.bodyLarge),
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
            authStore: widget.authStore,
            invoiceTotal: _sumTotal, // ارسال مبلغ کل فاکتور
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsTab() {
    final t = AppLocalizations.of(context);
    final isSalesOrReturn =
        _selectedInvoiceType == InvoiceType.sales || _selectedInvoiceType == InvoiceType.salesReturn;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isSalesOrReturn) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SwitchListTile(
                      title: Text(t.installmentsTitle),
                      subtitle: Text(t.installmentsSubtitle),
                      value: _useInstallments,
                      onChanged: _isProforma ? null : (value) => _onUseInstallmentsChanged(value),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.invoiceWarehouseReleaseSectionTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t.invoiceWarehouseReleaseSectionSubtitle,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: <ButtonSegment<String>>[
                          ButtonSegment<String>(
                            value: 'none',
                            label: Text(t.invoiceWarehouseReleaseNone),
                          ),
                          ButtonSegment<String>(
                            value: 'draft',
                            label: Text(t.invoiceWarehouseReleaseDraft),
                          ),
                          ButtonSegment<String>(
                            value: 'posted',
                            label: Text(t.invoiceWarehouseReleasePosted),
                          ),
                        ],
                        selected: <String>{_invoiceWarehouseReleaseMode},
                        onSelectionChanged: (Set<String> next) {
                          setState(() {
                            _invoiceWarehouseReleaseMode = next.first;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'توجه: با ذخیرهٔ فاکتور، حواله‌های قبلی مرتبط با همین فاکتور با تنظیمات بالا جایگزین می‌شوند؛ '
                        'حوالهٔ پیش‌نویس حذف می‌شود و برای حوالهٔ قطعی، سند معکوس ثبت می‌شود. اگر خطای همگام‌سازی دیدید، وضعیت انبار را بررسی کنید.',
                        style: TextStyle(fontSize: 13),
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

  /// `TabBarView` ممکن است تب اقساط را تا قبل از بازدید نسازد؛ برای اعتبارسنجی/ذخیره باید ویرایشگر وجود داشته باشد.
  Future<void> _ensureInstallmentsEditorBuilt() async {
    if (!_shouldShowInstallmentsTab) return;
    if (_installmentsEditorKey.currentState != null) return;
    final instIdx = 2 + (_shouldShowTransactionsTab ? 1 : 0);
    if (instIdx < 0 || instIdx >= _tabController.length) return;
    // TabController.animateTo در این نسخه void است (نه Future).
    _tabController.animateTo(instIdx);
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  Future<void> _saveChanges() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await _ensureInstallmentsEditorBuilt();
      if (!mounted) return;
      final payloadOrError = _validateAndBuildPayload();
      if (payloadOrError is String) {
        if (!mounted) return;
        SnackBarHelper.show(context, message: payloadOrError);
        return;
      }
      final payload = payloadOrError as Map<String, dynamic>;

      // بررسی مبلغ صفر فاکتور
      if (_sumTotal == 0) {
        final confirmed = await _showZeroAmountWarning();
        if (!confirmed) {
          return; // کاربر انصراف داد
        }
      }

      try {
        final service = InvoiceService(apiClient: ApiClient());
        await service.updateInvoice(
          businessId: widget.businessId,
          invoiceId: widget.invoiceId,
          payload: payload,
        );
        if (!mounted) return;
        SnackBarHelper.show(context, message: 'تغییرات فاکتور با موفقیت ذخیره شد');
        // بازگشت به لیست فاکتورها بعد از ذخیره موفق
        if (mounted) {
          // هدایت به لیست فاکتورها بعد از ویرایش موفق
          context.goNamed(
            'business_invoice',
            pathParameters: {
              'business_id': widget.businessId.toString(),
            },
          );
        }
      } catch (e) {
        if (!mounted) return;
        SnackBarHelper.show(context, message: 'خطا در ذخیره تغییرات: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
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

    final t = AppLocalizations.of(context);
    final invTypeVal0 = _selectedInvoiceType?.value;
    if (invoiceTypeSupportsGlobalDiscount(invTypeVal0)) {
      final graw = _globalDiscountValueController.text.replaceAll(',', '').trim();
      if (graw.isNotEmpty) {
        final gv = num.tryParse(graw);
        if (gv == null) return t.invoiceGlobalDiscountValueInvalid;
        if (_globalDiscountType == 'percent' && (gv < 0 || gv > 100)) {
          return t.invoiceGlobalDiscountPercentInvalid;
        }
        if (_globalDiscountType == 'amount' && gv < 0) {
          return t.invoiceGlobalDiscountAmountInvalid;
        }
      }
    }

    final codeTrimmed = (_invoiceNumber ?? '').trim();
    if (codeTrimmed.isEmpty) {
      return 'شماره فاکتور الزامی است';
    }
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(codeTrimmed)) {
      return 'شماره فاکتور فقط می‌تواند شامل حروف انگلیسی، اعداد، خط تیره و زیرخط باشد';
    }

    // ساخت extra_info با حفظ اطلاعات قبلی
    final mergedExtra = <String, dynamic>{..._originalExtraInfo};
    mergedExtra['post_inventory'] = _invoiceWarehouseReleaseMode != 'none';
    mergedExtra['auto_post_warehouse'] = _invoiceWarehouseReleaseMode == 'posted';
    mergedExtra['totals'] = {
      'gross': _sumSubtotal,
      'discount': _sumDiscount,
      'tax': _sumTax,
      'net': _sumTotal,
    };
    if (invoiceTypeSupportsGlobalDiscount(_selectedInvoiceType?.value)) {
      final graw = _globalDiscountValueController.text.replaceAll(',', '').trim();
      if (graw.isNotEmpty) {
        final gv = num.tryParse(graw) ?? 0;
        if (gv > 0) {
          mergedExtra['global_discount'] = {
            'type': _globalDiscountType,
            'value': gv.toDouble(),
          };
        } else {
          mergedExtra.remove('global_discount');
        }
      } else {
        mergedExtra.remove('global_discount');
      }
    } else {
      mergedExtra.remove('global_discount');
    }
    final dueForSave = _dueDate ?? _invoiceDate;
    if (dueForSave != null) {
      mergedExtra['due_date'] = dueForSave.toIso8601String().split('T').first;
    }

    final canKeepInstallments = !_isProforma &&
        (_selectedInvoiceType == InvoiceType.sales ||
            _selectedInvoiceType == InvoiceType.salesReturn) &&
        _useInstallments;
    if (!canKeepInstallments) {
      mergedExtra.remove('installment_plan');
    } else {
      final st = _installmentsEditorKey.currentState;
      if (st == null) {
        return 'برای ذخیرهٔ طرح اقساط، یک بار به تب «اقساط» بروید تا فرم بارگذاری شود.';
      }
      final instErr = st.validate();
      if (instErr != null) {
        return instErr;
      }
      mergedExtra['installment_plan'] = st.buildPlanMap();
    }

    final isSalesOrReturn =
        _selectedInvoiceType == InvoiceType.sales || _selectedInvoiceType == InvoiceType.salesReturn;
    final isPurchaseOrReturn = _selectedInvoiceType == InvoiceType.purchase ||
        _selectedInvoiceType == InvoiceType.purchaseReturn;

    if (isSalesOrReturn && _selectedCustomer == null) {
      return 'انتخاب طرف حساب الزامی است';
    }
    if (isPurchaseOrReturn && _selectedSupplier == null) {
      return 'انتخاب تامین‌کننده الزامی است';
    }

    // هم‌راستا با new_invoice_page: person_id باید از انتخاب فعلی در extra_info برود
    if (isSalesOrReturn && _selectedCustomer != null) {
      mergedExtra['person_id'] = _selectedCustomer!.id;
    } else if (isPurchaseOrReturn && _selectedSupplier != null) {
      mergedExtra['person_id'] = _selectedSupplier!.id;
    }

    String _convertInvoiceTypeToApi(InvoiceType type) => 'invoice_${type.value}';

    final payload = <String, dynamic>{
      'invoice_type': _convertInvoiceTypeToApi(_selectedInvoiceType!), // جهت سازگاری حساب‌ها
      'code': codeTrimmed,
      'document_date': _invoiceDate!.toIso8601String().split('T')[0],
      'currency_id': _selectedCurrencyId,
      'is_proforma': _isProforma, // ارسال وضعیت پیش‌فاکتور
      'extra_info': mergedExtra,
      if ((_invoiceTitle ?? '').isNotEmpty) 'description': _invoiceTitle,
      if (_selectedProjectId != null) 'project_id': _selectedProjectId,
      if (_showInvoiceFxField && _manualFxRateId != null) 'fx_rate_id': _manualFxRateId,
      'lines': _lineItems.map((e) => _serializeLineItem(e)).toList(),
    };
    
    // تراکنش‌های پرداخت برای فاکتور قطعی؛ همیشه آرایه بفرست تا حذف همهٔ تراکنش‌ها در سرور اعمال شود
    if (!_isProforma) {
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

    final extraInfoMap = <String, dynamic>{};
    if (e.extraInfo != null) {
      for (final entry in e.extraInfo!.entries) {
        final k = entry.key.toString();
        if (k.startsWith('_local_')) continue;
        extraInfoMap[k] = entry.value;
      }
    }
    extraInfoMap.addAll({
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
    });

    if (e.warehouseId != null) {
      extraInfoMap['warehouse_id'] = e.warehouseId;
    }

    if (e.selectedInstanceIds != null && e.selectedInstanceIds!.isNotEmpty) {
      extraInfoMap['selected_instance_ids'] = e.selectedInstanceIds;
    }

    return <String, dynamic>{
      'product_id': e.productId,
      'quantity': e.quantity,
      if ((e.description ?? '').isNotEmpty) 'description': e.description,
      'extra_info': extraInfoMap,
    };
  }
}


