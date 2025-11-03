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

class KardexPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  const KardexPage({super.key, required this.businessId, required this.calendarController});

  @override
  State<KardexPage> createState() => _KardexPageState();
}

class _KardexPageState extends State<KardexPage> {
  final GlobalKey _tableKey = GlobalKey();

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
  // Initial filters from URL
  List<int> _initialPersonIds = const [];

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
    final state = _tableKey.currentState;
    if (state != null) {
      try {
        (state as dynamic).refresh();
        return;
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Map<String, dynamic> _additionalParams() {
    String? fmt(DateTime? d) => d == null ? null : d.toIso8601String().substring(0, 10);
    var personIds = _selectedPersons.map((p) => p.id).whereType<int>().toList();
    if (personIds.isEmpty && _initialPersonIds.isNotEmpty) {
      personIds = List<int>.from(_initialPersonIds);
    }
    final productIds = _selectedProducts.map((m) => m['id']).map((e) => int.tryParse('$e')).whereType<int>().toList();
    final bankIds = _selectedBankAccounts.map((b) => int.tryParse(b.id)).whereType<int>().toList();
    final cashIds = _selectedCashRegisters.map((c) => int.tryParse(c.id)).whereType<int>().toList();
    final pettyIds = _selectedPettyCash.map((p) => int.tryParse(p.id)).whereType<int>().toList();
    final accountIds = _selectedAccounts.map((a) => a.id).whereType<int>().toList();
    final checkIds = _selectedChecks.map((c) => int.tryParse(c.id)).whereType<int>().toList();

    return {
      if (_fromDate != null) 'from_date': fmt(_fromDate),
      if (_toDate != null) 'to_date': fmt(_toDate),
      'person_ids': personIds,
      'product_ids': productIds,
      'bank_account_ids': bankIds,
      'cash_register_ids': cashIds,
      'petty_cash_ids': pettyIds,
      'account_ids': accountIds,
      'check_ids': checkIds,
      'match_mode': _matchMode,
      'result_scope': _resultScope,
      'include_running_balance': _includeRunningBalance,
      if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
    };
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
  }

  void _parseInitialQueryParams() {
    try {
      final uri = Uri.base;
      final single = int.tryParse(uri.queryParameters['person_id'] ?? '');
      final multi = uri.queryParametersAll['person_id']?.map((e) => int.tryParse(e)).whereType<int>().toList() ?? const <int>[];
      final s = <int>{};
      if (single != null) s.add(single);
      s.addAll(multi);
      // در initState مقدار را مستقیم ست می‌کنیم تا اولین build همان فیلتر را ارسال کند
      _initialPersonIds = s.toList();
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
          SizedBox(
            width: 200,
            child: DateInputField(
              labelText: 'از تاریخ',
              value: _fromDate,
              onChanged: (d) => setState(() => _fromDate = d),
              calendarController: widget.calendarController,
            ),
          ),
          SizedBox(
            width: 200,
            child: DateInputField(
              labelText: 'تا تاریخ',
              value: _toDate,
              onChanged: (d) => setState(() => _toDate = d),
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
                _refreshData();
              },
            ),
          ),
          _chipsSection(
            label: 'اشخاص',
            chips: _selectedPersons.map((p) => _ChipData(id: p.id!, label: p.displayName)).toList(),
            onRemove: (id) {
              setState(() => _selectedPersons.removeWhere((p) => p.id == id));
            },
            picker: SizedBox(
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
                  });
                  _refreshData();
                },
                hintText: 'افزودن شخص',
              ),
            ),
          ),
          _chipsSection(
            label: 'کالا/خدمت',
            chips: _selectedProducts.map((m) {
              final id = int.tryParse('${m['id']}') ?? 0;
              final code = (m['code'] ?? '').toString();
              final name = (m['name'] ?? '').toString();
              return _ChipData(id: id, label: code.isNotEmpty ? '$code - $name' : name);
            }).toList(),
            onRemove: (id) => setState(() => _selectedProducts.removeWhere((m) => int.tryParse('${m['id']}') == id)),
            picker: SizedBox(
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
                  });
                  _refreshData();
                },
              ),
            ),
          ),
          _chipsSection(
            label: 'بانک',
            chips: _selectedBankAccounts.map((b) => _ChipData(id: int.tryParse(b.id) ?? 0, label: b.name)).toList(),
            onRemove: (id) => setState(() => _selectedBankAccounts.removeWhere((b) => int.tryParse(b.id) == id)),
            picker: SizedBox(
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
                  });
                  _refreshData();
                },
                hintText: 'افزودن حساب بانکی',
              ),
            ),
          ),
          _chipsSection(
            label: 'صندوق',
            chips: _selectedCashRegisters.map((c) => _ChipData(id: int.tryParse(c.id) ?? 0, label: c.name)).toList(),
            onRemove: (id) => setState(() => _selectedCashRegisters.removeWhere((c) => int.tryParse(c.id) == id)),
            picker: SizedBox(
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
                  });
                  _refreshData();
                },
                hintText: 'افزودن صندوق',
              ),
            ),
          ),
          _chipsSection(
            label: 'تنخواه',
            chips: _selectedPettyCash.map((p) => _ChipData(id: int.tryParse(p.id) ?? 0, label: p.name)).toList(),
            onRemove: (id) => setState(() => _selectedPettyCash.removeWhere((p) => int.tryParse(p.id) == id)),
            picker: SizedBox(
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
                  });
                  _refreshData();
                },
                hintText: 'افزودن تنخواه',
              ),
            ),
          ),
          _chipsSection(
            label: 'حساب دفتری',
            chips: _selectedAccounts.map((a) => _ChipData(id: a.id!, label: '${a.code} - ${a.name}')).toList(),
            onRemove: (id) => setState(() => _selectedAccounts.removeWhere((a) => a.id == id)),
            picker: SizedBox(
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
                  });
                  _refreshData();
                },
                hintText: 'افزودن حساب',
              ),
            ),
          ),
          _chipsSection(
            label: 'چک',
            chips: _selectedChecks.map((c) => _ChipData(id: int.tryParse(c.id) ?? 0, label: c.number.isNotEmpty ? c.number : 'چک #${c.id}')).toList(),
            onRemove: (id) => setState(() => _selectedChecks.removeWhere((c) => int.tryParse(c.id) == id)),
            picker: SizedBox(
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
                  });
                  _refreshData();
                },
              ),
            ),
          ),
          DropdownButton<String>(
            value: _matchMode,
            onChanged: (v) => setState(() => _matchMode = v ?? 'any'),
            items: const [
              DropdownMenuItem(value: 'any', child: Text('هرکدام')),
              DropdownMenuItem(value: 'same_line', child: Text('هم‌زمان در یک خط')),
              DropdownMenuItem(value: 'document_and', child: Text('هم‌زمان در یک سند')),
            ],
          ),
          DropdownButton<String>(
            value: _resultScope,
            onChanged: (v) => setState(() => _resultScope = v ?? 'lines_matching'),
            items: const [
              DropdownMenuItem(value: 'lines_matching', child: Text('فقط خطوط منطبق')),
              DropdownMenuItem(value: 'lines_of_document', child: Text('کل خطوط سند')),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(value: _includeRunningBalance, onChanged: (v) => setState(() => _includeRunningBalance = v)),
              const SizedBox(width: 6),
              const Text('مانده تجمعی'),
            ],
          ),
          ElevatedButton.icon(
            onPressed: _refreshData,
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
                _chips(items: chips, onRemove: onRemove),
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
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: items
          .map((it) => Chip(
                label: Text(it.label),
                onDeleted: () => onRemove(it.id),
              ))
          .toList(),
    );
  }

}

class _ChipData {
  final int id;
  final String label;
  _ChipData({required this.id, required this.label});
}

// _DateBox حذف شد و با DateInputField جایگزین شد


