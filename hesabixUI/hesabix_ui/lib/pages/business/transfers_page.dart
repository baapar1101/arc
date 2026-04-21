import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../core/api_client.dart';
import '../../models/transfer_document.dart';
import '../../services/transfer_service.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../core/date_utils.dart' show HesabixDateUtils;
import '../../utils/number_formatters.dart' show formatWithThousands;
import '../../widgets/date_input_field.dart';
import '../../widgets/transfer/transfer_form_dialog.dart';
import '../../widgets/transfer/transfer_details_dialog.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../services/business_dashboard_service.dart';
import '../../widgets/project/project_selector_widget.dart';
import '../../widgets/invoice/bank_account_combobox_widget.dart';
import '../../widgets/invoice/cash_register_combobox_widget.dart';
import '../../widgets/invoice/petty_cash_combobox_widget.dart';

class TransfersPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;
  final ApiClient apiClient;

  const TransfersPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
    required this.apiClient,
  });

  @override
  State<TransfersPage> createState() => _TransfersPageState();
  
  /// Static map to store page states by business ID for external refresh
  static final Map<int, _TransfersPageState> _pageStates = {};
  
  /// Get the page state for a specific business ID
  static _TransfersPageState? getPageState(int businessId) {
    return _pageStates[businessId];
  }
  
  /// Clear the page state for a specific business ID
  static void clearPageState(int businessId) {
    _pageStates.remove(businessId);
  }
}

class _TransfersPageState extends State<TransfersPage> {
  // کنترل جدول برای دسترسی به refresh
  final GlobalKey _tableKey = GlobalKey();
  late final BusinessDashboardService _dashboardService =
      BusinessDashboardService(widget.apiClient);

  DateTime? _fromDate;
  DateTime? _toDate;

  int? _selectedFiscalYearId;
  List<Map<String, dynamic>> _fiscalYears = [];
  bool _fiscalYearsResolved = false;

  int? _selectedProjectId;
  BankAccountOption? _filterBankAccount;
  CashRegisterOption? _filterCashRegister;
  PettyCashOption? _filterPettyCash;
  bool _showDesktopFilters = false;

  List<FilterOption> _projectFilterOptions = [];

  @override
  void initState() {
    super.initState();
    // Register this page instance for external refresh access
    TransfersPage._pageStates[widget.businessId] = this;
    _loadProjects();
    _loadFiscalYears();
  }

  Future<void> _loadFiscalYears() async {
    try {
      final items = await _dashboardService.listFiscalYears(widget.businessId);
      if (!mounted) return;
      setState(() {
        _fiscalYears = items;
        if (_selectedFiscalYearId == null && _fiscalYears.isNotEmpty) {
          final current = _fiscalYears.firstWhere(
            (fy) => fy['is_current'] == true,
            orElse: () => _fiscalYears.first,
          );
          _selectedFiscalYearId = current['id'] as int?;
        }
        _fiscalYearsResolved = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _fiscalYearsResolved = true);
      }
    }
  }
  
  @override
  void dispose() {
    // Clean up the page state when disposed
    TransfersPage._pageStates.remove(widget.businessId);
    super.dispose();
  }

  /// بارگذاری لیست پروژه‌ها برای فیلتر
  Future<void> _loadProjects() async {
    if (!mounted) return;
    try {
      final response = await widget.apiClient.post(
        '/businesses/${widget.businessId}/projects/search',
        data: {
          'take': 1000,
          'skip': 0,
          'is_active': true,
        },
      );
      
      if (response.data['success'] == true) {
        final List<dynamic> projects = response.data['data']['items'] ?? [];
        if (mounted) {
          setState(() {
            _projectFilterOptions = projects.map((p) => FilterOption(
              value: p['id'].toString(),
              label: p['name'] ?? 'پروژه ${p['id']}',
              description: p['code'],
            )).toList();
          });
        }
      }
    } catch (e) {
      debugPrint('خطا در بارگذاری پروژه‌ها: $e');
    }
  }

  void _refreshData() {
    final state = _tableKey.currentState;
    if (state != null) {
      try {
        // ignore: avoid_dynamic_calls
        (state as dynamic).refresh();
        return;
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }
  
  /// Public method to refresh the data table
  void refresh() {
    _refreshData();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final contentPadding = ResponsiveHelper.getPadding(context);
    final isMobile = ResponsiveHelper.isMobile(context);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(t, isMobile),
              _buildFilters(t, isMobile),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  contentPadding,
                  8,
                  contentPadding,
                  isMobile ? 88 : 8,
                ),
                child: _fiscalYearsResolved
                    ? DataTableWidget<TransferDocument>(
                        key: _tableKey,
                        config: _buildTableConfig(t),
                        fromJson: (json) => TransferDocument.fromJson(json),
                        calendarController: widget.calendarController,
                      )
                    : const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: CircularProgressIndicator(),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: isMobile
          ? FloatingActionButton.extended(
              onPressed: _onAddNew,
              icon: const Icon(Icons.add),
              label: Text(t.add),
            )
          : null,
    );
  }

  Widget _buildHeader(AppLocalizations t, bool isMobile) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.getPadding(context),
        ResponsiveHelper.getPadding(context),
        ResponsiveHelper.getPadding(context),
        8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.transfers,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'مدیریت اسناد انتقال وجه',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          if (!isMobile)
            Tooltip(
              message: 'افزودن انتقال جدید',
              child: FilledButton.icon(
                onPressed: _onAddNew,
                icon: const Icon(Icons.add),
                label: Text(t.add),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilters(AppLocalizations t, bool isMobile) {
    final padding = ResponsiveHelper.getPadding(context);

    if (isMobile) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: padding, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _buildExternalFilterChips(t),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: () => _openMobileFiltersSheet(t),
              icon: const Icon(Icons.tune),
              tooltip: 'فیلترها',
            ),
            if (_hasExternalFiltersActive()) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  _clearExternalFilters();
                  _refreshData();
                },
                icon: const Icon(Icons.clear_all),
                tooltip: t.clear,
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _buildExternalFilterChips(t),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () =>
                    setState(() => _showDesktopFilters = !_showDesktopFilters),
                icon:
                    Icon(_showDesktopFilters ? Icons.expand_less : Icons.tune),
                label:
                    Text(_showDesktopFilters ? 'بستن فیلترها' : 'فیلترها'),
              ),
              if (_hasExternalFiltersActive()) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    _clearExternalFilters();
                    _refreshData();
                  },
                  icon: const Icon(Icons.clear_all),
                  tooltip: t.clear,
                ),
              ],
            ],
          ),
          if (_showDesktopFilters) ...[
            const SizedBox(height: 10),
            _buildFiltersForm(
              t: t,
              isMobileLayout: false,
              fiscalYearId: _selectedFiscalYearId,
              projectId: _selectedProjectId,
              filterBankAccount: _filterBankAccount,
              filterCashRegister: _filterCashRegister,
              filterPettyCash: _filterPettyCash,
              fromDate: _fromDate,
              toDate: _toDate,
              onFiscalYearChanged: (v) {
                setState(() => _selectedFiscalYearId = v);
                _refreshData();
              },
              onProjectChanged: (v) {
                setState(() => _selectedProjectId = v);
                _refreshData();
              },
              onBankAccountChanged: (v) {
                setState(() => _filterBankAccount = v);
                _refreshData();
              },
              onCashRegisterChanged: (v) {
                setState(() => _filterCashRegister = v);
                _refreshData();
              },
              onPettyCashChanged: (v) {
                setState(() => _filterPettyCash = v);
                _refreshData();
              },
              onFromDateChanged: (v) {
                setState(() => _fromDate = v);
                _refreshData();
              },
              onToDateChanged: (v) {
                setState(() => _toDate = v);
                _refreshData();
              },
              onClearDateRange: () {
                setState(() {
                  _fromDate = null;
                  _toDate = null;
                });
                _refreshData();
              },
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildExternalFilterChips(AppLocalizations t) {
    final chips = <Widget>[];

    if (_selectedFiscalYearId != null && _fiscalYears.isNotEmpty) {
      final fy = _fiscalYears
          .where((e) => (e['id'] as int?) == _selectedFiscalYearId)
          .toList();
      final title = fy.isNotEmpty ? (fy.first['title'] ?? '').toString() : '';
      chips.add(Chip(
        label: Text(title.isNotEmpty
            ? title
            : '${t.fiscalYear}: $_selectedFiscalYearId'),
        avatar: const Icon(Icons.event_note, size: 16),
      ));
    }

    if (_selectedProjectId != null) {
      final label = _projectFilterOptions
          .where((o) => o.value == _selectedProjectId.toString())
          .map((o) => o.label)
          .firstWhere(
            (e) => e.trim().isNotEmpty,
            orElse: () => 'پروژه: $_selectedProjectId',
          );
      chips.add(Chip(
        label: Text(label),
        avatar: const Icon(Icons.folder_open, size: 16),
      ));
    }

    if (_filterBankAccount != null) {
      chips.add(Chip(
        label: Text(_filterBankAccount!.name),
        avatar: const Icon(Icons.account_balance, size: 16),
      ));
    }
    if (_filterCashRegister != null) {
      chips.add(Chip(
        label: Text(_filterCashRegister!.name),
        avatar: const Icon(Icons.point_of_sale, size: 16),
      ));
    }
    if (_filterPettyCash != null) {
      chips.add(Chip(
        label: Text(_filterPettyCash!.name),
        avatar: const Icon(Icons.work_outline, size: 16),
      ));
    }

    if (_fromDate != null || _toDate != null) {
      final from = _fromDate != null
          ? HesabixDateUtils.formatForDisplay(
              _fromDate!, widget.calendarController.isJalali)
          : '—';
      final to = _toDate != null
          ? HesabixDateUtils.formatForDisplay(
              _toDate!, widget.calendarController.isJalali)
          : '—';
      chips.add(Chip(
        label: Text('${t.documentDate}: $from → $to'),
        avatar: const Icon(Icons.date_range, size: 16),
      ));
    }

    if (chips.isEmpty) {
      chips.add(Chip(label: Text(t.all)));
    }
    return chips;
  }

  bool _hasExternalFiltersActive() {
    return _fromDate != null ||
        _toDate != null ||
        _selectedFiscalYearId != null ||
        _selectedProjectId != null ||
        _filterBankAccount != null ||
        _filterCashRegister != null ||
        _filterPettyCash != null;
  }

  void _clearExternalFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
      _selectedProjectId = null;
      _filterBankAccount = null;
      _filterCashRegister = null;
      _filterPettyCash = null;
    });
    _refreshData();
  }

  Future<void> _openMobileFiltersSheet(AppLocalizations t) async {
    int? fiscalYearId = _selectedFiscalYearId;
    int? projectId = _selectedProjectId;
    BankAccountOption? filterBankAccount = _filterBankAccount;
    CashRegisterOption? filterCashRegister = _filterCashRegister;
    PettyCashOption? filterPettyCash = _filterPettyCash;
    DateTime? fromDate = _fromDate;
    DateTime? toDate = _toDate;

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text('فیلترها',
                          style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setModalState(() {
                            projectId = null;
                            filterBankAccount = null;
                            filterCashRegister = null;
                            filterPettyCash = null;
                            fromDate = null;
                            toDate = null;
                          });
                        },
                        child: Text(t.clear),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: _buildFiltersForm(
                        t: t,
                        isMobileLayout: true,
                        fiscalYearId: fiscalYearId,
                        projectId: projectId,
                        filterBankAccount: filterBankAccount,
                        filterCashRegister: filterCashRegister,
                        filterPettyCash: filterPettyCash,
                        fromDate: fromDate,
                        toDate: toDate,
                        onFiscalYearChanged: (v) =>
                            setModalState(() => fiscalYearId = v),
                        onProjectChanged: (v) =>
                            setModalState(() => projectId = v),
                        onBankAccountChanged: (v) =>
                            setModalState(() => filterBankAccount = v),
                        onCashRegisterChanged: (v) =>
                            setModalState(() => filterCashRegister = v),
                        onPettyCashChanged: (v) =>
                            setModalState(() => filterPettyCash = v),
                        onFromDateChanged: (v) =>
                            setModalState(() => fromDate = v),
                        onToDateChanged: (v) => setModalState(() => toDate = v),
                        onClearDateRange: () => setModalState(() {
                          fromDate = null;
                          toDate = null;
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.check),
                      label: Text(t.confirm),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (applied == true && mounted) {
      if (fromDate != null &&
          toDate != null &&
          fromDate!.isAfter(toDate!)) {
        final swap = fromDate;
        fromDate = toDate;
        toDate = swap;
      }
      setState(() {
        _selectedFiscalYearId = fiscalYearId;
        _selectedProjectId = projectId;
        _filterBankAccount = filterBankAccount;
        _filterCashRegister = filterCashRegister;
        _filterPettyCash = filterPettyCash;
        _fromDate = fromDate;
        _toDate = toDate;
      });
      _refreshData();
    }
  }

  Widget _buildFiltersForm({
    required AppLocalizations t,
    required bool isMobileLayout,
    required int? fiscalYearId,
    required int? projectId,
    required BankAccountOption? filterBankAccount,
    required CashRegisterOption? filterCashRegister,
    required PettyCashOption? filterPettyCash,
    required DateTime? fromDate,
    required DateTime? toDate,
    required ValueChanged<int?> onFiscalYearChanged,
    required ValueChanged<int?> onProjectChanged,
    required ValueChanged<BankAccountOption?> onBankAccountChanged,
    required ValueChanged<CashRegisterOption?> onCashRegisterChanged,
    required ValueChanged<PettyCashOption?> onPettyCashChanged,
    required ValueChanged<DateTime?> onFromDateChanged,
    required ValueChanged<DateTime?> onToDateChanged,
    required VoidCallback onClearDateRange,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_fiscalYears.isNotEmpty)
              SizedBox(
                width: isMobileLayout ? double.infinity : 280,
                child: DropdownButtonFormField<int>(
                  value: fiscalYearId,
                  decoration: InputDecoration(
                    labelText: t.fiscalYear,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 16),
                  ),
                  items: _fiscalYears.map<DropdownMenuItem<int>>((fy) {
                    final id = fy['id'] as int?;
                    final title = (fy['title'] ?? '').toString();
                    return DropdownMenuItem<int>(
                      value: id,
                      child: Text(
                        title.isNotEmpty ? title : 'FY ${id ?? ''}',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    );
                  }).toList(),
                  onChanged: onFiscalYearChanged,
                ),
              ),
            SizedBox(
              width: isMobileLayout ? double.infinity : 280,
              child: ProjectSelectorWidget(
                businessId: widget.businessId,
                apiClient: widget.apiClient,
                selectedProjectId: projectId,
                onChanged: onProjectChanged,
                authStore: widget.authStore,
                calendarController: widget.calendarController,
                allowNull: true,
                labelText: 'پروژه',
              ),
            ),
            SizedBox(
              width: isMobileLayout ? double.infinity : 280,
              child: BankAccountComboboxWidget(
                businessId: widget.businessId,
                selectedAccountId: filterBankAccount?.id,
                onChanged: onBankAccountChanged,
                label: 'بانک',
                hintText: 'همه حساب‌های بانکی',
              ),
            ),
            SizedBox(
              width: isMobileLayout ? double.infinity : 280,
              child: CashRegisterComboboxWidget(
                businessId: widget.businessId,
                selectedRegisterId: filterCashRegister?.id,
                onChanged: onCashRegisterChanged,
                label: 'صندوق',
                hintText: 'همه صندوق‌ها',
              ),
            ),
            SizedBox(
              width: isMobileLayout ? double.infinity : 280,
              child: PettyCashComboboxWidget(
                businessId: widget.businessId,
                selectedPettyCashId: filterPettyCash?.id,
                onChanged: onPettyCashChanged,
                label: 'تنخواه‌گردان',
                hintText: 'همه تنخواه‌ها',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (isMobileLayout)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DateInputField(
                      value: fromDate,
                      calendarController: widget.calendarController,
                      onChanged: onFromDateChanged,
                      labelText: t.dateFrom,
                      hintText: t.selectDate,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DateInputField(
                      value: toDate,
                      calendarController: widget.calendarController,
                      onChanged: onToDateChanged,
                      labelText: t.dateTo,
                      hintText: t.selectDate,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: onClearDateRange,
                    icon: const Icon(Icons.clear),
                    tooltip: t.clearDateFilter,
                  ),
                ],
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Expanded(
                      child: DateInputField(
                        value: fromDate,
                        calendarController: widget.calendarController,
                        onChanged: onFromDateChanged,
                        labelText: t.dateFrom,
                        hintText: t.selectDate,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DateInputField(
                        value: toDate,
                        calendarController: widget.calendarController,
                        onChanged: onToDateChanged,
                        labelText: t.dateTo,
                        hintText: t.selectDate,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: onClearDateRange,
                      icon: const Icon(Icons.clear),
                      tooltip: t.clearDateFilter,
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Map<String, dynamic> _transferTableExtraParams() {
    final m = <String, dynamic>{
      if (_fromDate != null) 'from_date': HesabixDateUtils.formatForApiDate(_fromDate!),
      if (_toDate != null) 'to_date': HesabixDateUtils.formatForApiDate(_toDate!),
      if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
      if (_selectedProjectId != null) 'project_id': _selectedProjectId,
    };
    final ba = int.tryParse(_filterBankAccount?.id ?? '');
    if (ba != null) m['bank_account_id'] = ba;
    final cr = int.tryParse(_filterCashRegister?.id ?? '');
    if (cr != null) m['cash_register_id'] = cr;
    final pc = int.tryParse(_filterPettyCash?.id ?? '');
    if (pc != null) m['petty_cash_id'] = pc;
    return m;
  }

  DataTableConfig<TransferDocument> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<TransferDocument>(
      endpoint: '/businesses/${widget.businessId}/transfers',
      title: t.transfers,
      excelEndpoint: '/businesses/${widget.businessId}/transfers/export/excel',
      pdfEndpoint: '/businesses/${widget.businessId}/transfers/export/pdf',
      businessId: widget.businessId,
      reportModuleKey: 'transfers',
      reportSubtype: 'list',
      getExportParams: _transferTableExtraParams,
      columns: [
        TextColumn(
          'code',
          'کد سند',
          width: ColumnWidth.medium,
          formatter: (it) => it.code,
        ),
        TextColumn(
          'description',
          'توضیحات',
          width: ColumnWidth.large,
          formatter: (it) => (it.description ?? '').isNotEmpty ? it.description! : _composeDesc(it),
        ),
        TextColumn(
          'source',
          'مبدا',
          width: ColumnWidth.large,
          formatter: (it) => _composeSource(it),
        ),
        TextColumn(
          'destination',
          'مقصد',
          width: ColumnWidth.large,
          formatter: (it) => _composeDestination(it),
        ),
        DateColumn(
          'document_date',
          'تاریخ سند',
          width: ColumnWidth.medium,
          formatter: (it) => HesabixDateUtils.formatForDisplay(it.documentDate, widget.calendarController.isJalali),
        ),
        TextColumn(
          'total_amount',
          'مبلغ کل',
          width: ColumnWidth.large,
          formatter: (it) => '${formatWithThousands(it.totalAmount)} ${it.currencyCode ?? 'ریال'}',
        ),
        TextColumn(
          'created_by_name',
          'ایجادکننده',
          width: ColumnWidth.medium,
          formatter: (it) => it.createdByName ?? 'نامشخص',
        ),
        DateColumn(
          'registered_at',
          'تاریخ ثبت',
          width: ColumnWidth.medium,
          formatter: (it) => HesabixDateUtils.formatForDisplay(it.registeredAt, widget.calendarController.isJalali),
        ),
        TextColumn(
          'project_name',
          'پروژه',
          width: ColumnWidth.medium,
          formatter: (it) => it.projectName ?? '-',
          searchable: true,
          filterType: ColumnFilterType.multiSelect,
          filterOptions: _projectFilterOptions,
        ),
        ActionColumn(
          'actions',
          'عملیات',
          width: ColumnWidth.medium,
          actions: [
            DataTableAction(icon: Icons.visibility, label: 'مشاهده', onTap: (it) => _onView(it as TransferDocument)),
            DataTableAction(icon: Icons.edit, label: 'ویرایش', onTap: (it) => _onEdit(it as TransferDocument)),
            DataTableAction(icon: Icons.delete, label: 'حذف', onTap: (it) => _onDelete(it as TransferDocument), isDestructive: true),
          ],
        ),
      ],
      searchFields: ['code', 'description', 'created_by_name', 'source', 'destination'],
      dateRangeField: 'document_date',
      showSearch: true,
      showFilters: true,
      showPagination: true,
      showColumnSearch: true,
      showRefreshButton: true,
      showClearFiltersButton: true,
      enableRowSelection: true,
      enableMultiRowSelection: true,
      showExportButtons: true,
      showExcelExport: true,
      showPdfExport: true,
      defaultPageSize: 20,
      pageSizeOptions: [10, 20, 50, 100],
      // انتخاب سطرها در این صفحه استفاده خاصی ندارد
      additionalParams: _transferTableExtraParams(),
      onRowTap: (item) => _onView(item as TransferDocument),
      onRowDoubleTap: (item) => _onEdit(item as TransferDocument),
      emptyStateMessage: 'هیچ سند انتقالی یافت نشد',
      loadingMessage: 'در حال بارگذاری اسناد انتقال...',
      errorMessage: 'خطا در بارگذاری اسناد انتقال',
      expandBodyHeightToFitRows: true,
    );
  }

  String _typeFa(String? t) {
    switch (t) {
      case 'bank':
        return 'بانک';
      case 'cash_register':
        return 'صندوق';
      case 'petty_cash':
        return 'تنخواه';
      default:
        return t ?? '';
    }
  }

  String _composeSource(TransferDocument it) {
    return '${_typeFa(it.sourceType)} ${it.sourceName ?? ''}'.trim();
  }

  String _composeDestination(TransferDocument it) {
    return '${_typeFa(it.destinationType)} ${it.destinationName ?? ''}'.trim();
  }

  String _composeDesc(TransferDocument it) {
    final src = _composeSource(it);
    final dst = _composeDestination(it);
    if (src.isEmpty && dst.isEmpty) return '';
    return 'انتقال $src → $dst';
  }

  void _onAddNew() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => TransferFormDialog(
        businessId: widget.businessId,
        calendarController: widget.calendarController,
        authStore: widget.authStore,
        apiClient: widget.apiClient,
        onSuccess: () {},
      ),
    );
    if (result == true) _refreshData();
  }

  void _onView(TransferDocument item) async {
    final svc = TransferService(widget.apiClient);
    final full = await svc.getById(item.id);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => TransferDetailsDialog(
        document: full,
        calendarController: widget.calendarController,
      ),
    );
  }

  void _onEdit(TransferDocument item) async {
    final svc = TransferService(widget.apiClient);
    final full = await svc.getById(item.id);
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => TransferFormDialog(
        businessId: widget.businessId,
        calendarController: widget.calendarController,
        authStore: widget.authStore,
        apiClient: widget.apiClient,
        initial: full,
        onSuccess: () {},
      ),
    );
    if (result == true) _refreshData();
  }

  void _onDelete(TransferDocument item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف انتقال'),
        content: Text('آیا از حذف سند ${item.code} مطمئن هستید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        final svc = TransferService(widget.apiClient);
        await svc.deleteById(item.id);
        if (mounted) {
          SnackBarHelper.showSuccess(context, message: 'حذف شد');
        }
        _refreshData();
      } catch (e) {
        if (mounted) {
          SnackBarHelper.showError(context, message: 'خطا: $e');
        }
      }
    }
  }
}
