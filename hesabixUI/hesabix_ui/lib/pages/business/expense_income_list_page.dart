import 'package:flutter/material.dart';
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
import '../../utils/snackbar_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/project/project_selector_widget.dart';
import '../../services/project_service.dart';

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
  String? _selectedDocumentType;
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedProjectId;
  String? _selectedProjectName;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _isInitialized = true);
    });
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
                child: DataTableWidget<ExpenseIncomeDocument>(
                  key: _tableKey,
                  config: _buildTableConfig(t, context, isMobile: isMobile),
                  fromJson: (json) => ExpenseIncomeDocument.fromJson(json),
                  calendarController: widget.calendarController,
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
                  children: _buildExternalFilterChips(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: _openMobileFiltersSheet,
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

    // Desktop/tablet: show full inline filter controls
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // فیلتر نوع سند
              Expanded(
                flex: 2,
                child: SegmentedButton<String?>(
                  segments: const [
                    ButtonSegment<String?>(value: null, label: Text('همه'), icon: Icon(Icons.all_inclusive)),
                    ButtonSegment<String?>(value: 'expense', label: Text('هزینه‌ها'), icon: Icon(Icons.trending_down)),
                    ButtonSegment<String?>(value: 'income', label: Text('درآمدها'), icon: Icon(Icons.trending_up)),
                  ],
                  // نکته: Set می‌تواند null را نگه دارد و باعث می‌شود «همه» واقعاً selected شود
                  selected: {_selectedDocumentType},
                  onSelectionChanged: (set) {
                    setState(() => _selectedDocumentType = set.first);
                    _refreshData();
                  },
                ),
              ),
              const SizedBox(width: 16),
              // فیلتر پروژه
              Expanded(
                flex: 2,
                child: ProjectSelectorWidget(
                  businessId: widget.businessId,
                  apiClient: widget.apiClient,
                  selectedProjectId: _selectedProjectId,
                  onChanged: (v) async {
                    setState(() {
                      _selectedProjectId = v;
                      _selectedProjectName = null;
                    });
                    await _hydrateSelectedProjectName();
                    _refreshData();
                  },
                  authStore: widget.authStore,
                  calendarController: widget.calendarController,
                  allowNull: true,
                  labelText: 'پروژه',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DateInputField(
                  value: _fromDate,
                  calendarController: widget.calendarController,
                  onChanged: (date) {
                    setState(() {
                      _fromDate = date;
                      if (_fromDate != null && _toDate != null && _fromDate!.isAfter(_toDate!)) {
                        final swap = _fromDate;
                        _fromDate = _toDate;
                        _toDate = swap;
                      }
                    });
                    _refreshData();
                  },
                  labelText: 'از تاریخ',
                  hintText: 'انتخاب تاریخ شروع',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DateInputField(
                  value: _toDate,
                  calendarController: widget.calendarController,
                  onChanged: (date) {
                    setState(() {
                      _toDate = date;
                      if (_fromDate != null && _toDate != null && _fromDate!.isAfter(_toDate!)) {
                        final swap = _fromDate;
                        _fromDate = _toDate;
                        _toDate = swap;
                      }
                    });
                    _refreshData();
                  },
                  labelText: 'تا تاریخ',
                  hintText: 'انتخاب تاریخ پایان',
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  setState(() {
                    _fromDate = null;
                    _toDate = null;
                  });
                  _refreshData();
                },
                icon: const Icon(Icons.clear),
                tooltip: 'پاک کردن فیلتر تاریخ',
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildExternalFilterChips() {
    final theme = Theme.of(context);
    final chips = <Widget>[];

    // نوع سند
    final docLabel = switch (_selectedDocumentType) {
      'income' => 'درآمدها',
      'expense' => 'هزینه‌ها',
      _ => 'همه',
    };
    chips.add(
      InputChip(
        label: Text('نوع: $docLabel'),
        backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        onPressed: _openMobileFiltersSheet,
        onDeleted: _selectedDocumentType == null
            ? null
            : () {
                setState(() => _selectedDocumentType = null);
                _refreshData();
              },
        deleteIcon: const Icon(Icons.close, size: 18),
        deleteButtonTooltipMessage: 'پاک کردن نوع',
      ),
    );

    // بازه تاریخ
    if (_fromDate != null || _toDate != null) {
      final from = _fromDate != null ? _formatDateShort(_fromDate!) : '...';
      final to = _toDate != null ? _formatDateShort(_toDate!) : '...';
      chips.add(
        InputChip(
          label: Text('تاریخ: $from تا $to'),
          backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          onPressed: _openMobileFiltersSheet,
          onDeleted: () {
            setState(() {
              _fromDate = null;
              _toDate = null;
            });
            _refreshData();
          },
          deleteIcon: const Icon(Icons.close, size: 18),
          deleteButtonTooltipMessage: 'پاک کردن بازه تاریخ',
        ),
      );
    }

    if (_selectedProjectId != null) {
      chips.add(
        InputChip(
          label: Text('پروژه: ${_selectedProjectName ?? '#${_selectedProjectId!}'}'),
          backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          onPressed: _openMobileFiltersSheet,
          onDeleted: () {
            setState(() {
              _selectedProjectId = null;
              _selectedProjectName = null;
            });
            _refreshData();
          },
          deleteIcon: const Icon(Icons.close, size: 18),
          deleteButtonTooltipMessage: 'پاک کردن پروژه',
        ),
      );
    }

    return chips;
  }

  bool _hasExternalFiltersActive() {
    return _selectedDocumentType != null || _fromDate != null || _toDate != null || _selectedProjectId != null;
  }

  void _clearExternalFilters() {
    setState(() {
      _selectedDocumentType = null;
      _fromDate = null;
      _toDate = null;
      _selectedProjectId = null;
      _selectedProjectName = null;
    });
  }

  String _formatDateShort(DateTime d) {
    return HesabixDateUtils.formatForDisplay(d, widget.calendarController.isJalali);
  }

  Future<void> _openMobileFiltersSheet() async {
    final theme = Theme.of(context);

    String? tmpType = _selectedDocumentType;
    DateTime? tmpFrom = _fromDate;
    DateTime? tmpTo = _toDate;
    int? tmpProjectId = _selectedProjectId;
    String? tmpProjectName = _selectedProjectName;

    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 12,
                    bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // handle
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
                      Row(
                        children: [
                          const Icon(Icons.tune),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'فیلترها',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                tmpType = null;
                                tmpFrom = null;
                                tmpTo = null;
                                tmpProjectId = null;
                              });
                            },
                            child: const Text('پاک کردن'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String?>(
                        segments: const [
                          ButtonSegment<String?>(value: null, label: Text('همه')),
                          ButtonSegment<String?>(value: 'expense', label: Text('هزینه')),
                          ButtonSegment<String?>(value: 'income', label: Text('درآمد')),
                        ],
                        selected: {tmpType},
                        onSelectionChanged: (set) => setModalState(() => tmpType = set.first),
                      ),
                      const SizedBox(height: 12),
                      DateInputField(
                        value: tmpFrom,
                        calendarController: widget.calendarController,
                        onChanged: (d) => setModalState(() => tmpFrom = d),
                        labelText: 'از تاریخ',
                        hintText: 'انتخاب تاریخ شروع',
                      ),
                      const SizedBox(height: 12),
                      DateInputField(
                        value: tmpTo,
                        calendarController: widget.calendarController,
                        onChanged: (d) => setModalState(() => tmpTo = d),
                        labelText: 'تا تاریخ',
                        hintText: 'انتخاب تاریخ پایان',
                      ),
                      const SizedBox(height: 12),
                      ProjectSelectorWidget(
                        businessId: widget.businessId,
                        apiClient: widget.apiClient,
                        selectedProjectId: tmpProjectId,
                        onChanged: (v) => setModalState(() {
                          tmpProjectId = v;
                          tmpProjectName = null;
                        }),
                        authStore: widget.authStore,
                        calendarController: widget.calendarController,
                        allowNull: true,
                        labelText: 'پروژه',
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('بستن'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('اعمال'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result == true) {
      // normalize date range
      if (tmpFrom != null && tmpTo != null && tmpFrom!.isAfter(tmpTo!)) {
        final swap = tmpFrom;
        tmpFrom = tmpTo;
        tmpTo = swap;
      }
      setState(() {
        _selectedDocumentType = tmpType;
        _fromDate = tmpFrom;
        _toDate = tmpTo;
        _selectedProjectId = tmpProjectId;
        _selectedProjectName = tmpProjectName;
      });
      await _hydrateSelectedProjectName();
      _refreshData();
    }
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
        searchFields: const ['code'],
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
        additionalParams: {
          'document_type': _selectedDocumentType,
          if (_fromDate != null) 'from_date': HesabixDateUtils.formatForApiDate(_fromDate!),
          if (_toDate != null) 'to_date': HesabixDateUtils.formatForApiDate(_toDate!),
          if (_selectedProjectId != null) 'project_id': _selectedProjectId,
        },
        getExportParams: () => {
          'business_id': widget.businessId,
          'document_type': _selectedDocumentType,
          if (_fromDate != null) 'from_date': HesabixDateUtils.formatForApiDate(_fromDate!),
          if (_toDate != null) 'to_date': HesabixDateUtils.formatForApiDate(_toDate!),
          if (_selectedProjectId != null) 'project_id': _selectedProjectId,
        },
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
      getExportParams: () => {
        'business_id': widget.businessId,
        // همیشه document_type را ارسال کن، حتی اگر null باشد
        'document_type': _selectedDocumentType,
        if (_fromDate != null) 'from_date': HesabixDateUtils.formatForApiDate(_fromDate!),
        if (_toDate != null) 'to_date': HesabixDateUtils.formatForApiDate(_toDate!),
        if (_selectedProjectId != null) 'project_id': _selectedProjectId,
      },
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
          searchable: false,
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
      searchFields: ['code', 'created_by_name'],
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
      additionalParams: {
        // همیشه document_type را ارسال کن، حتی اگر null باشد
        'document_type': _selectedDocumentType,
        if (_fromDate != null) 'from_date': HesabixDateUtils.formatForApiDate(_fromDate!),
        if (_toDate != null) 'to_date': HesabixDateUtils.formatForApiDate(_toDate!),
        if (_selectedProjectId != null) 'project_id': _selectedProjectId,
      },
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
      SnackBarHelper.show(ctx, message: 'خطا در بارگذاری جزئیات: $e');
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
      SnackBarHelper.show(ctx, message: 'خطا در آماده‌سازی ویرایش: $e');
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
          message = e.toString();
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
      String message = 'خطا در حذف اسناد';
      if (e is DioException) {
        message = e.message ?? message;
      } else {
        message = e.toString();
      }
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