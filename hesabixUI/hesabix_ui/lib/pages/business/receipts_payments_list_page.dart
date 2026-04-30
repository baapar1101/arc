import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/models/receipt_payment_document.dart';
import 'package:hesabix_ui/services/receipt_payment_list_service.dart';
import 'package:hesabix_ui/services/invoice_service.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/services/receipt_payment_service.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
// removed duplicate import
import 'package:hesabix_ui/widgets/invoice/invoice_transactions_widget.dart';
import 'package:hesabix_ui/widgets/invoice/check_combobox_widget.dart';
import 'package:hesabix_ui/widgets/banking/currency_picker_widget.dart';
import 'package:hesabix_ui/widgets/project/project_selector_widget.dart';
import 'package:hesabix_ui/utils/number_formatters.dart' show formatWithThousands;
import 'package:hesabix_ui/core/date_utils.dart' show HesabixDateUtils;
import 'package:hesabix_ui/models/invoice_transaction.dart';
import 'package:hesabix_ui/models/invoice_type_model.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';
// removed duplicate import
import 'package:hesabix_ui/models/business_dashboard_models.dart';
import 'package:hesabix_ui/utils/web/web_utils.dart' as web_utils;
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/responsive_helper.dart';
import 'package:hesabix_ui/widgets/money/amount_field_words_tooltip.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import 'package:hesabix_ui/utils/currency_display_utils.dart';
import '../../services/business_dashboard_service.dart';

/// صفحه لیست اسناد دریافت و پرداخت با ویجت جدول
class ReceiptsPaymentsListPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final AuthStore authStore;
  final ApiClient apiClient;

  const ReceiptsPaymentsListPage({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.authStore,
    required this.apiClient,
  });

  @override
  State<ReceiptsPaymentsListPage> createState() => _ReceiptsPaymentsListPageState();
  
  /// Static map to store page states by business ID for external refresh
  static final Map<int, _ReceiptsPaymentsListPageState> _pageStates = {};
  
  /// Get the page state for a specific business ID
  static _ReceiptsPaymentsListPageState? getPageState(int businessId) {
    return _pageStates[businessId];
  }
  
  /// Clear the page state for a specific business ID
  static void clearPageState(int businessId) {
    _pageStates.remove(businessId);
  }
}

class _ReceiptsPaymentsListPageState extends State<ReceiptsPaymentsListPage> {
  late ReceiptPaymentListService _service;
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

  bool _showDesktopFilters = false;

  // کلید کنترل جدول برای دسترسی به selection و refresh
  final GlobalKey _tableKey = GlobalKey();
  int _selectedCount = 0; // تعداد سطرهای انتخاب‌شده
  List<FilterOption> _projectFilterOptions = [];
  bool _loadingProjects = false;

  @override
  void initState() {
    super.initState();
    // Register this page instance for external refresh access
    ReceiptsPaymentsListPage._pageStates[widget.businessId] = this;
    _service = ReceiptPaymentListService(widget.apiClient);
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
    ReceiptsPaymentsListPage._pageStates.remove(widget.businessId);
    super.dispose();
  }

  /// بارگذاری لیست پروژه‌ها برای فیلتر
  Future<void> _loadProjects() async {
    if (!mounted) return;
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
              label: p['name'] ?? 'پروژه ${p['id']}',
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

  /// تازه‌سازی داده‌های جدول
  void _refreshData() {
    if (!mounted) return;
    
    final state = _tableKey.currentState;
    if (state != null) {
      try {
        // استفاده از متد عمومی refresh در ویجت جدول
        // نوت: دسترسی دینامیک چون State کلاس خصوصی است
        // ignore: avoid_dynamic_calls
        (state as dynamic).refresh();
        return;
      } catch (e) {
        // در صورت خطا، با setState تلاش می‌کنیم
        debugPrint('خطا در refresh جدول: $e');
      }
    }
    
    // Fallback: استفاده از setState برای به‌روزرسانی
    if (mounted) {
      setState(() {});
    }
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
                    ? DataTableWidget<ReceiptPaymentDocument>(
                        key: _tableKey,
                        config: _buildTableConfig(t),
                        fromJson: (json) =>
                            ReceiptPaymentDocument.fromJson(json),
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
                  t.receiptsAndPayments,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'مدیریت اسناد دریافت و پرداخت',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          if (!isMobile)
            FilledButton.icon(
              onPressed: _onAddNew,
              icon: const Icon(Icons.add),
              label: Text(t.add),
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
                onPressed: _clearExternalFilters,
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
                  onPressed: _clearExternalFilters,
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
              filterPerson: _filterPerson,
              fromDate: _fromDate,
              toDate: _toDate,
              onDocumentTypeChanged: (v) {
                setState(() => _selectedDocumentType = v);
              },
              onFiscalYearChanged: (v) {
                setState(() => _selectedFiscalYearId = v);
              },
              onProjectChanged: (v) {
                setState(() => _selectedProjectId = v);
              },
              onPersonChanged: (v) {
                setState(() => _filterPerson = v);
              },
              onFromDateChanged: (v) {
                setState(() => _fromDate = v);
              },
              onToDateChanged: (v) {
                setState(() => _toDate = v);
              },
              onClearDateRange: () {
                setState(() {
                  _fromDate = null;
                  _toDate = null;
                });
              },
            ),
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
        _filterPerson != null;
  }

  void _clearExternalFilters() {
    setState(() {
      _selectedDocumentType = null;
      _fromDate = null;
      _toDate = null;
      _selectedProjectId = null;
      _filterPerson = null;
    });
  }

  List<Widget> _buildExternalFilterChips(AppLocalizations t) {
    final chips = <Widget>[];
    if (_selectedDocumentType != null) {
      chips.add(Chip(
        label: Text(_documentTypeChipLabel(t, _selectedDocumentType)),
        avatar: Icon(
          _selectedDocumentType == 'receipt'
              ? Icons.download_done_outlined
              : Icons.upload_outlined,
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

    if (_filterPerson != null) {
      chips.add(Chip(
        label: Text(_filterPerson!.displayName),
        avatar: const Icon(Icons.person_outline, size: 16),
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

  String _documentTypeChipLabel(AppLocalizations t, String? type) {
    switch (type) {
      case 'receipt':
        return t.receipts;
      case 'payment':
        return t.payments;
      default:
        return t.all;
    }
  }

  Future<void> _openMobileFiltersSheet(AppLocalizations t) async {
    String? documentType = _selectedDocumentType;
    int? fiscalYearId = _selectedFiscalYearId;
    int? projectId = _selectedProjectId;
    Person? filterPerson = _filterPerson;
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
                            filterPerson = null;
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
                        filterPerson: filterPerson,
                        fromDate: fromDate,
                        toDate: toDate,
                        onDocumentTypeChanged: (v) =>
                            setModalState(() => documentType = v),
                        onFiscalYearChanged: (v) =>
                            setModalState(() => fiscalYearId = v),
                        onProjectChanged: (v) =>
                            setModalState(() => projectId = v),
                        onPersonChanged: (v) =>
                            setModalState(() => filterPerson = v),
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
      setState(() {
        _selectedDocumentType = documentType;
        _selectedFiscalYearId = fiscalYearId;
        _selectedProjectId = projectId;
        _filterPerson = filterPerson;
        _fromDate = fromDate;
        _toDate = toDate;
      });
    }
  }

  Widget _buildFiltersForm({
    required AppLocalizations t,
    required bool isMobileLayout,
    required String? documentType,
    required int? fiscalYearId,
    required int? projectId,
    required Person? filterPerson,
    required DateTime? fromDate,
    required DateTime? toDate,
    required ValueChanged<String?> onDocumentTypeChanged,
    required ValueChanged<int?> onFiscalYearChanged,
    required ValueChanged<int?> onProjectChanged,
    required ValueChanged<Person?> onPersonChanged,
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
            segments: [
              ButtonSegment<String?>(
                value: null,
                label: Text(t.all),
                icon: const Icon(Icons.all_inclusive),
              ),
              ButtonSegment<String?>(
                value: 'receipt',
                label: Text(t.receipts),
                icon: const Icon(Icons.download_done_outlined),
              ),
              ButtonSegment<String?>(
                value: 'payment',
                label: Text(t.payments),
                icon: const Icon(Icons.upload_outlined),
              ),
            ],
            selected:
                documentType != null ? {documentType} : <String?>{},
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
              child: PersonComboboxWidget(
                businessId: widget.businessId,
                selectedPerson: filterPerson,
                onChanged: onPersonChanged,
                label: 'شخص',
                hintText: 'همه اشخاص',
                searchHint: 'جست‌وجو در اشخاص...',
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

  /// ساخت تنظیمات جدول
  DataTableConfig<ReceiptPaymentDocument> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<ReceiptPaymentDocument>(
      endpoint: '/businesses/${widget.businessId}/receipts-payments',
      title: t.receiptsAndPayments,
      excelEndpoint: '/businesses/${widget.businessId}/receipts-payments/export/excel',
      pdfEndpoint: '/businesses/${widget.businessId}/receipts-payments/export/pdf',
      businessId: widget.businessId,
      reportModuleKey: 'receipts_payments',
      reportSubtype: 'list',
      // دکمه حذف گروهی در هدر جدول
      customHeaderActions: [
        Tooltip(
          message: 'حذف انتخاب‌شده‌ها',
          child: FilledButton.icon(
            onPressed: _selectedCount > 0 ? _onBulkDelete : null,
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            icon: const Icon(Icons.delete_forever),
            label: Text('حذف ($_selectedCount)'),
          ),
        ),
      ],
      getExportParams: () => {
        'business_id': widget.businessId,
        'document_type': _selectedDocumentType,
        if (_fromDate != null) 'from_date': HesabixDateUtils.formatForApiDate(_fromDate!),
        if (_toDate != null) 'to_date': HesabixDateUtils.formatForApiDate(_toDate!),
        if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
        if (_selectedProjectId != null) 'project_id': _selectedProjectId,
        if (_filterPerson?.id != null) 'person_id': _filterPerson!.id,
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
        
        // نام اشخاص
        TextColumn(
          'person_names',
          'اشخاص',
          width: ColumnWidth.medium,
          formatter: (item) => item.personNames ?? 'نامشخص',
        ),
        
        // توضیحات
        TextColumn(
          'description',
          'توضیحات',
          width: ColumnWidth.large,
          formatter: (item) => item.description ?? '',
        ),
        
        // تعداد حساب‌ها
        NumberColumn(
          'account_lines_count',
          'حساب‌ها',
          width: ColumnWidth.small,
          formatter: (item) => item.accountLinesCount.toString(),
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
            DataTableAction(
              icon: Icons.edit,
              label: 'ویرایش',
              onTap: (item) => _onEdit(item),
            ),
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
        setState(() {
          _selectedCount = rows.length;
        });
      },
      additionalParams: {
        'document_type': _selectedDocumentType,
        if (_fromDate != null) 'from_date': HesabixDateUtils.formatForApiDate(_fromDate!),
        if (_toDate != null) 'to_date': HesabixDateUtils.formatForApiDate(_toDate!),
        if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
        if (_selectedProjectId != null) 'project_id': _selectedProjectId,
        if (_filterPerson?.id != null) 'person_id': _filterPerson!.id,
      },
      onRowTap: (item) => _onView(item),
      onRowDoubleTap: (item) => _onEdit(item),
      emptyStateMessage: 'هیچ سند دریافت یا پرداختی یافت نشد',
      loadingMessage: 'در حال بارگذاری اسناد...',
      errorMessage: 'خطا در بارگذاری اسناد',
      expandBodyHeightToFitRows: true,
    );
  }

  /// افزودن سند جدید
  void _onAddNew() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => BulkSettlementDialog(
        businessId: widget.businessId,
        calendarController: widget.calendarController,
        isReceipt: true, // پیش‌فرض دریافت
        businessInfo: widget.authStore.currentBusiness,
        apiClient: widget.apiClient,
        authStore: widget.authStore,
      ),
    );
    
    // اگر سند با موفقیت ثبت شد، جدول را تازه‌سازی کن
    if (result == true) {
      _refreshData();
    }
  }

  /// مشاهده جزئیات سند
  void _onView(ReceiptPaymentDocument document) async {
    try {
      // دریافت جزئیات کامل سند
      final fullDoc = await _service.getById(document.id);
      if (fullDoc == null) {
        if (!mounted) return;
        SnackBarHelper.show(context, message: 'سند یافت نشد');
        return;
      }

      // نمایش دیالوگ مشاهده جزئیات
      if (!context.mounted) return;
      final ctx = context;
      await showDialog(
        context: ctx,
        builder: (_) => ReceiptPaymentViewDialog(
          document: fullDoc,
          calendarController: widget.calendarController,
          businessId: widget.businessId,
          apiClient: widget.apiClient,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: 'خطا در بارگذاری جزئیات: ${ErrorExtractor.forContext(e, context)}',
      );
    }
  }

  /// ویرایش سند
  void _onEdit(ReceiptPaymentDocument document) async {
    try {
      // دریافت جزئیات کامل سند
      final fullDoc = await _service.getById(document.id);
      if (fullDoc == null) {
        if (!mounted) return;
        SnackBarHelper.show(context, message: 'سند یافت نشد');
        return;
      }

      if (!context.mounted) return;
      final ctx = context;
      final result = await showDialog<bool>(
        context: ctx,
        builder: (_) => BulkSettlementDialog(
          businessId: widget.businessId,
          calendarController: widget.calendarController,
          isReceipt: fullDoc.isReceipt,
          businessInfo: widget.authStore.currentBusiness,
          apiClient: widget.apiClient,
          initialDocument: fullDoc,
          authStore: widget.authStore,
        ),
      );

      if (result == true) {
        _refreshData();
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: 'خطا در آماده‌سازی ویرایش: ${ErrorExtractor.forContext(e, context)}',
      );
    }
  }

  /// حذف سند
  ///
  /// تأیید را با [Navigator.pop(ctx, bool)] تمام می‌کنیم و بعد از بسته‌شدن کامل دیالوگ، حذف را اجرا می‌کنیم؛
  /// باز کردن بلافاصلهٔ دیالوگ لودینگ داخل `onPressed` همزمان با بسته‌شدن دیالوگ تأیید باعث ناسازگاری پشتهٔ [Navigator] و صفحهٔ سفید می‌شود.
  Future<void> _onDelete(ReceiptPaymentDocument document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأیید حذف'),
        content: Text('حذف سند ${document.code} غیرقابل بازگشت است. آیا ادامه می‌دهید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _performDelete(document);
  }

  /// انجام عملیات حذف
  Future<void> _performDelete(ReceiptPaymentDocument document) async {
    if (!mounted) return;

    // لودینگ روی root navigator همان‌جایی که showDialog پیش‌فرض قرار می‌گیرد؛ بستن با context صفحه گاهی نزدیک‌ترین Navigator را می‌پَکد و به‌اشتباه مسیر GoRouter را برمی‌دارد (صفحهٔ سفید).
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final success = await _service.delete(document.id);
      if (!mounted) return;

      if (success) {
        // پاک‌سازی شمارنده انتخاب
        setState(() {
          _selectedCount = 0;
        });

        // تازه‌سازی داده‌ها بعد از بستن دیالوگ
        Future.microtask(() {
          if (mounted) {
            _refreshData();
          }
        });

        // نمایش پیام موفقیت
        SnackBarHelper.showSuccess(context, message: 'سند ${document.code} با موفقیت حذف شد');
      } else {
        throw Exception('خطا در حذف سند');
      }
    } catch (e) {
      if (!mounted) return;

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
          // تازه‌سازی داده‌ها در صورت 404
          Future.microtask(() {
            if (mounted) {
              _refreshData();
            }
          });
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
    } finally {
      if (mounted) {
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) nav.pop();
      }
    }
  }

  /// حذف گروهی اسناد انتخاب‌شده
  Future<void> _onBulkDelete() async {
    if (!mounted) return;
    
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
    final docs = selectedItems.cast<ReceiptPaymentDocument>();
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
    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await _service.deleteMultiple(ids);
      if (!mounted) return;

      setState(() {
        _selectedCount = 0;
      });

      Future.microtask(() {
        if (mounted) {
          _refreshData();
        }
      });

      SnackBarHelper.showSuccess(context, message: '${ids.length} سند با موفقیت حذف شد');
    } catch (e) {
      if (!mounted) return;

      String message = 'خطا در حذف اسناد';
      if (e is DioException) {
        message = e.message ?? message;
      } else {
        message = ErrorExtractor.forContext(e, context);
      }
      SnackBarHelper.showError(context, message: message);
    } finally {
      if (mounted) {
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) nav.pop();
      }
    }
  }
}

class BulkSettlementDialog extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final bool isReceipt;
  final BusinessWithPermission? businessInfo;
  final ApiClient apiClient;
  final ReceiptPaymentDocument? initialDocument;
  final AuthStore? authStore;
  const BulkSettlementDialog({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.isReceipt,
    this.businessInfo,
    required this.apiClient,
    this.initialDocument,
    this.authStore,
  });

  @override
  State<BulkSettlementDialog> createState() => _BulkSettlementDialogState();
}

class _BulkSettlementDialogState extends State<BulkSettlementDialog> {
  final _formKey = GlobalKey<FormState>();

  late DateTime _docDate;
  late bool _isReceipt;
  int? _selectedCurrencyId;
  int? _selectedProjectId;
  final TextEditingController _descriptionController = TextEditingController();
  final List<_PersonLine> _personLines = <_PersonLine>[];
  final List<InvoiceTransaction> _centerTransactions = <InvoiceTransaction>[];
  List<Map<String, dynamic>>? _businessCurrenciesCache;
  String _documentCurrencyUnitLabel = 'ریال';
  // استراتژی پیش‌فرض انتخاب قسط جاری برای این کسب‌وکار
  late String _defaultInstallmentSelectionStrategy; // 'first_remaining' | 'nearest_due' | 'prefer_partial'

  @override
  void initState() {
    super.initState();
    // بارگذاری استراتژی پیش‌فرض از localStorage
    final key = 'installment_strategy_${widget.businessId}';
    final storedStrategy = web_utils.getLocalStorageValue(key);
    _defaultInstallmentSelectionStrategy =
        (storedStrategy == 'nearest_due' || storedStrategy == 'prefer_partial')
            ? storedStrategy!
            : 'first_remaining';
    final initial = widget.initialDocument;
    if (initial != null) {
      // حالت ویرایش: پرکردن اولیه از سند
      _isReceipt = initial.isReceipt;
      _docDate = initial.documentDate;
      _selectedCurrencyId = initial.currencyId;
      _selectedProjectId = initial.projectId;
      _descriptionController.text = initial.description ?? '';
      // تبدیل خطوط اشخاص
      _personLines.clear();
      for (final pl in initial.personLines) {
        final extraInfo = pl.extraInfo;
        _personLines.add(
          _PersonLine(
            personId: pl.personId?.toString(),
            personName: pl.personName,
            amount: pl.amount,
            description: pl.description,
            linkToInvoice: extraInfo?['link_to_invoice'] == true,
            invoiceId: extraInfo?['invoice_id'] is int 
                ? extraInfo!['invoice_id'] as int 
                : extraInfo?['invoice_id'] is num
                    ? (extraInfo!['invoice_id'] as num).toInt()
                    : null,
            invoiceCode: extraInfo?['invoice_code']?.toString(),
          ),
        );
      }
      // لود کردن اطلاعات اقساط از extra_info.settlements
      if (initial.extraInfo != null && initial.extraInfo!['settlements'] != null) {
        final settlements = initial.extraInfo!['settlements'] as List<dynamic>?;
        if (settlements != null && settlements.isNotEmpty) {
          for (final st in settlements) {
            final personId = st['person_id'] as int?;
            final invoiceId = st['invoice_id'] as int?;
            final allocations = st['allocations'] as List<dynamic>?;
            if (personId != null && invoiceId != null && allocations != null && allocations.isNotEmpty) {
              // پیدا کردن personLine مربوطه
              final personLineIndex = _personLines.indexWhere((pl) => pl.personId == personId.toString());
              if (personLineIndex >= 0) {
                // تبدیل allocations به Map<int, double>
                final allocMap = <int, double>{};
                for (final al in allocations) {
                  final seq = (al['seq'] as num?)?.toInt();
                  final amount = (al['amount'] as num?)?.toDouble();
                  if (seq != null && amount != null && amount > 0) {
                    allocMap[seq] = amount;
                  }
                }
                if (allocMap.isNotEmpty) {
                  // پیدا کردن قسط جاری (اولین قسط با تخصیص)
                  int? currentSeq;
                  if (allocMap.isNotEmpty) {
                    currentSeq = allocMap.keys.first;
                  }
                  // فعال کردن اقساط و تنظیم اطلاعات
                  _personLines[personLineIndex] = _personLines[personLineIndex].copyWith(
                    installmentsEnabled: true,
                    installmentInvoiceId: invoiceId,
                    installmentAllocations: allocMap,
                    installmentCurrentSeq: currentSeq,
                    installmentSelectionStrategy: _defaultInstallmentSelectionStrategy,
                  );
                  // لود کردن برنامه اقساط برای نمایش (بعد از initState)
                  final lineToLoad = _personLines[personLineIndex];
                  Future.microtask(() async {
                    if (mounted) {
                      await _loadInstallmentPlanForLine(lineToLoad);
                    }
                  });
                }
              }
            }
          }
        }
      }
      // تبدیل خطوط حساب‌ها (حذف خطوط کارمزد)
      _centerTransactions.clear();
      for (final al in initial.accountLines) {
        final isCommission = (al.extraInfo != null && (al.extraInfo!['is_commission_line'] == true));
        if (isCommission) continue;
        final t = TransactionType.fromValue(al.transactionType ?? '') ?? TransactionType.person;
        _centerTransactions.add(
          InvoiceTransaction(
            id: al.id.toString(),
            type: t,
            bankId: al.extraInfo?['bank_id']?.toString(),
            bankName: al.extraInfo?['bank_name']?.toString(),
            cashRegisterId: al.extraInfo?['cash_register_id']?.toString(),
            cashRegisterName: al.extraInfo?['cash_register_name']?.toString(),
            pettyCashId: al.extraInfo?['petty_cash_id']?.toString(),
            pettyCashName: al.extraInfo?['petty_cash_name']?.toString(),
            checkId: al.extraInfo?['check_id']?.toString(),
            checkNumber: al.extraInfo?['check_number']?.toString(),
            personId: al.extraInfo?['person_id']?.toString(),
            personName: al.extraInfo?['person_name']?.toString(),
            accountId: al.accountId.toString(),
            accountName: al.accountName,
            transactionDate: al.transactionDate ?? _docDate,
            amount: al.amount,
            commission: al.commission,
            description: al.description,
          ),
        );
      }
    } else {
      // حالت ایجاد
      _docDate = DateTime.now();
      _isReceipt = widget.isReceipt;
      _selectedCurrencyId = widget.businessInfo?.defaultCurrency?.id;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBusinessCurrenciesForBulkDialog());
  }

  Future<void> _loadBusinessCurrenciesForBulkDialog() async {
    try {
      final list = await CurrencyService(widget.apiClient).listBusinessCurrencies(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _businessCurrenciesCache = list;
        _syncDocumentCurrencyUnitLabel();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _businessCurrenciesCache = null;
        _syncDocumentCurrencyUnitLabel();
      });
    }
  }

  void _syncDocumentCurrencyUnitLabel() {
    var label = currencyUnitLabelForBusinessCurrencyIdOrNull(
      _selectedCurrencyId,
      _businessCurrenciesCache,
    );
    final doc = widget.initialDocument;
    if (label == null &&
        doc != null &&
        doc.currencyId == _selectedCurrencyId &&
        doc.currencyCode != null &&
        doc.currencyCode!.trim().isNotEmpty) {
      label = doc.currencyCode!.trim();
    }
    _documentCurrencyUnitLabel = label ?? 'ریال';
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  static const double _balanceEpsilon = 1e-6;

  double _sumPersons() =>
      _personLines.fold<double>(0, (p, e) => p + e.amount);

  double _sumCenters() => _centerTransactions.fold<double>(
        0,
        (p, e) => p + e.amount.toDouble(),
      );

  /// اختلافی که باید صفر شود (همان [diff] در فوتر).
  double _diffAmount() {
    final sumP = _sumPersons();
    final sumC = _sumCenters();
    return (_isReceipt ? sumC - sumP : sumP - sumC);
  }

  double _allocSumForPersonLine(_PersonLine line) {
    if (line.installmentAllocations == null ||
        line.installmentAllocations!.isEmpty) {
      return 0.0;
    }
    return line.installmentAllocations!.values.fold<double>(
      0,
      (p, e) => p + (e > 0 ? e : 0),
    );
  }

  /// آخرین ردیفی که با افزودن [delta] به مبلغش، مبلغ ≥ ۰ (و در اقساط ≥ جمع تخصیص) می‌ماند.
  int? _personLineIndexForBalanceDelta(double delta) {
    for (int i = _personLines.length - 1; i >= 0; i--) {
      final line = _personLines[i];
      final newAmount = line.amount + delta;
      if (line.installmentsEnabled == true) {
        final asum = _allocSumForPersonLine(line);
        if (newAmount + _balanceEpsilon >= asum) return i;
      } else {
        if (newAmount + _balanceEpsilon >= 0) return i;
      }
    }
    return null;
  }

  void _onBalanceToMatchPeople() {
    if (_centerTransactions.isEmpty) {
      SnackBarHelper.show(
        context,
        message: 'برای تعدیل مطابق اشخاص، حداقل یک ردیف حساب لازم است',
      );
      return;
    }
    final sumP = _sumPersons();
    final sumC = _sumCenters();
    final addToLastCenter = sumP - sumC;
    if (addToLastCenter.abs() < _balanceEpsilon) return;
    final last = _centerTransactions.length - 1;
    final newAmt = _centerTransactions[last].amount.toDouble() + addToLastCenter;
    if (newAmt < -_balanceEpsilon) {
      SnackBarHelper.showError(
        context,
        message: 'مبلغ ردیف آخر حساب پس از تعدیل منفی می‌شود. اختلاف را در چند ردیف تقسیم کنید.',
      );
      return;
    }
    setState(() {
      _centerTransactions[last] =
          _centerTransactions[last].copyWith(amount: newAmt);
    });
  }

  void _onBalanceToMatchAccounts() {
    if (_personLines.isEmpty) {
      SnackBarHelper.show(
        context,
        message: 'برای تعدیل مطابق حساب‌ها، حداقل یک ردیف شخص لازم است',
      );
      return;
    }
    final sumP = _sumPersons();
    final sumC = _sumCenters();
    final addToPerson = sumC - sumP;
    if (addToPerson.abs() < _balanceEpsilon) return;
    final idx = _personLineIndexForBalanceDelta(addToPerson);
    if (idx == null) {
      SnackBarHelper.showError(
        context,
        message:
            'هیچ ردیف اشخاصی قابل تعدیل خودکار نیست (مثلاً مبناهای اقساط اجازه کاهش نمی‌دهد).',
      );
      return;
    }
    setState(() {
      final line = _personLines[idx];
      _personLines[idx] = line.copyWith(amount: line.amount + addToPerson);
    });
  }

  /// دکمه‌های تسویه اختلاف وقتی هر دو طرف ردیف دارند و اختلاف ≠ ۰ است.
  Widget _buildBalanceActionButtons() {
    final d = _diffAmount();
    if (d.abs() < _balanceEpsilon) return const SizedBox.shrink();
    if (_personLines.isEmpty || _centerTransactions.isEmpty) {
      return const SizedBox.shrink();
    }
    final sumP = _sumPersons();
    final sumC = _sumCenters();
    final addToLastCenter = sumP - sumC;
    final last = _centerTransactions.length - 1;
    final canMatchPeople = _centerTransactions[last].amount.toDouble() +
            addToLastCenter >=
        -_balanceEpsilon;
    final addToPerson = sumC - sumP;
    final canMatchAccounts = addToPerson.abs() >= _balanceEpsilon &&
        _personLineIndexForBalanceDelta(addToPerson) != null;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: canMatchPeople ? _onBalanceToMatchPeople : null,
          icon: const Icon(Icons.people, size: 18),
          label: const Text('مطابق اشخاص'),
        ),
        OutlinedButton.icon(
          onPressed: canMatchAccounts ? _onBalanceToMatchAccounts : null,
          icon: const Icon(Icons.account_balance, size: 18),
          label: const Text('مطابق حساب‌ها'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    
    if (isMobile) {
      return _buildMobileLayout();
    } else {
      return _buildDesktopLayout();
    }
  }

  Widget _buildMobileLayout() {
    final t = AppLocalizations.of(context);
    final sumPersons = _personLines.fold<double>(0, (p, e) => p + e.amount);
    final sumCenters = _centerTransactions.fold<double>(0, (p, e) => p + (e.amount.toDouble()));
    final diff = (_isReceipt ? sumCenters - sumPersons : sumPersons - sumCenters).toDouble();
    final padding = ResponsiveHelper.getPadding(context);

    return Dialog(
      insetPadding: EdgeInsets.zero,
      child: SafeArea(
        child: Scaffold(
          appBar: AppBar(
            title: Text(t.receiptsAndPayments),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(padding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.initialDocument == null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: SegmentedButton<bool>(
                              segments: [
                                ButtonSegment<bool>(value: true, label: Text(t.receipts)),
                                ButtonSegment<bool>(value: false, label: Text(t.payments)),
                              ],
                              selected: {_isReceipt},
                              onSelectionChanged: (s) => setState(() => _isReceipt = s.first),
                            ),
                          ),
                        DateInputField(
                          value: _docDate,
                          calendarController: widget.calendarController,
                          onChanged: (d) => setState(() => _docDate = d ?? DateTime.now()),
                          labelText: 'تاریخ سند',
                          hintText: 'انتخاب تاریخ',
                        ),
                        const SizedBox(height: 12),
                        CurrencyPickerWidget(
                          businessId: widget.businessId,
                          selectedCurrencyId: _selectedCurrencyId,
                          onChanged: (currencyId) => setState(() {
                            _selectedCurrencyId = currencyId;
                            _syncDocumentCurrencyUnitLabel();
                          }),
                          label: 'ارز',
                          hintText: 'انتخاب ارز',
                        ),
                        const SizedBox(height: 12),
                        ProjectSelectorWidget(
                          businessId: widget.businessId,
                          apiClient: widget.apiClient,
                          selectedProjectId: _selectedProjectId,
                          onChanged: (projectId) => setState(() => _selectedProjectId = projectId),
                          allowNull: true,
                          labelText: 'پروژه',
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _descriptionController,
                          decoration: const InputDecoration(
                            labelText: 'توضیحات کلی سند',
                            hintText: 'توضیحات اختیاری...',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 2,
                        ),
                        const Divider(height: 32),
                        _PersonsPanel(
                          businessId: widget.businessId,
                          lines: _personLines,
                          onChanged: (ls) {
                            debugPrint('⚫ [BulkSettlementDialog] onChanged - old lines count: ${_personLines.length}, new lines count: ${ls.length}');
                            for (int i = 0; i < ls.length && i < _personLines.length; i++) {
                              if (_personLines[i].amount != ls[i].amount) {
                                debugPrint('⚫ [BulkSettlementDialog] line $i amount changed: ${_personLines[i].amount} -> ${ls[i].amount}');
                              }
                            }
                            setState(() {
                              _personLines.clear();
                              _personLines.addAll(ls);
                            });
                            debugPrint('⚫ [BulkSettlementDialog] after setState - _personLines[0].amount: ${_personLines.isNotEmpty ? _personLines[0].amount : "N/A"}');
                          },
                          calendarController: widget.calendarController,
                          apiClient: widget.apiClient,
                          selectedCurrencyId: _selectedCurrencyId,
                          currencyUnitLabel: _documentCurrencyUnitLabel,
                          isReceipt: _isReceipt,
                        ),
                        const SizedBox(height: 16),
                        Card(
                          elevation: 0,
                          clipBehavior: Clip.antiAlias,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  t.accounts,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                InvoiceTransactionsWidget(
                                  transactions: _centerTransactions,
                                  onChanged: (txs) => setState(() {
                                    _centerTransactions.clear();
                                    _centerTransactions.addAll(txs);
                                  }),
                                  businessId: widget.businessId,
                                  calendarController: widget.calendarController,
                                  invoiceType: InvoiceType.sales,
                                  selectedCurrencyId: _selectedCurrencyId,
                                  checkPickerMode: _isReceipt ? CheckPickerMode.receipt : CheckPickerMode.payment,
                                  authStore: widget.authStore,
                                  shrinkWrapBody: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                // فوتر موبایل
                Padding(
                  padding: EdgeInsets.all(padding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _TotalChip(label: t.people, value: sumPersons),
                          _TotalChip(label: t.accounts, value: sumCenters),
                          _TotalChip(label: 'اختلاف', value: diff, isError: diff != 0),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: _buildBalanceActionButtons(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(t.cancel),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: diff == 0 && _personLines.isNotEmpty && _centerTransactions.isNotEmpty
                                  ? _onSave
                                  : null,
                              icon: const Icon(Icons.save),
                              label: Text(t.save),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    final t = AppLocalizations.of(context);
    final sumPersons = _personLines.fold<double>(0, (p, e) => p + e.amount);
    final sumCenters = _centerTransactions.fold<double>(0, (p, e) => p + (e.amount.toDouble()));
    final diff = (_isReceipt ? sumCenters - sumPersons : sumPersons - sumCenters).toDouble();
    final padding = ResponsiveHelper.getPadding(context);

    return Dialog(
      insetPadding: ResponsiveHelper.getDialogPadding(context),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1400,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // هدر دسکتاپ
              Padding(
                padding: EdgeInsets.fromLTRB(padding, padding, padding, padding / 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.receiptsAndPayments,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (widget.initialDocument == null)
                      SegmentedButton<bool>(
                        segments: [
                          ButtonSegment<bool>(value: true, label: Text(t.receipts)),
                          ButtonSegment<bool>(value: false, label: Text(t.payments)),
                        ],
                        selected: {_isReceipt},
                        onSelectionChanged: (s) => setState(() => _isReceipt = s.first),
                      ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 200,
                      child: DateInputField(
                        value: _docDate,
                        calendarController: widget.calendarController,
                        onChanged: (d) => setState(() => _docDate = d ?? DateTime.now()),
                        labelText: 'تاریخ سند',
                        hintText: 'انتخاب تاریخ',
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 200,
                      child: CurrencyPickerWidget(
                        businessId: widget.businessId,
                        selectedCurrencyId: _selectedCurrencyId,
                        onChanged: (currencyId) => setState(() {
                          _selectedCurrencyId = currencyId;
                          _syncDocumentCurrencyUnitLabel();
                        }),
                        label: 'ارز',
                        hintText: 'انتخاب ارز',
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 200,
                      child: ProjectSelectorWidget(
                        businessId: widget.businessId,
                        apiClient: widget.apiClient,
                        selectedProjectId: _selectedProjectId,
                        onChanged: (projectId) => setState(() => _selectedProjectId = projectId),
                        allowNull: true,
                        labelText: 'پروژه',
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(padding, 0, padding, padding / 2),
                child: TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'توضیحات کلی سند',
                    hintText: 'توضیحات اختیاری...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ),
              const Divider(height: 1),
              // پنل‌ها دسکتاپ
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _PersonsPanel(
                        businessId: widget.businessId,
                        lines: _personLines,
                        onChanged: (ls) {
                          debugPrint('⚫ [BulkSettlementDialog] onChanged - old lines count: ${_personLines.length}, new lines count: ${ls.length}');
                          for (int i = 0; i < ls.length && i < _personLines.length; i++) {
                            if (_personLines[i].amount != ls[i].amount) {
                              debugPrint('⚫ [BulkSettlementDialog] line $i amount changed: ${_personLines[i].amount} -> ${ls[i].amount}');
                            }
                          }
                          setState(() {
                            _personLines.clear();
                            _personLines.addAll(ls);
                          });
                          debugPrint('⚫ [BulkSettlementDialog] after setState - _personLines[0].amount: ${_personLines.isNotEmpty ? _personLines[0].amount : "N/A"}');
                        },
                        calendarController: widget.calendarController,
                        apiClient: widget.apiClient,
                        selectedCurrencyId: _selectedCurrencyId,
                        currencyUnitLabel: _documentCurrencyUnitLabel,
                        isReceipt: _isReceipt,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(padding),
                        child: InvoiceTransactionsWidget(
                          transactions: _centerTransactions,
                          onChanged: (txs) => setState(() {
                            _centerTransactions.clear();
                            _centerTransactions.addAll(txs);
                          }),
                          businessId: widget.businessId,
                          calendarController: widget.calendarController,
                          invoiceType: InvoiceType.sales,
                          selectedCurrencyId: _selectedCurrencyId,
                          checkPickerMode: _isReceipt ? CheckPickerMode.receipt : CheckPickerMode.payment,
                          authStore: widget.authStore,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // فوتر دسکتاپ
              Padding(
                padding: EdgeInsets.fromLTRB(padding, padding / 2, padding, padding),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _TotalChip(label: t.people, value: sumPersons),
                              _TotalChip(label: t.accounts, value: sumCenters),
                              _TotalChip(
                                label: 'اختلاف',
                                value: diff,
                                isError: diff != 0,
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: _buildBalanceActionButtons(),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(t.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: diff == 0 && _personLines.isNotEmpty && _centerTransactions.isNotEmpty
                          ? _onSave
                          : null,
                      icon: const Icon(Icons.save),
                      label: Text(t.save),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onSave() async {
    if (!mounted) return;
    
    // بررسی اعتبارسنجی: اگر سویچ اقساط روشن است، باید فاکتور انتخاب شده باشد
    for (final line in _personLines) {
      if (line.installmentsEnabled == true && line.installmentInvoiceId == null) {
        SnackBarHelper.show(context, message: 'برای ${line.personName ?? 'شخص انتخاب شده'} سویچ اقساط روشن است اما فاکتوری انتخاب نشده است. لطفاً فاکتور را انتخاب کنید یا سویچ اقساط را خاموش کنید.');
        return;
      }
    }
    
    // نمایش loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    
    try {
      final service = ReceiptPaymentService(widget.apiClient);
      
      // تبدیل personLines به فرمت مورد نیاز API
      final personLinesData = _personLines.map((line) {
        final trimmedDesc = line.description?.trim();
        final personLine = <String, dynamic>{
          'person_id': int.parse(line.personId!),
          'person_name': line.personName,
          'amount': line.amount,
          if (trimmedDesc != null && trimmedDesc.isNotEmpty) 'description': trimmedDesc,
        };
        
        // اضافه کردن اطلاعات فاکتور در extra_info
        if (line.linkToInvoice && line.invoiceId != null) {
          personLine['extra_info'] = {
            'invoice_id': line.invoiceId,
            'invoice_code': line.invoiceCode,
            'link_to_invoice': true,
          };
        }
        
        return personLine;
      }).toList();
      
      // تبدیل centerTransactions به فرمت مورد نیاز API
      final accountLinesData = _centerTransactions.map((tx) => {
        'account_id': tx.accountId,
        'amount': tx.amount.toDouble(),
        'transaction_type': tx.type.value,
        'transaction_date': tx.transactionDate.toIso8601String(),
        if (tx.commission != null && tx.commission! > 0)
          'commission': tx.commission!.toDouble(),
        if (tx.description != null && tx.description!.isNotEmpty)
          'description': tx.description,
        // اطلاعات اضافی بر اساس نوع تراکنش
        if (tx.type == TransactionType.bank) ...{
          'bank_id': tx.bankId,
          'bank_name': tx.bankName,
        },
        if (tx.type == TransactionType.cashRegister) ...{
          'cash_register_id': tx.cashRegisterId,
          'cash_register_name': tx.cashRegisterName,
        },
        if (tx.type == TransactionType.pettyCash) ...{
          'petty_cash_id': tx.pettyCashId,
          'petty_cash_name': tx.pettyCashName,
        },
        if (tx.type == TransactionType.check) ...{
          'check_id': tx.checkId,
          'check_number': tx.checkNumber,
        },
        if (tx.type == TransactionType.person) ...{
          'person_id': tx.personId,
          'person_name': tx.personName,
        },
      }).toList();
      
      // ساخت extra_info (تخصیص اقساط بر اساس ردیف‌های شخص)
      Map<String, dynamic>? extraInfo;
      final settlementsPayload = <Map<String, dynamic>>[];
      for (final line in _personLines) {
        if (!(line.installmentsEnabled == true)) continue;
        if (line.installmentInvoiceId == null || (line.installmentAllocations?.isEmpty ?? true)) continue;
        final pidStr = line.personId;
        if (pidStr == null) continue;
        // سقف جمع: مجموع تخصیص‌های همین ردیف ≤ مبلغ ردیف
        final allocSum = line.installmentAllocations!.values.fold<double>(0, (p, e) => p + (e > 0 ? e : 0));
        if (allocSum > (line.amount + 0.0001)) {
          Navigator.pop(context);
          SnackBarHelper.showError(context, message: 'جمع تخصیص اقساط برای ${line.personName ?? ''} از مبلغ خط همان شخص بیشتر است');
          return;
        }
        final allocations = line.installmentAllocations!.entries
            .where((e) => (e.value) > 0)
            .map((e) => {'seq': e.key, 'amount': e.value})
            .toList();
        if (allocations.isEmpty) continue;
        settlementsPayload.add({
          'invoice_id': line.installmentInvoiceId,
          'person_id': int.tryParse(pidStr),
                'allocations': allocations,
        });
              }
      if (settlementsPayload.isNotEmpty) {
        extraInfo = {'settlements': settlementsPayload};
      }
      // اگر initialDocument وجود دارد، حالت ویرایش
      if (widget.initialDocument != null) {
        await service.updateReceiptPayment(
          documentId: widget.initialDocument!.id,
          documentDate: _docDate,
          currencyId: _selectedCurrencyId!,
          description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
          personLines: personLinesData,
          accountLines: accountLinesData,
          projectId: _selectedProjectId,
          extraInfo: extraInfo,
        );
      } else {
        // ایجاد سند جدید
        await service.createReceiptPayment(
          businessId: widget.businessId,
          documentType: _isReceipt ? 'receipt' : 'payment',
          documentDate: _docDate,
          currencyId: _selectedCurrencyId!,
          description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
          personLines: personLinesData,
          accountLines: accountLinesData,
          projectId: _selectedProjectId,
          extraInfo: extraInfo,
        );
      }
      
      if (!mounted) return;
      
      // بستن dialog loading
      Navigator.pop(context);
      
      // بستن dialog اصلی با موفقیت
      Navigator.pop(context, true);
      
      // نمایش پیام موفقیت
      SnackBarHelper.showSuccess(
        context,
        message: widget.initialDocument != null
            ? 'سند با موفقیت ویرایش شد'
            : (_isReceipt ? 'سند دریافت با موفقیت ثبت شد' : 'سند پرداخت با موفقیت ثبت شد'),
      );
    } catch (e) {
      if (!mounted) return;
      
      // بستن dialog loading
      Navigator.pop(context);
      
      // نمایش خطا
      SnackBarHelper.showError(
        context,
        message: 'خطا: ${ErrorExtractor.forContext(e, context)}',
      );
    }
  }

  Future<void> _loadInstallmentPlanForLine(_PersonLine line) async {
    if (line.installmentInvoiceId == null) return;
    try {
      final svc = InvoiceService(apiClient: widget.apiClient);
      final data = await svc.getInstallmentPlan(
        businessId: widget.businessId,
        invoiceId: line.installmentInvoiceId!,
      );
      // بررسی هم‌ارزی ارز سند دریافت با ارز فاکتور اقساطی
      final planCurrencyId = (data['currency_id'] as num?)?.toInt();
      if (_selectedCurrencyId != null && planCurrencyId != null && _selectedCurrencyId != planCurrencyId) {
        if (!mounted) return;
        SnackBarHelper.show(context, message: 'ارز فاکتور اقساط با ارز سند دریافت متفاوت است. لطفاً ارزی همسان انتخاب کنید.');
        final idx = _personLines.indexOf(line);
        if (idx >= 0) {
          final updated = _personLines[idx].copyWith(
            installmentSchedule: const <Map<String, dynamic>>[],
            installmentAllocations: <int, double>{},
            installmentCurrentSeq: null,
        );
        setState(() {
            _personLines[idx] = updated;
        });
        }
        return;
      }
      final plan = (data['plan'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
      final schedule = (plan['schedule'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
      final invoiceCode = (data['invoice_code'] as String?) ?? '';
      // اگر allocations موجود است (حالت ویرایش)، از آن استفاده کن، در غیر این صورت قسط جاری را انتخاب کن
      final existingAllocations = line.installmentAllocations;
      final strategy = line.installmentSelectionStrategy ?? 'first_remaining';
      int? currentSeq;
      double currentRemaining = 0;
      if (strategy == 'nearest_due') {
        DateTime? bestDue;
        for (final it in schedule) {
          final seq = (it['seq'] as num?)?.toInt() ?? 0;
          final total = (it['total'] as num?)?.toDouble() ?? 0;
          final paid = (it['paid_amount'] as num?)?.toDouble() ?? 0;
          final remaining = (it['remaining'] as num?)?.toDouble() ?? (total - paid);
          if (remaining <= 0) continue;
          final dueStr = (it['due_date'] as String?) ?? '';
          DateTime? due;
          try { if (dueStr.isNotEmpty) due = DateTime.parse(dueStr); } catch (_) {}
          if (due != null && (bestDue == null || due.isBefore(bestDue))) {
            bestDue = due;
            currentSeq = seq;
            currentRemaining = remaining;
          }
        }
      } else if (strategy == 'prefer_partial') {
        for (final it in schedule) {
          final seq = (it['seq'] as num?)?.toInt() ?? 0;
          final total = (it['total'] as num?)?.toDouble() ?? 0;
          final paid = (it['paid_amount'] as num?)?.toDouble() ?? 0;
          final remaining = (it['remaining'] as num?)?.toDouble() ?? (total - paid);
          if (paid > 0 && remaining > 0) { currentSeq = seq; currentRemaining = remaining; break; }
        }
        if (currentSeq == null) {
          for (final it in schedule) {
            final seq = (it['seq'] as num?)?.toInt() ?? 0;
            final total = (it['total'] as num?)?.toDouble() ?? 0;
            final paid = (it['paid_amount'] as num?)?.toDouble() ?? 0;
            final remaining = (it['remaining'] as num?)?.toDouble() ?? (total - paid);
            if (remaining > 0) { currentSeq = seq; currentRemaining = remaining; break; }
          }
        }
      } else {
        for (final it in schedule) {
          final seq = (it['seq'] as num?)?.toInt() ?? 0;
          final total = (it['total'] as num?)?.toDouble() ?? 0;
          final paid = (it['paid_amount'] as num?)?.toDouble() ?? 0;
          final remaining = (it['remaining'] as num?)?.toDouble() ?? (total - paid);
          if (seq > 0 && remaining > 0) { currentSeq = seq; currentRemaining = remaining; break; }
        }
      }
      final idx = _personLines.indexOf(line);
      if (idx >= 0) {
        // اگر allocations موجود است (حالت ویرایش)، از آن استفاده کن
        final finalAllocs = existingAllocations?.isNotEmpty == true 
            ? existingAllocations! 
            : (currentSeq != null ? <int, double>{currentSeq: currentRemaining} : <int, double>{});
        // اگر allocations موجود است، currentSeq را از آن بگیر
        final finalCurrentSeq = existingAllocations?.isNotEmpty == true 
            ? existingAllocations!.keys.first 
            : currentSeq;
        var newDesc = _personLines[idx].description;
        if (finalCurrentSeq != null && invoiceCode.isNotEmpty) {
          // توضیح خودکار: قسط N فاکتور CODE
          newDesc = 'قسط $finalCurrentSeq فاکتور $invoiceCode'.trim();
        }
        final updated = _personLines[idx].copyWith(
          installmentSchedule: schedule,
          installmentAllocations: finalAllocs,
          installmentCurrentSeq: finalCurrentSeq,
          installmentInvoiceCode: invoiceCode.isNotEmpty ? invoiceCode : _personLines[idx].installmentInvoiceCode,
          amount: existingAllocations?.isNotEmpty == true 
              ? _personLines[idx].amount  // در حالت ویرایش، مبلغ را تغییر نده
              : (currentSeq != null ? currentRemaining : _personLines[idx].amount),
          description: newDesc,
        );
      setState(() {
          _personLines[idx] = updated;
      });
      }
    } catch (e) {
      if (!mounted) return;
      String message = 'خطا در دریافت اقساط';
      if (e is DioException) {
        final status = e.response?.statusCode;
        if (status == 404) {
          message = 'برای این فاکتور طرح اقساط ثبت نشده است';
          // پاک‌سازی انتخاب اقساط تا UI در حالت ناسازگار نماند
          final idx = _personLines.indexOf(line);
          if (idx >= 0) {
            final updated = _personLines[idx].copyWith(
              installmentSchedule: const <Map<String, dynamic>>[],
              installmentAllocations: <int, double>{},
              installmentCurrentSeq: null,
            );
          setState(() {
              _personLines[idx] = updated;
          });
          }
        } else {
          // تلاش برای استخراج پیام سرور
          final data = e.response?.data;
          final serverMsg = (data is Map && data['error'] is Map && (data['error']['message'] is String))
              ? (data['error']['message'] as String)
              : null;
          if (serverMsg != null && serverMsg.trim().isNotEmpty) {
            message = serverMsg;
          }
        }
      } else {
        message = ErrorExtractor.forContext(e, context);
      }
      SnackBarHelper.show(context, message: message);
    }
  }

  Future<void> _pickInvoiceForLine(_PersonLine line) async {
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _InstallmentInvoicePickerDialog(
        businessId: widget.businessId,
        apiClient: widget.apiClient,
        personId: int.tryParse(line.personId ?? ''),
        personName: line.personName,
        currencyId: _selectedCurrencyId,
        calendarController: widget.calendarController,
      ),
    );
    if (picked != null) {
      final id = picked['id'] as int?;
      final code = (picked['code']?.toString() ?? '').trim();
      if (id != null) {
        final idx = _personLines.indexOf(line);
        if (idx >= 0) {
          setState(() {
            _personLines[idx] = _personLines[idx].copyWith(
              installmentInvoiceId: id,
              installmentInvoiceCode: code.isNotEmpty ? code : _personLines[idx].installmentInvoiceCode,
            );
          });
          await _loadInstallmentPlanForLine(_personLines[idx]);
        }
      }
    }
  }
}

/// دیالوگ انتخاب فاکتور اقساطی با جستجو، debounce، صفحه‌بندی و نمایش مانده/وضعیت
class _InstallmentInvoicePickerDialog extends StatefulWidget {
  final int businessId;
  final ApiClient apiClient;
  final int? personId;
  final String? personName;
  final int? currencyId;
  final CalendarController calendarController;

  const _InstallmentInvoicePickerDialog({
    required this.businessId,
    required this.apiClient,
    this.personId,
    this.personName,
    this.currencyId,
    required this.calendarController,
  });

  @override
  State<_InstallmentInvoicePickerDialog> createState() => _InstallmentInvoicePickerDialogState();
}

class _InstallmentInvoicePickerDialogState extends State<_InstallmentInvoicePickerDialog> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late final InvoiceService _invoiceService;
  List<Map<String, dynamic>> _results = [];
  int _page = 1;
  static const _limit = 20;
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    _invoiceService = InvoiceService(apiClient: widget.apiClient);
    _load(page: 1, reset: true);
    _searchCtrl.addListener(_onSearchChanged);
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      if (mounted) _load(page: 1, reset: true);
    });
  }

  void _onScroll() {
    if (_loadingMore || _loading) return;
    if (_results.length >= _total) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 80) {
      _load(page: _page + 1, reset: false);
    }
  }

  Future<void> _load({required int page, required bool reset}) async {
    if (_loading && reset) return;
    if (_loadingMore && !reset) return;
    if (reset) {
      setState(() => _loading = true);
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final data = await _invoiceService.searchInstallmentInvoices(
        businessId: widget.businessId,
        personId: widget.personId,
        currencyId: widget.currencyId,
        page: page,
        limit: _limit,
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        sortBy: 'remaining_amount',
        sortDesc: true,
      );
      final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final total = (data['total'] as num?)?.toInt() ?? 0;
      if (mounted) {
        setState(() {
          if (reset) {
            _results = items;
            _page = 1;
          } else {
            _results = [..._results, ...items];
            _page = page;
          }
          _total = total;
        });
      }
    } catch (_) {
      if (mounted && reset) setState(() => _results = []);
    } finally {
      if (mounted) setState(() { _loading = false; _loadingMore = false; });
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'paid': return AppLocalizations.of(context)!.installmentsStatusPaid;
      case 'partial': return AppLocalizations.of(context)!.installmentsStatusPartial;
      case 'pending': return AppLocalizations.of(context)!.installmentsStatusPending;
      case 'overdue': return AppLocalizations.of(context)!.installmentsStatusOverdue;
      default: return status ?? '-';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'paid': return Colors.green;
      case 'partial': return Colors.orange;
      case 'pending': return Colors.blue;
      case 'overdue': return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.receipt_long, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(child: Text(t.installmentsInvoicePickerTitle)),
        ],
      ),
      content: SizedBox(
        width: 680,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                labelText: t.installmentsInvoicePickerSearchLabel,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () { _searchCtrl.clear(); _load(page: 1, reset: true); },
                ),
              ),
              onSubmitted: (_) => _load(page: 1, reset: true),
            ),
            if (widget.personName != null) ...[
              const SizedBox(height: 8),
              Chip(
                avatar: const Icon(Icons.person_outline, size: 18),
                label: Text('مشتری: ${widget.personName!}'),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  t.installmentInvoicesCount(_total),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _loading ? null : () => _load(page: 1, reset: true),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(t.search),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading && _results.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_results.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(t.noDataFound, style: Theme.of(context).textTheme.bodyLarge),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView.builder(
                  controller: _scrollCtrl,
                  shrinkWrap: true,
                  itemCount: _results.length + (_loadingMore ? 1 : 0),
                  itemBuilder: (c, i) {
                    if (i >= _results.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )),
                      );
                    }
                    final it = _results[i];
                    final code = (it['code']?.toString() ?? '-');
                    final desc = (it['description']?.toString() ?? '').trim();
                    final docDate = (it['document_date']?.toString() ?? '').split('T').first;
                    final total = (it['total_amount'] is num) ? (it['total_amount'] as num).toDouble() : null;
                    final remaining = (it['remaining_amount'] is num) ? (it['remaining_amount'] as num).toDouble() : null;
                    final currency = (it['currency_code']?.toString() ?? '').trim();
                    final status = it['installment_status']?.toString();
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.receipt_long, color: Colors.green),
                        title: Row(
                          children: [
                            Text(code, style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (currency.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Chip(
                                label: Text(currency),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                            ],
                            if (status != null && status.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _statusColor(status).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _statusLabel(status),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _statusColor(status),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                if (docDate.isNotEmpty) Text('تاریخ: $docDate', style: const TextStyle(fontSize: 12)),
                                if (total != null) Text('مبلغ کل: ${formatWithThousands(total)}', style: const TextStyle(fontSize: 12)),
                                if (remaining != null && remaining > 0)
                                  Text(
                                    '${t.installmentsTableRemaining}: ${formatWithThousands(remaining)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                              ],
                            ),
                            if (desc.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                            ],
                          ],
                        ),
                        isThreeLine: true,
                        onTap: () => Navigator.pop(context, it),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
      ],
    );
  }
}

class _PersonsPanel extends StatefulWidget {
  final int businessId;
  final List<_PersonLine> lines;
  final ValueChanged<List<_PersonLine>> onChanged;
  final CalendarController calendarController;
  final ApiClient apiClient;
  final int? selectedCurrencyId;
  final String currencyUnitLabel;
  final bool isReceipt;
  const _PersonsPanel({
    required this.businessId,
    required this.lines,
    required this.onChanged,
    required this.calendarController,
    required this.apiClient,
    required this.selectedCurrencyId,
    this.currencyUnitLabel = 'ریال',
    required this.isReceipt,
  });

  @override
  State<_PersonsPanel> createState() => _PersonsPanelState();
}

class _PersonsPanelState extends State<_PersonsPanel> {
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final padding = ResponsiveHelper.getPadding(context);
    final spacing = ResponsiveHelper.getGridSpacing(context);

    return Padding(
      padding: EdgeInsets.all(padding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // داخل SingleChildScrollView ارتفاع نامحدود است؛ Expanded اینجا ارتفاع صفر می‌دهد.
          final bool hasBoundedHeight = constraints.maxHeight < double.infinity;

          final listContent = widget.lines.isEmpty
              ? Center(child: Text(t.noDataFound))
              : ListView.separated(
                  shrinkWrap: !hasBoundedHeight,
                  physics: hasBoundedHeight ? null : const NeverScrollableScrollPhysics(),
                  itemCount: widget.lines.length,
                  separatorBuilder: (_, _) => SizedBox(height: spacing),
                  itemBuilder: (ctx, i) {
                    final line = widget.lines[i];
                    return _PersonLineTile(
                      businessId: widget.businessId,
                      line: line,
                      onChanged: (l) {
                        debugPrint('🔴 [PersonsPanel] onChanged called - index: $i, old amount: ${line.amount}, new amount: ${l.amount}');
                        final newLines = List<_PersonLine>.from(widget.lines);
                        newLines[i] = l;
                        debugPrint('🔴 [PersonsPanel] calling widget.onChanged with ${newLines.length} lines');
                        widget.onChanged(newLines);
                      },
                      onDelete: () {
                        final newLines = List<_PersonLine>.from(widget.lines);
                        newLines.removeAt(i);
                        widget.onChanged(newLines);
                      },
                      apiClient: (context.findAncestorStateOfType<_BulkSettlementDialogState>())!.widget.apiClient,
                      calendarController: (context.findAncestorStateOfType<_BulkSettlementDialogState>())!.widget.calendarController,
                      selectedCurrencyId: (context.findAncestorStateOfType<_BulkSettlementDialogState>())!._selectedCurrencyId,
                      currencyUnit: widget.currencyUnitLabel,
                      isReceipt: widget.isReceipt,
                    );
                  },
                );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: hasBoundedHeight ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.people,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      final newLines = List<_PersonLine>.from(widget.lines);
                      newLines.add(_PersonLine.empty());
                      widget.onChanged(newLines);
                    },
                    icon: const Icon(Icons.add),
                    tooltip: t.add,
                  ),
                ],
              ),
              SizedBox(height: spacing),
              if (hasBoundedHeight) Expanded(child: listContent) else listContent,
            ],
          );
        },
      ),
    );
  }
}

class _PersonLineTile extends StatefulWidget {
  final int businessId;
  final _PersonLine line;
  final ValueChanged<_PersonLine> onChanged;
  final VoidCallback onDelete;
  final ApiClient apiClient;
  final CalendarController calendarController;
  final int? selectedCurrencyId;
  final String currencyUnit;
  final bool isReceipt;
  const _PersonLineTile({
    required this.businessId,
    required this.line,
    required this.onChanged,
    required this.onDelete,
    required this.apiClient,
    required this.calendarController,
    required this.selectedCurrencyId,
    this.currencyUnit = 'ریال',
    required this.isReceipt,
  });

  @override
  State<_PersonLineTile> createState() => _PersonLineTileState();
}

class _PersonLineTileState extends State<_PersonLineTile> {
  final _amountController = TextEditingController();
  final _descController = TextEditingController();
  final FocusNode _descFocusNode = FocusNode();
  bool _showInstallmentSchedule = false; // برای نمایش/مخفی کردن لیست اقساط
  List<Map<String, dynamic>> _invoices = [];
  bool _loadingInvoices = false;
  
  // متغیرهای بهینه‌سازی برای جلوگیری از درخواست‌های مکرر
  bool _isLoadingInvoices = false;
  Timer? _loadInvoicesDebounceTimer;
  String? _lastLoadedPersonId;
  
  // Cache برای مانده فاکتورها
  final Map<int, double> _invoiceRemainingCache = {};
  DateTime? _cacheTimestamp;
  static const _cacheValidDuration = Duration(minutes: 5);
  
  // Cache برای لیست receipts-payments (برای استفاده در محاسبه مانده همه فاکتورها)
  Map<String, dynamic>? _cachedReceiptsPaymentsList;
  DateTime? _receiptsPaymentsCacheTimestamp;
  static const _receiptsPaymentsCacheValidDuration = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    final formatted = widget.line.amount == 0 ? '' : formatNumberForInput(widget.line.amount);
    _amountController.text = formatted;
    _descController.text = widget.line.description ?? '';
    // اگر قسط جاری انتخاب شده باشد، لیست را مخفی کن
    _showInstallmentSchedule = widget.line.installmentCurrentSeq == null;
    if (widget.line.linkToInvoice && widget.line.personId != null) {
      debugPrint('🚀 [PersonLineTile] initState - لود فاکتورها (linkToInvoice فعال است)');
      _loadInvoices(force: true);
    }
    debugPrint('🔵 [PersonLineTile] initState - amount: ${widget.line.amount}, formatted: "$formatted", controller.text: "${_amountController.text}"');
  }

  @override
  void dispose() {
    _loadInvoicesDebounceTimer?.cancel();
    _amountController.dispose();
    _descController.dispose();
    _descFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _PersonLineTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // اگر شخص تغییر کرد و لینک فاکتور فعال است، فاکتورها را دوباره لود کن
    // فقط اگر person_id واقعاً تغییر کرده و قبلاً لود نشده باشد
    if (widget.line.linkToInvoice && 
        widget.line.personId != null && 
        widget.line.personId != oldWidget.line.personId &&
        widget.line.personId != _lastLoadedPersonId) {
      debugPrint('🔄 [PersonLineTile] didUpdateWidget - person_id تغییر کرد: ${oldWidget.line.personId} -> ${widget.line.personId}');
      debugPrint('🔄 [PersonLineTile] didUpdateWidget - _lastLoadedPersonId: $_lastLoadedPersonId');
      _loadInvoices(force: true);
    }
    if (oldWidget.line.amount != widget.line.amount) {
      final oldAmount = oldWidget.line.amount;
      final newAmount = widget.line.amount;
      final oldControllerText = _amountController.text;
      final formatted = widget.line.amount == 0 ? '' : formatNumberForInput(widget.line.amount);
      final currentControllerText = _amountController.text;
      final parsedCurrent = parseFormattedDouble(currentControllerText);
      
      debugPrint('🟡 [PersonLineTile] didUpdateWidget - amount changed: $oldAmount -> $newAmount');
      debugPrint('🟡 [PersonLineTile] didUpdateWidget - oldControllerText: "$oldControllerText", formatted: "$formatted"');
      debugPrint('🟡 [PersonLineTile] didUpdateWidget - parsedCurrent: $parsedCurrent, newAmount: $newAmount');
      debugPrint('🟡 [PersonLineTile] didUpdateWidget - selection: ${_amountController.selection}');
      
      // فقط اگر مقدار کنترلر با مقدار جدید متفاوت است، آن را به‌روزرسانی کن
      // این از پاک شدن مقدار هنگام تایپ جلوگیری می‌کند
      if (parsedCurrent != newAmount) {
        _amountController.text = formatted;
        debugPrint('🟡 [PersonLineTile] didUpdateWidget - controller updated to: "$formatted"');
      } else {
        debugPrint('🟡 [PersonLineTile] didUpdateWidget - controller NOT updated (parsedCurrent == newAmount: ${parsedCurrent == newAmount})');
      }
    }
    if (oldWidget.line.description != widget.line.description) {
      final desired = widget.line.description ?? '';
      // هنگام تایپ کاربر، controller.text عملاً همین مقدار است.
      // فقط وقتی برنامه‌وار/از بیرون تغییر کند sync می‌کنیم تا کرسر/متن وسط تایپ reset نشود.
      if (_descController.text != desired) {
        final selection = TextSelection.collapsed(offset: desired.length);
        _descController.value = TextEditingValue(text: desired, selection: selection);
      }
    }
    // اگر قسط جاری انتخاب شده باشد، لیست را مخفی کن
    if (widget.line.installmentCurrentSeq != null && oldWidget.line.installmentCurrentSeq == null) {
      _showInstallmentSchedule = false;
    }
    // اگر invoiceId تغییر کرد، state را به‌روز کن تا dropdown به‌روز شود
    if (oldWidget.line.invoiceId != widget.line.invoiceId) {
      debugPrint('🔄 [PersonLineTile] didUpdateWidget - invoiceId تغییر کرد: ${oldWidget.line.invoiceId} -> ${widget.line.invoiceId}');
      // اگر invoiceId تنظیم شد اما فاکتور در لیست نیست، ممکن است نیاز به لود مجدد باشد
      if (widget.line.invoiceId != null && _invoices.isNotEmpty) {
        final invoiceExists = _invoices.any(
          (inv) => (inv['id'] as num?)?.toInt() == widget.line.invoiceId,
        );
        if (!invoiceExists) {
          debugPrint('⚠️ [PersonLineTile] didUpdateWidget - فاکتور ${widget.line.invoiceId} در لیست نیست، لود مجدد...');
          _loadInvoices(force: true);
        } else {
          debugPrint('✅ [PersonLineTile] didUpdateWidget - فاکتور ${widget.line.invoiceId} در لیست موجود است');
        }
      }
      // force rebuild برای به‌روزرسانی dropdown
      if (mounted) {
        setState(() {});
      }
    }
  }

  /// محاسبه مانده فاکتور بر اساس تراکنش‌های مرتبط
  /// [receiptsPaymentsList] لیست receipts-payments که قبلاً لود شده (اختیاری)
  Future<double> _calculateInvoiceRemaining(
    Map<String, dynamic> invoice, {
    Map<String, dynamic>? receiptsPaymentsList,
  }) async {
    try {
      final invoiceId = (invoice['id'] as num?)?.toInt();
      if (invoiceId == null) return 0;
      
      debugPrint('🔵 [InvoiceRemaining] شروع محاسبه مانده برای فاکتور ID: $invoiceId');
      
      // بررسی cache
      if (_invoiceRemainingCache.containsKey(invoiceId) && 
          _cacheTimestamp != null &&
          DateTime.now().difference(_cacheTimestamp!) < _cacheValidDuration) {
        final cached = _invoiceRemainingCache[invoiceId]!;
        debugPrint('✅ [InvoiceRemaining] استفاده از cache برای فاکتور ID: $invoiceId, مانده: $cached');
        return cached;
      }
      
      debugPrint('⚠️ [InvoiceRemaining] cache موجود نیست یا منقضی شده برای فاکتور ID: $invoiceId');
      
      // دریافت مبلغ کل فاکتور
      final totalAmount = _getInvoiceTotal(invoice);
      
      // دریافت لیست اسناد دریافت/پرداخت مرتبط
      final receiptPaymentService = ReceiptPaymentService(widget.apiClient);
      double totalPaid = 0;
      
      // 1. بررسی از طریق links.receipt_payment_document_ids
      final extraInfo = invoice['extra_info'] as Map<String, dynamic>?;
      if (extraInfo != null) {
        final links = extraInfo['links'] as Map<String, dynamic>?;
        if (links != null) {
          final receiptPaymentIds = links['receipt_payment_document_ids'] as List<dynamic>?;
          if (receiptPaymentIds != null && receiptPaymentIds.isNotEmpty) {
            for (final id in receiptPaymentIds) {
              try {
                final docId = id is int ? id : int.tryParse(id.toString());
                if (docId == null) continue;
                
                final doc = await receiptPaymentService.getById(docId);
                if (doc == null) continue;
                
                // مجموع account_lines (بدون کارمزد)
                for (final accountLine in doc.accountLines) {
                  final isCommission = accountLine.extraInfo?['is_commission_line'] == true;
                  if (!isCommission) {
                    totalPaid += accountLine.amount;
                  }
                }
              } catch (e) {
                // ادامه در صورت خطا
              }
            }
          }
        }
      }
      
      // 2. بررسی از طریق جستجو در اسناد دریافت/پرداخت که invoice_id دارند
      try {
        List<dynamic> items;
        
        // اگر لیست receipts-payments از قبل لود شده، از آن استفاده کن
        if (receiptsPaymentsList != null) {
          debugPrint('✅ [InvoiceRemaining] استفاده از لیست receipts-payments از قبل لود شده برای فاکتور ID: $invoiceId');
          items = (receiptsPaymentsList['items'] as List<dynamic>?) ?? [];
        } else {
          // در غیر این صورت، لود کن (این حالت نباید اتفاق بیفتد اگر از _loadInvoices استفاده شود)
          debugPrint('🚨 [InvoiceRemaining] ارسال درخواست POST به receipts-payments برای فاکتور ID: $invoiceId (لیست از قبل لود نشده)');
          debugPrint('🚨 [InvoiceRemaining] businessId: ${widget.businessId}, skip: 0, take: 1000');
          final receiptPaymentList = await receiptPaymentService.listReceiptsPayments(
            businessId: widget.businessId,
            skip: 0,
            take: 1000,
          );
          debugPrint('✅ [InvoiceRemaining] پاسخ دریافت شد برای فاکتور ID: $invoiceId, تعداد آیتم‌ها: ${(receiptPaymentList['items'] as List<dynamic>?)?.length ?? 0}');
          items = (receiptPaymentList['items'] as List<dynamic>?) ?? [];
        }
        final Set<int> processedDocIds = {};
        
        // محاسبه receipt_payment_document_ids برای جلوگیری از تکرار
        if (extraInfo != null) {
          final links = extraInfo['links'] as Map<String, dynamic>?;
          if (links != null) {
            final receiptPaymentIds = links['receipt_payment_document_ids'] as List<dynamic>?;
            if (receiptPaymentIds != null) {
              for (final id in receiptPaymentIds) {
                final docId = id is int ? id : int.tryParse(id.toString());
                if (docId != null) {
                  processedDocIds.add(docId);
                }
              }
            }
          }
        }
        
        for (final item in items) {
          try {
            final docId = (item['id'] as num?)?.toInt();
            if (docId == null || processedDocIds.contains(docId)) continue;
            
            // بررسی person_lines برای invoice_id
            final personLines = item['person_lines'] as List<dynamic>?;
            if (personLines == null) continue;
            
            bool hasInvoiceLink = false;
            for (final pl in personLines) {
              final plExtraInfo = pl['extra_info'] as Map<String, dynamic>?;
              if (plExtraInfo != null) {
                final plInvoiceId = plExtraInfo['invoice_id'];
                if (plInvoiceId is int && plInvoiceId == invoiceId) {
                  hasInvoiceLink = true;
                  break;
                } else if (plInvoiceId is num && plInvoiceId.toInt() == invoiceId) {
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
            
            // مجموع account_lines (بدون کارمزد)
            for (final accountLine in doc.accountLines) {
              final isCommission = accountLine.extraInfo?['is_commission_line'] == true;
              if (!isCommission) {
                totalPaid += accountLine.amount;
              }
            }
          } catch (e) {
            // ادامه در صورت خطا
          }
        }
      } catch (e) {
        // در صورت خطا در جستجو، فقط از links استفاده می‌کنیم
      }
      
      final remaining = totalAmount - totalPaid;
      
      debugPrint('💰 [InvoiceRemaining] محاسبه مانده برای فاکتور ID: $invoiceId - کل: $totalAmount, پرداخت شده: $totalPaid, مانده: $remaining');
      
      // ذخیره در cache
      _invoiceRemainingCache[invoiceId] = remaining;
      _cacheTimestamp = DateTime.now();
      
      debugPrint('💾 [InvoiceRemaining] ذخیره در cache برای فاکتور ID: $invoiceId');
      
      return remaining;
    } catch (e) {
      return 0;
    }
  }

  /// استخراج مبلغ کل فاکتور
  double _getInvoiceTotal(Map<String, dynamic> invoice) {
    try {
      // اول از total_amount
      if (invoice['total_amount'] != null) {
        final total = invoice['total_amount'];
        if (total is num) return total.toDouble();
        if (total is String) return double.tryParse(total) ?? 0;
      }
      
      // سپس از extra_info.totals.net
      final extraInfo = invoice['extra_info'] as Map<String, dynamic>?;
      if (extraInfo != null) {
        final totals = extraInfo['totals'] as Map<String, dynamic>?;
        if (totals != null && totals['net'] != null) {
          final net = totals['net'];
          if (net is num) return net.toDouble();
          if (net is String) return double.tryParse(net) ?? 0;
        }
      }
      
      // در نهایت از total
      if (invoice['total'] != null) {
        final total = invoice['total'];
        if (total is num) return total.toDouble();
        if (total is String) return double.tryParse(total) ?? 0;
      }
      
      return 0;
    } catch (e) {
      return 0;
    }
  }

  Future<void> _loadInvoices({bool force = false}) async {
    debugPrint('📥 [LoadInvoices] فراخوانی _loadInvoices - force: $force, personId: ${widget.line.personId}, _lastLoadedPersonId: $_lastLoadedPersonId, _isLoadingInvoices: $_isLoadingInvoices');
    
    if (widget.line.personId == null) {
      debugPrint('❌ [LoadInvoices] personId null است، خروج');
      return;
    }
    
    // اگر در حال لود است و force نیست، صبر کن
    if (_isLoadingInvoices && !force) {
      debugPrint('⏸️ [LoadInvoices] در حال لود است و force نیست، صبر می‌کنیم');
      return;
    }
    
    // اگر person_id تغییر نکرده و force نیست، نیازی به لود مجدد نیست
    if (!force && _lastLoadedPersonId == widget.line.personId) {
      debugPrint('⏭️ [LoadInvoices] person_id تغییر نکرده و force نیست، نیازی به لود مجدد نیست');
      return;
    }
    
    // Cancel timer قبلی
    _loadInvoicesDebounceTimer?.cancel();
    debugPrint('⏱️ [LoadInvoices] timer قبلی cancel شد، شروع timer جدید (300ms)');
    
    // Debounce: صبر کن 300ms قبل از لود
    _loadInvoicesDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      debugPrint('⏰ [LoadInvoices] timer فعال شد - force: $force, personId: ${widget.line.personId}');
      
      if (widget.line.personId == null) {
        debugPrint('❌ [LoadInvoices] personId null است در timer callback، خروج');
        return;
      }
      
      // اگر در حال لود است و force نیست، صبر کن
      if (_isLoadingInvoices && !force) {
        debugPrint('⏸️ [LoadInvoices] در حال لود است و force نیست در timer callback، صبر می‌کنیم');
        return;
      }
      
      // اگر person_id تغییر نکرده و force نیست، نیازی به لود مجدد نیست
      if (!force && _lastLoadedPersonId == widget.line.personId) {
        debugPrint('⏭️ [LoadInvoices] person_id تغییر نکرده و force نیست در timer callback، نیازی به لود مجدد نیست');
        return;
      }
      
      debugPrint('🔄 [LoadInvoices] شروع لود فاکتورها - personId: ${widget.line.personId}');
      
      setState(() {
        _isLoadingInvoices = true;
        _loadingInvoices = true;
      });

      try {
        final invoiceService = InvoiceService(apiClient: widget.apiClient);
        
        // تعیین نوع فاکتورهای مناسب
        final List<String> invoiceTypes;
        if (widget.isReceipt) {
          // برای دریافت: فاکتورهای فروش و برگشت از خرید
          invoiceTypes = ['invoice_sales', 'invoice_purchase_return'];
        } else {
          // برای پرداخت: فاکتورهای خرید و برگشت از فروش
          invoiceTypes = ['invoice_purchase', 'invoice_sales_return'];
        }

        final filters = <String, dynamic>{
          'document_type': invoiceTypes,
          'person_id': int.tryParse(widget.line.personId!) ?? 0,
          'is_proforma': false, // فقط فاکتورهای قطعی
        };
        
        // اضافه کردن فیلتر ارز اگر انتخاب شده باشد
        if (widget.selectedCurrencyId != null) {
          filters['currency_id'] = widget.selectedCurrencyId;
        }

        debugPrint('🔍 [LoadInvoices] ارسال درخواست searchInvoices - businessId: ${widget.businessId}, filters: $filters');
        
        final result = await invoiceService.searchInvoices(
          businessId: widget.businessId,
          page: 1,
          limit: 100,
          filters: filters,
        );
        
        debugPrint('✅ [LoadInvoices] پاسخ searchInvoices دریافت شد - تعداد فاکتورها: ${(result['items'] as List<dynamic>?)?.length ?? 0}');

        if (mounted) {
          final items = (result['items'] as List<dynamic>?)
              ?.map((item) => Map<String, dynamic>.from(item as Map))
              .toList() ?? [];
          
          // لاگ فاکتورهای دریافت شده
          final itemIds = items.map((item) => (item['id'] as num?)?.toInt()).whereType<int>().toList();
          debugPrint('📋 [LoadInvoices] فاکتورهای دریافت شده از searchInvoices (IDs): $itemIds');
          
          debugPrint('📊 [LoadInvoices] شروع محاسبه مانده برای ${items.length} فاکتور');
          
          // استخراج invoice_ids
          final invoiceIds = items
              .map((item) => (item['id'] as num?)?.toInt())
              .whereType<int>()
              .toList();
          
          debugPrint('📋 [LoadInvoices] فاکتورهای دریافت شده از searchInvoices: $invoiceIds');
          
          // محاسبه مانده برای همه فاکتورها در یک درخواست
          Map<int, double> remainingMap = {};
          if (invoiceIds.isNotEmpty) {
            debugPrint('🔄 [LoadInvoices] محاسبه مانده برای ${invoiceIds.length} فاکتور در یک درخواست - invoiceIds: $invoiceIds');
            
            try {
              final remainingResult = await invoiceService.calculateInvoicesRemaining(
                businessId: widget.businessId,
                invoiceIds: invoiceIds,
              );
              
              debugPrint('📥 [LoadInvoices] پاسخ calculateInvoicesRemaining دریافت شد: $remainingResult');
              
              final results = remainingResult['results'] as Map<String, dynamic>? ?? {};
              final errors = remainingResult['errors'] as Map<String, dynamic>? ?? {};
              
              debugPrint('📊 [LoadInvoices] تعداد نتایج: ${results.length}, تعداد خطاها: ${errors.length}');
              debugPrint('📊 [LoadInvoices] کلیدهای results: ${results.keys.toList()}');
              
              for (final entry in results.entries) {
                final invoiceId = int.tryParse(entry.key);
                final data = entry.value as Map<String, dynamic>;
                if (invoiceId != null && data['remaining'] != null) {
                  remainingMap[invoiceId] = (data['remaining'] as num).toDouble();
                  debugPrint('✅ [LoadInvoices] مانده برای فاکتور $invoiceId: ${remainingMap[invoiceId]}');
                } else {
                  debugPrint('⚠️ [LoadInvoices] خطا در پردازش نتیجه - key: ${entry.key}, invoiceId: $invoiceId, data: $data');
                }
              }
              
              if (errors.isNotEmpty) {
                debugPrint('⚠️ [LoadInvoices] خطا در محاسبه مانده ${errors.length} فاکتور: $errors');
              }
              
              debugPrint('✅ [LoadInvoices] مانده ${remainingMap.length} فاکتور محاسبه شد');
            } catch (e) {
              debugPrint('❌ [LoadInvoices] خطا در محاسبه مانده: $e');
              // در صورت خطا، از متد قدیمی استفاده می‌کنیم (fallback)
              debugPrint('🔄 [LoadInvoices] استفاده از fallback برای محاسبه مانده');
              for (final invoice in items) {
                final invoiceId = (invoice['id'] as num?)?.toInt();
                if (invoiceId != null) {
                  try {
                    final remaining = await _calculateInvoiceRemaining(invoice);
                    remainingMap[invoiceId] = remaining;
                  } catch (e) {
                    debugPrint('❌ [LoadInvoices] خطا در محاسبه مانده فاکتور $invoiceId: $e');
                  }
                }
              }
            }
          }
          
          // فیلتر کردن فاکتورهای تسویه شده
          final List<Map<String, dynamic>> validInvoices = [];
          debugPrint('🔍 [LoadInvoices] شروع فیلتر کردن ${items.length} فاکتور');
          for (final invoice in items) {
            final invoiceId = (invoice['id'] as num?)?.toInt();
            if (invoiceId == null) {
              debugPrint('⚠️ [LoadInvoices] فاکتور بدون ID رد شد');
              continue;
            }
            
            final remaining = remainingMap[invoiceId] ?? 0.0;
            debugPrint('🔍 [LoadInvoices] فاکتور ID: $invoiceId, remaining: $remaining, remainingMap.containsKey: ${remainingMap.containsKey(invoiceId)}');
            
            // فقط فاکتورهایی که مانده > 0 دارند (تسویه نشده‌اند)
            if (remaining > 0.01) { // tolerance برای خطای ممیز شناور
              validInvoices.add({
                ...invoice,
                '_remaining': remaining,
              });
              debugPrint('✅ [LoadInvoices] فاکتور ID: $invoiceId با مانده $remaining اضافه شد');
            } else {
              debugPrint('⏭️ [LoadInvoices] فاکتور ID: $invoiceId با مانده $remaining رد شد (تسویه شده یا مانده محاسبه نشده)');
            }
          }
          
          debugPrint('📊 [LoadInvoices] فیلتر تمام شد - ${validInvoices.length} فاکتور معتبر از ${items.length} فاکتور');
          
          debugPrint('📊 [LoadInvoices] محاسبه مانده تمام شد - ${validInvoices.length} فاکتور معتبر از ${items.length} فاکتور');
          
          // ذخیره person_id برای جلوگیری از لود مجدد
          _lastLoadedPersonId = widget.line.personId;
          debugPrint('💾 [LoadInvoices] ذخیره _lastLoadedPersonId: $_lastLoadedPersonId');
          
          setState(() {
            _invoices = validInvoices;
          });
          
          debugPrint('✅ [LoadInvoices] لود فاکتورها تمام شد - ${validInvoices.length} فاکتور نمایش داده می‌شود');
        }
      } catch (e) {
        debugPrint('❌ [LoadInvoices] خطا در لود فاکتورها: $e');
        if (mounted) {
          setState(() {
            _invoices = [];
          });
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoadingInvoices = false;
            _loadingInvoices = false;
          });
          debugPrint('🏁 [LoadInvoices] لود فاکتورها تمام شد (finally)');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: PersonComboboxWidget(
                    businessId: widget.businessId,
                    showFinancialBalance: true,
                    selectedPerson: widget.line.personId != null 
                        ? Person(
                            id: int.tryParse(widget.line.personId!),
                            businessId: widget.businessId,
                            aliasName: widget.line.personName ?? '',
                            personTypes: const [],
                            createdAt: DateTime.now(),
                            updatedAt: DateTime.now(),
                          )
                        : null,
                    onChanged: (opt) {
                      widget.onChanged(widget.line.copyWith(
                        personId: opt?.id?.toString(), 
                        personName: opt?.displayName,
                        // اگر شخص تغییر کرد و لینک فاکتور فعال است، فاکتورها را reset کن
                        invoiceId: opt == null ? null : widget.line.invoiceId,
                        invoiceCode: opt == null ? null : widget.line.invoiceCode,
                      ));
                      // اگر شخص انتخاب شد و لینک فاکتور فعال است، فاکتورها را لود کن
                      // فقط اگر person_id تغییر کرده باشد
                      if (opt != null && widget.line.linkToInvoice && opt.id?.toString() != _lastLoadedPersonId) {
                        debugPrint('👤 [PersonLineTile] onChanged PersonCombobox - شخص جدید انتخاب شد: ${opt.id}, _lastLoadedPersonId: $_lastLoadedPersonId');
                        Future.microtask(() => _loadInvoices(force: true));
                      } else {
                        debugPrint('⏭️ [PersonLineTile] onChanged PersonCombobox - شخص تغییر نکرده یا لینک فاکتور غیرفعال است');
                      }
                    },
                    label: t.people,
                    hintText: t.search,
                    isRequired: true,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 180,
                  child: AmountFieldWordsTooltip(
                    controller: _amountController,
                    currencyUnit: widget.currencyUnit,
                    child: TextFormField(
                      controller: _amountController,
                      decoration: InputDecoration(
                        labelText: t.amount,
                        hintText: '1,000,000',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        EnglishDigitsFormatter(),
                        ThousandsSeparatorInputFormatter(allowDecimal: false),
                      ],
                      validator: (v) {
                        final val = parseFormattedDouble(v);
                        debugPrint('🟢 [PersonLineTile] validator - input: "$v", parsed: $val');
                        if (val == null || val <= 0) return t.mustBePositiveNumber;
                        return null;
                      },
                      onChanged: (v) {
                        final controllerTextBefore = _amountController.text;
                        final parsed = parseFormattedDouble(v);
                        final val = parsed ?? 0;
                        debugPrint('🟠 [PersonLineTile] onChanged - input: "$v", controller.text before: "$controllerTextBefore", parsed: $parsed, final val: $val, old line.amount: ${widget.line.amount}');
                        widget.onChanged(widget.line.copyWith(amount: val));
                        debugPrint('🟣 [PersonLineTile] onChanged - after widget.onChanged, controller.text: "${_amountController.text}"');
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descController,
              focusNode: _descFocusNode,
              decoration: InputDecoration(
                labelText: t.description,
              ),
              // IMPORTANT: اینجا trim نکن تا هر keypress باعث sync مجدد controller و reset شدن کرسر نشود.
              // trim را موقع ذخیره‌سازی/ارسال به API انجام می‌دهیم.
              onChanged: (v) => widget.onChanged(widget.line.copyWith(description: v.trim().isEmpty ? null : v)),
            ),
            const SizedBox(height: 8),
            // سوئیچ لینک به فاکتور (فقط برای اسناد غیراقساطی)
            SwitchListTile(
              title: const Text('لینک به فاکتور'),
              subtitle: Text(widget.isReceipt 
                  ? 'این دریافت را به فاکتور فروش مرتبط کن (قابل استفاده نیست اگر اقساط فعال باشد)'
                  : 'این پرداخت را به فاکتور خرید مرتبط کن'),
              value: widget.line.linkToInvoice,
              onChanged: (widget.line.personId != null && !widget.line.installmentsEnabled)
                  ? (value) {
                      if (value && widget.line.installmentsEnabled) {
                        // نباید همزمان فعال شود
                        SnackBarHelper.show(context, message: 'نمی‌توان همزمان لینک به فاکتور و اقساط را فعال کرد. لطفاً ابتدا اقساط را غیرفعال کنید.');
                        return;
                      }
                      widget.onChanged(widget.line.copyWith(
                        linkToInvoice: value,
                        invoiceId: value ? null : null,
                        invoiceCode: value ? null : null,
                      ));
                      if (value) {
                        debugPrint('🔘 [PersonLineTile] onChanged SwitchListTile - لینک به فاکتور فعال شد');
                        _loadInvoices(force: true);
                      } else {
                        debugPrint('🔘 [PersonLineTile] onChanged SwitchListTile - لینک به فاکتور غیرفعال شد');
                      }
                    }
                  : null,
            ),
            // Dropdown انتخاب فاکتور (فقط اگر سوئیچ فعال باشد)
            if (widget.line.linkToInvoice && widget.line.personId != null) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: widget.line.invoiceId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'فاکتور',
                  hintText: _loadingInvoices ? 'در حال بارگذاری...' : 'انتخاب فاکتور',
                  border: const OutlineInputBorder(),
                ),
                items: _loadingInvoices
                    ? [
                        const DropdownMenuItem<int>(
                          value: null,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      ]
                    : _invoices.map((invoice) {
                        final id = (invoice['id'] as num?)?.toInt();
                        final code = invoice['code']?.toString() ?? '';
                        final total = _getInvoiceTotal(invoice);
                        final remaining = (invoice['_remaining'] as num?)?.toDouble() ?? (total - 0);
                        final dateStr = invoice['document_date']?.toString();
                        final date = dateStr != null ? DateTime.tryParse(dateStr) : null;
                        final dateDisplay = date != null ? HesabixDateUtils.formatForDisplay(date, true) : '';
                        
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                code,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                dateDisplay.isNotEmpty 
                                    ? 'تاریخ: $dateDisplay'
                                    : '',
                                style: Theme.of(context).textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'مبلغ کل: ${formatWithThousands(total)}',
                                style: Theme.of(context).textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'مانده: ${formatWithThousands(remaining)}',
                                style: TextStyle(
                                  color: remaining > 0 
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                selectedItemBuilder: (context) {
                  // الزام Flutter: طول لیست برگشتی باید دقیقاً برابر items باشد؛
                  // ویجت در ایندکس i وقتی نمایش داده می‌شود که items[i] انتخاب شده باشد.
                  debugPrint('🔄 [PersonLineTile] selectedItemBuilder - invoiceId: ${widget.line.invoiceId}, تعداد فاکتورها: ${_invoices.length}');
                  if (_loadingInvoices) {
                    return [
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    ];
                  }
                  return _invoices.map((inv) {
                    final code = inv['code']?.toString() ?? '';
                    return Text(
                      code.isNotEmpty ? code : 'فاکتور',
                      overflow: TextOverflow.ellipsis,
                    );
                  }).toList();
                },
                onChanged: (invoiceId) {
                  debugPrint('🔄 [PersonLineTile] onChanged - انتخاب فاکتور: $invoiceId');
                  if (invoiceId == null) {
                    debugPrint('⚠️ [PersonLineTile] onChanged - invoiceId null است!');
                    return;
                  }
                  final invoice = _invoices.firstWhere(
                    (inv) => (inv['id'] as num?)?.toInt() == invoiceId,
                    orElse: () => <String, dynamic>{},
                  );
                  if (invoice.isEmpty) {
                    debugPrint('⚠️ [PersonLineTile] onChanged - فاکتور $invoiceId در لیست پیدا نشد!');
                    return;
                  }
                  final invoiceCode = invoice['code']?.toString();
                  debugPrint('🔄 [PersonLineTile] onChanged - فاکتور پیدا شد: $invoiceCode');
                  debugPrint('🔄 [PersonLineTile] onChanged - widget.line.invoiceId قبل از تغییر: ${widget.line.invoiceId}');
                  widget.onChanged(widget.line.copyWith(
                    invoiceId: invoiceId,
                    invoiceCode: invoiceCode,
                  ));
                  debugPrint('🔄 [PersonLineTile] onChanged - widget.onChanged فراخوانی شد با invoiceId: $invoiceId, invoiceCode: $invoiceCode');
                  // توجه: widget.line.invoiceId هنوز به‌روز نشده است چون state در parent به‌روز نشده
                  // بعد از rebuild و didUpdateWidget، widget.line.invoiceId به‌روز می‌شود
                },
              ),
            ],
            // بخش اقساط فقط برای اسناد دریافت نمایش داده می‌شود
            if (widget.isReceipt) ...[
              const SizedBox(height: 8),
              // سطر اول: سویچ اقساط و انتخاب فاکتور
              Row(
                children: [
                  Switch(
                    value: widget.line.installmentsEnabled,
                    onChanged: (enabled) {
                      if (enabled && widget.line.linkToInvoice) {
                        // نباید همزمان فعال شود
                        SnackBarHelper.show(context, message: 'نمی‌توان همزمان اقساط و لینک به فاکتور را فعال کرد. لطفاً ابتدا لینک به فاکتور را غیرفعال کنید.');
                        return;
                      }
                      final ancestor = context.findAncestorStateOfType<_BulkSettlementDialogState>();
                      final defaultStrategy = ancestor?._defaultInstallmentSelectionStrategy ?? 'first_remaining';
                      var updated = widget.line.copyWith(
                        installmentsEnabled: enabled,
                        installmentSelectionStrategy: enabled
                            ? (widget.line.installmentSelectionStrategy ?? defaultStrategy)
                            : widget.line.installmentSelectionStrategy,
                      );
                      if (!enabled) {
                        updated = updated.copyWith(
                          installmentInvoiceId: null,
                          installmentSchedule: const <Map<String, dynamic>>[],
                          installmentAllocations: <int, double>{},
                          installmentCurrentSeq: null,
                          installmentSelectionStrategy: null,
                        );
                      }
                      widget.onChanged(updated);
                    },
                  ),
                  const SizedBox(width: 8),
                  const Text('اقساط'),
                  const Spacer(),
                if (widget.line.installmentsEnabled) ...[
                  FilledButton(
                    onPressed: (widget.line.personId == null)
                        ? null
                        : () async {
                            await (context.findAncestorStateOfType<_BulkSettlementDialogState>())!
                                ._pickInvoiceForLine(widget.line);
                            setState(() {});
                          },
                    child: Text(widget.line.installmentInvoiceId == null ? 'انتخاب فاکتور' : 'تغییر فاکتور'),
                  ),
                  if (widget.line.installmentInvoiceCode != null && widget.line.installmentInvoiceCode!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Chip(
                      label: Text('فاکتور: ${widget.line.installmentInvoiceCode}'),
                      avatar: const Icon(Icons.receipt_long, size: 18),
                    ),
                  ],
                ],
              ],
            ),
            // سطر دوم: استراتژی و دکمه اعمال
            if (widget.line.installmentsEnabled) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  // استراتژی انتخاب قسط جاری
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: widget.line.installmentSelectionStrategy
                          ?? (context.findAncestorStateOfType<_BulkSettlementDialogState>()?._defaultInstallmentSelectionStrategy ?? 'first_remaining'),
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'روش انتخاب قسط جاری',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 'first_remaining', child: Text('اولین قسط با مانده')),
                        DropdownMenuItem(value: 'nearest_due', child: Text('نزدیک‌ترین سررسید با مانده')),
                        DropdownMenuItem(value: 'prefer_partial', child: Text('اول قسط‌های نیمه‌پرداخت')),
                      ],
                      onChanged: (v) {
                        widget.onChanged(widget.line.copyWith(installmentSelectionStrategy: v));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'تنظیم استراتژی پیش‌فرض اقساط برای این کسب‌وکار',
                    child: IconButton(
                      onPressed: () async {
                        final ancestor = context.findAncestorStateOfType<_BulkSettlementDialogState>();
                        if (ancestor == null) return;
                        final current = ancestor._defaultInstallmentSelectionStrategy;
                        String temp = current;
                        await showDialog(
                          context: context,
                          builder: (ctx) {
                            return AlertDialog(
                              title: const Text('تنظیم استراتژی پیش‌فرض اقساط'),
                              content: StatefulBuilder(
                                builder: (ctx, setSt) {
                                  return SizedBox(
                                    width: 360,
                                    child: DropdownButtonFormField<String>(
                                      value: temp,
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        labelText: 'استراتژی پیش‌فرض',
                                        border: OutlineInputBorder(),
                                      ),
                                      items: const [
                                        DropdownMenuItem(value: 'first_remaining', child: Text('اولین قسط با مانده')),
                                        DropdownMenuItem(value: 'nearest_due', child: Text('نزدیک‌ترین سررسید با مانده')),
                                        DropdownMenuItem(value: 'prefer_partial', child: Text('اول قسط‌های نیمه‌پرداخت')),
                                      ],
                                      onChanged: (v) => setSt(() => temp = v ?? 'first_remaining'),
                                    ),
                                  );
                                },
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
                                FilledButton(
                                  onPressed: () {
                                    try {
                                      final key = 'installment_strategy_${ancestor.widget.businessId}';
                                      web_utils.setLocalStorageValue(key, temp);
                                      ancestor.setState(() {
                                        ancestor._defaultInstallmentSelectionStrategy = temp;
                                      });
                                    } catch (_) {}
                                    Navigator.pop(ctx);
                                  },
                                  child: const Text('ذخیره'),
                                ),
                              ],
                            );
                          },
                        );
                      },
                      icon: const Icon(Icons.settings_suggest_outlined),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: (widget.line.installmentInvoiceId == null) ? null : () async {
                      // اعمال مجدد استراتژی روی برنامه موجود
                      final schedule = widget.line.installmentSchedule ?? const <Map<String, dynamic>>[];
                      if (schedule.isEmpty) return;
                      final strategy = widget.line.installmentSelectionStrategy ?? 'first_remaining';
                      int? selSeq;
                      double selRemain = 0;
                      if (strategy == 'nearest_due') {
                        DateTime? bestDue;
                        for (final it in schedule) {
                          final total = (it['total'] as num?)?.toDouble() ?? 0;
                          final paid = (it['paid_amount'] as num?)?.toDouble() ?? 0;
                          final remain = (it['remaining'] as num?)?.toDouble() ?? (total - paid);
                          if (remain <= 0) continue;
                          final dueStr = (it['due_date'] as String?) ?? '';
                          DateTime? due;
                          try { if (dueStr.isNotEmpty) due = DateTime.parse(dueStr); } catch (_) {}
                          final seq = (it['seq'] as num?)?.toInt() ?? 0;
                          if (due != null && (bestDue == null || due.isBefore(bestDue))) {
                            bestDue = due;
                            selSeq = seq;
                            selRemain = remain;
                          }
                        }
                      } else if (strategy == 'prefer_partial') {
                        // ابتدا partial: paid>0 && remaining>0
                        for (final it in schedule) {
                          final total = (it['total'] as num?)?.toDouble() ?? 0;
                          final paid = (it['paid_amount'] as num?)?.toDouble() ?? 0;
                          final remain = (it['remaining'] as num?)?.toDouble() ?? (total - paid);
                          final seq = (it['seq'] as num?)?.toInt() ?? 0;
                          if (paid > 0 && remain > 0) {
                            selSeq = seq; selRemain = remain; break;
                          }
                        }
                        // اگر نبود، اولین با مانده
                        if (selSeq == null) {
                          for (final it in schedule) {
                            final total = (it['total'] as num?)?.toDouble() ?? 0;
                            final paid = (it['paid_amount'] as num?)?.toDouble() ?? 0;
                            final remain = (it['remaining'] as num?)?.toDouble() ?? (total - paid);
                            final seq = (it['seq'] as num?)?.toInt() ?? 0;
                            if (remain > 0) { selSeq = seq; selRemain = remain; break; }
                          }
                        }
                      } else {
                        // first_remaining
                        for (final it in schedule) {
                          final total = (it['total'] as num?)?.toDouble() ?? 0;
                          final paid = (it['paid_amount'] as num?)?.toDouble() ?? 0;
                          final remain = (it['remaining'] as num?)?.toDouble() ?? (total - paid);
                          final seq = (it['seq'] as num?)?.toInt() ?? 0;
                          if (remain > 0) { selSeq = seq; selRemain = remain; break; }
                        }
                      }
                      if (selSeq != null && selRemain > 0) {
                        final newAllocs = <int, double>{selSeq: selRemain};
                        final newDesc = 'قسط $selSeq فاکتور ${widget.line.installmentInvoiceCode ?? ''}'.trim();
                        widget.onChanged(widget.line.copyWith(
                          installmentAllocations: newAllocs,
                          installmentCurrentSeq: selSeq,
                          amount: selRemain,
                          description: newDesc,
                        ));
                        setState(() {});
                      }
                    },
                    child: const Text('اعمال استراتژی'),
                  ),
                ],
              ),
            ],
            if (widget.line.installmentsEnabled && (widget.line.installmentSchedule?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 8),
              // دکمه نمایش/مخفی کردن لیست اقساط
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showInstallmentSchedule = !_showInstallmentSchedule;
                      });
                    },
                    icon: Icon(_showInstallmentSchedule ? Icons.expand_less : Icons.expand_more),
                    label: Text(_showInstallmentSchedule ? 'مخفی کردن لیست اقساط' : 'نمایش لیست اقساط'),
                  ),
                  if (widget.line.installmentCurrentSeq != null) ...[
                    const SizedBox(width: 8),
                    Chip(
                      label: Text('قسط جاری: ${widget.line.installmentCurrentSeq}'),
                      avatar: const Icon(Icons.check_circle, size: 18),
                    ),
                  ],
                ],
              ),
              if (_showInstallmentSchedule) ...[
                const SizedBox(height: 8),
                Row(
                  children: const [
                    Expanded(child: Text('قسط')),
                    Expanded(child: Text('سررسید')),
                    Expanded(child: Text('باقیمانده')),
                    SizedBox(width: 120, child: Text('مبلغ تخصیص', textAlign: TextAlign.end)),
                  ],
                ),
                const Divider(),
                ...(widget.line.installmentSchedule ?? const <Map<String, dynamic>>[]).map((it) {
                  final seq = (it['seq'] as num?)?.toInt() ?? 0;
                  final dueStr = (it['due_date'] as String?);
                  DateTime? dueDate;
                  String dueDisplay = '-';
                  if (dueStr != null && dueStr.isNotEmpty && dueStr != '-') {
                    try {
                      dueDate = DateTime.parse(dueStr);
                      dueDisplay = HesabixDateUtils.formatForDisplay(dueDate, widget.calendarController.isJalali);
                    } catch (_) {
                      dueDisplay = dueStr;
                    }
                  }
                  final remaining = (it['remaining'] as num?)?.toDouble() ??
                      (((it['total'] as num?)?.toDouble() ?? 0) - ((it['paid_amount'] as num?)?.toDouble() ?? 0));
                  final current = widget.line.installmentAllocations?[seq] ?? 0.0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(child: Text('#$seq')),
                        Expanded(child: Text(dueDisplay)),
                        Expanded(child: Text(formatWithThousands(remaining))),
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            textAlign: TextAlign.end,
                            initialValue: current > 0 ? formatWithThousands(current) : '',
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (v) {
                              final val = double.tryParse(v.replaceAll(',', '')) ?? 0;
                              final newMap = Map<int, double>.from(widget.line.installmentAllocations ?? <int, double>{});
                              if (val <= 0) {
                                newMap.remove(seq);
                              } else {
                                newMap[seq] = val;
                              }
                              widget.onChanged(widget.line.copyWith(installmentAllocations: newMap));
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        // دکمه انتخاب به عنوان قسط جاری: مبلغ و توضیح ردیف را خودکار تنظیم می‌کند
                        FilledButton.tonal(
                          onPressed: remaining <= 0
                              ? null
                              : () {
                                  final newAllocs = <int, double>{seq: remaining};
                                  final newDesc = 'قسط $seq فاکتور ${widget.line.installmentInvoiceCode ?? ''}'.trim();
                                  widget.onChanged(widget.line.copyWith(
                                    installmentAllocations: newAllocs,
                                    installmentCurrentSeq: seq,
                                    amount: remaining,
                                    description: newDesc,
                                  ));
                                  setState(() {
                                    _showInstallmentSchedule = false; // مخفی کردن لیست بعد از انتخاب
                                  });
                                },
                          child: const Text('انتخاب به عنوان جاری'),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
            ],
          ],
        ),
      ),
    );
  }
}

class _TotalChip extends StatelessWidget {
  final String label;
  final double value;
  final bool isError;
  const _TotalChip({required this.label, required this.value, this.isError = false});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text('$label: ${formatWithThousands(value)}'),
      backgroundColor: isError ? scheme.errorContainer : scheme.surfaceContainerHighest,
      labelStyle: TextStyle(color: isError ? scheme.onErrorContainer : scheme.onSurfaceVariant),
    );
  }
}

class _PersonLine {
  final String? personId;
  final String? personName;
  final double amount;
  final String? description;
  final bool installmentsEnabled;
  final int? installmentInvoiceId;
  final List<Map<String, dynamic>>? installmentSchedule;
  final Map<int, double>? installmentAllocations;
  final String? installmentInvoiceCode;
  final int? installmentCurrentSeq;
  final String? installmentSelectionStrategy; // 'first_remaining' | 'nearest_due' | 'prefer_partial'
  final bool linkToInvoice;
  final int? invoiceId;
  final String? invoiceCode;

  const _PersonLine({
    this.personId,
    this.personName,
    required this.amount,
    this.description,
    this.installmentsEnabled = false,
    this.installmentInvoiceId,
    this.installmentSchedule,
    this.installmentAllocations,
    this.installmentInvoiceCode,
    this.installmentCurrentSeq,
    this.installmentSelectionStrategy,
    this.linkToInvoice = false,
    this.invoiceId,
    this.invoiceCode,
  });

  factory _PersonLine.empty() => const _PersonLine(
        amount: 0,
        installmentsEnabled: false,
      );

  _PersonLine copyWith({
    String? personId,
    String? personName,
    double? amount,
    String? description,
    bool? installmentsEnabled,
    int? installmentInvoiceId,
    List<Map<String, dynamic>>? installmentSchedule,
    Map<int, double>? installmentAllocations,
    String? installmentInvoiceCode,
    int? installmentCurrentSeq,
    String? installmentSelectionStrategy,
    bool? linkToInvoice,
    int? invoiceId,
    String? invoiceCode,
  }) {
    final newAmount = amount ?? this.amount;
    if (amount != null && amount != this.amount) {
      debugPrint('🟤 [PersonLine.copyWith] amount changed: ${this.amount} -> $newAmount');
    }
    return _PersonLine(
      personId: personId ?? this.personId,
      personName: personName ?? this.personName,
      amount: newAmount,
      description: description ?? this.description,
      installmentsEnabled: installmentsEnabled ?? this.installmentsEnabled,
      installmentInvoiceId: installmentInvoiceId ?? this.installmentInvoiceId,
      installmentSchedule: installmentSchedule ?? this.installmentSchedule,
      installmentAllocations: installmentAllocations ?? this.installmentAllocations,
      installmentInvoiceCode: installmentInvoiceCode ?? this.installmentInvoiceCode,
      installmentCurrentSeq: installmentCurrentSeq ?? this.installmentCurrentSeq,
      installmentSelectionStrategy: installmentSelectionStrategy ?? this.installmentSelectionStrategy,
      linkToInvoice: linkToInvoice ?? this.linkToInvoice,
      invoiceId: invoiceId ?? this.invoiceId,
      invoiceCode: invoiceCode ?? this.invoiceCode,
    );
  }
}

/// دیالوگ مشاهده جزئیات سند دریافت/پرداخت
class ReceiptPaymentViewDialog extends StatefulWidget {
  final ReceiptPaymentDocument document;
  final CalendarController calendarController;
  final int businessId;
  final ApiClient apiClient;

  const ReceiptPaymentViewDialog({
    super.key,
    required this.document,
    required this.calendarController,
    required this.businessId,
    required this.apiClient,
  });

  @override
  State<ReceiptPaymentViewDialog> createState() => _ReceiptPaymentViewDialogState();
}

class _ReceiptPaymentViewDialogState extends State<ReceiptPaymentViewDialog> {
  bool _isGeneratingPdf = false;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final doc = widget.document;
    
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // هدر دیالوگ
            _buildHeader(t, doc),
            
            // محتوای اصلی
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // اطلاعات کلی سند
                    _buildDocumentInfo(t, doc),
                    
                    const SizedBox(height: 24),
                    
                    // خطوط اشخاص
                    _buildPersonLines(t, doc),
                    
                    const SizedBox(height: 24),
                    
                    // خطوط حساب‌ها
                    _buildAccountLines(t, doc),
                  ],
                ),
              ),
            ),
            
            // دکمه‌های پایین
            _buildFooter(t),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations t, ReceiptPaymentDocument doc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'جزئیات سند ${doc.documentTypeName}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'کد سند: ${doc.code}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            tooltip: 'بستن',
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentInfo(AppLocalizations t, ReceiptPaymentDocument doc) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'اطلاعات کلی سند',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _buildInfoRow('نوع سند', doc.documentTypeName),
            _buildInfoRow('تاریخ سند', HesabixDateUtils.formatForDisplay(doc.documentDate, widget.calendarController.isJalali)),
            _buildInfoRow('تاریخ ثبت', HesabixDateUtils.formatForDisplay(doc.registeredAt, widget.calendarController.isJalali)),
            _buildInfoRow('ارز', doc.currencyCode ?? 'نامشخص'),
            _buildInfoRow('ایجادکننده', doc.createdByName ?? 'نامشخص'),
            _buildInfoRow('مبلغ کل', formatWithThousands(doc.totalAmount) + ' ${doc.currencyCode ?? 'ریال'}'),
            if (doc.description != null && doc.description!.isNotEmpty)
              _buildInfoRow('توضیحات', doc.description!),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonLines(AppLocalizations t, ReceiptPaymentDocument doc) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'خطوط اشخاص (${doc.personLinesCount})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (doc.personLines.isEmpty)
              const Text('هیچ خط شخصی یافت نشد')
            else
              ...doc.personLines.map((line) => _buildPersonLineItem(line, doc)),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonLineItem(PersonLine line, ReceiptPaymentDocument doc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.personName ?? 'نامشخص',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (line.description != null && line.description!.isNotEmpty)
                  Text(
                    line.description!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          Text(
            formatWithThousands(line.amount) + ' ${doc.currencyCode ?? 'ریال'}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountLines(AppLocalizations t, ReceiptPaymentDocument doc) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'خطوط حساب‌ها (${doc.accountLinesCount})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (doc.accountLines.isEmpty)
              const Text('هیچ خط حسابی یافت نشد')
            else
              ...doc.accountLines.map((line) => _buildAccountLineItem(line, doc)),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountLineItem(AccountLine line, ReceiptPaymentDocument doc) {
    final isCommission = line.extraInfo?['is_commission_line'] == true;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: isCommission 
            ? Theme.of(context).colorScheme.error 
            : Theme.of(context).colorScheme.outline,
        ),
        borderRadius: BorderRadius.circular(8),
        color: isCommission 
          ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.1)
          : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.accountName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      'کد: ${line.accountCode}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (line.transactionType != null)
                      Text(
                        'نوع: ${_getTransactionTypeName(line.transactionType!)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              Text(
                formatWithThousands(line.amount) + ' ${doc.currencyCode ?? 'ریال'}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (line.description != null && line.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              line.description!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (isCommission) ...[
            const SizedBox(height: 4),
            Text(
              'کارمزد',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getTransactionTypeName(String type) {
    switch (type) {
      case 'bank':
        return 'بانک';
      case 'cash_register':
        return 'صندوق';
      case 'petty_cash':
        return 'تنخواهگردان';
      case 'check':
        return 'چک';
      case 'person':
        return 'شخص';
      default:
        return type;
    }
  }

  Widget _buildFooter(AppLocalizations t) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.close),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _isGeneratingPdf ? null : _generatePdf,
            icon: _isGeneratingPdf 
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf),
            label: Text(_isGeneratingPdf ? AppLocalizations.of(context).generating : AppLocalizations.of(context).exportToPdf),
          ),
        ],
      ),
    );
  }

  Future<void> _generatePdf() async {
    setState(() {
      _isGeneratingPdf = true;
    });

    try {
      // ایجاد PDF از سند
      final pdfBytes = await widget.apiClient.downloadPdf(
        '/receipts-payments/${widget.document.id}/pdf',
      );

      // ذخیره فایل
      await _savePdfFile(pdfBytes, widget.document.code);

      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.showSuccess(context, message: t.exportSuccess);
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.showError(
        context,
        message: '${t.exportError}: ${ErrorExtractor.forContext(e, context)}',
      );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingPdf = false;
        });
      }
    }
  }

  Future<void> _savePdfFile(List<int> bytes, String filename) async {
    if (kIsWeb) {
      await web_utils.saveBytesAsFileWeb(
        bytes,
        filename.endsWith('.pdf') ? filename : '$filename.pdf',
        mimeType: 'application/pdf',
      );
    } else {
      throw UnsupportedError('PDF download is only supported on web.');
    }
  }
}

