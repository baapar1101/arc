import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/fiscal_year_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/models/document_model.dart';
import 'package:hesabix_ui/services/document_service.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/utils/number_formatters.dart' show formatWithThousands;
import 'package:hesabix_ui/widgets/document/document_details_dialog.dart';
import 'package:hesabix_ui/widgets/document/document_form_dialog.dart';
import 'package:hesabix_ui/pages/business/documents_mobile_view.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../services/business_dashboard_service.dart';
import '../../models/person_model.dart';
import '../../widgets/project/project_selector_widget.dart';
import '../../widgets/invoice/person_combobox_widget.dart';
import '../../widgets/fx/report_currency_filter_dropdown.dart';
import '../../services/list_filter_preferences_service.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

/// صفحه لیست اسناد حسابداری (عمومی و اتوماتیک)
class DocumentsPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final AuthStore authStore;
  final ApiClient apiClient;

  const DocumentsPage({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.authStore,
    required this.apiClient,
  });

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
  
  /// Static map to store page states by business ID for external refresh
  static final Map<int, _DocumentsPageState> _pageStates = {};
  
  /// Get the page state for a specific business ID
  static _DocumentsPageState? getPageState(int businessId) {
    return _pageStates[businessId];
  }
  
  /// Clear the page state for a specific business ID
  static void clearPageState(int businessId) {
    _pageStates.remove(businessId);
  }
}

class _DocumentsPageState extends State<DocumentsPage> {
  late DocumentService _service;
  late final BusinessDashboardService _dashboardService =
      BusinessDashboardService(widget.apiClient);

  String? _selectedDocumentType;
  DateTime? _fromDate;
  DateTime? _toDate;

  int? _selectedFiscalYearId;
  List<Map<String, dynamic>> _fiscalYears = [];
  bool _fiscalYearsResolved = false;

  int? _selectedProjectId;
  Person? _filterPerson;
  /// null = همه ارزها (فقط وقتی چندارزی فعال است معنا دارد)
  int? _filterCurrencyId;
  bool _currencyFilterTouched = false;

  bool _showDesktopFilters = false;

  final GlobalKey _tableKey = GlobalKey();
  int _selectedCount = 0;
  List<FilterOption> _projectFilterOptions = [];
  bool _loadingProjects = false;

  void _onCalendarChanged() {
    if (!mounted) return;
    // فقط برای رندر مجدد تاریخ‌ها/فیلدهای وابسته به تقویم
    setState(() {});
  }

  Map<String, String> _documentTypeLabels(AppLocalizations t) => {
        'all': t.all,
        'manual': t.documentTypeManual,
        'expense': t.documentTypeExpense,
        'income': t.documentTypeIncome,
        'receipt': t.documentTypeReceipt,
        'payment': t.documentTypePayment,
        'transfer': t.documentTypeTransfer,
        'invoice': t.documentTypeInvoice,
      };

  @override
  void initState() {
    super.initState();
    // Register this page instance for external refresh access
    DocumentsPage._pageStates[widget.businessId] = this;
    _service = DocumentService(widget.apiClient);
    widget.calendarController.addListener(_onCalendarChanged);
    _loadProjects();
    _loadFiscalYears();
  }

  Future<void> _loadFiscalYears() async {
    try {
      final items = await _dashboardService.listFiscalYears(widget.businessId);
      final defaultFyId = await FiscalYearController.resolveDefaultId(widget.businessId, items);
      if (!mounted) return;
      setState(() {
        _fiscalYears = items;
        if (_selectedFiscalYearId == null) {
          _selectedFiscalYearId = defaultFyId;
        }
        _fiscalYearsResolved = true;
      });
    } catch (_) {
      if (mounted) setState(() => _fiscalYearsResolved = true);
    }
  }

  @override
  void dispose() {
    // Clean up the page state when disposed
    DocumentsPage._pageStates.remove(widget.businessId);
    widget.calendarController.removeListener(_onCalendarChanged);
    super.dispose();
  }

  /// بارگذاری لیست پروژه‌ها برای فیلتر
  Future<void> _loadProjects() async {
    if (!mounted) return;
    final t = AppLocalizations.of(context);
    setState(() => _loadingProjects = true);
    
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
              label: p['name'] ?? t.documentProjectValue('${p['id']}'),
              description: p['code'],
            )).toList();
            _loadingProjects = false;
          });
        }
      }
    } catch (e) {
      debugPrint('خطا در بارگذاری پروژه‌ها: $e');
      if (mounted) setState(() => _loadingProjects = false);
    }
  }

  /// تازه‌سازی صریح جدول پس از عملیات روی داده (حذف، ثبت از دیالوگ و غیره).
  /// تغییر فیلترهای بیرونی بدون این فراخوانی هم با `additionalParams` در [DataTableWidget] به‌روز می‌شود.
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
  
  /// Public method to refresh the data table
  void refresh() {
    _refreshData();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final contentPadding = ResponsiveHelper.getPadding(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < ResponsiveHelper.mobileBreakpoint;
        if (isMobile) {
          return DocumentsMobileView(
            businessId: widget.businessId,
            calendarController: widget.calendarController,
            authStore: widget.authStore,
            apiClient: widget.apiClient,
            service: _service,
            onCreateNew: _createNewDocument,
            onShowDetails: _showDocumentDetails,
            onEdit: _editDocument,
            onDelete: _deleteDocument,
            onBulkDelete: _bulkDeleteDocumentsByIds,
          );
        }

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildDesktopHeader(t),
                  _buildFilters(t),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      contentPadding,
                      8,
                      contentPadding,
                      8,
                    ),
                    child: _fiscalYearsResolved
                        ? DataTableWidget<DocumentModel>(
                            key: _tableKey,
                            config: _buildTableConfig(t),
                            fromJson: (json) =>
                                DocumentModel.fromJson(json),
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
        );
      },
    );
  }

  Widget _buildDesktopHeader(AppLocalizations t) {
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
                  t.accountingDocuments,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  t.presetDocumentsList,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _createNewDocument,
            icon: const Icon(Icons.add),
            label: Text(t.add),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(AppLocalizations t) {
    final padding = ResponsiveHelper.getPadding(context);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: padding, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
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
                    Text(_showDesktopFilters ? t.hideFilters : t.filters),
              ),
              if (_hasExternalFiltersActive()) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _clearExternalFilters,
                  icon: const Icon(Icons.clear_all),
                  tooltip: t.clear,
                ),
              ],
            ],
          ),
          if (_showDesktopFilters) ...[
            const SizedBox(height: 10),
            _buildFiltersForm(t),
          ],
        ],
      ),
    );
  }

  bool _hasExternalFiltersActive() {
    return _selectedDocumentType != null ||
        _fromDate != null ||
        _toDate != null ||
        _selectedFiscalYearId != null ||
        _selectedProjectId != null ||
        _filterPerson != null ||
        (_currencyFilterTouched && widget.authStore.isMultiCurrency);
  }

  void _clearExternalFilters() {
    setState(() {
      _selectedDocumentType = null;
      _fromDate = null;
      _toDate = null;
      _selectedProjectId = null;
      _filterPerson = null;
      _filterCurrencyId = null;
      _currencyFilterTouched = false;
    });
  }

  List<Widget> _buildExternalFilterChips(AppLocalizations t) {
    final chips = <Widget>[];

    if (_selectedDocumentType != null) {
      chips.add(Chip(
        label: Text(
            _documentTypeLabels(t)[_selectedDocumentType] ?? _selectedDocumentType!),
        avatar: const Icon(Icons.category_outlined, size: 16),
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
        label: Text(label ?? t.documentProjectValue('$_selectedProjectId')),
        avatar: const Icon(Icons.folder_open, size: 16),
      ));
    }

    if (_filterPerson != null) {
      chips.add(Chip(
        label: Text(_filterPerson!.displayName),
        avatar: const Icon(Icons.person_outline, size: 16),
      ));
    }

    if (widget.authStore.isMultiCurrency && _currencyFilterTouched) {
      chips.add(Chip(
        label: Text(
          _filterCurrencyId == null ? t.allCurrencies : t.documentSelectedCurrency,
        ),
        avatar: const Icon(Icons.currency_exchange, size: 16),
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

  Widget _buildFiltersForm(AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: DropdownButtonFormField<String?>(
            value: _selectedDocumentType,
            decoration: InputDecoration(
              labelText: t.documentType,
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            ),
            items: _documentTypeLabels(t).entries.map((entry) {
              return DropdownMenuItem<String?>(
                value: entry.key == 'all' ? null : entry.key,
                child: Text(entry.value),
              );
            }).toList(),
            onChanged: (value) {
              setState(() => _selectedDocumentType = value);
            },
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_fiscalYears.isNotEmpty)
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<int>(
                  value: _selectedFiscalYearId,
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
                  onChanged: (v) {
                    setState(() => _selectedFiscalYearId = v);
                  },
                ),
              ),
            SizedBox(
              width: 280,
              child: ProjectSelectorWidget(
                businessId: widget.businessId,
                apiClient: widget.apiClient,
                selectedProjectId: _selectedProjectId,
                onChanged: (v) {
                  setState(() => _selectedProjectId = v);
                },
                authStore: widget.authStore,
                calendarController: widget.calendarController,
                allowNull: true,
                labelText: t.documentProject,
              ),
            ),
            SizedBox(
              width: 280,
              child: PersonComboboxWidget(
                businessId: widget.businessId,
                selectedPerson: _filterPerson,
                onChanged: (person) {
                  setState(() => _filterPerson = person);
                },
                label: t.person,
                hintText: t.documentAllPersons,
                searchHint: t.documentSearchPersons,
              ),
            ),
            if (widget.authStore.isMultiCurrency)
              ReportCurrencyFilterDropdown(
                businessId: widget.businessId,
                isMultiCurrency: true,
                selectedCurrencyId: _filterCurrencyId,
                width: 280,
                dense: true,
                onChanged: (id) {
                  setState(() {
                    _filterCurrencyId = id;
                    _currencyFilterTouched = true;
                  });
                  _refreshData();
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DateInputField(
                calendarController: widget.calendarController,
                value: _fromDate,
                onChanged: (date) {
                  setState(() => _fromDate = date);
                },
                labelText: t.dateFrom,
                hintText: t.selectDate,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DateInputField(
                calendarController: widget.calendarController,
                value: _toDate,
                onChanged: (date) {
                  setState(() => _toDate = date);
                },
                labelText: t.dateTo,
                hintText: t.selectDate,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {
                setState(() {
                  _fromDate = null;
                  _toDate = null;
                });
              },
              icon: const Icon(Icons.clear),
              tooltip: t.clearDateFilter,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _bulkDeleteDocumentsByIds(List<int> documentIds) async {
    try {
      final result = await _service.bulkDeleteDocuments(documentIds);
      if (!mounted) return;
      final deletedCount = (result['deleted_count'] as int?) ?? 0;
      final skipped = (result['skipped_auto_documents'] as List?) ?? const [];
      final t = AppLocalizations.of(context);
      String message = t.documentDeletedCount('$deletedCount');
      if (skipped.isNotEmpty) {
        message += '\n${t.documentSkippedAutoCount('${skipped.length}')}';
      }
      SnackBarHelper.show(context, message: message);
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      SnackBarHelper.showError(
        context,
        message: t.documentBulkDeleteError(ErrorExtractor.forContext(e, context)),
      );
    }
  }

  /// ایجاد سند جدید
  Future<void> _createNewDocument() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => DocumentFormDialog(
        businessId: widget.businessId,
        calendarController: widget.calendarController,
        authStore: widget.authStore,
        apiClient: widget.apiClient,
        fiscalYearId: null,
        currencyId: null, // از CurrencyPickerWidget (پیش‌فرض کسب‌وکار) دریافت می‌شود
      ),
    );

    if (result == true) {
      _refreshData();
    }
  }

  /// ساخت تنظیمات جدول
  DataTableConfig<DocumentModel> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<DocumentModel>(
      endpoint: '/businesses/${widget.businessId}/documents',
      businessId: widget.businessId,
      persistTableFiltersPageId: ListFilterPageIds.documentsTable,
      title: t.accountingDocuments,
      excelEndpoint: '/businesses/${widget.businessId}/documents/export/excel',
      customHeaderActions: [
        if (_selectedCount > 0)
          Tooltip(
            message: t.deleteSelected,
            child: FilledButton.icon(
              onPressed: _handleBulkDelete,
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
              ),
              icon: const Icon(Icons.delete_forever),
              label: Text(t.documentDeleteSelectedCount('$_selectedCount')),
            ),
          ),
      ],
      getExportParams: () => {
        'business_id': widget.businessId,
        if (_selectedDocumentType != null)
          'document_type': _selectedDocumentType,
        if (_fromDate != null) 'from_date': HesabixDateUtils.formatForApiDate(_fromDate!),
        if (_toDate != null) 'to_date': HesabixDateUtils.formatForApiDate(_toDate!),
        if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
        if (_selectedProjectId != null) 'project_id': _selectedProjectId,
        if (_filterPerson?.id != null) 'person_id': _filterPerson!.id,
        if (_filterCurrencyId != null) 'currency_id': _filterCurrencyId,
      },
      additionalParams: {
        if (_selectedDocumentType != null)
          'document_type': _selectedDocumentType!,
        if (_fromDate != null)
          'from_date': HesabixDateUtils.formatForApiDate(_fromDate!),
        if (_toDate != null)
          'to_date': HesabixDateUtils.formatForApiDate(_toDate!),
        if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
        if (_selectedProjectId != null) 'project_id': _selectedProjectId,
        if (_filterPerson?.id != null) 'person_id': _filterPerson!.id,
        if (_filterCurrencyId != null) 'currency_id': _filterCurrencyId!,
      },
      columns: [
        // شماره سند
        TextColumn(
          'code',
          t.documentCode,
          width: ColumnWidth.medium,
          formatter: (item) => item.code,
        ),

        // نوع سند
        CustomColumn(
          'document_type',
          t.type,
          width: ColumnWidth.medium,
          builder: (item, index) {
            final doc = item as DocumentModel;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getDocumentTypeColor(doc.documentType).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _getDocumentTypeColor(doc.documentType),
                  width: 1,
                ),
              ),
              child: Text(
                doc.getDocumentTypeName(t),
                style: TextStyle(
                  color: _getDocumentTypeColor(doc.documentType),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          },
        ),

        // تاریخ سند
        TextColumn(
          'document_date',
          t.documentDate,
          width: ColumnWidth.medium,
          // نمایش تاریخ بر اساس تقویم انتخاب‌شده‌ی کاربر در UI (نه متن برگشتی سرور).
          formatter: (item) =>
              HesabixDateUtils.formatForDisplay(item.documentDate, widget.calendarController.isJalali),
        ),

        // سال مالی
        TextColumn(
          'fiscal_year_title',
          t.fiscalYear,
          width: ColumnWidth.medium,
          formatter: (item) => item.fiscalYearTitle ?? '-',
        ),

        // بدهکار
        TextColumn(
          'total_debit',
          t.debit,
          width: ColumnWidth.large,
          formatter: (item) => '${formatWithThousands(item.totalDebit.toInt())} ${item.currencyCode ?? t.documentDefaultCurrency}',
        ),

        // بستانکار
        TextColumn(
          'total_credit',
          t.credit,
          width: ColumnWidth.large,
          formatter: (item) => '${formatWithThousands(item.totalCredit.toInt())} ${item.currencyCode ?? t.documentDefaultCurrency}',
        ),

        // وضعیت
        CustomColumn(
          'is_proforma',
          t.status,
          width: ColumnWidth.small,
          builder: (item, index) {
            final doc = item as DocumentModel;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: doc.isProforma
                    ? SemanticColorResolver.warning(context).withValues(alpha: 0.1)
                    : SemanticColorResolver.positive(context).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                doc.statusText(t),
                style: TextStyle(
                  color: doc.isProforma ? SemanticColorResolver.warning(context) : SemanticColorResolver.positive(context),
                  fontSize: 11,
                ),
              ),
            );
          },
        ),

        // توضیحات
        TextColumn(
          'description',
          t.description,
          width: ColumnWidth.large,
          formatter: (item) => item.description ?? '-',
        ),

        // پروژه
        TextColumn(
          'project_name',
          t.documentProject,
          width: ColumnWidth.medium,
          formatter: (item) => item.projectName ?? '-',
          searchable: true,
          filterType: ColumnFilterType.multiSelect,
          filterOptions: _projectFilterOptions,
        ),

        // ایجاد کننده
        TextColumn(
          'created_by_name',
          t.creatorColumnTitle,
          width: ColumnWidth.medium,
          formatter: (item) {
            final n = item.createdByName?.trim();
            return (n == null || n.isEmpty) ? '-' : n;
          },
        ),

        // عملیات
        ActionColumn(
          'actions',
          t.actions,
          width: ColumnWidth.medium,
          actions: [
            // مشاهده - برای همه اسناد
            DataTableAction(
              icon: Icons.visibility,
              label: t.view,
              onTap: (item) => _showDocumentDetails(item as DocumentModel),
            ),
            // ویرایش - فقط برای manual
            DataTableAction(
              icon: Icons.edit,
              label: t.edit,
              onTap: (item) => _editDocument(item as DocumentModel),
              enabled: true,
            ),
            // حذف - فقط برای manual
            DataTableAction(
              icon: Icons.delete,
              label: t.delete,
              onTap: (item) => _deleteDocument(item as DocumentModel),
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
      pdfEndpoint: '/businesses/${widget.businessId}/documents/export/pdf',
      showPdfExport: true,
      reportModuleKey: 'documents',
      reportSubtype: 'list',
      defaultPageSize: 50,
      pageSizeOptions: [20, 50, 100, 200],
      onRowSelectionChanged: (rows) {
        setState(() {
          _selectedCount = rows.length;
        });
      },
      onRowTap: (item) => _showDocumentDetails(item as DocumentModel),
      expandBodyHeightToFitRows: true,
    );
  }

  /// رنگ بر اساس نوع سند
  Color _getDocumentTypeColor(String type) {
    switch (type) {
      case 'manual':
        return SemanticColorResolver.info(context);
      case 'expense':
        return SemanticColorResolver.negative(context);
      case 'income':
        return SemanticColorResolver.positive(context);
      case 'receipt':
        return Colors.teal;
      case 'payment':
        return SemanticColorResolver.warning(context);
      case 'transfer':
        return Colors.purple;
      case 'invoice':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  /// نمایش جزئیات سند
  Future<void> _showDocumentDetails(DocumentModel doc) async {
    await showDialog(
      context: context,
      builder: (context) => DocumentDetailsDialog(
        documentId: doc.id,
        calendarController: widget.calendarController,
      ),
    );
  }

  /// ویرایش سند
  Future<void> _editDocument(DocumentModel doc) async {
    if (!doc.isEditable) {
      SnackBarHelper.show(context, message: AppLocalizations.of(context).documentOnlyManualEditable);
      return;
    }

    // بارگذاری جزئیات کامل سند (با سطرها)
    try {
      final fullDocument = await _service.getDocument(doc.id);
      
      if (!mounted) return;
      
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => DocumentFormDialog(
          businessId: widget.businessId,
          calendarController: widget.calendarController,
          authStore: widget.authStore,
          apiClient: widget.apiClient,
          document: fullDocument, // حالت ویرایش
          fiscalYearId: fullDocument.fiscalYearId,
          currencyId: fullDocument.currencyId,
        ),
      );

      if (result == true) {
        _refreshData();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: AppLocalizations.of(context).documentLoadError(ErrorExtractor.forContext(e, context)),
        );
      }
    }
  }

  /// حذف سند
  Future<void> _deleteDocument(DocumentModel doc) async {
    if (!doc.isDeletable) {
      SnackBarHelper.show(context, message: AppLocalizations.of(context).documentOnlyManualDeletable);
      return;
    }

    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.documentConfirmDeleteTitle),
        content: Text(t.documentConfirmDeleteBody(doc.code)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: SemanticColorResolver.negative(context),
              foregroundColor: Colors.white,
            ),
            child: Text(t.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _service.deleteDocument(doc.id);
        if (mounted) {
          SnackBarHelper.show(context, message: AppLocalizations.of(context).documentDeleted);
          _refreshData();
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.showError(
            context,
            message: AppLocalizations.of(context).documentDeleteError(ErrorExtractor.forContext(e, context)),
          );
        }
      }
    }
  }

  /// حذف گروهی اسناد
  Future<void> _handleBulkDelete() async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.documentConfirmBulkDeleteTitle),
        content: Text(t.documentConfirmBulkDeleteBody('$_selectedCount')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: SemanticColorResolver.negative(context),
              foregroundColor: Colors.white,
            ),
            child: Text(t.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // دریافت آیتم‌های انتخاب شده از جدول
        final state = _tableKey.currentState;
        if (state != null) {
          // DataTableWidget exposes `getSelectedItems()` (not `getSelectedRows()`).
          final selectedItems =
              List<DocumentModel>.from((state as dynamic).getSelectedItems());
          final documentIds = selectedItems.map((doc) => doc.id).toList();

          if (documentIds.isNotEmpty) {
            final result = await _service.bulkDeleteDocuments(documentIds);

            if (mounted) {
              final deletedCount = result['deleted_count'] as int;
              final skipped = result['skipped_auto_documents'] as List;

              final t = AppLocalizations.of(context);
              String message = t.documentDeletedCount('$deletedCount');
              if (skipped.isNotEmpty) {
                message += '\n${t.documentSkippedAutoCount('${skipped.length}')}';
              }

              SnackBarHelper.show(context, message: message);
              _refreshData();
            }
          }
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.showError(
            context,
            message: AppLocalizations.of(context).documentBulkDeleteError(ErrorExtractor.forContext(e, context)),
          );
        }
      }
    }
  }
}
