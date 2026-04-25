import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/expense_income_document.dart';
import 'package:hesabix_ui/services/expense_income_list_service.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/utils/number_formatters.dart' show formatWithThousands;
import 'package:hesabix_ui/core/date_utils.dart' show HesabixDateUtils;
import 'package:hesabix_ui/widgets/expense_income/expense_income_form_dialog.dart';
import 'package:hesabix_ui/widgets/expense_income/expense_income_details_dialog.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/project/project_selector_widget.dart';
import '../../services/project_service.dart';
import '../../widgets/invoice/account_tree_combobox_widget.dart';
import '../../models/account_model.dart';
import '../../services/business_dashboard_service.dart';

/// صفحه لیست اسناد هزینه و درآمد با ویجت جدول
class ExpenseIncomeListPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final AuthStore authStore;
  final ApiClient apiClient;

  const ExpenseIncomeListPage({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.authStore,
    required this.apiClient,
  });

  @override
  State<ExpenseIncomeListPage> createState() => _ExpenseIncomeListPageState();
  
  /// Static map to store page states by business ID for external refresh
  static final Map<int, _ExpenseIncomeListPageState> _pageStates = {};
  
  /// Get the page state for a specific business ID
  static _ExpenseIncomeListPageState? getPageState(int businessId) {
    return _pageStates[businessId];
  }
  
  /// Clear the page state for a specific business ID
  static void clearPageState(int businessId) {
    _pageStates.remove(businessId);
  }
}

class _ExpenseIncomeListPageState extends State<ExpenseIncomeListPage> {
  late ExpenseIncomeListService _service;
  late final BusinessDashboardService _dashboardService =
      BusinessDashboardService(widget.apiClient);

  String? _selectedDocumentType;
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedProjectId;
  String? _selectedProjectName;

  int? _selectedFiscalYearId;
  List<Map<String, dynamic>> _fiscalYears = [];
  bool _fiscalYearsResolved = false;

  Account? _filterAccount;
  bool _showDesktopFilters = false;

  List<FilterOption> _projectFilterOptions = [];

  // کلید کنترل جدول برای دسترسی به selection و refresh
  final GlobalKey _tableKey = GlobalKey();
  int _selectedCount = 0; // تعداد سطرهای انتخاب‌شده
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    // Register this page instance for external refresh access
    ExpenseIncomeListPage._pageStates[widget.businessId] = this;
    _service = ExpenseIncomeListService(widget.apiClient);
    _loadProjects();
    _loadFiscalYears();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _isInitialized = true);
    });
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
  
  @override
  void dispose() {
    // Clean up the page state when disposed
    ExpenseIncomeListPage._pageStates.remove(widget.businessId);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // اگر صفحه قبلاً initialize شده بود، داده‌ها را refresh کن (مثل برگشت از دیالوگ ثبت/ویرایش)
    if (_isInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshData();
      });
    }
  }

  /// تازه‌سازی داده‌های جدول
  void _refreshData() {
    final state = _tableKey.currentState;
    if (state != null) {
      try {
        // استفاده از متد عمومی refresh در ویجت جدول
        // نوت: دسترسی دینامیک چون State کلاس خصوصی است
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
    final isMobile = ResponsiveHelper.isMobile(context);
    final contentPadding = ResponsiveHelper.getPadding(context);
    
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
                  // avoid FAB overlapping footer/pagination on mobile
                  isMobile ? 88 : 8,
                ),
                child: _fiscalYearsResolved
                    ? DataTableWidget<ExpenseIncomeDocument>(
                        key: _tableKey,
                        config: _buildTableConfig(t, context, isMobile: isMobile),
                        fromJson: (json) => ExpenseIncomeDocument.fromJson(json),
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
      floatingActionButton: (isMobile && widget.authStore.canWriteSection('expenses_income'))
          ? FloatingActionButton.extended(
              onPressed: _onAddNew,
              icon: const Icon(Icons.add),
              label: Text(t.add),
            )
          : null,
    );
  }

  /// ساخت هدر صفحه
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
                  'هزینه و درآمد',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'مدیریت اسناد هزینه و درآمد',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!isMobile && widget.authStore.canWriteSection('expenses_income'))
            FilledButton.icon(
              onPressed: _onAddNew,
              icon: const Icon(Icons.add),
              label: Text(t.add),
            ),
        ],
      ),
    );
  }

  /// ساخت بخش فیلترها
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
              documentType: _selectedDocumentType,
              fiscalYearId: _selectedFiscalYearId,
              projectId: _selectedProjectId,
              filterAccount: _filterAccount,
              fromDate: _fromDate,
              toDate: _toDate,
              onDocumentTypeChanged: (v) {
                setState(() => _selectedDocumentType = v);
                _refreshData();
              },
              onFiscalYearChanged: (v) {
                setState(() => _selectedFiscalYearId = v);
                _refreshData();
              },
              onProjectChanged: (v) async {
                setState(() {
                  _selectedProjectId = v;
                  _selectedProjectName = null;
                });
                await _hydrateSelectedProjectName();
                _refreshData();
              },
              onAccountChanged: (v) {
                setState(() => _filterAccount = v);
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
    if (_selectedDocumentType != null) {
      chips.add(Chip(
        label: Text(_expenseIncomeDocTypeChipLabel(t, _selectedDocumentType)),
        avatar: Icon(
          _selectedDocumentType == 'income'
              ? Icons.trending_up
              : Icons.trending_down,
          size: 16,
        ),
      ));
    } else {
      chips.add(Chip(
        label: Text(t.all),
        avatar: const Icon(Icons.all_inclusive, size: 16),
      ));
    }

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
          .cast<String?>()
          .firstWhere((e) => e != null && e!.isNotEmpty, orElse: () => null);
      chips.add(Chip(
        label: Text(label ?? 'پروژه: $_selectedProjectId'),
        avatar: const Icon(Icons.folder_open, size: 16),
      ));
    }

    if (_filterAccount != null) {
      chips.add(Chip(
        label: Text(
          '${_filterAccount!.code} ${_filterAccount!.name}',
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        avatar: const Icon(Icons.account_tree, size: 16),
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

  String _expenseIncomeDocTypeChipLabel(AppLocalizations t, String? type) {
    switch (type) {
      case 'income':
        return 'درآمدها';
      case 'expense':
        return 'هزینه‌ها';
      default:
        return t.all;
    }
  }

  bool _hasExternalFiltersActive() {
    return _selectedDocumentType != null ||
        _fromDate != null ||
        _toDate != null ||
        _selectedFiscalYearId != null ||
        _selectedProjectId != null ||
        _filterAccount != null;
  }

  void _clearExternalFilters() {
    setState(() {
      _selectedDocumentType = null;
      _fromDate = null;
      _toDate = null;
      _selectedProjectId = null;
      _selectedProjectName = null;
      _filterAccount = null;
    });
    _refreshData();
  }

  Future<void> _openMobileFiltersSheet(AppLocalizations t) async {
    String? documentType = _selectedDocumentType;
    int? fiscalYearId = _selectedFiscalYearId;
    int? projectId = _selectedProjectId;
    Account? filterAccount = _filterAccount;
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
                            documentType = null;
                            projectId = null;
                            filterAccount = null;
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
                        documentType: documentType,
                        fiscalYearId: fiscalYearId,
                        projectId: projectId,
                        filterAccount: filterAccount,
                        fromDate: fromDate,
                        toDate: toDate,
                        onDocumentTypeChanged: (v) =>
                            setModalState(() => documentType = v),
                        onFiscalYearChanged: (v) =>
                            setModalState(() => fiscalYearId = v),
                        onProjectChanged: (v) =>
                            setModalState(() => projectId = v),
                        onAccountChanged: (v) =>
                            setModalState(() => filterAccount = v),
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
        _selectedDocumentType = documentType;
        _selectedFiscalYearId = fiscalYearId;
        _selectedProjectId = projectId;
        _filterAccount = filterAccount;
        _fromDate = fromDate;
        _toDate = toDate;
      });
      await _hydrateSelectedProjectName();
      _refreshData();
    }
  }

  Widget _buildFiltersForm({
    required AppLocalizations t,
    required bool isMobileLayout,
    required String? documentType,
    required int? fiscalYearId,
    required int? projectId,
    required Account? filterAccount,
    required DateTime? fromDate,
    required DateTime? toDate,
    required ValueChanged<String?> onDocumentTypeChanged,
    required ValueChanged<int?> onFiscalYearChanged,
    required ValueChanged<int?> onProjectChanged,
    required ValueChanged<Account?> onAccountChanged,
    required ValueChanged<DateTime?> onFromDateChanged,
    required ValueChanged<DateTime?> onToDateChanged,
    required VoidCallback onClearDateRange,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String?>(
            style: SegmentedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            segments: const [
              ButtonSegment<String?>(
                value: null,
                label: Text('همه'),
                icon: Icon(Icons.all_inclusive),
              ),
              ButtonSegment<String?>(
                value: 'expense',
                label: Text('هزینه‌ها'),
                icon: Icon(Icons.trending_down),
              ),
              ButtonSegment<String?>(
                value: 'income',
                label: Text('درآمدها'),
                icon: Icon(Icons.trending_up),
              ),
            ],
            selected: documentType != null ? {documentType} : <String?>{},
            onSelectionChanged: (set) =>
                onDocumentTypeChanged(set.isEmpty ? null : set.first),
          ),
        ),
        const SizedBox(height: 8),
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
              child: AccountTreeComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: filterAccount,
                onChanged: onAccountChanged,
                label: 'حساب',
                hintText: 'انتخاب حساب از درخت',
                documentTypeFilter: documentType,
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

  Future<void> _hydrateSelectedProjectName() async {
    final projectId = _selectedProjectId;
    if (projectId == null) {
      if (mounted) setState(() => _selectedProjectName = null);
      return;
    }
    try {
      final svc = ProjectService(widget.apiClient);
      final data = await svc.getProject(projectId);
      if (!mounted) return;
      final name = (data['name'] ?? data['project_name'] ?? '').toString().trim();
      setState(() => _selectedProjectName = name.isEmpty ? null : name);
    } catch (_) {
      if (mounted) setState(() => _selectedProjectName = null);
    }
  }

  Map<String, dynamic> _expenseIncomeFilterParams({required bool includeBusinessId}) {
    final m = <String, dynamic>{
      'document_type': _selectedDocumentType,
      if (_fromDate != null) 'from_date': HesabixDateUtils.formatForApiDate(_fromDate!),
      if (_toDate != null) 'to_date': HesabixDateUtils.formatForApiDate(_toDate!),
      if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
      if (_selectedProjectId != null) 'project_id': _selectedProjectId,
      if (_filterAccount?.id != null) 'account_id': _filterAccount!.id,
    };
    if (includeBusinessId) {
      m['business_id'] = widget.businessId;
    }
    return m;
  }

  /// ساخت تنظیمات جدول
  DataTableConfig<ExpenseIncomeDocument> _buildTableConfig(
    AppLocalizations t,
    BuildContext context, {
    required bool isMobile,
  }) {
    final theme = Theme.of(context);

    if (isMobile) {
      return DataTableConfig<ExpenseIncomeDocument>(
        endpoint: '/businesses/${widget.businessId}/expense-income',
        // avoid duplicate titles (page already has its own header)
        title: null,
        excelEndpoint: '/businesses/${widget.businessId}/expense-income/export/excel',
        pdfEndpoint: '/businesses/${widget.businessId}/expense-income/export/pdf',
        businessId: widget.businessId,
        reportModuleKey: 'expense_income',
        reportSubtype: 'list',
        enableColumnSettings: false,
        showColumnSettingsButton: false,
        defaultSortBy: 'document_date',
        defaultSortDesc: true,
        dataRowHeight: 168,
        padding: const EdgeInsets.all(8),
        columns: [
          CustomColumn(
            'summary',
            'سند',
            sortable: false,
            searchable: false,
            width: ColumnWidth.extraLarge,
            builder: (dynamic item, int index) => _buildMobileSummaryCard(item as ExpenseIncomeDocument),
          ),
        ],
        searchFields: const ['code', 'description', 'created_by_name'],
        filterFields: const ['document_type'],
        dateRangeField: 'document_date',
        showSearch: true,
        showFilters: false,
        showPagination: true,
        showColumnSearch: false,
        showRefreshButton: true,
        showClearFiltersButton: false,
        enableRowSelection: false,
        enableMultiRowSelection: false,
        showExportButtons: true,
        showExcelExport: true,
        showPdfExport: true,
        defaultPageSize: 20,
        pageSizeOptions: const [10, 20, 50, 100],
        additionalParams: _expenseIncomeFilterParams(includeBusinessId: false),
        getExportParams: () => _expenseIncomeFilterParams(includeBusinessId: true),
        onRowTap: (item) => _onView(item as ExpenseIncomeDocument),
        emptyStateMessage: 'هیچ سند هزینه یا درآمدی یافت نشد',
        loadingMessage: 'در حال بارگذاری اسناد...',
        errorMessage: 'خطا در بارگذاری اسناد',
        expandBodyHeightToFitRows: true,
      );
    }

    return DataTableConfig<ExpenseIncomeDocument>(
      endpoint: '/businesses/${widget.businessId}/expense-income',
      title: 'هزینه و درآمد',
      excelEndpoint: '/businesses/${widget.businessId}/expense-income/export/excel',
      pdfEndpoint: '/businesses/${widget.businessId}/expense-income/export/pdf',
      businessId: widget.businessId,
      reportModuleKey: 'expense_income',
      reportSubtype: 'list',
      // دکمه حذف گروهی در هدر جدول
      customHeaderActions: [
        if (widget.authStore.canDeleteSection('expenses_income'))
          Tooltip(
            message: 'حذف انتخاب‌شده‌ها',
            child: FilledButton.icon(
              onPressed: _selectedCount > 0 ? _onBulkDelete : null,
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.errorContainer,
                foregroundColor: theme.colorScheme.onErrorContainer,
              ),
              icon: const Icon(Icons.delete_forever),
              label: Text('حذف ($_selectedCount)'),
            ),
          ),
      ],
      getExportParams: () => _expenseIncomeFilterParams(includeBusinessId: true),
      columns: [
        // کد سند
        TextColumn(
          'code',
          'کد سند',
          width: ColumnWidth.medium,
          formatter: (item) => item.code,
        ),
        
        // نوع سند
        TextColumn(
          'document_type',
          'نوع',
          width: ColumnWidth.small,
          formatter: (item) => item.documentTypeName,
        ),
        
        // تاریخ سند
        DateColumn(
          'document_date',
          'تاریخ سند',
          width: ColumnWidth.medium,
          formatter: (item) => HesabixDateUtils.formatForDisplay(item.documentDate, widget.calendarController.isJalali),
        ),
        
        // مبلغ کل
        TextColumn(
          'total_amount',
          'مبلغ کل',
          width: ColumnWidth.large,
          formatter: (item) => '${formatWithThousands(item.totalAmount)} ${item.currencyCode ?? 'ریال'}',
        ),
        
        // نام حساب‌ها
        TextColumn(
          'item_accounts',
          'حساب‌ها',
          width: ColumnWidth.medium,
          formatter: (item) => item.itemAccountNames ?? 'نامشخص',
        ),
        
        // اطلاعات طرف‌حساب
        TextColumn(
          'counterparty_info',
          'طرف‌حساب',
          width: ColumnWidth.medium,
          formatter: (item) => item.counterpartyInfo ?? 'نامشخص',
        ),
        
        // توضیحات
        TextColumn(
          'description',
          'توضیحات',
          width: ColumnWidth.large,
          formatter: (item) => item.description ?? '',
        ),
        
        // تعداد خطوط
        NumberColumn(
          'lines_count',
          'خطوط',
          width: ColumnWidth.small,
          formatter: (item) => (item.itemLinesCount + item.counterpartyLinesCount).toString(),
        ),
        
        // ایجادکننده
        TextColumn(
          'created_by_name',
          'ایجادکننده',
          width: ColumnWidth.medium,
          formatter: (item) => item.createdByName ?? 'نامشخص',
        ),
        
        // تاریخ ثبت
        DateColumn(
          'registered_at',
          'تاریخ ثبت',
          width: ColumnWidth.medium,
          formatter: (item) => HesabixDateUtils.formatForDisplay(item.registeredAt, widget.calendarController.isJalali),
        ),
        
        // پروژه
        TextColumn(
          'project_name',
          'پروژه',
          width: ColumnWidth.medium,
          formatter: (item) => item.projectName ?? '-',
          searchable: true,
          filterType: ColumnFilterType.multiSelect,
          filterOptions: _projectFilterOptions,
        ),
        
        // عملیات
        ActionColumn(
          'actions',
          'عملیات',
          width: ColumnWidth.medium,
          actions: [
            DataTableAction(
              icon: Icons.visibility,
              label: 'مشاهده',
              onTap: (item) => _onView(item),
            ),
            if (widget.authStore.canWriteSection('expenses_income'))
              DataTableAction(
                icon: Icons.edit,
                label: 'ویرایش',
                onTap: (item) => _onEdit(item),
              ),
            if (widget.authStore.canDeleteSection('expenses_income'))
              DataTableAction(
                icon: Icons.delete,
                label: 'حذف',
                onTap: (item) => _onDelete(item),
                isDestructive: true,
              ),
          ],
        ),
      ],
      searchFields: ['code', 'description', 'created_by_name'],
      filterFields: ['document_type'],
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
      onRowSelectionChanged: (rows) {
        if (mounted) {
          setState(() {
            _selectedCount = rows.length;
          });
        }
      },
      additionalParams: _expenseIncomeFilterParams(includeBusinessId: false),
      onRowTap: (item) => _onView(item),
      onRowDoubleTap: (item) => _onEdit(item),
      emptyStateMessage: 'هیچ سند هزینه یا درآمدی یافت نشد',
      loadingMessage: 'در حال بارگذاری اسناد...',
      errorMessage: 'خطا در بارگذاری اسناد',
      expandBodyHeightToFitRows: true,
    );
  }

  Widget _buildMobileSummaryCard(ExpenseIncomeDocument doc) {
    final theme = Theme.of(context);
    final isIncome = doc.isIncome;
    final typeColor = isIncome ? Colors.green : Colors.orange;
    final amountText = '${formatWithThousands(doc.totalAmount)} ${doc.currencyCode ?? 'ریال'}';
    final dateText = HesabixDateUtils.formatForDisplay(doc.documentDate, widget.calendarController.isJalali);
    final counterparty = (doc.counterpartyInfo ?? '').trim();
    final accounts = (doc.itemAccountNames ?? '').trim();
    final description = (doc.description ?? '').trim();
    final linesCount = doc.itemLinesCount + doc.counterpartyLinesCount;

    final canEdit = widget.authStore.canWriteSection('expenses_income');
    final canDelete = widget.authStore.canDeleteSection('expenses_income');

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onView(doc),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          doc.code,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: typeColor.withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            doc.documentTypeName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: typeColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'عملیات',
                    onSelected: (value) {
                      switch (value) {
                        case 'view':
                          _onView(doc);
                          break;
                        case 'edit':
                          _onEdit(doc);
                          break;
                        case 'delete':
                          _onDelete(doc);
                          break;
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'view', child: _PopupRow(icon: Icons.visibility, label: 'مشاهده')),
                      if (canEdit) const PopupMenuItem(value: 'edit', child: _PopupRow(icon: Icons.edit, label: 'ویرایش')),
                      if (canDelete)
                        PopupMenuItem(
                          value: 'delete',
                          child: _PopupRow(
                            icon: Icons.delete,
                            label: 'حذف',
                            isDestructive: true,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      dateText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    amountText,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                ],
              ),
              if (counterparty.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.person_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        counterparty,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ],
              if (accounts.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.account_balance_wallet_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        accounts,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ],
              if (description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.format_list_numbered, size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    'تعداد خطوط: $linesCount',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if ((doc.projectName ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.work_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        doc.projectName!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// افزودن سند جدید
  void _onAddNew() async {
    if (!widget.authStore.canWriteSection('expenses_income')) {
      SnackBarHelper.showError(context, message: 'دسترسی لازم برای افزودن را ندارید');
      return;
    }

    // اگر نوع سند مشخص نیست، از کاربر بپرس
    bool? isIncome;
    if (_selectedDocumentType == 'income') {
      isIncome = true;
    } else if (_selectedDocumentType == 'expense') {
      isIncome = false;
    } else {
      isIncome = await _askAddType();
      if (!mounted) return;
      if (isIncome == null) return; // cancelled
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ExpenseIncomeFormDialog(
        businessId: widget.businessId,
        calendarController: widget.calendarController,
        isIncome: isIncome!,
        businessInfo: widget.authStore.currentBusiness,
        apiClient: widget.apiClient,
      ),
    );
    if (!mounted) return;
    
    // اگر سند با موفقیت ثبت شد، جدول را تازه‌سازی کن
    if (result == true) {
      _refreshData();
    }
  }

  Future<bool?> _askAddType() async {
    if (!mounted) return null;
    final theme = Theme.of(context);
    final isMobile = ResponsiveHelper.isMobile(context);

    if (isMobile) {
      return showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const Text(
                      'افزودن سند',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, false),
                      icon: const Icon(Icons.trending_down),
                      label: const Text('هزینه'),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.trending_up),
                      label: const Text('درآمد'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, null),
                      child: const Text('انصراف'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('افزودن سند'),
          content: const Text('نوع سند را انتخاب کنید:'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, false),
              icon: const Icon(Icons.trending_down),
              label: const Text('هزینه'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.trending_up),
              label: const Text('درآمد'),
            ),
          ],
        );
      },
    );
  }

  /// مشاهده جزئیات سند
  void _onView(ExpenseIncomeDocument document) async {
    if (!context.mounted) return;
    final ctx = context;
    try {
      // دریافت جزئیات کامل سند
      final fullDoc = await _service.getById(document.id);
      if (fullDoc == null) {
        if (!ctx.mounted) return;
        SnackBarHelper.show(ctx, message: 'سند یافت نشد');
        return;
      }

      // نمایش دیالوگ مشاهده جزئیات
      if (!ctx.mounted) return;
      await showDialog(
        context: ctx,
        builder: (_) => ExpenseIncomeDetailsDialog(
          document: fullDoc,
          calendarController: widget.calendarController,
          businessId: widget.businessId,
          apiClient: widget.apiClient,
        ),
      );
    } catch (e) {
      if (!ctx.mounted) return;
      SnackBarHelper.show(
        ctx,
        message:
            'خطا در بارگذاری جزئیات: ${ErrorExtractor.forContext(e, ctx)}',
      );
    }
  }

  /// ویرایش سند
  void _onEdit(ExpenseIncomeDocument document) async {
    if (!context.mounted) return;
    if (!widget.authStore.canWriteSection('expenses_income')) {
      SnackBarHelper.showError(context, message: 'دسترسی لازم برای ویرایش را ندارید');
      return;
    }
    final ctx = context;
    try {
      // دریافت جزئیات کامل سند
      final fullDoc = await _service.getById(document.id);
      if (fullDoc == null) {
        if (!ctx.mounted) return;
        SnackBarHelper.show(ctx, message: 'سند یافت نشد');
        return;
      }
      if (!ctx.mounted) return;
      final result = await showDialog<bool>(
        context: ctx,
        builder: (_) => ExpenseIncomeFormDialog(
          businessId: widget.businessId,
          calendarController: widget.calendarController,
          isIncome: fullDoc.isIncome,
          businessInfo: widget.authStore.currentBusiness,
          apiClient: widget.apiClient,
          initialDocument: fullDoc,
        ),
      );

      if (result == true) {
        _refreshData();
      }
    } catch (e) {
      if (!ctx.mounted) return;
      SnackBarHelper.show(
        ctx,
        message:
            'خطا در آماده‌سازی ویرایش: ${ErrorExtractor.forContext(e, ctx)}',
      );
    }
  }

  /// حذف سند
  void _onDelete(ExpenseIncomeDocument document) {
    if (!widget.authStore.canDeleteSection('expenses_income')) {
      SnackBarHelper.showError(context, message: 'دسترسی لازم برای حذف را ندارید');
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأیید حذف'),
        content: Text('حذف سند ${document.code} غیرقابل بازگشت است. آیا ادامه می‌دهید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _performDelete(document);
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  /// انجام عملیات حذف
  Future<void> _performDelete(ExpenseIncomeDocument document) async {
    try {
      // نمایش لودینگ هنگام حذف
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final success = await _service.delete(document.id);
      if (success) {
        if (mounted) {
          Navigator.pop(context); // بستن لودینگ
          SnackBarHelper.showSuccess(context, message: 'سند ${document.code} با موفقیت حذف شد');
          setState(() {
            _selectedCount = 0; // پاک‌سازی شمارنده انتخاب پس از حذف
          });
          _refreshData();
        }
      } else {
        if (mounted) Navigator.pop(context);
        throw Exception('خطا در حذف سند');
      }
    } catch (e) {
      if (mounted) {
        // بستن لودینگ در صورت بروز خطا
        Navigator.pop(context);

        String message = 'خطا در حذف سند';
        int? statusCode;
        if (e is DioException) {
          statusCode = e.response?.statusCode;
          final data = e.response?.data;
          try {
            final detail = (data is Map<String, dynamic>) ? data['detail'] : null;
            if (detail is Map<String, dynamic>) {
              final err = detail['error'];
              if (err is Map<String, dynamic>) {
                final m = err['message'];
                if (m is String && m.trim().isNotEmpty) {
                  message = m;
                }
              }
            }
          } catch (_) {
            // ignore parse errors
          }

          if (statusCode == 404) {
            message = 'سند یافت نشد یا قبلاً حذف شده است';
            _refreshData();
          } else if (statusCode == 403) {
            message = 'دسترسی لازم برای حذف این سند را ندارید';
          } else if (statusCode == 409) {
            // پیام از سرور استخراج شده است (مثلاً سند قفل/دارای وابستگی)
            if (message == 'خطا در حذف سند') {
              message = 'حذف این سند امکان‌پذیر نیست';
            }
          }
        } else {
          message = ErrorExtractor.forContext(e, context);
        }

        SnackBarHelper.showError(context, message: message);
      }
    }
  }

  /// حذف گروهی اسناد انتخاب‌شده
  Future<void> _onBulkDelete() async {
    if (!widget.authStore.canDeleteSection('expenses_income')) {
      if (mounted) {
        SnackBarHelper.showError(context, message: 'دسترسی لازم برای حذف را ندارید');
      }
      return;
    }
    // استخراج آیتم‌های انتخاب‌شده از جدول
    final state = _tableKey.currentState;
    if (state == null) return;

    List<dynamic> selectedItems = const [];
    try {
      // ignore: avoid_dynamic_calls
      selectedItems = (state as dynamic).getSelectedItems();
    } catch (_) {}

    if (selectedItems.isEmpty) return;

    // نگاشت به مدل و شناسه‌ها
    final docs = selectedItems.cast<ExpenseIncomeDocument>();
    final ids = docs.map((d) => d.id).toList();
    final codes = docs.map((d) => d.code).toList();

    // تایید کاربر
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('تأیید حذف گروهی'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('تعداد اسناد انتخاب‌شده: ${ids.length}'),
              const SizedBox(height: 8),
              Text('این عملیات غیرقابل بازگشت است. ادامه می‌دهید؟'),
              if (codes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('نمونه کدها: ${codes.take(5).join(', ')}${codes.length > 5 ? ' ...' : ''}'),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
          ],
        );
      },
    );

    if (confirmed != true) return;

    // نمایش لودینگ
    if (!context.mounted) return;
    final ctx = context;
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await _service.deleteMultiple(ids);
      if (!ctx.mounted) return;
      Navigator.pop(ctx); // بستن لودینگ
      SnackBarHelper.showSuccess(ctx, message: '${ids.length} سند با موفقیت حذف شد');
      setState(() {
        _selectedCount = 0; // پاک‌سازی شمارنده انتخاب پس از حذف گروهی
      });
      _refreshData();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // بستن لودینگ
      final message = e is DioException && (e.message?.trim().isNotEmpty ?? false)
          ? e.message!
          : ErrorExtractor.forContext(e, context);
      SnackBarHelper.showError(context, message: message);
    }
  }
}

class _PopupRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDestructive;
  const _PopupRow({
    required this.icon,
    required this.label,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isDestructive ? theme.colorScheme.error : theme.iconTheme.color;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: isDestructive ? TextStyle(color: theme.colorScheme.error) : null,
        ),
      ],
    );
  }
}