import 'package:flutter/material.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/models/account_model.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/product_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/bank_account_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/cash_register_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/petty_cash_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/account_tree_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/check_combobox_widget.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/services/person_service.dart';
import 'package:hesabix_ui/services/product_service.dart';
import 'package:hesabix_ui/services/bank_account_service.dart';
import 'package:hesabix_ui/services/cash_register_service.dart';
import 'package:hesabix_ui/services/petty_cash_service.dart';
import 'package:hesabix_ui/services/account_service.dart';
import 'package:hesabix_ui/services/check_service.dart';
import 'package:hesabix_ui/services/warehouse_service.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class KardexPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final List<int>? initialPersonIds;
  const KardexPage({super.key, required this.businessId, required this.calendarController, this.initialPersonIds});

  @override
  State<KardexPage> createState() => _KardexPageState();
}

enum FilterType { person, product, bank, cash, petty, account, check }

class _KardexPageState extends State<KardexPage> {
  final GlobalKey _tableKey = GlobalKey();
  final GlobalKey _addFilterBtnKey = GlobalKey();
  void _log(String msg) {
    // ignore: avoid_print
    print('[KardexPage] ' + msg);
  }

  // Unified filter picker control
  FilterType? _activePicker;
  bool _manualApply = false;
  Timer? _applyDebounce;
  // Presets
  Map<String, Map<String, dynamic>> _presets = <String, Map<String, dynamic>>{};
  String? _selectedPresetName;

  // Simple filter inputs (initial version)
  DateTime? _fromDate;
  DateTime? _toDate;
  String _matchMode = 'any';
  String _resultScope = 'lines_matching';
  bool _includeRunningBalance = false;
  int? _selectedFiscalYearId;
  List<Map<String, dynamic>> _fiscalYears = const [];

  // Multi-select state
  final List<Person> _selectedPersons = [];
  final List<Map<String, dynamic>> _selectedProducts = [];
  final List<BankAccountOption> _selectedBankAccounts = [];
  final List<CashRegisterOption> _selectedCashRegisters = [];
  final List<PettyCashOption> _selectedPettyCash = [];
  final List<Account> _selectedAccounts = [];
  final List<CheckOption> _selectedChecks = [];
  final List<Map<String, dynamic>> _selectedWarehouses = [];
  // Initial filters from URL
  List<int> _initialPersonIds = const [];
  final PersonService _personService = PersonService();
  List<int> _initialProductIds = const [];
  List<int> _initialBankAccountIds = const [];
  List<int> _initialCashRegisterIds = const [];
  List<int> _initialPettyCashIds = const [];
  List<int> _initialAccountIds = const [];
  List<int> _initialCheckIds = const [];
  List<int> _initialWarehouseIds = const [];

  final ProductService _productService = ProductService();
  final BankAccountService _bankAccountService = BankAccountService();
  final CashRegisterService _cashRegisterService = CashRegisterService();
  final PettyCashService _pettyCashService = PettyCashService();
  final AccountService _accountService = AccountService();
  final CheckService _checkService = CheckService();
  final WarehouseService _warehouseService = WarehouseService();

  // Temp selections for pickers (to clear after add)
  Person? _personToAdd;
  Map<String, dynamic>? _productToAdd;
  BankAccountOption? _bankToAdd;
  CashRegisterOption? _cashToAdd;
  PettyCashOption? _pettyToAdd;
  Account? _accountToAdd;
  CheckOption? _checkToAdd;

  @override
  void dispose() {
    super.dispose();
  }

  void _refreshData() {
    _log('Manual refresh triggered. additionalParams=' + _additionalParams().toString());
    final state = _tableKey.currentState;
    if (state != null) {
      try {
        (state as dynamic).refresh();
        return;
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  void _scheduleApply() {
    if (_manualApply) return;
    _applyDebounce?.cancel();
    _applyDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _refreshData();
      _updateRouteQuery();
    });
  }

  void _updateRouteQuery() {
    try {
      final qp = <String, String>{};
      Map<String, dynamic> params = _additionalParams();
      List<int> idsOf(String key) => (params[key] as List<dynamic>? ?? const <dynamic>[]) 
          .map((e) => int.tryParse('$e'))
          .whereType<int>()
          .toList();

      void addCsv(String key, List<int> ids) {
        if (ids.isEmpty) return;
        qp[key] = ids.join(',');
      }

      addCsv('person_ids', idsOf('person_ids'));
      addCsv('product_ids', idsOf('product_ids'));
      addCsv('bank_account_ids', idsOf('bank_account_ids'));
      addCsv('cash_register_ids', idsOf('cash_register_ids'));
      addCsv('petty_cash_ids', idsOf('petty_cash_ids'));
      addCsv('account_ids', idsOf('account_ids'));
      addCsv('check_ids', idsOf('check_ids'));
      addCsv('warehouse_ids', idsOf('warehouse_ids'));
      if (params['from_date'] != null) qp['dateFrom'] = '${params['from_date']}';
      if (params['to_date'] != null) qp['dateTo'] = '${params['to_date']}';
      if (params['fiscal_year_id'] != null) qp['fiscal_year_id'] = '${params['fiscal_year_id']}';
      if ((params['match_mode'] ?? '').toString().isNotEmpty) qp['match_mode'] = '${params['match_mode']}';
      if ((params['result_scope'] ?? '').toString().isNotEmpty) qp['result_scope'] = '${params['result_scope']}';

      final path = '/business/${widget.businessId}/reports/kardex';
      final uri = Uri(path: path, queryParameters: qp.isEmpty ? null : qp);
      if (!mounted) return;
      context.go(uri.toString());
    } catch (_) {}
  }

  void _clearAllFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
      _selectedFiscalYearId = _selectedFiscalYearId; // نگه‌داشتن سال مالی انتخاب‌شده
      _matchMode = 'any';
      _resultScope = 'lines_matching';
      _includeRunningBalance = false;

      _selectedPersons.clear();
      _selectedProducts.clear();
      _selectedBankAccounts.clear();
      _selectedCashRegisters.clear();
      _selectedPettyCash.clear();
      _selectedAccounts.clear();
      _selectedChecks.clear();

      // همچنین fallback اولیه را خنثی می‌کنیم تا بعد از ریست از URL خوانده نشود
      _initialPersonIds = const [];
      _initialProductIds = const [];
      _initialBankAccountIds = const [];
      _initialCashRegisterIds = const [];
      _initialPettyCashIds = const [];
      _initialAccountIds = const [];
      _initialCheckIds = const [];
      _initialWarehouseIds = const [];
      _activePicker = null;
    });
    // اعمال فوری
    _refreshData();
    _updateRouteQuery();
  }

  String _presetsKey() => 'kardex_presets_${widget.businessId}';

  Future<void> _loadPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_presetsKey());
      if (raw != null && raw.isNotEmpty) {
        final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        final converted = <String, Map<String, dynamic>>{};
        for (final entry in map.entries) {
          converted[entry.key] = Map<String, dynamic>.from(entry.value as Map);
        }
        if (!mounted) return;
        setState(() {
          _presets = converted;
          if (_presets.isNotEmpty && _selectedPresetName == null) {
            _selectedPresetName = _presets.keys.first;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _savePreset(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final params = _additionalParams();
      final updated = Map<String, Map<String, dynamic>>.from(_presets);
      updated[name] = params;
      await prefs.setString(_presetsKey(), jsonEncode(updated));
      if (!mounted) return;
      setState(() {
        _presets = updated;
        _selectedPresetName = name;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('پریست ذخیره شد')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در ذخیره پریست: $e')));
    }
  }

  Future<void> _deletePreset(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final updated = Map<String, Map<String, dynamic>>.from(_presets);
      updated.remove(name);
      await prefs.setString(_presetsKey(), jsonEncode(updated));
      if (!mounted) return;
      setState(() {
        _presets = updated;
        if (_selectedPresetName == name) {
          _selectedPresetName = _presets.isNotEmpty ? _presets.keys.first : null;
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در حذف پریست: $e')));
    }
  }

  Future<void> _applyPreset(Map<String, dynamic> p) async {
    try {
      DateTime? parseDate(String? s) => (s == null || s.isEmpty) ? null : DateTime.tryParse(s);
      final from = parseDate(p['from_date']?.toString());
      final to = parseDate(p['to_date']?.toString());
      List<int> ids(String key) {
        final raw = (p[key] as List<dynamic>? ?? const <dynamic>[]);
        return raw.map((e) => int.tryParse('$e')).whereType<int>().toList();
      }
      setState(() {
        _fromDate = from;
        _toDate = to;
        _selectedFiscalYearId = (p['fiscal_year_id'] is int) ? p['fiscal_year_id'] as int : int.tryParse('${p['fiscal_year_id'] ?? ''}');
        _matchMode = (p['match_mode'] ?? 'any').toString();
        _resultScope = (p['result_scope'] ?? 'lines_matching').toString();
        _includeRunningBalance = (p['include_running_balance'] == true);

        _selectedPersons.clear();
        _selectedProducts.clear();
        _selectedBankAccounts.clear();
        _selectedCashRegisters.clear();
        _selectedPettyCash.clear();
        _selectedAccounts.clear();
        _selectedChecks.clear();

        _initialPersonIds = ids('person_ids');
        _initialProductIds = ids('product_ids');
        _initialBankAccountIds = ids('bank_account_ids');
        _initialCashRegisterIds = ids('cash_register_ids');
        _initialPettyCashIds = ids('petty_cash_ids');
        _initialAccountIds = ids('account_ids');
        _initialCheckIds = ids('check_ids');
        _initialWarehouseIds = ids('warehouse_ids');
      });

      if (_initialPersonIds.isNotEmpty) await _hydrateInitialPersons(_initialPersonIds);
      if (_initialProductIds.isNotEmpty) await _hydrateInitialProducts(_initialProductIds);
      if (_initialBankAccountIds.isNotEmpty) await _hydrateInitialBankAccounts(_initialBankAccountIds);
      if (_initialCashRegisterIds.isNotEmpty) await _hydrateInitialCashRegisters(_initialCashRegisterIds);
      if (_initialPettyCashIds.isNotEmpty) await _hydrateInitialPettyCash(_initialPettyCashIds);
      if (_initialAccountIds.isNotEmpty) await _hydrateInitialAccounts(_initialAccountIds);
      if (_initialCheckIds.isNotEmpty) await _hydrateInitialChecks(_initialCheckIds);
      if (_initialWarehouseIds.isNotEmpty) await _hydrateInitialWarehouses(_initialWarehouseIds);

      _updateRouteQuery();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در اعمال پریست: $e')));
    }
  }

  Map<String, dynamic> _additionalParams() {
    String? fmt(DateTime? d) => d == null ? null : d.toIso8601String().substring(0, 10);
    var personIds = _selectedPersons.map((p) => p.id).whereType<int>().toList();
    if (personIds.isEmpty && _initialPersonIds.isNotEmpty) {
      personIds = List<int>.from(_initialPersonIds);
    }
    var productIds = _selectedProducts.map((m) => m['id']).map((e) => int.tryParse('$e')).whereType<int>().toList();
    if (productIds.isEmpty && _initialProductIds.isNotEmpty) {
      productIds = List<int>.from(_initialProductIds);
    }
    var bankIds = _selectedBankAccounts.map((b) => int.tryParse(b.id)).whereType<int>().toList();
    if (bankIds.isEmpty && _initialBankAccountIds.isNotEmpty) {
      bankIds = List<int>.from(_initialBankAccountIds);
    }
    var cashIds = _selectedCashRegisters.map((c) => int.tryParse(c.id)).whereType<int>().toList();
    if (cashIds.isEmpty && _initialCashRegisterIds.isNotEmpty) {
      cashIds = List<int>.from(_initialCashRegisterIds);
    }
    var pettyIds = _selectedPettyCash.map((p) => int.tryParse(p.id)).whereType<int>().toList();
    if (pettyIds.isEmpty && _initialPettyCashIds.isNotEmpty) {
      pettyIds = List<int>.from(_initialPettyCashIds);
    }
    var accountIds = _selectedAccounts.map((a) => a.id).whereType<int>().toList();
    if (accountIds.isEmpty && _initialAccountIds.isNotEmpty) {
      accountIds = List<int>.from(_initialAccountIds);
    }
    var checkIds = _selectedChecks.map((c) => int.tryParse(c.id)).whereType<int>().toList();
    if (checkIds.isEmpty && _initialCheckIds.isNotEmpty) {
      checkIds = List<int>.from(_initialCheckIds);
    }
    var warehouseIds = _selectedWarehouses.map((w) => int.tryParse('${w['id']}')).whereType<int>().toList();
    if (warehouseIds.isEmpty && _initialWarehouseIds.isNotEmpty) {
      warehouseIds = List<int>.from(_initialWarehouseIds);
    }

    final params = {
      if (_fromDate != null) 'from_date': fmt(_fromDate),
      if (_toDate != null) 'to_date': fmt(_toDate),
      'person_ids': personIds,
      'product_ids': productIds,
      'bank_account_ids': bankIds,
      'cash_register_ids': cashIds,
      'petty_cash_ids': pettyIds,
      'account_ids': accountIds,
      'check_ids': checkIds,
      'warehouse_ids': warehouseIds,
      'match_mode': _matchMode,
      'result_scope': _resultScope,
      'include_running_balance': _includeRunningBalance,
      if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
    };
    _log('Built additionalParams=' + params.toString());
    return params;
  }

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/kardex/businesses/${widget.businessId}/lines',
      excelEndpoint: '/api/v1/kardex/businesses/${widget.businessId}/lines/export/excel',
      pdfEndpoint: '/api/v1/kardex/businesses/${widget.businessId}/lines/export/pdf',
      columns: [
        DateColumn('document_date', 'تاریخ سند',
            formatter: (item) => (item as Map<String, dynamic>)['document_date']?.toString()),
        TextColumn('document_code', 'کد سند',
            formatter: (item) => (item as Map<String, dynamic>)['document_code']?.toString()),
        TextColumn('document_type', 'نوع سند',
            formatter: (item) => (item as Map<String, dynamic>)['document_type']?.toString()),
        TextColumn('warehouse_name', 'انبار',
            formatter: (item) {
              final m = (item as Map<String, dynamic>);
              return (m['warehouse_name'] ?? m['warehouse_id'])?.toString();
            }),
        TextColumn('movement', 'جهت حرکت',
            formatter: (item) => (item as Map<String, dynamic>)['movement']?.toString()),
        TextColumn('description', 'شرح',
            formatter: (item) => (item as Map<String, dynamic>)['description']?.toString()),
        NumberColumn('debit', 'بدهکار',
            formatter: (item) => ((item as Map<String, dynamic>)['debit'])?.toString()),
        NumberColumn('credit', 'بستانکار',
            formatter: (item) => ((item as Map<String, dynamic>)['credit'])?.toString()),
        NumberColumn('quantity', 'تعداد',
            formatter: (item) => ((item as Map<String, dynamic>)['quantity'])?.toString()),
        NumberColumn('running_amount', 'مانده مبلغ',
            formatter: (item) => ((item as Map<String, dynamic>)['running_amount'])?.toString()),
        NumberColumn('running_quantity', 'مانده تعداد',
            formatter: (item) => ((item as Map<String, dynamic>)['running_quantity'])?.toString()),
      ],
      searchFields: const [],
      defaultPageSize: 20,
      additionalParams: _additionalParams(),
      showExportButtons: true,
      getExportParams: () => _additionalParams(),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadFiscalYears();
    _parseInitialQueryParams();
    _loadPresets();
    if (widget.initialPersonIds != null && widget.initialPersonIds!.isNotEmpty) {
      _initialPersonIds = List<int>.from(widget.initialPersonIds!);
    }
    _log('initState: initialPersonIds=' + _initialPersonIds.toString());
    if (_initialPersonIds.isNotEmpty) {
      _hydrateInitialPersons(_initialPersonIds);
    }
    if (_initialProductIds.isNotEmpty) {
      _hydrateInitialProducts(_initialProductIds);
    }
    if (_initialBankAccountIds.isNotEmpty) {
      _hydrateInitialBankAccounts(_initialBankAccountIds);
    }
    if (_initialCashRegisterIds.isNotEmpty) {
      _hydrateInitialCashRegisters(_initialCashRegisterIds);
    }
    if (_initialPettyCashIds.isNotEmpty) {
      _hydrateInitialPettyCash(_initialPettyCashIds);
    }
    if (_initialAccountIds.isNotEmpty) {
      _hydrateInitialAccounts(_initialAccountIds);
    }
    if (_initialCheckIds.isNotEmpty) {
      _hydrateInitialChecks(_initialCheckIds);
    }
  }

  Future<void> _hydrateInitialPersons(List<int> ids) async {
    try {
      final added = <int>{ for (final p in _selectedPersons) if (p.id != null) p.id! };
      for (final id in ids) {
        if (added.contains(id)) continue;
        final person = await _personService.getPerson(id);
        if (!mounted) return;
        setState(() {
          _selectedPersons.add(person);
        });
      }
      _log('Hydrated selected persons from ids=' + ids.toString());
      // بعد از نمایش چیپ‌ها، رفرش کن تا پارامترهای انتخابی همواره ارسال شوند
      _refreshData();
    } catch (e) {
      _log('Failed to hydrate persons: ' + e.toString());
    }
  }

  Future<void> _hydrateInitialProducts(List<int> ids) async {
    try {
      final added = <int>{ for (final m in _selectedProducts) int.tryParse('${m['id']}') ?? -1 };
      for (final id in ids) {
        if (added.contains(id)) continue;
        try {
          final m = await _productService.getProduct(businessId: widget.businessId, productId: id);
          if (!mounted) return;
          setState(() {
            _selectedProducts.add(<String, dynamic>{
              'id': m['id'],
              'code': m['code'],
              'name': m['name'],
            });
          });
        } catch (_) {}
      }
      _refreshData();
    } catch (_) {}
  }

  Future<void> _hydrateInitialBankAccounts(List<int> ids) async {
    try {
      final added = <int>{ for (final it in _selectedBankAccounts) int.tryParse(it.id) ?? -1 };
      for (final id in ids) {
        if (added.contains(id)) continue;
        try {
          final acc = await _bankAccountService.getById(id);
          if (!mounted) return;
          setState(() {
            _selectedBankAccounts.add(BankAccountOption('${acc.id}', acc.name, currencyId: acc.currencyId));
          });
        } catch (_) {}
      }
      _refreshData();
    } catch (_) {}
  }

  Future<void> _hydrateInitialCashRegisters(List<int> ids) async {
    try {
      final added = <int>{ for (final it in _selectedCashRegisters) int.tryParse(it.id) ?? -1 };
      for (final id in ids) {
        if (added.contains(id)) continue;
        try {
          final cr = await _cashRegisterService.getById(id);
          if (!mounted) return;
          setState(() {
            _selectedCashRegisters.add(CashRegisterOption('${cr.id}', cr.name, currencyId: cr.currencyId));
          });
        } catch (_) {}
      }
      _refreshData();
    } catch (_) {}
  }

  Future<void> _hydrateInitialPettyCash(List<int> ids) async {
    try {
      final added = <int>{ for (final it in _selectedPettyCash) int.tryParse(it.id) ?? -1 };
      for (final id in ids) {
        if (added.contains(id)) continue;
        try {
          final pc = await _pettyCashService.getById(id);
          if (!mounted) return;
          setState(() {
            _selectedPettyCash.add(PettyCashOption('${pc.id}', pc.name, currencyId: pc.currencyId));
          });
        } catch (_) {}
      }
      _refreshData();
    } catch (_) {}
  }

  Future<void> _hydrateInitialAccounts(List<int> ids) async {
    try {
      final added = <int>{ for (final it in _selectedAccounts) it.id ?? -1 };
      for (final id in ids) {
        if (added.contains(id)) continue;
        try {
          final m = await _accountService.getAccount(businessId: widget.businessId, accountId: id);
          if (!mounted) return;
          setState(() {
            _selectedAccounts.add(Account.fromJson(m));
          });
        } catch (_) {}
      }
      _refreshData();
    } catch (_) {}
  }

  Future<void> _hydrateInitialChecks(List<int> ids) async {
    try {
      final added = <int>{ for (final it in _selectedChecks) int.tryParse(it.id) ?? -1 };
      for (final id in ids) {
        if (added.contains(id)) continue;
        try {
          final m = await _checkService.getById(id);
          if (!mounted) return;
          final checkNumber = (m['check_number'] ?? '').toString();
          final personName = (m['person_name'] ?? m['holder_name'])?.toString();
          final bankName = (m['bank_name'] ?? '').toString();
          final sayad = (m['sayad_code'] ?? '').toString();
          setState(() {
            _selectedChecks.add(CheckOption(
              id: '$id',
              number: checkNumber,
              personName: personName,
              bankName: bankName,
              sayadCode: sayad,
            ));
          });
        } catch (_) {}
      }
      _refreshData();
    } catch (_) {}
  }

  Future<void> _hydrateInitialWarehouses(List<int> ids) async {
    try {
      final added = <int>{ for (final it in _selectedWarehouses) int.tryParse('${it['id']}') ?? -1 };
      for (final id in ids) {
        if (added.contains(id)) continue;
        try {
          final w = await _warehouseService.getWarehouse(businessId: widget.businessId, warehouseId: id);
          if (!mounted) return;
          setState(() {
            _selectedWarehouses.add(<String, dynamic>{
              'id': w.id,
              'name': w.name,
              'code': w.code,
            });
          });
        } catch (_) {}
      }
      _refreshData();
    } catch (_) {}
  }
  void _parseInitialQueryParams() {
    try {
      final uri = Uri.base;
      _log('Parsing query params: ' + uri.toString());
      List<int> _parseIds(String singularKey, String pluralKey) {
        final out = <int>{};
        final repeated = uri.queryParametersAll[singularKey] ?? const <String>[];
        for (final v in repeated) {
          final p = int.tryParse(v);
          if (p != null) out.add(p);
        }
        final csv = uri.queryParameters[pluralKey];
        if (csv != null && csv.trim().isNotEmpty) {
          for (final part in csv.split(',')) {
            final p = int.tryParse(part.trim());
            if (p != null) out.add(p);
          }
        }
        return out.toList();
      }

      _initialPersonIds = _parseIds('person_id', 'person_ids');
      _initialProductIds = _parseIds('product_id', 'product_ids');
      _initialBankAccountIds = _parseIds('bank_account_id', 'bank_account_ids');
      _initialCashRegisterIds = _parseIds('cash_register_id', 'cash_register_ids');
      _initialPettyCashIds = _parseIds('petty_cash_id', 'petty_cash_ids');
      _initialAccountIds = _parseIds('account_id', 'account_ids');
      _initialCheckIds = _parseIds('check_id', 'check_ids');
      _initialWarehouseIds = _parseIds('warehouse_id', 'warehouse_ids');

      _log('Parsed initial ids | person=' + _initialPersonIds.toString() + ' product=' + _initialProductIds.toString() + ' bank=' + _initialBankAccountIds.toString() + ' cash=' + _initialCashRegisterIds.toString() + ' petty=' + _initialPettyCashIds.toString() + ' account=' + _initialAccountIds.toString() + ' check=' + _initialCheckIds.toString() + ' warehouse=' + _initialWarehouseIds.toString());
    } catch (_) {}
  }

  Future<void> _loadFiscalYears() async {
    try {
      final svc = BusinessDashboardService(ApiClient());
      final items = await svc.listFiscalYears(widget.businessId);
      if (!mounted) return;
      setState(() {
        _fiscalYears = items;
        final current = items.firstWhere(
          (e) => (e['is_current'] == true),
          orElse: () => const <String, dynamic>{},
        );
        final id = current['id'];
        if (id is int) {
          _selectedFiscalYearId = id;
        }
      });
    } catch (_) {
      // ignore errors; dropdown remains empty
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFilters(t),
              const SizedBox(height: 8),
              _buildTableArea(t),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(AppLocalizations t) {
    return Card(
      margin: const EdgeInsets.all(0),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Add filter button
          ElevatedButton.icon(
            key: _addFilterBtnKey,
            onPressed: () async {
              RelativeRect position = const RelativeRect.fromLTRB(100, 100, 0, 0);
              try {
                final RenderBox button = _addFilterBtnKey.currentContext!.findRenderObject() as RenderBox;
                final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
                position = RelativeRect.fromRect(
                  Rect.fromPoints(
                    button.localToGlobal(Offset.zero, ancestor: overlay),
                    button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
                  ),
                  Offset.zero & overlay.size,
                );
              } catch (_) {}
              final picked = await showMenu<FilterType>(
                context: context,
                position: position,
                items: [
                  PopupMenuItem(value: FilterType.person, child: Text('افزودن فیلتر: اشخاص')),
                  PopupMenuItem(value: FilterType.product, child: Text('افزودن فیلتر: کالا/خدمت')),
                  PopupMenuItem(value: FilterType.bank, child: Text('افزودن فیلتر: بانک')),
                  PopupMenuItem(value: FilterType.cash, child: Text('افزودن فیلتر: صندوق')),
                  PopupMenuItem(value: FilterType.petty, child: Text('افزودن فیلتر: تنخواه')),
                  PopupMenuItem(value: FilterType.account, child: Text('افزودن فیلتر: حساب دفتری')),
                  PopupMenuItem(value: FilterType.check, child: Text('افزودن فیلتر: چک')),
                ],
              );
              if (picked != null && mounted) setState(() => _activePicker = picked);
            },
            icon: const Icon(Icons.add),
            label: const Text('افزودن فیلتر'),
          ),
          TextButton.icon(
            onPressed: _clearAllFilters,
            icon: const Icon(Icons.refresh),
            label: const Text('بازنشانی'),
          ),

          // Presets controls
          if (_presets.isNotEmpty)
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                value: _selectedPresetName,
                items: _presets.keys
                    .map((name) => DropdownMenuItem<String>(value: name, child: Text(name)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedPresetName = v),
                decoration: const InputDecoration(
                  labelText: 'پریست‌ها',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          if (_presets.isNotEmpty)
            ElevatedButton.icon(
              onPressed: (_selectedPresetName != null)
                  ? () => _applyPreset(_presets[_selectedPresetName] ?? const <String, dynamic>{})
                  : null,
              icon: const Icon(Icons.playlist_add_check),
              label: const Text('اعمال پریست'),
            ),
          if (_presets.isNotEmpty)
            IconButton(
              onPressed: (_selectedPresetName != null)
                  ? () => _deletePreset(_selectedPresetName!)
                  : null,
              tooltip: 'حذف پریست انتخاب‌شده',
              icon: const Icon(Icons.delete_outline),
            ),
          TextButton.icon(
            onPressed: () async {
              final controller = TextEditingController();
              final name = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('ذخیره پریست'),
                  content: TextField(
                    controller: controller,
                    decoration: const InputDecoration(hintText: 'نام پریست را وارد کنید'),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
                    ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('ذخیره')),
                  ],
                ),
              );
              if (name != null && name.isNotEmpty) {
                await _savePreset(name);
              }
            },
            icon: const Icon(Icons.save_alt),
            label: const Text('ذخیره پریست'),
          ),

          SizedBox(
            width: 200,
            child: DateInputField(
              labelText: 'از تاریخ',
              value: _fromDate,
              onChanged: (d) {
                setState(() => _fromDate = d);
                _scheduleApply();
              },
              calendarController: widget.calendarController,
            ),
          ),
          SizedBox(
            width: 200,
            child: DateInputField(
              labelText: 'تا تاریخ',
              value: _toDate,
              onChanged: (d) {
                setState(() => _toDate = d);
                _scheduleApply();
              },
              calendarController: widget.calendarController,
            ),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<int>(
              value: _selectedFiscalYearId,
              decoration: const InputDecoration(
                labelText: 'سال مالی',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _fiscalYears.map<DropdownMenuItem<int>>((fy) {
                final id = fy['id'] as int?;
                final title = (fy['title'] ?? '').toString();
                return DropdownMenuItem<int>(
                  value: id,
                  child: Text(title.isNotEmpty ? title : 'FY ${id ?? ''}'),
                );
              }).toList(),
              onChanged: (val) {
                setState(() => _selectedFiscalYearId = val);
                _scheduleApply();
              },
            ),
          ),
          _chipsSection(
            label: 'اشخاص',
            chips: _selectedPersons.map((p) => _ChipData(id: p.id!, label: p.displayName)).toList(),
            onRemove: (id) {
              setState(() => _selectedPersons.removeWhere((p) => p.id == id));
              _scheduleApply();
            },
            picker: _activePicker == FilterType.person ? SizedBox(
              width: 260,
              child: PersonComboboxWidget(
                businessId: widget.businessId,
                selectedPerson: _personToAdd,
                onChanged: (person) {
                  if (person == null) return;
                  final exists = _selectedPersons.any((p) => p.id == person.id);
                  setState(() {
                    if (!exists) _selectedPersons.add(person);
                    _personToAdd = null;
                    _activePicker = null;
                  });
                  _scheduleApply();
                },
                hintText: 'افزودن شخص',
              ),
            ) : const SizedBox.shrink(),
            type: FilterType.person,
          ),
          _chipsSection(
            label: 'کالا/خدمت',
            chips: _selectedProducts.map((m) {
              final id = int.tryParse('${m['id']}') ?? 0;
              final code = (m['code'] ?? '').toString();
              final name = (m['name'] ?? '').toString();
              return _ChipData(id: id, label: code.isNotEmpty ? '$code - $name' : name);
            }).toList(),
            onRemove: (id) {
              setState(() => _selectedProducts.removeWhere((m) => int.tryParse('${m['id']}') == id));
              _scheduleApply();
            },
            picker: _activePicker == FilterType.product ? SizedBox(
              width: 260,
              child: ProductComboboxWidget(
                businessId: widget.businessId,
                selectedProduct: _productToAdd,
                onChanged: (prod) {
                  if (prod == null) return;
                  final pid = int.tryParse('${prod['id']}');
                  final exists = _selectedProducts.any((m) => int.tryParse('${m['id']}') == pid);
                  setState(() {
                    if (!exists) _selectedProducts.add(prod);
                    _productToAdd = null;
                    _activePicker = null;
                  });
                  _scheduleApply();
                },
              ),
            ) : const SizedBox.shrink(),
            type: FilterType.product,
          ),
          _chipsSection(
            label: 'بانک',
            chips: _selectedBankAccounts.map((b) => _ChipData(id: int.tryParse(b.id) ?? 0, label: b.name)).toList(),
            onRemove: (id) {
              setState(() => _selectedBankAccounts.removeWhere((b) => int.tryParse(b.id) == id));
              _scheduleApply();
            },
            picker: _activePicker == FilterType.bank ? SizedBox(
              width: 260,
              child: BankAccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccountId: _bankToAdd?.id,
                onChanged: (opt) {
                  if (opt == null) return;
                  final exists = _selectedBankAccounts.any((b) => b.id == opt.id);
                  setState(() {
                    if (!exists) _selectedBankAccounts.add(opt);
                    _bankToAdd = null;
                    _activePicker = null;
                  });
                  _scheduleApply();
                },
                hintText: 'افزودن حساب بانکی',
              ),
            ) : const SizedBox.shrink(),
            type: FilterType.bank,
          ),
          _chipsSection(
            label: 'صندوق',
            chips: _selectedCashRegisters.map((c) => _ChipData(id: int.tryParse(c.id) ?? 0, label: c.name)).toList(),
            onRemove: (id) {
              setState(() => _selectedCashRegisters.removeWhere((c) => int.tryParse(c.id) == id));
              _scheduleApply();
            },
            picker: _activePicker == FilterType.cash ? SizedBox(
              width: 260,
              child: CashRegisterComboboxWidget(
                businessId: widget.businessId,
                selectedRegisterId: _cashToAdd?.id,
                onChanged: (opt) {
                  if (opt == null) return;
                  final exists = _selectedCashRegisters.any((c) => c.id == opt.id);
                  setState(() {
                    if (!exists) _selectedCashRegisters.add(opt);
                    _cashToAdd = null;
                    _activePicker = null;
                  });
                  _scheduleApply();
                },
                hintText: 'افزودن صندوق',
              ),
            ) : const SizedBox.shrink(),
            type: FilterType.cash,
          ),
          _chipsSection(
            label: 'تنخواه',
            chips: _selectedPettyCash.map((p) => _ChipData(id: int.tryParse(p.id) ?? 0, label: p.name)).toList(),
            onRemove: (id) {
              setState(() => _selectedPettyCash.removeWhere((p) => int.tryParse(p.id) == id));
              _scheduleApply();
            },
            picker: _activePicker == FilterType.petty ? SizedBox(
              width: 260,
              child: PettyCashComboboxWidget(
                businessId: widget.businessId,
                selectedPettyCashId: _pettyToAdd?.id,
                onChanged: (opt) {
                  if (opt == null) return;
                  final exists = _selectedPettyCash.any((p) => p.id == opt.id);
                  setState(() {
                    if (!exists) _selectedPettyCash.add(opt);
                    _pettyToAdd = null;
                    _activePicker = null;
                  });
                  _scheduleApply();
                },
                hintText: 'افزودن تنخواه',
              ),
            ) : const SizedBox.shrink(),
            type: FilterType.petty,
          ),
          _chipsSection(
            label: 'حساب دفتری',
            chips: _selectedAccounts.map((a) => _ChipData(id: a.id!, label: '${a.code} - ${a.name}')).toList(),
            onRemove: (id) {
              setState(() => _selectedAccounts.removeWhere((a) => a.id == id));
              _scheduleApply();
            },
            picker: _activePicker == FilterType.account ? SizedBox(
              width: 260,
              child: AccountTreeComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: _accountToAdd,
                onChanged: (acc) {
                  if (acc == null) return;
                  final exists = _selectedAccounts.any((a) => a.id == acc.id);
                  setState(() {
                    if (!exists) _selectedAccounts.add(acc);
                    _accountToAdd = null;
                    _activePicker = null;
                  });
                  _scheduleApply();
                },
                hintText: 'افزودن حساب',
              ),
            ) : const SizedBox.shrink(),
            type: FilterType.account,
          ),
          _chipsSection(
            label: 'چک',
            chips: _selectedChecks.map((c) => _ChipData(id: int.tryParse(c.id) ?? 0, label: c.number.isNotEmpty ? c.number : 'چک #${c.id}')).toList(),
            onRemove: (id) {
              setState(() => _selectedChecks.removeWhere((c) => int.tryParse(c.id) == id));
              _scheduleApply();
            },
            picker: _activePicker == FilterType.check ? SizedBox(
              width: 260,
              child: CheckComboboxWidget(
                businessId: widget.businessId,
                selectedCheckId: _checkToAdd?.id,
                onChanged: (opt) {
                  if (opt == null) return;
                  final exists = _selectedChecks.any((c) => c.id == opt.id);
                  setState(() {
                    if (!exists) _selectedChecks.add(opt);
                    _checkToAdd = null;
                    _activePicker = null;
                  });
                  _scheduleApply();
                },
              ),
            ) : const SizedBox.shrink(),
            type: FilterType.check,
          ),
          _chipsSection(
            label: 'انبار',
            chips: _selectedWarehouses.map((w) {
              final id = int.tryParse('${w['id']}') ?? 0;
              final code = (w['code'] ?? '').toString();
              final name = (w['name'] ?? '').toString();
              return _ChipData(id: id, label: code.isNotEmpty ? '$code - $name' : name);
            }).toList(),
            onRemove: (id) {
              setState(() => _selectedWarehouses.removeWhere((w) => int.tryParse('${w['id']}') == id));
              _scheduleApply();
            },
            picker: _activePicker == null ? const SizedBox.shrink() : const SizedBox.shrink(),
          ),
          DropdownButton<String>(
            value: _matchMode,
            onChanged: (v) {
              setState(() => _matchMode = v ?? 'any');
              _scheduleApply();
            },
            items: const [
              DropdownMenuItem(value: 'any', child: Text('هرکدام')),
              DropdownMenuItem(value: 'same_line', child: Text('هم‌زمان در یک خط')),
              DropdownMenuItem(value: 'document_and', child: Text('هم‌زمان در یک سند')),
            ],
          ),
          DropdownButton<String>(
            value: _resultScope,
            onChanged: (v) {
              setState(() => _resultScope = v ?? 'lines_matching');
              _scheduleApply();
            },
            items: const [
              DropdownMenuItem(value: 'lines_matching', child: Text('فقط خطوط منطبق')),
              DropdownMenuItem(value: 'lines_of_document', child: Text('کل خطوط سند')),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(value: _includeRunningBalance, onChanged: (v) {
                setState(() => _includeRunningBalance = v);
                _scheduleApply();
              }),
              const SizedBox(width: 6),
              const Text('مانده تجمعی'),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(value: _manualApply, onChanged: (v) => setState(() => _manualApply = v)),
              const SizedBox(width: 6),
              const Text('اعمال دستی'),
            ],
          ),
          ElevatedButton.icon(
            onPressed: () {
              _refreshData();
              _updateRouteQuery();
            },
            icon: const Icon(Icons.search),
            label: const Text('اعمال فیلتر'),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildTableArea(AppLocalizations t) {
    final screenH = MediaQuery.of(context).size.height;
    // حداقل ارتفاع مناسب برای جدول؛ اگر فضا کمتر بود، صفحه اسکرول می‌خورد
    final tableHeight = screenH - 280.0; // تقریبی با احتساب فیلترها و پدینگ
    final effectiveHeight = tableHeight < 420 ? 420.0 : tableHeight;
    _log('Building table area with height=' + effectiveHeight.toString());
    return SizedBox(
      height: effectiveHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        child: DataTableWidget<Map<String, dynamic>>(
          key: _tableKey,
          config: _buildTableConfig(t),
          fromJson: (json) => Map<String, dynamic>.from(json as Map),
          calendarController: widget.calendarController,
        ),
      ),
    );
  }

  // Chips helpers
  Widget _chipsSection({
    required String label,
    required List<_ChipData> chips,
    required void Function(int id) onRemove,
    required Widget picker,
    FilterType? type,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(label, textAlign: TextAlign.right),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _chips(items: chips, onRemove: onRemove, type: type),
                picker,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chips({
    required List<_ChipData> items,
    required void Function(int id) onRemove,
    FilterType? type,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    const int maxToShow = 5;
    final List<_ChipData> visible = (items.length > maxToShow)
        ? items.sublist(0, maxToShow - 1)
        : items;
    final int remaining = items.length - visible.length;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ...visible.map((it) => InputChip(
              label: Text(it.label),
              onDeleted: () => onRemove(it.id),
              onPressed: () {
                if (type != null) setState(() => _activePicker = type);
              },
            )),
        if (remaining > 0)
          InputChip(
            label: Text('+$remaining مورد دیگر'),
            onPressed: () {
              if (type != null) setState(() => _activePicker = type);
            },
          ),
      ],
    );
  }

}

class _ChipData {
  final int id;
  final String label;
  _ChipData({required this.id, required this.label});
}

// _DateBox حذف شد و با DateInputField جایگزین شد


