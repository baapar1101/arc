import 'dart:async';
import 'dart:convert';

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

/// اقدامات سروری که تا پایان درخواست دکمه‌ها را در حالت بارگذاری نگه می‌دارند.
enum _OpeningBalanceSubmitting { save, finalize, unpost }

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
  Timer? _draftAutoSaveTimer;
  String? _lastDraftSnapshot;
  _OpeningBalanceSubmitting? _submitting;

  String get _draftStorageKey => 'opening_balance_draft_${widget.businessId}';

  Widget _smallActionProgress({required Color? color}) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: color),
    );
  }

  Widget _toolbarLeadingIcon({
    required _OpeningBalanceSubmitting action,
    required IconData idleIcon,
  }) {
    if (_submitting == action) return _smallActionProgress(color: Theme.of(context).colorScheme.primary);
    return Icon(idleIcon);
  }

  Widget _toolbarFinalizeIcon() {
    if (_submitting == _OpeningBalanceSubmitting.finalize) {
      return _smallActionProgress(color: Theme.of(context).colorScheme.onPrimary);
    }
    return const Icon(Icons.how_to_reg);
  }

  Widget _toolbarUnpostIcon() {
    if (_submitting == _OpeningBalanceSubmitting.unpost) {
      return _smallActionProgress(color: Theme.of(context).colorScheme.primary);
    }
    return const Icon(Icons.undo_outlined);
  }

  @override
  void initState() {
    super.initState();
    _service = OpeningBalanceService(ApiClient());
    _bootstrap();
    _startDraftAutoSave();
  }

  Future<void> _bootstrap() async {
    await _initializeAccounts();
    if (mounted) {
      await _load();
      await _restoreDraftIfAvailable();
    }
  }

  void _startDraftAutoSave() {
    _draftAutoSaveTimer?.cancel();
    _draftAutoSaveTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted || _loading || _submitting != null) return;
      final isPosted = (_document?['extra_info']?['posted'] ?? false) == true;
      if (isPosted) return;
      await _persistDraftIfChanged();
    });
  }

  Map<String, dynamic> _buildDraftPayload() {
    final otherAccountLines = _otherAccountLines.map((m) {
      final acc = m['account'] as Account?;
      return {
        'account': acc == null
            ? null
            : {
                'id': acc.id,
                'code': acc.code,
                'name': acc.name,
                'account_type': acc.accountType,
              },
        'debit': m['debit'],
        'credit': m['credit'],
      };
    }).toList();

    return {
      'saved_at': DateTime.now().toIso8601String(),
      'auto_balance': _autoBalance,
      'inventory_account_id': _inventoryAccountId,
      'equity_account_id': _equityAccountId,
      'bank_control_id': _bankControlAccountId,
      'cash_control_id': _cashControlAccountId,
      'petty_control_id': _pettyControlAccountId,
      'ar_control_id': _personReceivableAccountId,
      'ap_control_id': _personPayableAccountId,
      'bank_cash_petty_lines': _bankCashPettyLines,
      'person_lines': _personLines,
      'inventory_lines': _inventoryLines,
      'other_account_lines': otherAccountLines,
    };
  }

  Future<void> _persistDraftIfChanged() async {
    try {
      final payload = _buildDraftPayload();
      final snapshot = jsonEncode(payload);
      if (snapshot == _lastDraftSnapshot) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_draftStorageKey, snapshot);
      _lastDraftSnapshot = snapshot;
    } catch (_) {}
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftStorageKey);
      _lastDraftSnapshot = null;
    } catch (_) {}
  }

  Future<void> _restoreDraftIfAvailable() async {
    try {
      final isPosted = (_document?['extra_info']?['posted'] ?? false) == true;
      if (isPosted) return;

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftStorageKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      final bankLines = (decoded['bank_cash_petty_lines'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final personLines = (decoded['person_lines'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final inventoryLines = (decoded['inventory_lines'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final otherLinesRaw = (decoded['other_account_lines'] as List<dynamic>? ?? const <dynamic>[]);
      if (bankLines.isEmpty && personLines.isEmpty && inventoryLines.isEmpty && otherLinesRaw.isEmpty) return;

      final accountService = AccountService();
      Future<Account?> loadAccountById(int? id) async {
        if (id == null) return null;
        try {
          final data = await accountService.getAccount(businessId: widget.businessId, accountId: id);
          return Account.fromJson(data);
        } catch (_) {
          return null;
        }
      }

      final inventoryId = decoded['inventory_account_id'] as int?;
      final equityId = decoded['equity_account_id'] as int?;
      final bankControlId = decoded['bank_control_id'] as int?;
      final cashControlId = decoded['cash_control_id'] as int?;
      final pettyControlId = decoded['petty_control_id'] as int?;
      final arControlId = decoded['ar_control_id'] as int?;
      final apControlId = decoded['ap_control_id'] as int?;

      final invAcc = await loadAccountById(inventoryId);
      final eqAcc = await loadAccountById(equityId);
      final bankAcc = await loadAccountById(bankControlId);
      final cashAcc = await loadAccountById(cashControlId);
      final pettyAcc = await loadAccountById(pettyControlId);
      final arAcc = await loadAccountById(arControlId);
      final apAcc = await loadAccountById(apControlId);

      if (!mounted) return;
      setState(() {
        _autoBalance = decoded['auto_balance'] as bool? ?? _autoBalance;

        _inventoryAccountId = inventoryId ?? _inventoryAccountId;
        _equityAccountId = equityId ?? _equityAccountId;
        _bankControlAccountId = bankControlId ?? _bankControlAccountId;
        _cashControlAccountId = cashControlId ?? _cashControlAccountId;
        _pettyControlAccountId = pettyControlId ?? _pettyControlAccountId;
        _personReceivableAccountId = arControlId ?? _personReceivableAccountId;
        _personPayableAccountId = apControlId ?? _personPayableAccountId;

        _inventoryAccount = invAcc ?? _inventoryAccount;
        _equityAccount = eqAcc ?? _equityAccount;
        _bankControlAccount = bankAcc ?? _bankControlAccount;
        _cashControlAccount = cashAcc ?? _cashControlAccount;
        _pettyControlAccount = pettyAcc ?? _pettyControlAccount;
        _personReceivableAccount = arAcc ?? _personReceivableAccount;
        _personPayableAccount = apAcc ?? _personPayableAccount;

        _bankCashPettyLines
          ..clear()
          ..addAll(bankLines);
        _personLines
          ..clear()
          ..addAll(personLines);
        _inventoryLines
          ..clear()
          ..addAll(inventoryLines);

        _otherAccountLines.clear();
        for (final rawLine in otherLinesRaw) {
          if (rawLine is! Map) continue;
          final m = Map<String, dynamic>.from(rawLine);
          final accountMap = m['account'] is Map ? Map<String, dynamic>.from(m['account'] as Map) : null;
          _otherAccountLines.add({
            'account': accountMap == null
                ? null
                : Account(
                    id: accountMap['id'] as int?,
                    code: accountMap['code']?.toString() ?? '',
                    name: accountMap['name']?.toString() ?? '',
                    accountType: accountMap['account_type']?.toString() ?? 'asset',
                    businessId: widget.businessId,
                  ),
            'debit': (m['debit'] as num?)?.toDouble() ?? 0.0,
            'credit': (m['credit'] as num?)?.toDouble() ?? 0.0,
          });
        }
      });

      if (mounted) {
        SnackBarHelper.show(
          context,
          message: 'پیش‌نویس ذخیره‌نشده بازیابی شد',
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        );
      }
      _lastDraftSnapshot = raw;
    } catch (_) {}
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
      final docNullable = await _service.fetch(businessId: widget.businessId);
      if (docNullable != null && docNullable.isNotEmpty) {
        final doc = docNullable;
        setState(() {
          _document = doc;
          _loadLinesFromDocument(doc);
        });
        if (mounted) {
          await _applyOpeningBalanceAccountObjects(doc);
        }
      } else {
        setState(() => _document = docNullable);
      }
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

    // بارگردانی تنظیمات (ریشهٔ پاسخ API و extra_info پس از ادغام در سرور)
    final docExtra = doc['extra_info'] as Map<String, dynamic>? ?? {};
    _autoBalance = (doc['auto_balance_to_equity'] as bool?) ??
        docExtra['auto_balance_to_equity'] as bool? ??
        true;

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

        // سطر تجمیعی بهای موجودی — فقط در تب کالا نمایش داده می‌شود؛ در «سایر حساب» تکرار نشود
        if (description == 'موجودی ابتدای دوره') {
          if (_inventoryAccountId == null && accountId != null) {
            _inventoryAccountId = accountId;
          }
          continue;
        }

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

    _inventoryAccountId =
        (doc['inventory_account_id'] as int?) ?? docExtra['inventory_account_id'] as int?;
    _equityAccountId = (doc['equity_account_id'] as int?) ?? docExtra['equity_account_id'] as int?;
  }

  Future<void> _applyOpeningBalanceAccountObjects(Map<String, dynamic> doc) async {
    final docExtra = doc['extra_info'] as Map<String, dynamic>? ?? {};
    final invId = (doc['inventory_account_id'] as int?) ?? docExtra['inventory_account_id'] as int?;
    final eqId = (doc['equity_account_id'] as int?) ?? docExtra['equity_account_id'] as int?;
    if (invId == null && eqId == null) return;

    final accountService = AccountService();
    Future<Account?> loadAccountById(int id) async {
      try {
        final data = await accountService.getAccount(businessId: widget.businessId, accountId: id);
        return Account.fromJson(data);
      } catch (_) {
        try {
          final res = await accountService.getAccounts(businessId: widget.businessId);
          final items = (res['items'] as List<dynamic>? ?? const <dynamic>[]);
          for (final it in items) {
            final acc = Account.fromJson(Map<String, dynamic>.from(it as Map));
            if (acc.id == id) return acc;
          }
        } catch (_) {}
        return null;
      }
    }

    final invAcc = invId != null ? await loadAccountById(invId) : null;
    final eqAcc = eqId != null ? await loadAccountById(eqId) : null;
    if (!mounted) return;
    setState(() {
      if (invAcc != null) {
        _inventoryAccount = invAcc;
        _inventoryAccountId = invAcc.id;
      }
      if (eqAcc != null) {
        _equityAccount = eqAcc;
        _equityAccountId = eqAcc.id;
      }
    });
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

      // موجودی: 10102 (نمودار استاندارد فاکتورها)، سپس 12101 (بستن سال / OB خودکار)، سپس سایر
      final inv = await findByCodeWithFallback('10102', ['12101', '10101', '101', '1010']);
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
  void dispose() {
    _draftAutoSaveTimer?.cancel();
    super.dispose();
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
    final serverBusy = _submitting != null;
    final canSave = !(_loading || serverBusy || !canEdit || (validation['save_disabled'] == true) || isPosted);
    final canFinalize =
        !(_loading || serverBusy || !canEdit || (validation['finalize_disabled'] == true) || isPosted);
    final canUnpost = !(_loading || serverBusy || !canEdit || !isPosted);
    final isCompactAppBar = MediaQuery.sizeOf(context).width < 760;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.openingBalance),
        actions: isCompactAppBar
            ? [
                PopupMenuButton<String>(
                  tooltip: 'اقدامات',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (serverBusy) return;
                    if (value == 'save' && canSave) _save();
                    if (value == 'finalize' && canFinalize) _post();
                    if (value == 'unpost' && canUnpost) _confirmUnpost();
                  },
                  itemBuilder: (context) => isPosted
                      ? [
                          PopupMenuItem<String>(
                            value: 'unpost',
                            enabled: canUnpost,
                            child: const Row(
                              children: [
                                Icon(Icons.undo, size: 18),
                                SizedBox(width: 8),
                                Text('لغو نهایی‌سازی'),
                              ],
                            ),
                          ),
                        ]
                      : [
                          PopupMenuItem<String>(
                            value: 'save',
                            enabled: canSave,
                            child: Row(
                              children: [
                                const Icon(Icons.save_outlined, size: 18),
                                const SizedBox(width: 8),
                                Text(t.save),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'finalize',
                            enabled: canFinalize,
                            child: const Row(
                              children: [
                                Icon(Icons.how_to_reg, size: 18),
                                SizedBox(width: 8),
                                Text('نهایی‌سازی'),
                              ],
                            ),
                          ),
                        ],
                ),
                const SizedBox(width: 8),
              ]
            : isPosted
                ? [
                    OutlinedButton.icon(
                      onPressed: canUnpost ? _confirmUnpost : null,
                      icon: _toolbarUnpostIcon(),
                      label: const Text('لغو نهایی‌سازی'),
                    ),
                    const SizedBox(width: 12),
                  ]
                : [
                    TextButton.icon(
                      onPressed: canSave ? _save : null,
                      icon: _toolbarLeadingIcon(
                        action: _OpeningBalanceSubmitting.save,
                        idleIcon: Icons.save,
                      ),
                      label: Text(t.save),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: canFinalize ? _post : null,
                      icon: _toolbarFinalizeIcon(),
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
        final tabHeight = (screenHeight - 320).clamp(280.0, 560.0);
        final isPosted = (_document?['extra_info']?['posted'] ?? false) == true;
        
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isPosted)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Chip(
                      label: const Text('نهایی شده'),
                      avatar: const Icon(Icons.check_circle, size: 18),
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      labelStyle: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                  ),
                if (isPosted) const SizedBox(height: 12),
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
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(
                              label: Text('جمع بدهکار: ${formatNumberForInput(totals['debit'], decimalPlaces: 0)}'),
                              avatar: const Icon(Icons.call_received_outlined, size: 18),
                            ),
                            Chip(
                              label: Text('جمع بستانکار: ${formatNumberForInput(totals['credit'], decimalPlaces: 0)}'),
                              avatar: const Icon(Icons.call_made_outlined, size: 18),
                            ),
                            Chip(
                              label: Text('اختلاف: ${formatNumberForInput(totals['diff'], decimalPlaces: 0)}'),
                              avatar: const Icon(Icons.balance_outlined, size: 18),
                              backgroundColor: ((totals['diff'] ?? 0).abs() > 0.01)
                                  ? Theme.of(context).colorScheme.errorContainer
                                  : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: _autoBalance,
                          onChanged: isPosted ? null : (v) => setState(() => _autoBalance = v),
                          title: const Text('بستن خودکار اختلاف به حقوق صاحبان سهام'),
                        ),
                        const SizedBox(height: 8),
                        _buildQuickSelectors(isPosted: isPosted),
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

  Widget _buildBankCashPettyTab() {
    final isPosted = (_document?['extra_info']?['posted'] ?? false) == true;
    final canEdit = widget.authStore.hasBusinessPermission('opening_balance', 'edit');
    final allowEdit = canEdit && !isPosted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 320,
              child: BankAccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccountId: null,
                onChanged: (opt) {
                  if (!allowEdit) return;
                  if (opt == null) return;
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
            SizedBox(
              width: 320,
              child: CashRegisterComboboxWidget(
                businessId: widget.businessId,
                selectedRegisterId: null,
                onChanged: (opt) {
                  if (!allowEdit) return;
                  if (opt == null) return;
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
            SizedBox(
              width: 320,
              child: PettyCashComboboxWidget(
                businessId: widget.businessId,
                selectedPettyCashId: null,
                onChanged: (opt) {
                  if (!allowEdit) return;
                  if (opt == null) return;
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
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: allowEdit && _bankCashPettyLines.isNotEmpty
                ? () {
                    final last = Map<String, dynamic>.from(_bankCashPettyLines.last);
                    last['debit'] = 0.0;
                    last['credit'] = 0.0;
                    _bankCashPettyLines.add(last);
                    setState(() {});
                  }
                : null,
            icon: const Icon(Icons.content_copy_outlined),
            label: const Text('تکرار آخرین سطر'),
          ),
        ),
        const SizedBox(height: 8),
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
                          if (!allowEdit) return;
                          m['debit'] = parseFormattedDouble(v) ?? 0.0;
                          setState(() {});
                        },
                        enabled: allowEdit,
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
                          if (!allowEdit) return;
                          m['credit'] = parseFormattedDouble(v) ?? 0.0;
                          setState(() {});
                        },
                        enabled: allowEdit,
                      ),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: allowEdit ? () { _bankCashPettyLines.removeAt(index); setState(() {}); } : null,
                ),
              );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPersonsTab() {
    final isPosted = (_document?['extra_info']?['posted'] ?? false) == true;
    final canEdit = widget.authStore.hasBusinessPermission('opening_balance', 'edit');
    final allowEdit = canEdit && !isPosted;

    return Column(
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
            child: PersonComboboxWidget(
            businessId: widget.businessId,
            onChanged: (p) {
              if (!allowEdit) return;
              if (p == null) return;
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
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: allowEdit && _personLines.isNotEmpty
                ? () {
                    final last = Map<String, dynamic>.from(_personLines.last);
                    last['debit'] = 0.0;
                    last['credit'] = 0.0;
                    _personLines.add(last);
                    setState(() {});
                  }
                : null,
            icon: const Icon(Icons.content_copy_outlined),
            label: const Text('تکرار آخرین سطر'),
          ),
        ),
        const SizedBox(height: 8),
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
                          if (!allowEdit) return;
                          m['debit'] = parseFormattedDouble(v) ?? 0.0;
                          setState(() {});
                        },
                        enabled: allowEdit,
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
                          if (!allowEdit) return;
                          m['credit'] = parseFormattedDouble(v) ?? 0.0;
                          setState(() {});
                        },
                        enabled: allowEdit,
                      ),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: allowEdit ? () { _personLines.removeAt(index); setState(() {}); } : null,
                ),
              );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildInventoryTab() {
    final isPosted = (_document?['extra_info']?['posted'] ?? false) == true;
    final canEdit = widget.authStore.hasBusinessPermission('opening_balance', 'edit');
    final allowEditInventory = canEdit && !isPosted;

    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 420,
              child: ProductComboboxWidget(
                businessId: widget.businessId,
                onChanged: (p) {
                  if (!allowEditInventory) return;
                  if (p == null) return;
                  final productId = p['id'] as int?;
                  if (productId == null) return;
                  _inventoryLines.add({'product': p, 'warehouseId': null, 'quantity': 0.0, 'cost_price': 0.0});
                  setState(() {});
                },
                label: 'افزودن کالا',
              ),
            ),
            SizedBox(
              width: 320,
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: _inventoryAccount,
                onChanged: (acc) {
                  if (!allowEditInventory) return;
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
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: allowEditInventory && _inventoryLines.isNotEmpty
                ? () {
                    final last = Map<String, dynamic>.from(_inventoryLines.last);
                    last['quantity'] = 0.0;
                    last['cost_price'] = 0.0;
                    _inventoryLines.add(last);
                    setState(() {});
                  }
                : null,
            icon: const Icon(Icons.content_copy_outlined),
            label: const Text('تکرار آخرین سطر'),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _inventoryLines.isEmpty
              ? const Center(child: Text('هیچ موردی اضافه نشده است'))
              : ListView.separated(
                  itemCount: _inventoryLines.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
              final m = _inventoryLines[index];
              return ListTile(
                key: ObjectKey(m),
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
                          if (!allowEditInventory) return;
                          m['warehouseId'] = wid;
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _OpeningBalanceInventoryQtyPriceFields(
                        line: m,
                        enabled: allowEditInventory,
                        onModelChanged: () {
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: allowEditInventory
                      ? () {
                          _inventoryLines.removeAt(index);
                          setState(() {});
                        }
                      : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOtherAccountsTab() {
    final isPosted = (_document?['extra_info']?['posted'] ?? false) == true;
    final canEdit = widget.authStore.hasBusinessPermission('opening_balance', 'edit');
    final allowEdit = canEdit && !isPosted;

    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 320,
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: null,
                onChanged: (acc) {
                  if (!allowEdit) return;
                  if (acc != null) {
                    _otherAccountLines.add({'account': acc, 'debit': 0.0, 'credit': 0.0});
                    setState(() {});
                  }
                },
                label: 'افزودن حساب',
                hintText: 'جستجو و انتخاب حساب',
              ),
            ),
            SizedBox(
              width: 320,
              child: AccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: _equityAccount,
                onChanged: (acc) {
                  if (!allowEdit) return;
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
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: allowEdit && _otherAccountLines.isNotEmpty
                ? () {
                    final last = Map<String, dynamic>.from(_otherAccountLines.last);
                    last['debit'] = 0.0;
                    last['credit'] = 0.0;
                    _otherAccountLines.add(last);
                    setState(() {});
                  }
                : null,
            icon: const Icon(Icons.content_copy_outlined),
            label: const Text('تکرار آخرین سطر'),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _otherAccountLines.isEmpty
              ? const Center(child: Text('هیچ موردی اضافه نشده است'))
              : ListView.separated(
                  itemCount: _otherAccountLines.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
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
                          if (!allowEdit) return;
                          m['debit'] = parseFormattedDouble(v) ?? 0.0;
                          setState(() {});
                        },
                        enabled: allowEdit,
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
                          if (!allowEdit) return;
                          m['credit'] = parseFormattedDouble(v) ?? 0.0;
                          setState(() {});
                        },
                        enabled: allowEdit,
                      ),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: allowEdit ? () { _otherAccountLines.removeAt(index); setState(() {}); } : null,
                ),
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
        msgs.add(_warn('سند متوازن نیست. اختلاف ${diff.toStringAsFixed(2)}. برای نهایی‌سازی، تراز را برابر کنید یا «تراز خودکار» را روشن کنید.'));
      } else if (_autoBalance && _equityAccountId == null) {
        msgs.add(_warn('تراز خودکار فعال است اما «حساب حقوق صاحبان سهام» انتخاب نشده است.'));
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

  Widget _buildQuickSelectors({required bool isPosted}) {
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
                  if (isPosted) return;
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
                  if (isPosted) return;
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
                  if (isPosted) return;
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
                  if (isPosted) return;
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
                  if (isPosted) return;
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
                  if (isPosted) return;
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
                  if (isPosted) return;
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
    if (_submitting != null) return;

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

    setState(() => _submitting = _OpeningBalanceSubmitting.save);
    try {
      final saved = await _service.save(businessId: widget.businessId, payload: payload);
      if (!mounted) return;
      setState(() => _document = saved);
      await _clearDraft();
      SnackBarHelper.show(
        context,
        message: 'ذخیره شد',
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      );
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: 'خطا در ذخیره: ${ErrorExtractor.forContext(e, context)}',
          backgroundColor: Theme.of(context).colorScheme.error,
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = null);
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
    if (_submitting != null) return;

    setState(() => _submitting = _OpeningBalanceSubmitting.finalize);
    try {
      final posted = await _service.post(businessId: widget.businessId);
      if (!mounted) return;
      setState(() => _document = posted);
      await _clearDraft();
      SnackBarHelper.show(
        context,
        message: 'تراز افتتاحیه نهایی شد',
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      );
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: 'خطا در نهایی‌سازی: ${ErrorExtractor.forContext(e, context)}',
          backgroundColor: Theme.of(context).colorScheme.error,
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = null);
    }
  }

  Future<void> _confirmUnpost() async {
    if (_submitting != null) return;

    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('لغو نهایی‌سازی تراز افتتاحیه'),
            content: const Text(
              'فقط در صورتی مجاز است که در همین سال مالی به‌جز سند افتتاحیه، سند حسابداری دیگری ثبت نشده باشد. '
              'در غیر این صورت پیام خطا از سامانه نشان داده می‌شود.\nآیا ادامه می‌دهید؟',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('خیر')),
              FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('بله')),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;

    setState(() => _submitting = _OpeningBalanceSubmitting.unpost);
    try {
      final fyIdRaw = _document?['fiscal_year_id'];
      final int? fiscalYearId =
          fyIdRaw is int ? fyIdRaw : (fyIdRaw is num ? fyIdRaw.toInt() : int.tryParse('$fyIdRaw'));
      final restored = await _service.unpost(
        businessId: widget.businessId,
        fiscalYearId: fiscalYearId,
      );
      if (!mounted) return;
      setState(() => _document = restored);
      SnackBarHelper.show(
        context,
        message: 'نهایی‌سازی تراز افتتاحیه لغو شد؛ اکنون می‌توانید ویرایش کنید.',
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      );
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: 'خطا در لغو نهایی‌سازی: ${ErrorExtractor.forContext(e, context)}',
          backgroundColor: Theme.of(context).colorScheme.error,
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = null);
    }
  }
}

/// ورودی تعداد و بهای واحد با کنترلر پایدار و جهت LTR (رفع مشکل تایپ برعکس در RTL).
class _OpeningBalanceInventoryQtyPriceFields extends StatefulWidget {
  final Map<String, dynamic> line;
  final bool enabled;
  final VoidCallback onModelChanged;

  const _OpeningBalanceInventoryQtyPriceFields({
    required this.line,
    required this.enabled,
    required this.onModelChanged,
  });

  @override
  State<_OpeningBalanceInventoryQtyPriceFields> createState() =>
      _OpeningBalanceInventoryQtyPriceFieldsState();
}

class _OpeningBalanceInventoryQtyPriceFieldsState extends State<_OpeningBalanceInventoryQtyPriceFields> {
  late final TextEditingController _quantityController;
  late final TextEditingController _costPriceController;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(
      text: formatNumberForInput(widget.line['quantity'] as double?, decimalPlaces: 2),
    );
    _costPriceController = TextEditingController(
      text: formatNumberForInput(widget.line['cost_price'] as double?, decimalPlaces: 2),
    );
  }

  @override
  void didUpdateWidget(covariant _OpeningBalanceInventoryQtyPriceFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.line, widget.line)) {
      _quantityController.text = formatNumberForInput(
        widget.line['quantity'] as double?,
        decimalPlaces: 2,
      );
      _costPriceController.text = formatNumberForInput(
        widget.line['cost_price'] as double?,
        decimalPlaces: 2,
      );
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _costPriceController.dispose();
    super.dispose();
  }

  void _onQuantityChanged(String v) {
    widget.line['quantity'] = parseFormattedDouble(v) ?? 0.0;
    widget.onModelChanged();
  }

  void _onCostChanged(String v) {
    widget.line['cost_price'] = parseFormattedDouble(v) ?? 0.0;
    widget.onModelChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _quantityController,
            enabled: widget.enabled,
            decoration: const InputDecoration(isDense: true, labelText: 'تعداد'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            inputFormatters: const [NumberInputFormatter(allowDecimal: true)],
            onChanged: _onQuantityChanged,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _costPriceController,
            enabled: widget.enabled,
            decoration: const InputDecoration(isDense: true, labelText: 'بهای واحد'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            inputFormatters: const [NumberInputFormatter(allowDecimal: true)],
            onChanged: _onCostChanged,
          ),
        ),
      ],
    );
  }
}

