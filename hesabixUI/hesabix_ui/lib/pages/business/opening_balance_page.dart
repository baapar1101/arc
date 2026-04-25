import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/permission_guard.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/opening_balance_service.dart';
import 'package:hesabix_ui/widgets/invoice/bank_account_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/cash_register_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/petty_cash_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/product_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/warehouse_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/account_combobox_widget.dart';
import 'package:hesabix_ui/models/account_model.dart';
import 'package:hesabix_ui/services/account_service.dart';
import 'package:hesabix_ui/services/bank_account_service.dart';
import 'package:hesabix_ui/services/cash_register_service.dart';
import 'package:hesabix_ui/services/petty_cash_service.dart';
import 'package:hesabix_ui/services/person_service.dart';
import 'package:hesabix_ui/services/product_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

class OpeningBalancePage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const OpeningBalancePage({super.key, required this.businessId, required this.authStore});

  @override
  State<OpeningBalancePage> createState() => _OpeningBalancePageState();
}

class _OpeningBalancePageState extends State<OpeningBalancePage> {
  late final OpeningBalanceService _service;
  bool _loading = false;
  bool _accountsLoading = true; // برای ردیابی بارگذاری حساب‌ها
  Map<String, dynamic>? _document;
  // Local form state
  final List<Map<String, dynamic>> _bankCashPettyLines = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _personLines = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _inventoryLines = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _otherAccountLines = <Map<String, dynamic>>[];
  bool _autoBalance = true;
  int? _inventoryAccountId;
  int? _equityAccountId;
  Account? _inventoryAccount;
  Account? _equityAccount;
  int? _bankControlAccountId;    // 10203
  int? _cashControlAccountId;    // 10202
  int? _pettyControlAccountId;   // 10201
  int? _personReceivableAccountId; // 10401
  int? _personPayableAccountId;    // 20201
  Account? _bankControlAccount;
  Account? _cashControlAccount;
  Account? _pettyControlAccount;
  Account? _personReceivableAccount;
  Account? _personPayableAccount;

  @override
  void initState() {
    super.initState();
    _service = OpeningBalanceService(ApiClient());
    _initializeAccounts();
    _load();
  }

  Future<void> _initializeAccounts() async {
    setState(() => _accountsLoading = true);
    try {
      // ابتدا حساب‌های پیش‌فرض را بارگذاری کن
      await _loadDefaultAccounts();
      // سپس حساب‌های ذخیره شده را بارگذاری کن (که ممکن است حساب‌های پیش‌فرض را override کنند)
      await _loadSavedDefaults();
    } finally {
      if (mounted) {
        setState(() => _accountsLoading = false);
      }
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final doc = await _service.fetch(businessId: widget.businessId);
      setState(() {
        _document = doc;
        // بارگذاری خطوط از document
        if (doc != null) {
          _loadLinesFromDocument(doc);
        }
      });
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message:
              'خطا در دریافت تراز افتتاحیه: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _loadLinesFromDocument(Map<String, dynamic> doc) {
    // پاک کردن لیست‌های قبلی
    _bankCashPettyLines.clear();
    _personLines.clear();
    _inventoryLines.clear();
    _otherAccountLines.clear();

    // بارگذاری تنظیمات
    final extraInfo = doc['extra_info'] as Map<String, dynamic>? ?? {};
    _autoBalance = extraInfo['auto_balance_to_equity'] as bool? ?? true;

    // بارگذاری خطوط
    final lines = doc['lines'] as List<dynamic>? ?? [];
    for (final line in lines) {
      final lineMap = Map<String, dynamic>.from(line as Map);
      
      // خطوط موجودی (دارای product_id)
      if (lineMap['product_id'] != null) {
        final extraInfo = Map<String, dynamic>.from(lineMap['extra_info'] as Map? ?? {});
        final warehouseId = extraInfo['warehouse_id'] as int?;
        final quantity = (lineMap['quantity'] as num?)?.toDouble() ?? 0.0;
        final costPrice = (extraInfo['cost_price'] as num?)?.toDouble() ?? 0.0;
        
        if (warehouseId != null && quantity > 0) {
          _inventoryLines.add({
            'product': {
              'id': lineMap['product_id'],
              'code': lineMap['product_code'] ?? '',
              'name': lineMap['product_name'] ?? '',
            },
            'warehouseId': warehouseId,
            'quantity': quantity,
            'cost_price': costPrice,
          });
        }
      }
      // خطوط بانک/صندوق/تنخواه
      else if (lineMap['bank_account_id'] != null || 
               lineMap['cash_register_id'] != null || 
               lineMap['petty_cash_id'] != null) {
        final debit = (lineMap['debit'] as num?)?.toDouble() ?? 0.0;
        final credit = (lineMap['credit'] as num?)?.toDouble() ?? 0.0;
        if (debit > 0 || credit > 0) {
          String type = 'bank';
          int? refId;
          String? name;
          
          if (lineMap['bank_account_id'] != null) {
            type = 'bank';
            refId = lineMap['bank_account_id'] as int?;
            name = lineMap['bank_account_name'] as String?;
          } else if (lineMap['cash_register_id'] != null) {
            type = 'cash';
            refId = lineMap['cash_register_id'] as int?;
            name = lineMap['cash_register_name'] as String?;
          } else if (lineMap['petty_cash_id'] != null) {
            type = 'petty';
            refId = lineMap['petty_cash_id'] as int?;
            name = lineMap['petty_cash_name'] as String?;
          }
          
          if (refId != null) {
            _bankCashPettyLines.add({
              'type': type,
              'refId': refId,
              'name': name ?? 'نامشخص',
              'debit': debit,
              'credit': credit,
            });
          }
        }
      }
      // خطوط اشخاص
      else if (lineMap['person_id'] != null) {
        final debit = (lineMap['debit'] as num?)?.toDouble() ?? 0.0;
        final credit = (lineMap['credit'] as num?)?.toDouble() ?? 0.0;
        if (debit > 0 || credit > 0) {
          _personLines.add({
            'personId': lineMap['person_id'],
            'personName': lineMap['person_name'] ?? 'نامشخص',
            'debit': debit,
            'credit': credit,
          });
        }
      }
      // سایر حساب‌ها (که auto-balance نیستند)
      else if (lineMap['account_id'] != null) {
        final accountId = lineMap['account_id'] as int?;
        final debit = (lineMap['debit'] as num?)?.toDouble() ?? 0.0;
        final credit = (lineMap['credit'] as num?)?.toDouble() ?? 0.0;
        final description = lineMap['description'] as String? ?? '';
        
        // خطوط auto-balance را نادیده بگیر (دارای description خاص هستند)
        if (description.contains('بستن اختلاف تراز افتتاحیه')) {
          // این خط auto-balance است، فقط account_id را برای equity ذخیره کن
          if (_equityAccountId == null && accountId != null) {
            _equityAccountId = accountId;
          }
          continue;
        }
        
        if (accountId != null && (debit > 0 || credit > 0)) {
          _otherAccountLines.add({
            'account': Account(
              id: accountId,
              code: lineMap['account_code'] ?? '',
              name: lineMap['account_name'] ?? '',
              accountType: lineMap['account_type'] ?? 'asset',
              businessId: widget.businessId,
            ),
            'debit': debit,
            'credit': credit,
          });
        }
      }
    }

    // بارگذاری inventory_account_id و equity_account_id از extra_info
    if (doc['inventory_account_id'] != null) {
      _inventoryAccountId = doc['inventory_account_id'] as int?;
    }
    if (doc['equity_account_id'] != null) {
      _equityAccountId = doc['equity_account_id'] as int?;
    }
  }

  Future<void> _loadDefaultAccounts() async {
    try {
      final accountService = AccountService();
      
      // تابع برای پیدا کردن حساب با کد دقیق
      Future<Account?> findByCode(String code) async {
        try {
          // ابتدا از getAccounts استفاده می‌کنیم که همه حساب‌ها را برمی‌گرداند
          final res = await accountService.getAccounts(businessId: widget.businessId);
          final items = (res['items'] as List<dynamic>? ?? const <dynamic>[]);
          for (final it in items) {
            final acc = Account.fromJson(Map<String, dynamic>.from(it as Map));
            if (acc.code == code) {
              debugPrint('حساب با کد $code پیدا شد: ${acc.name} (ID: ${acc.id})');
              return acc;
            }
          }
          debugPrint('حساب با کد $code پیدا نشد');
        } catch (e) {
          debugPrint('خطا در جستجوی حساب با کد $code: $e');
        }
        return null;
      }

      // تابع برای پیدا کردن حساب با کدهای جایگزین (fallback)
      Future<Account?> findByCodeWithFallback(String primaryCode, List<String> fallbackCodes) async {
        // ابتدا کد اصلی را امتحان کن
        final primary = await findByCode(primaryCode);
        if (primary != null) return primary;
        
        // اگر پیدا نشد، کدهای جایگزین را امتحان کن
        for (final code in fallbackCodes) {
          final acc = await findByCode(code);
          if (acc != null) return acc;
        }
        return null;
      }

      // بارگذاری حساب‌ها با fallback
      final inv = await findByCodeWithFallback('10101', ['101', '1010']);
      final bank = await findByCodeWithFallback('10203', ['102', '1020']);
      final cash = await findByCodeWithFallback('10202', ['102', '1020']);
      final petty = await findByCodeWithFallback('10201', ['102', '1020']);
      final ar = await findByCodeWithFallback('10401', ['104', '1040']);
      final ap = await findByCodeWithFallback('20201', ['202', '2020']);
      // برای تراز خودکار: ابتدا 30201، سپس 30101، سپس 302 یا 301
      final equity = (await findByCode('30201')) ?? 
                     (await findByCode('30101')) ?? 
                     (await findByCode('302')) ?? 
                     (await findByCode('301'));

      if (!mounted) return;
      
      // Debug: لاگ کردن حساب‌های پیدا شده
      debugPrint('حساب‌های پیش‌فرض پیدا شده:');
      debugPrint('  موجودی: ${inv?.code} - ${inv?.name}');
      debugPrint('  بانک: ${bank?.code} - ${bank?.name}');
      debugPrint('  صندوق: ${cash?.code} - ${cash?.name}');
      debugPrint('  تنخواه: ${petty?.code} - ${petty?.name}');
      debugPrint('  دریافتنی: ${ar?.code} - ${ar?.name}');
      debugPrint('  پرداختنی: ${ap?.code} - ${ap?.name}');
      debugPrint('  حقوق صاحبان سهام: ${equity?.code} - ${equity?.name}');
      
      setState(() {
        _inventoryAccount = inv;
        _inventoryAccountId = inv?.id;
        _bankControlAccount = bank;
        _bankControlAccountId = bank?.id;
        _cashControlAccount = cash;
        _cashControlAccountId = cash?.id;
        _pettyControlAccount = petty;
        _pettyControlAccountId = petty?.id;
        _personReceivableAccount = ar;
        _personReceivableAccountId = ar?.id;
        _personPayableAccount = ap;
        _personPayableAccountId = ap?.id;
        _equityAccount = equity;
        _equityAccountId = equity?.id;
      });
      
      // ذخیره خودکار حساب‌های پیدا شده به عنوان پیش‌فرض
      if (mounted) {
        if (inv != null) await _saveDefault('inventory_account_id', inv.id);
        if (bank != null) await _saveDefault('bank_control_id', bank.id);
        if (cash != null) await _saveDefault('cash_control_id', cash.id);
        if (petty != null) await _saveDefault('petty_control_id', petty.id);
        if (ar != null) await _saveDefault('ar_control_id', ar.id);
        if (ap != null) await _saveDefault('ap_control_id', ap.id);
        if (equity != null) await _saveDefault('equity_account_id', equity.id);
      }
    } catch (e) {
      // در صورت خطا، لاگ کن اما ادامه بده
      if (mounted) {
        debugPrint('خطا در بارگذاری حساب‌های پیش‌فرض: $e');
      }
    }
  }

  Future<void> _loadSavedDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accountService = AccountService();
      String k(String name) => 'ob_default_${widget.businessId}_$name';
      
      int? gi(String name) {
        final v = prefs.getInt(k(name));
        return v is int && v > 0 ? v : null;
      }
      
      // بارگذاری Account objects برای حساب‌های ذخیره شده
      Future<Account?> loadAccountById(int? id) async {
        if (id == null) return null;
        try {
          // ابتدا سعی می‌کنیم با business_id حساب را بگیریم
          final accountData = await accountService.getAccount(businessId: widget.businessId, accountId: id);
          return Account.fromJson(accountData);
        } catch (e) {
          // اگر خطا گرفتیم (مثلاً حساب عمومی است که business_id ندارد)، 
          // از getAccounts استفاده می‌کنیم که حساب‌های عمومی و اختصاصی را برمی‌گرداند
          try {
            final accountsResult = await accountService.getAccounts(businessId: widget.businessId);
            final items = (accountsResult['items'] as List<dynamic>? ?? const <dynamic>[]);
            for (final it in items) {
              final acc = Account.fromJson(Map<String, dynamic>.from(it as Map));
              if (acc.id == id) return acc;
            }
          } catch (_) {
            // اگر getAccounts هم خطا داد، null برمی‌گردانیم
          }
          return null;
        }
      }

      final savedInventoryId = gi('inventory_account_id') ?? _inventoryAccountId;
      final savedEquityId = gi('equity_account_id') ?? _equityAccountId;
      final savedBankId = gi('bank_control_id') ?? _bankControlAccountId;
      final savedCashId = gi('cash_control_id') ?? _cashControlAccountId;
      final savedPettyId = gi('petty_control_id') ?? _pettyControlAccountId;
      final savedArId = gi('ar_control_id') ?? _personReceivableAccountId;
      final savedApId = gi('ap_control_id') ?? _personPayableAccountId;

      // بارگذاری Account objects
      final savedInventory = savedInventoryId != null ? await loadAccountById(savedInventoryId) : null;
      final savedEquity = savedEquityId != null ? await loadAccountById(savedEquityId) : null;
      final savedBank = savedBankId != null ? await loadAccountById(savedBankId) : null;
      final savedCash = savedCashId != null ? await loadAccountById(savedCashId) : null;
      final savedPetty = savedPettyId != null ? await loadAccountById(savedPettyId) : null;
      final savedAr = savedArId != null ? await loadAccountById(savedArId) : null;
      final savedAp = savedApId != null ? await loadAccountById(savedApId) : null;

      if (!mounted) return;
      setState(() {
        // فقط اگر حساب ذخیره شده وجود دارد، آن را استفاده کن (override پیش‌فرض)
        if (savedInventoryId != null) {
          _inventoryAccount = savedInventory ?? _inventoryAccount;
          _inventoryAccountId = savedInventoryId;
        }
        if (savedEquityId != null) {
          _equityAccount = savedEquity ?? _equityAccount;
          _equityAccountId = savedEquityId;
        }
        if (savedBankId != null) {
          _bankControlAccount = savedBank;
          _bankControlAccountId = savedBankId;
        }
        if (savedCashId != null) {
          _cashControlAccount = savedCash;
          _cashControlAccountId = savedCashId;
        }
        if (savedPettyId != null) {
          _pettyControlAccount = savedPetty;
          _pettyControlAccountId = savedPettyId;
        }
        if (savedArId != null) {
          _personReceivableAccount = savedAr;
          _personReceivableAccountId = savedArId;
        }
        if (savedApId != null) {
          _personPayableAccount = savedAp;
          _personPayableAccountId = savedApId;
        }
      });
    } catch (e) {
      if (mounted) {
        debugPrint('خطا در بارگذاری حساب‌های ذخیره شده: $e');
      }
    }
  }

  Future<void> _saveDefault(String name, int? id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'ob_default_${widget.businessId}_$name';
      if (id == null || id <= 0) {
        await prefs.remove(key);
      } else {
        await prefs.setInt(key, id);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    // Guard: view permission
    if (!widget.authStore.canReadSection('opening_balance')) {
      return PermissionGuard.buildAccessDeniedPage();
    }
    final canEdit = widget.authStore.hasBusinessPermission('opening_balance', 'edit');
    final validation = _computeValidation();
    final isPosted = (_document?['extra_info']?['posted'] ?? false) == true;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.openingBalance),
        actions: [
          TextButton.icon(
            onPressed: (_loading || !canEdit || (validation['save_disabled'] == true) || isPosted) ? null : _save,
            icon: const Icon(Icons.save),
            label: Text(t.save),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: (_loading || !canEdit || (validation['finalize_disabled'] == true) || isPosted) ? null : _post,
            icon: const Icon(Icons.how_to_reg),
            label: const Text('نهایی‌سازی'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(t),
    );
  }

  Widget _buildContent(AppLocalizations t) {
    final totals = _calcTotals();
    _computeValidation();
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = constraints.maxHeight;
        final tabHeight = screenHeight * 0.5; // 50% از ارتفاع صفحه برای تب‌ها
        
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(t.openingBalance, style: Theme.of(context).textTheme.titleLarge),
                    if ((_document?['extra_info']?['posted'] ?? false) == true)
                      Chip(
                        label: const Text('نهایی شده'),
                        avatar: const Icon(Icons.check_circle, size: 18),
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        labelStyle: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildValidationWarnings(),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('سال مالی: ${_document?['fiscal_year_title'] ?? '-'}'),
                        const SizedBox(height: 8),
                        Text('تاریخ سند: ${_document?['document_date'] ?? '-'}'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: Text('جمع بدهکار: ${totals['debit']?.toStringAsFixed(2) ?? '0'}')),
                            Expanded(child: Text('جمع بستانکار: ${totals['credit']?.toStringAsFixed(2) ?? '0'}')),
                            Expanded(child: Text('اختلاف: ${(totals['diff'] as double).toStringAsFixed(2)}')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Switch(value: _autoBalance, onChanged: (v) => setState(() => _autoBalance = v)),
                            const SizedBox(width: 8),
                            const Text('بستن خودکار اختلاف به حقوق صاحبان سهام'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildQuickSelectors(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: tabHeight,
                  child: _buildTabs(t),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabs(AppLocalizations t) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'بانک/صندوق/تنخواه'),
              Tab(text: 'اشخاص'),
              Tab(text: 'کالا'),
              Tab(text: 'سایر حساب‌ها'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              children: [
                _buildBankCashPettyTab(),
                _buildPersonsTab(),
                _buildInventoryTab(),
                _buildOtherAccountsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isBankCashPettyDuplicate(String type, dynamic refId) {
    final int? refIdInt = refId is int ? refId : (refId is String ? int.tryParse(refId) : (refId is num ? refId.toInt() : null));
    if (refIdInt == null) return false;
    return _bankCashPettyLines.any((line) => 
      line['type'] == type && (line['refId'] as int? ?? 0) == refIdInt
    );
  }

  Widget _buildBankCashPettyTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: BankAccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccountId: null,
                onChanged: (opt) {
                  if (opt == null) return;
                  if (_isBankCashPettyDuplicate('bank', opt.id)) {
                    if (mounted) {
                      SnackBarHelper.show(
                        context,
                        message: 'این حساب بانکی قبلاً اضافه شده است',
                        backgroundColor: Theme.of(context).colorScheme.error,
                        isError: true,
                      );
                    }
                    return;
                  }
                  final bankId = int.tryParse(opt.id);
                  if (bankId == null) return;
                  _bankCashPettyLines.add({
                    'type': 'bank', 
                    'refId': bankId, 
                    'name': opt.name ?? 'نامشخص',
                    'debit': 0.0,
                    'credit': 0.0,
                  });
                  setState(() {});
                },
                label: 'افزودن بانک',
                hintText: 'انتخاب و افزودن بانک',
                filterCurrencyId: widget.authStore.selectedCurrencyId,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CashRegisterComboboxWidget(
                businessId: widget.businessId,
                selectedRegisterId: null,
                onChanged: (opt) {
                  if (opt == null) return;
                  if (_isBankCashPettyDuplicate('cash', opt.id)) {
                    if (mounted) {
                      SnackBarHelper.show(
                        context,
                        message: 'این صندوق قبلاً اضافه شده است',
                        backgroundColor: Theme.of(context).colorScheme.error,
                        isError: true,
                      );
                    }
                    return;
                  }
                  final cashId = int.tryParse(opt.id);
                  if (cashId == null) return;
                  _bankCashPettyLines.add({
                    'type': 'cash', 
                    'refId': cashId, 
                    'name': opt.name ?? 'نامشخص',
                    'debit': 0.0,
                    'credit': 0.0,
                  });
                  setState(() {});
                },
                label: 'افزودن صندوق',
                hintText: 'انتخاب و افزودن صندوق',
                filterCurrencyId: widget.authStore.selectedCurrencyId,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PettyCashComboboxWidget(
                businessId: widget.businessId,
                selectedPettyCashId: null,
                onChanged: (opt) {
                  if (opt == null) return;
                  if (_isBankCashPettyDuplicate('petty', opt.id)) {
                    if (mounted) {
                      SnackBarHelper.show(
                        context,
                        message: 'این تنخواه قبلاً اضافه شده است',
                        backgroundColor: Theme.of(context).colorScheme.error,
                        isError: true,
                      );
                    }
                    return;
                  }
                  final pettyId = int.tryParse(opt.id);
                  if (pettyId == null) return;
                  _bankCashPettyLines.add({
                    'type': 'petty', 
                    'refId': pettyId, 
                    'name': opt.name ?? 'نامشخص',
                    'debit': 0.0,
                    'credit': 0.0,
                  });
                  setState(() {});
                },
                label: 'افزودن تنخواه',
                hintText: 'انتخاب و افزودن تنخواه',
                filterCurrencyId: widget.authStore.selectedCurrencyId,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _bankCashPettyLines.isEmpty
              ? const Center(child: Text('هیچ موردی اضافه نشده است'))
              : ListView.separated(
                  itemCount: _bankCashPettyLines.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
              final m = _bankCashPettyLines[index];
              final typeLabel = m['type'] == 'bank' ? 'بانک' : (m['type'] == 'cash' ? 'صندوق' : 'تنخواه');
              final name = m['name'] as String? ?? 'نامشخص';
              return ListTile(
                leading: Icon(m['type'] == 'bank' ? Icons.account_balance : (m['type'] == 'cash' ? Icons.point_of_sale : Icons.wallet)),
                title: Text('$typeLabel: $name'),
                subtitle: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: formatNumberForInput(m['debit'] as double?, decimalPlaces: 0),
                        decoration: const InputDecoration(isDense: true, labelText: 'بدهکار'),
                        keyboardType: TextInputType.number,
                        inputFormatters: const [
                          NumberInputFormatter(allowDecimal: false),
                        ],
                        onChanged: (v) {
                          m['debit'] = parseFormattedDouble(v) ?? 0.0;
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: formatNumberForInput(m['credit'] as double?, decimalPlaces: 0),
                        decoration: const InputDecoration(isDense: true, labelText: 'بستانکار'),
                        keyboardType: TextInputType.number,
                        inputFormatters: const [
                          NumberInputFormatter(allowDecimal: false),
                        ],
                        onChanged: (v) {
                          m['credit'] = parseFormattedDouble(v) ?? 0.0;
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () { _bankCashPettyLines.removeAt(index); setState(() {}); }),
              );
                  },
                ),
        ),
      ],
    );
  }

  bool _isPersonDuplicate(int? personId) {
    if (personId == null) return false;
    return _personLines.any((line) => line['personId'] == personId);
  }

  Widget _buildPersonsTab() {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
            child: PersonComboboxWidget(
            businessId: widget.businessId,
            onChanged: (p) {
              if (p == null) return;
              if (_isPersonDuplicate(p.id)) {
                if (mounted) {
                  SnackBarHelper.show(
                    context,
                    message: 'این شخص قبلاً اضافه شده است',
                    backgroundColor: Theme.of(context).colorScheme.error,
                    isError: true,
                  );
                }
                return;
              }
              _personLines.add({
                'personId': p.id, 
                'personName': p.aliasName ?? 'نامشخص',
                'debit': 0.0, 
                'credit': 0.0
              });
              setState(() {});
            },
            label: 'افزودن شخص',
            searchHint: 'نام/کد/تلفن...',
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _personLines.isEmpty
              ? const Center(child: Text('هیچ موردی اضافه نشده است'))
              : ListView.separated(
                  itemCount: _personLines.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
              final m = _personLines[index];
              final personName = m['personName'] as String? ?? 'شخص #${m['personId']}';
              return ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(personName),
                subtitle: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: formatNumberForInput(m['debit'] as double?, decimalPlaces: 0),
                        decoration: const InputDecoration(isDense: true, labelText: 'بدهکار'),
                        keyboardType: TextInputType.number,
                        inputFormatters: const [
                          NumberInputFormatter(allowDecimal: false),
                        ],
                        onChanged: (v) {
                          m['debit'] = parseFormattedDouble(v) ?? 0.0;
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: formatNumberForInput(m['credit'] as double?, decimalPlaces: 0),
                        decoration: const InputDecoration(isDense: true, labelText: 'بستانکار'),
                        keyboardType: TextInputType.number,
                        inputFormatters: const [
                          NumberInputFormatter(allowDecimal: false),
                        ],
                        onChanged: (v) {
                          m['credit'] = parseFormattedDouble(v) ?? 0.0;
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () { _personLines.removeAt(index); setState(() {}); }),
              );
                  },
                ),
        ),
      ],
    );
  }

  bool _isInventoryDuplicate(int productId, int? warehouseId) {
    return _inventoryLines.any((line) {
      final product = line['product'] as Map<String, dynamic>?;
      final pid = product?['id'] as int?;
      final wid = line['warehouseId'] as int?;
      return pid == productId && wid == warehouseId;
    });
  }

  Widget _buildInventoryTab() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: ProductComboboxWidget(
                businessId: widget.businessId,
                onChanged: (p) {
                  if (p == null) return;
                  final productId = p['id'] as int?;
                  if (productId == null) return;
                  // چک می‌کنیم که آیا این کالا با انبار null قبلاً اضافه شده یا نه
                  if (_isInventoryDuplicate(productId, null)) {
                    if (mounted) {
                      SnackBarHelper.show(
                        context,
                        message: 'این کالا قبلاً اضافه شده است. لطفاً مورد موجود را ویرایش کنید یا حذف کنید',
                        backgroundColor: Theme.of(context).colorScheme.error,
                        isError: true,
                      );
                    }
                    return;
                  }
                  _inventoryLines.add({'product': p, 'warehouseId': null, 'quantity': 0.0, 'cost_price': 0.0});
                  setState(() {});
                },
                label: 'افزودن کالا',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: _inventoryAccount,
                onChanged: (acc) {
                  _inventoryAccount = acc;
                  _inventoryAccountId = acc?.id;
                  setState(() {});
                },
                label: 'حساب موجودی',
                hintText: 'انتخاب حساب موجودی کالا',
                isRequired: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _inventoryLines.isEmpty
              ? const Center(child: Text('هیچ موردی اضافه نشده است'))
              : ListView.separated(
                  itemCount: _inventoryLines.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
              final m = _inventoryLines[index];
              return ListTile(
                leading: const Icon(Icons.inventory_outlined),
                title: Text('${m['product']?['code'] ?? ''} - ${m['product']?['name'] ?? ''}'),
                subtitle: Row(
                  children: [
                    Expanded(
                      child: WarehouseComboboxWidget(
                        businessId: widget.businessId,
                        selectedWarehouseId: m['warehouseId'] as int?,
                        selectDefaultWhenUnset: true,
                        onChanged: (wid) {
                          final product = m['product'] as Map<String, dynamic>?;
                          final pid = product?['id'] as int?;
                          if (pid != null && wid != null) {
                            // چک می‌کنیم که آیا این کالا با این انبار در سایر موارد (غیر از مورد فعلی) وجود دارد
                            final isDuplicate = _inventoryLines.asMap().entries.any((entry) {
                              if (entry.key == index) return false; // مورد فعلی را نادیده بگیر
                              final otherLine = entry.value;
                              final otherProduct = otherLine['product'] as Map<String, dynamic>?;
                              final otherPid = otherProduct?['id'] as int?;
                              final otherWid = otherLine['warehouseId'] as int?;
                              return otherPid == pid && otherWid == wid;
                            });
                            if (isDuplicate) {
                              if (mounted) {
                                SnackBarHelper.show(
                                  context,
                                  message: 'این کالا با این انبار قبلاً اضافه شده است',
                                  backgroundColor: Theme.of(context).colorScheme.error,
                                  isError: true,
                                );
                              }
                              return;
                            }
                          }
                          m['warehouseId'] = wid;
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: TextEditingController(
                          text: formatNumberForInput(m['quantity'] as double?, decimalPlaces: 2),
                        ),
                        decoration: const InputDecoration(isDense: true, labelText: 'تعداد'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          NumberInputFormatter(allowDecimal: true),
                        ],
                        onChanged: (v) {
                          m['quantity'] = parseFormattedDouble(v) ?? 0.0;
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: TextEditingController(
                          text: formatNumberForInput(m['cost_price'] as double?, decimalPlaces: 2),
                        ),
                        decoration: const InputDecoration(isDense: true, labelText: 'بهای واحد'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          NumberInputFormatter(allowDecimal: true),
                        ],
                        onChanged: (v) {
                          m['cost_price'] = parseFormattedDouble(v) ?? 0.0;
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () { _inventoryLines.removeAt(index); setState(() {}); }),
              );
            },
          ),
        ),
      ],
    );
  }

  bool _isAccountDuplicate(int? accountId) {
    if (accountId == null) return false;
    return _otherAccountLines.any((line) {
      final acc = line['account'] as Account?;
      return acc?.id == accountId;
    });
  }

  Widget _buildOtherAccountsTab() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: null,
                onChanged: (acc) {
                  if (acc != null) {
                    if (_isAccountDuplicate(acc.id)) {
                      if (mounted) {
                        SnackBarHelper.show(
                          context,
                          message: 'این حساب قبلاً اضافه شده است',
                          backgroundColor: Theme.of(context).colorScheme.error,
                          isError: true,
                        );
                      }
                      return;
                    }
                    _otherAccountLines.add({'account': acc, 'debit': 0.0, 'credit': 0.0});
                    setState(() {});
                  }
                },
                label: 'افزودن حساب',
                hintText: 'جستجو و انتخاب حساب',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: _equityAccount,
                onChanged: (acc) {
                  _equityAccount = acc;
                  _equityAccountId = acc?.id;
                  setState(() {});
                },
                label: 'حساب حقوق صاحبان سهام',
                hintText: 'انتخاب حساب سرمایه/سنواتی',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _otherAccountLines.isEmpty
              ? const Center(child: Text('هیچ موردی اضافه نشده است'))
              : ListView.builder(
                  itemCount: _otherAccountLines.length,
                  itemBuilder: (context, index) {
              final m = _otherAccountLines[index];
              return ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: Text(m['account'] != null ? (m['account'] as Account).displayName : 'حساب'),
                subtitle: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: formatNumberForInput(m['debit'] as double?, decimalPlaces: 0),
                        decoration: const InputDecoration(isDense: true, labelText: 'بدهکار'),
                        keyboardType: TextInputType.number,
                        inputFormatters: const [
                          NumberInputFormatter(allowDecimal: false),
                        ],
                        onChanged: (v) {
                          m['debit'] = parseFormattedDouble(v) ?? 0.0;
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: formatNumberForInput(m['credit'] as double?, decimalPlaces: 0),
                        decoration: const InputDecoration(isDense: true, labelText: 'بستانکار'),
                        keyboardType: TextInputType.number,
                        inputFormatters: const [
                          NumberInputFormatter(allowDecimal: false),
                        ],
                        onChanged: (v) {
                          m['credit'] = parseFormattedDouble(v) ?? 0.0;
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () { _otherAccountLines.removeAt(index); setState(() {}); }),
              );
            },
          ),
        ),
      ],
    );
  }

  Map<String, double> _calcTotals() {
    double debit = 0.0;
    double credit = 0.0;
    for (final m in _bankCashPettyLines) {
      debit += (m['debit'] as double? ?? 0.0);
      credit += (m['credit'] as double? ?? 0.0);
    }
    for (final m in _personLines) {
      debit += (m['debit'] as double? ?? 0.0);
      credit += (m['credit'] as double? ?? 0.0);
    }
    for (final m in _otherAccountLines) {
      final d = (m['debit'] as double? ?? 0.0);
      final c = (m['credit'] as double? ?? 0.0);
      if (d <= 0 && c <= 0) continue;
      final acc = m['account'] as Account?;
      if (acc?.id == null) continue;
      debit += d;
      credit += c;
    }
    double invValue = 0.0;
    for (final m in _inventoryLines) {
      final q = (m['quantity'] as double? ?? 0.0);
      final c = (m['cost_price'] as double? ?? 0.0);
      invValue += (q * c);
    }
    debit += invValue;
    return {'debit': debit, 'credit': credit, 'diff': debit - credit};
  }
  
  Map<String, bool> _computeValidation() {
    final totals = _calcTotals();
    final diff = (totals['diff'] ?? 0.0).abs();
    final needsInventoryAccount = _inventoryLines.isNotEmpty && _inventoryAccountId == null;
    final canAutoBalance = _autoBalance && _equityAccountId != null;
    final balanced = diff <= 0.01 || canAutoBalance;
    final saveDisabled = needsInventoryAccount; // برای جلوگیری از ذخیره ناسالم با خطوط موجودی بدون حساب
    final finalizeDisabled = needsInventoryAccount || !balanced;
    return {
      'save_disabled': saveDisabled,
      'finalize_disabled': finalizeDisabled,
    };
  }

  Widget _buildValidationWarnings() {
    final List<Widget> msgs = [];
    if (_inventoryLines.isNotEmpty && _inventoryAccountId == null) {
      msgs.add(_warn('برای ثبت موجودی ابتدای دوره، انتخاب «حساب موجودی» الزامی است.'));
    }
    final totals = _calcTotals();
    final diff = (totals['diff'] ?? 0.0);
    if (diff.abs() > 0.01) {
      if (!_autoBalance) {
        msgs.add(_warn('سند متوازن نیست. اختلاف ${diff.toStringAsFixed(2)}. برای نهایی‌سازی، تراز را برابر کنید یا Auto-balance را روشن کنید.'));
      } else if (_autoBalance && _equityAccountId == null) {
        msgs.add(_warn('Auto-balance فعال است اما «حساب حقوق صاحبان سهام» انتخاب نشده است.'));
      }
    }
    if (msgs.isEmpty) return const SizedBox.shrink();
    return Column(children: msgs);
  }

  Widget _warn(String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.3),
        border: Border.all(color: cs.error.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: cs.error),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  // Deprecated helpers removed

  Widget _buildQuickSelectors() {
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    final hasDefaults = _inventoryAccountId != null || 
                        _equityAccountId != null || 
                        _bankControlAccountId != null ||
                        _cashControlAccountId != null ||
                        _pettyControlAccountId != null ||
                        _personReceivableAccountId != null ||
                        _personPayableAccountId != null;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'حساب‌های کلیدی (به صورت خودکار تکمیل شده):',
                style: textStyle?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            if (hasDefaults)
              Icon(
                Icons.check_circle_outline,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
        if (hasDefaults)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              'حساب‌های پیش‌فرض به صورت خودکار انتخاب شده‌اند. در صورت نیاز می‌توانید تغییر دهید.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              'لطفاً حساب‌های کلیدی را انتخاب کنید تا بتوانید تراز افتتاحیه را ثبت کنید.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: _inventoryAccount,
                onChanged: (acc) {
                  setState(() {
                    _inventoryAccount = acc;
                    _inventoryAccountId = acc?.id;
                  });
                  _saveDefault('inventory_account_id', _inventoryAccountId);
                },
                label: 'حساب موجودی',
                hintText: 'انتخاب حساب موجودی (مثل 10101)',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: _equityAccount,
                onChanged: (acc) {
                  setState(() {
                    _equityAccount = acc;
                    _equityAccountId = acc?.id;
                  });
                  _saveDefault('equity_account_id', _equityAccountId);
                },
                label: 'حساب حقوق صاحبان سهام',
                hintText: 'انتخاب سرمایه/سنواتی (مثل 30201/30101)',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: _bankControlAccount,
                onChanged: (acc) {
                  setState(() {
                    _bankControlAccount = acc;
                    _bankControlAccountId = acc?.id;
                  });
                  _saveDefault('bank_control_id', _bankControlAccountId);
                },
                label: 'حساب کنترل بانک',
                hintText: 'مثال: 10203',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: _cashControlAccount,
                onChanged: (acc) {
                  setState(() {
                    _cashControlAccount = acc;
                    _cashControlAccountId = acc?.id;
                  });
                  _saveDefault('cash_control_id', _cashControlAccountId);
                },
                label: 'حساب کنترل صندوق',
                hintText: 'مثال: 10202',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: _pettyControlAccount,
                onChanged: (acc) {
                  setState(() {
                    _pettyControlAccount = acc;
                    _pettyControlAccountId = acc?.id;
                  });
                  _saveDefault('petty_control_id', _pettyControlAccountId);
                },
                label: 'حساب کنترل تنخواه',
                hintText: 'مثال: 10201',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: _personReceivableAccount,
                onChanged: (acc) {
                  setState(() {
                    _personReceivableAccount = acc;
                    _personReceivableAccountId = acc?.id;
                  });
                  _saveDefault('ar_control_id', _personReceivableAccountId);
                },
                label: 'حساب دریافتنی اشخاص',
                hintText: 'مثال: 10401',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: _personPayableAccount,
                onChanged: (acc) {
                  setState(() {
                    _personPayableAccount = acc;
                    _personPayableAccountId = acc?.id;
                  });
                  _saveDefault('ap_control_id', _personPayableAccountId);
                },
                label: 'حساب پرداختنی اشخاص',
                hintText: 'مثال: 20201',
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(child: SizedBox.shrink()),
          ],
        ),
      ],
    );
  }

  Future<void> _save() async {
    final accountLines = <Map<String, dynamic>>[];
    for (final m in _bankCashPettyLines) {
      final debit = (m['debit'] as double? ?? 0.0);
      final credit = (m['credit'] as double? ?? 0.0);
      if (debit <= 0 && credit <= 0) continue;
      final refId = m['refId'];
      final int? refIdInt = refId is int ? refId : (refId is num ? refId.toInt() : int.tryParse('$refId'));
      if (refIdInt == null) continue;
      
      final accountId = _inferAccountIdForType(m['type'] as String);
      if (accountId == null) {
        final typeLabel = m['type'] == 'bank' ? 'بانک' : (m['type'] == 'cash' ? 'صندوق' : 'تنخواه');
        if (mounted) {
          SnackBarHelper.showError(
            context,
            message: 'برای ثبت $typeLabel، انتخاب حساب کنترل الزامی است',
          );
        }
        return;
      }
      
      accountLines.add({
        'account_id': accountId,
        if (m['type'] == 'bank') 'bank_account_id': refIdInt,
        if (m['type'] == 'cash') 'cash_register_id': refIdInt,
        if (m['type'] == 'petty') 'petty_cash_id': refIdInt,
        'debit': debit,
        'credit': credit,
      });
    }
    for (final m in _personLines) {
      final d = (m['debit'] as double? ?? 0.0);
      final c = (m['credit'] as double? ?? 0.0);
      if (d <= 0 && c <= 0) continue;
      final accountId = _inferPersonAccountId(d, c);
      if (accountId == null) {
        if (mounted) {
          SnackBarHelper.showError(
            context,
            message: 'برای ثبت اشخاص، انتخاب حساب دریافتنی یا پرداختنی الزامی است',
          );
        }
        return;
      }
      accountLines.add({'account_id': accountId, 'person_id': m['personId'], 'debit': d, 'credit': c});
    }
    for (final m in _otherAccountLines) {
      final d = (m['debit'] as double? ?? 0.0);
      final c = (m['credit'] as double? ?? 0.0);
      if (d <= 0 && c <= 0) continue;
      final acc = m['account'] as Account?;
      if (acc?.id == null) continue;
      accountLines.add({'account_id': acc!.id, 'debit': d, 'credit': c});
    }
    final inventoryLines = <Map<String, dynamic>>[];
    for (final m in _inventoryLines) {
      final product = (m['product'] as Map<String, dynamic>?);
      final dynamic pidRaw = product != null ? product['id'] : null;
      final int? pid = pidRaw is int ? pidRaw : int.tryParse("$pidRaw");
      final wid = m['warehouseId'] as int?;
      final q = (m['quantity'] as double? ?? 0.0);
      final c = (m['cost_price'] as double? ?? 0.0);
      
      if (pid == null) {
        if (mounted) {
          SnackBarHelper.showError(
            context,
            message: 'شناسه کالا نامعتبر است',
          );
        }
        return;
      }
      if (wid == null) {
        if (mounted) {
          SnackBarHelper.showError(
            context,
            message: 'برای ثبت موجودی، انتخاب انبار الزامی است',
          );
        }
        return;
      }
      if (q <= 0) continue;
      
      inventoryLines.add({
        'product_id': pid, 
        'quantity': q, 
        'extra_info': {
          'movement': 'in', 
          'warehouse_id': wid, 
          if (c > 0) 'cost_price': c
        }
      });
    }

    final payload = <String, dynamic>{
      'fiscal_year_id': _document?['fiscal_year_id'],
      'currency_id': _document?['currency_id'] ?? widget.authStore.selectedCurrencyId,
      'account_lines': accountLines,
      'inventory_lines': inventoryLines,
      if (_inventoryAccountId != null) 'inventory_account_id': _inventoryAccountId,
      'auto_balance_to_equity': _autoBalance,
      if (_equityAccountId != null) 'equity_account_id': _equityAccountId,
    };

    try {
      final saved = await _service.save(businessId: widget.businessId, payload: payload);
      setState(() => _document = saved);
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: 'ذخیره شد',
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: 'خطا در ذخیره: ${ErrorExtractor.forContext(e, context)}',
          backgroundColor: Theme.of(context).colorScheme.error,
          isError: true,
        );
      }
    }
  }

  int? _inferAccountIdForType(String type) {
    switch (type) {
      case 'bank':
        return _bankControlAccountId;
      case 'cash':
        return _cashControlAccountId;
      case 'petty':
        return _pettyControlAccountId;
    }
    return null;
  }

  int? _inferPersonAccountId(double debit, double credit) {
    if (debit > 0 && (credit <= 0)) {
      return _personReceivableAccountId; // دریافتنی
    }
    if (credit > 0 && (debit <= 0)) {
      return _personPayableAccountId; // پرداختنی
    }
    return null;
  }

  Future<void> _post() async {
    try {
      final posted = await _service.post(businessId: widget.businessId);
      setState(() => _document = posted);
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: 'تراز افتتاحیه نهایی شد',
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: 'خطا در نهایی‌سازی: ${ErrorExtractor.forContext(e, context)}',
          backgroundColor: Theme.of(context).colorScheme.error,
          isError: true,
        );
      }
    }
  }
}


