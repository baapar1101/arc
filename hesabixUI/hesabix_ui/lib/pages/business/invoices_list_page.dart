import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/business_named_route_locations.dart';
import 'package:hesabix_ui/models/invoice_list_item.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/core/date_utils.dart' show HesabixDateUtils;
import 'package:hesabix_ui/utils/number_formatters.dart' show formatWithThousands;
import 'package:hesabix_ui/widgets/document/document_details_dialog.dart';
import 'package:hesabix_ui/widgets/invoice/invoice_pdf_print_flow.dart';
import 'package:hesabix_ui/services/invoice_service.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/services/invoice_warehouse_bulk_service.dart';
import 'package:hesabix_ui/services/list_filter_preferences_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/invoice/invoice_import_dialog.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/project/project_selector_widget.dart';
import '../../widgets/invoice/invoice_list_document_type_filter_bar.dart';
import '../../models/invoice_tag_ref.dart';

/// صفحه لیست فاکتورها با ویجت جدول عمومی
class InvoicesListPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final AuthStore authStore;
  final ApiClient apiClient;

  const InvoicesListPage({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.authStore,
    required this.apiClient,
  });

  @override
  State<InvoicesListPage> createState() => _InvoicesListPageState();
  
  /// Static map to store page states by business ID for external refresh
  static final Map<int, _InvoicesListPageState> _pageStates = {};
  
  /// Get the page state for a specific business ID
  static _InvoicesListPageState? getPageState(int businessId) {
    return _pageStates[businessId];
  }
  
  /// Clear the page state for a specific business ID
  static void clearPageState(int businessId) {
    _pageStates.remove(businessId);
  }

  /// بازگشت به لیست فاکتورها و تازه‌سازی جدول بعد از ثبت/ویرایش.
  /// اگر با [push] به صفحهٔ فعال آمده باشیم با [pop] برمی‌گردیم تا همان نمونهٔ لیست
  /// دوباره ساخته نشود و داده از سرور دوباره خوانده شود.
  static void popOrGoToInvoiceList(BuildContext context, int businessId) {
    if (!context.mounted) return;
    if (context.canPop()) {
      context.pop(true);
      return;
    }
    BusinessNamedRoutes.goNamed(
      context,
      businessId: businessId,
      routeName: 'business_invoice',
      pathParameters: {'business_id': businessId.toString()},
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      getPageState(businessId)?.refresh();
    });
  }
}

class _InvoicesListPageState extends State<InvoicesListPage> {
  final GlobalKey _tableKey = GlobalKey();
  final InvoiceService _invoiceService = InvoiceService();
  late final InvoiceWarehouseBulkService _warehouseBulkService = InvoiceWarehouseBulkService(apiClient: widget.apiClient);
  late final BusinessDashboardService _dashboardService = BusinessDashboardService(widget.apiClient);

  static const double _mobileInvoiceRowHeight = 164;
  static const double _mobileInvoiceCardVPadding = 6; // inside row height budget

  String? _selectedInvoiceType;
  DateTime? _fromDate;
  DateTime? _toDate;
  bool? _isProforma; // null=همه، true=پیشفاکتور، false=قطعی

  int? _selectedFiscalYearId;
  List<Map<String, dynamic>> _fiscalYears = [];
  /// تا زمان آماده شدن لیست سال مالی، جدول ساخته نمی‌شود تا اولین درخواست با fiscal_year_id درست باشد.
  bool _fiscalYearsResolved = false;
  int? _selectedProjectId; // فیلتر پروژه
  List<FilterOption> _projectFilterOptions = [];
  bool _loadingProjects = false;
  /// فیلتر برچسب
  List<int> _selectedTagIds = [];
  String _tagMatch = 'any'; // any | all
  List<InvoiceTagRef> _invoiceTagsForFilter = [];
  bool _loadingInvoiceTags = false;
  bool _showDesktopFilters = false;
  int _selectedCount = 0;

  Timer? _invoiceFilterPrefsDebounce;

  Map<String, dynamic> _serializeInvoiceFilters() {
    return <String, dynamic>{
      if (_selectedInvoiceType != null && _selectedInvoiceType!.isNotEmpty)
        'document_type': _selectedInvoiceType,
      if (_fromDate != null) 'from_date': _fromDate!.toIso8601String(),
      if (_toDate != null) 'to_date': _toDate!.toIso8601String(),
      if (_isProforma != null) 'is_proforma': _isProforma,
      if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
      if (_selectedProjectId != null) 'project_id': _selectedProjectId,
      if (_selectedTagIds.isNotEmpty) 'tag_ids': List<int>.from(_selectedTagIds)..sort(),
      'tag_match': _tagMatch,
    };
  }

  void _schedulePersistInvoiceFilters() {
    _invoiceFilterPrefsDebounce?.cancel();
    _invoiceFilterPrefsDebounce = Timer(const Duration(milliseconds: 400), () {
      _invoiceFilterPrefsDebounce = null;
      if (!mounted) return;
      ListFilterPreferencesService.save(
        ListFilterPageIds.invoices,
        widget.businessId,
        _serializeInvoiceFilters(),
      );
    });
  }

  void _applyInvoiceSavedFiltersMap(Map<String, dynamic> s) {
    final dt = s['document_type']?.toString();
    if (dt != null && dt.isNotEmpty && isKnownInvoiceDocumentType(dt)) {
      _selectedInvoiceType = dt;
    }
    final from = s['from_date']?.toString();
    if (from != null && from.isNotEmpty) {
      _fromDate = DateTime.tryParse(from);
    }
    final to = s['to_date']?.toString();
    if (to != null && to.isNotEmpty) {
      _toDate = DateTime.tryParse(to);
    }
    final ip = s['is_proforma'];
    if (ip is bool) {
      _isProforma = ip;
    } else if (ip is int) {
      if (ip == 1) _isProforma = true;
      if (ip == 0) _isProforma = false;
    }
    final pid = s['project_id'];
    if (pid is int) {
      _selectedProjectId = pid;
    } else if (pid != null) {
      _selectedProjectId = int.tryParse('$pid');
    }
    final rawTags = s['tag_ids'];
    if (rawTags is List) {
      _selectedTagIds = rawTags.map((e) => int.tryParse('$e')).whereType<int>().toList()..sort();
    }
    final tm = s['tag_match']?.toString();
    if (tm == 'all' || tm == 'any') {
      _tagMatch = tm!;
    }
    final fy = s['fiscal_year_id'];
    int? fyId;
    if (fy is int) {
      fyId = fy;
    } else if (fy != null) {
      fyId = int.tryParse('$fy');
    }
    if (fyId != null && _fiscalYears.any((e) => e['id'] == fyId)) {
      _selectedFiscalYearId = fyId;
    }
  }

  void _onInvoiceTypeFilterChanged(String? v) {
    setState(() => _selectedInvoiceType = v);
    _schedulePersistInvoiceFilters();
  }

  void _onDataTableAllFiltersCleared() {
    _invoiceFilterPrefsDebounce?.cancel();
    unawaited(_clearExternalFilters());
  }

  void _touchInvoiceFilters(VoidCallback fn) {
    setState(fn);
    _schedulePersistInvoiceFilters();
  }

  void _refreshData([int attempt = 0]) {
    final state = _tableKey.currentState;
    if (state != null) {
      try {
        // ignore: avoid_dynamic_calls
        (state as dynamic).refresh();
        return;
      } catch (_) {}
    }
    // جدول ممکن است هنوز بعد از بارگذاری سال مالی ساخته نشده باشد؛ چند فریم بعد دوباره امتحان کن.
    if (attempt < 24 && mounted) {
      Future<void>.delayed(
        const Duration(milliseconds: 50),
        () {
          if (mounted) _refreshData(attempt + 1);
        },
      );
      return;
    }
    if (mounted) setState(() {});
  }
  
  /// Public method to refresh the data table
  void refresh() {
    _refreshData();
  }

  @override
  void initState() {
    super.initState();
    // Register this page instance for external refresh access
    InvoicesListPage._pageStates[widget.businessId] = this;
    _loadFiscalYears();
    _loadProjects();
    _loadInvoiceTagsForFilter();
  }
  
  @override
  void dispose() {
    _invoiceFilterPrefsDebounce?.cancel();
    InvoicesListPage._pageStates.remove(widget.businessId);
    super.dispose();
  }

  /// بارگذاری لیست پروژه‌ها برای فیلتر
  Future<void> _loadInvoiceTagsForFilter() async {
    if (!mounted) return;
    setState(() => _loadingInvoiceTags = true);
    try {
      final response = await widget.apiClient.get<Map<String, dynamic>>(
        '/api/v1/invoices/business/${widget.businessId}/tags',
      );
      final data = response.data?['data'];
      final List<dynamic> items = (data is Map) ? (data['items'] as List<dynamic>? ?? []) : [];
      if (mounted) {
        setState(() {
          _invoiceTagsForFilter = items
              .whereType<Map<String, dynamic>>()
              .map(InvoiceTagRef.fromJson)
              .where((t) => t.isActive)
              .toList();
          _loadingInvoiceTags = false;
        });
      }
    } catch (e) {
      debugPrint('خطا در بارگذاری برچسب‌های فاکتور: $e');
      if (mounted) setState(() => _loadingInvoiceTags = false);
    }
  }

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

  Future<void> _loadFiscalYears() async {
    Map<String, dynamic>? savedFilters;
    try {
      savedFilters = await ListFilterPreferencesService.loadInvoicesMergedLegacy(widget.businessId);
    } catch (_) {}

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
        if (savedFilters != null && savedFilters.isNotEmpty) {
          _applyInvoiceSavedFiltersMap(savedFilters);
        }
        _fiscalYearsResolved = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _fiscalYearsResolved = true;
        });
      }
    }
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
              InvoiceListDocumentTypeFilterBar(
                selectedDocumentType: _selectedInvoiceType,
                onDocumentTypeChanged: _onInvoiceTypeFilterChanged,
              ),
              const Divider(height: 1),
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
                    ? DataTableWidget<InvoiceListItem>(
                        key: _tableKey,
                        config: _buildTableConfig(t, isMobile: isMobile),
                        fromJson: (json) => InvoiceListItem.fromJson(json),
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
                Text(t.invoices, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(t.invoicesListManage, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          // دکمه افزودن فاکتور - فقط در دسکتاپ نمایش داده می‌شود
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
                onPressed: () => unawaited(_clearExternalFilters()),
                icon: const Icon(Icons.clear_all),
                tooltip: t.clear,
              ),
            ],
          ],
        ),
      );
    }

    // Desktop/tablet: show full filter controls inline
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
                onPressed: () => setState(() => _showDesktopFilters = !_showDesktopFilters),
                icon: Icon(_showDesktopFilters ? Icons.expand_less : Icons.tune),
                label: Text(_showDesktopFilters ? 'بستن فیلترها' : 'فیلترها'),
              ),
              if (_hasExternalFiltersActive()) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => unawaited(_clearExternalFilters()),
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
              invoiceType: _selectedInvoiceType,
              fiscalYearId: _selectedFiscalYearId,
              projectId: _selectedProjectId,
              fromDate: _fromDate,
              toDate: _toDate,
              isProforma: _isProforma,
              onInvoiceTypeChanged: (v) => _onInvoiceTypeFilterChanged(v),
              onFiscalYearChanged: (v) {
                _touchInvoiceFilters(() => _selectedFiscalYearId = v);
              },
              onProjectChanged: (v) {
                _touchInvoiceFilters(() => _selectedProjectId = v);
              },
              onFromDateChanged: (v) {
                _touchInvoiceFilters(() => _fromDate = v);
              },
              onToDateChanged: (v) {
                _touchInvoiceFilters(() => _toDate = v);
              },
              onClearDateRange: () {
                _touchInvoiceFilters(() {
                  _fromDate = null;
                  _toDate = null;
                });
              },
              onIsProformaChanged: (v) {
                _touchInvoiceFilters(() => _isProforma = v);
              },
              selectedTagIds: _selectedTagIds,
              tagMatch: _tagMatch,
              onTagIdsChanged: (v) {
                _touchInvoiceFilters(() => _selectedTagIds = v);
              },
              onTagMatchChanged: (v) {
                _touchInvoiceFilters(() => _tagMatch = v);
              },
            ),
          ],
        ],
      ),
    );
  }

  bool _hasExternalFiltersActive() {
    return _selectedInvoiceType != null ||
        _fromDate != null ||
        _toDate != null ||
        _isProforma != null ||
        _selectedFiscalYearId != null ||
        _selectedProjectId != null ||
        _selectedTagIds.isNotEmpty;
  }

  Future<void> _clearExternalFilters() async {
    _invoiceFilterPrefsDebounce?.cancel();
    await ListFilterPreferencesService.clearInvoicesWithLegacy(widget.businessId);
    if (!mounted) return;
    setState(() {
      _selectedInvoiceType = null;
      _fromDate = null;
      _toDate = null;
      _isProforma = null;
      _selectedProjectId = null;
      _selectedTagIds = [];
      _tagMatch = 'any';
      // Fiscal year is typically important; keep it unless explicitly cleared by user.
    });
    _refreshData();
  }

  List<Widget> _buildExternalFilterChips(AppLocalizations t) {
    final chips = <Widget>[];
    if (_selectedInvoiceType != null) {
      chips.add(Chip(
        label: Text(_invoiceTypeLabel(t, _selectedInvoiceType)),
        avatar: const Icon(Icons.receipt_long, size: 16),
      ));
    } else {
      chips.add(Chip(
        label: Text(t.all),
        avatar: const Icon(Icons.all_inclusive, size: 16),
      ));
    }

    if (_selectedFiscalYearId != null && _fiscalYears.isNotEmpty) {
      final fy = _fiscalYears.where((e) => (e['id'] as int?) == _selectedFiscalYearId).toList();
      final title = fy.isNotEmpty ? (fy.first['title'] ?? '').toString() : '';
      chips.add(Chip(
        label: Text(title.isNotEmpty ? title : '${t.fiscalYear}: $_selectedFiscalYearId'),
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

    if (_fromDate != null || _toDate != null) {
      final from = _fromDate != null
          ? HesabixDateUtils.formatForDisplay(_fromDate!, widget.calendarController.isJalali)
          : '—';
      final to = _toDate != null
          ? HesabixDateUtils.formatForDisplay(_toDate!, widget.calendarController.isJalali)
          : '—';
      chips.add(Chip(
        label: Text('${t.documentDate}: $from → $to'),
        avatar: const Icon(Icons.date_range, size: 16),
      ));
    }

    if (_isProforma != null) {
      chips.add(Chip(
        label: Text(_isProforma == true ? t.proforma : t.finalized),
        avatar: Icon(_isProforma == true ? Icons.description_outlined : Icons.verified, size: 16),
      ));
    }

    if (_selectedTagIds.isNotEmpty) {
      final label = _tagMatch == 'all' ? 'برچسب: همه' : 'برچسب: هرکدام';
      chips.add(Chip(
        label: Text('$label (${_selectedTagIds.length})'),
        avatar: const Icon(Icons.label, size: 16),
      ));
    }

    if (chips.isEmpty) {
      chips.add(Chip(label: Text(t.all)));
    }
    return chips;
  }

  String _invoiceTypeLabel(AppLocalizations t, String? type) => invoiceDocumentTypeLabel(t, type);

  Future<void> _openMobileFiltersSheet(AppLocalizations t) async {
    String? invoiceType = _selectedInvoiceType;
    int? fiscalYearId = _selectedFiscalYearId;
    int? projectId = _selectedProjectId;
    DateTime? fromDate = _fromDate;
    DateTime? toDate = _toDate;
    bool? isProforma = _isProforma;
    List<int> tagIds = List<int>.from(_selectedTagIds);
    String tagMatchLocal = _tagMatch;

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
                      Text('فیلترها', style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setModalState(() {
                            invoiceType = null;
                            projectId = null;
                            fromDate = null;
                            toDate = null;
                            isProforma = null;
                            tagIds = [];
                            tagMatchLocal = 'any';
                            // fiscalYearId intentionally kept
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
                        invoiceType: invoiceType,
                        fiscalYearId: fiscalYearId,
                        projectId: projectId,
                        fromDate: fromDate,
                        toDate: toDate,
                        isProforma: isProforma,
                        onInvoiceTypeChanged: (v) => setModalState(() {
                          invoiceType = v;
                        }),
                        onFiscalYearChanged: (v) => setModalState(() => fiscalYearId = v),
                        onProjectChanged: (v) => setModalState(() => projectId = v),
                        onFromDateChanged: (v) => setModalState(() => fromDate = v),
                        onToDateChanged: (v) => setModalState(() => toDate = v),
                        onClearDateRange: () => setModalState(() {
                          fromDate = null;
                          toDate = null;
                        }),
                        onIsProformaChanged: (v) => setModalState(() => isProforma = v),
                        selectedTagIds: tagIds,
                        tagMatch: tagMatchLocal,
                        onTagIdsChanged: (v) => setModalState(() => tagIds = v),
                        onTagMatchChanged: (v) => setModalState(() => tagMatchLocal = v),
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
        _selectedInvoiceType = invoiceType;
        _selectedFiscalYearId = fiscalYearId;
        _selectedProjectId = projectId;
        _fromDate = fromDate;
        _toDate = toDate;
        _isProforma = isProforma;
        _selectedTagIds = tagIds;
        _tagMatch = tagMatchLocal;
      });
      _schedulePersistInvoiceFilters();
    }
  }

  Widget _buildFiltersForm({
    required AppLocalizations t,
    required bool isMobileLayout,
    required String? invoiceType,
    required int? fiscalYearId,
    required int? projectId,
    required DateTime? fromDate,
    required DateTime? toDate,
    required bool? isProforma,
    required ValueChanged<String?> onInvoiceTypeChanged,
    required ValueChanged<int?> onFiscalYearChanged,
    required ValueChanged<int?> onProjectChanged,
    required ValueChanged<DateTime?> onFromDateChanged,
    required ValueChanged<DateTime?> onToDateChanged,
    required VoidCallback onClearDateRange,
    required ValueChanged<bool?> onIsProformaChanged,
    required List<int> selectedTagIds,
    required String tagMatch,
    required void Function(List<int>) onTagIdsChanged,
    required ValueChanged<String> onTagMatchChanged,
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
              ButtonSegment<String?>(value: null, label: Text(t.all), icon: const Icon(Icons.all_inclusive)),
              ...kInvoiceDocumentTypeOptions.map(
                (o) => ButtonSegment<String?>(
                  value: o.documentTypeValue,
                  label: Text(o.label(t)),
                  icon: Icon(o.icon),
                ),
              ),
            ],
            selected: invoiceType != null ? {invoiceType} : <String?>{},
            onSelectionChanged: (set) => onInvoiceTypeChanged(set.isEmpty ? null : set.first),
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
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
              const SizedBox(height: 8),
              SegmentedButton<bool?>(
                segments: [
                  ButtonSegment<bool?>(value: null, label: Text(t.all)),
                  ButtonSegment<bool?>(value: true, label: Text(t.proforma)),
                  ButtonSegment<bool?>(value: false, label: Text(t.finalized)),
                ],
                selected: {isProforma},
                onSelectionChanged: (set) => onIsProformaChanged(set.first),
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
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: SegmentedButton<bool?>(
                  segments: [
                    ButtonSegment<bool?>(value: null, label: Text(t.all)),
                    ButtonSegment<bool?>(value: true, label: Text(t.proforma)),
                    ButtonSegment<bool?>(value: false, label: Text(t.finalized)),
                  ],
                  selected: {isProforma},
                  onSelectionChanged: (set) => onIsProformaChanged(set.first),
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: Text('فیلتر برچسب', style: Theme.of(context).textTheme.titleSmall),
        ),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment<String>(value: 'any', label: Text('هرکدام'), icon: Icon(Icons.filter_alt_outlined)),
            ButtonSegment<String>(value: 'all', label: Text('همه با هم'), icon: Icon(Icons.join_inner)),
          ],
          selected: {tagMatch},
          onSelectionChanged: (set) => onTagMatchChanged(set.first),
        ),
        const SizedBox(height: 8),
        if (_loadingInvoiceTags)
          const LinearProgressIndicator(minHeight: 2)
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in _invoiceTagsForFilter)
                FilterChip(
                  label: Text(tag.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  selected: selectedTagIds.contains(tag.id),
                  onSelected: (v) {
                    final next = <int>{...selectedTagIds};
                    if (v) {
                      next.add(tag.id);
                    } else {
                      next.remove(tag.id);
                    }
                    onTagIdsChanged(next.toList()..sort());
                  },
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildProjectFilter() {
    return ProjectSelectorWidget(
      businessId: widget.businessId,
      apiClient: widget.apiClient,
      selectedProjectId: _selectedProjectId,
      onChanged: (projectId) {
        _touchInvoiceFilters(() {
          _selectedProjectId = projectId;
        });
      },
      authStore: widget.authStore, // برای بررسی دسترسی به ایجاد پروژه
      calendarController: widget.calendarController, // برای دیالوگ ایجاد پروژه
      allowNull: true,
      labelText: 'پروژه',
    );
  }

  DataTableConfig<InvoiceListItem> _buildTableConfig(AppLocalizations t, {required bool isMobile}) {
    if (isMobile) {
      return DataTableConfig<InvoiceListItem>(
        endpoint: '/invoices/business/${widget.businessId}/search',
        // avoid duplicate titles (page already has its own header)
        title: null,
        excelEndpoint: '/invoices/business/${widget.businessId}/export/excel',
        pdfEndpoint: '/invoices/business/${widget.businessId}/export/pdf',
        businessId: widget.businessId,
        persistTableFiltersPageId: ListFilterPageIds.invoicesListTable,
        reportModuleKey: 'invoices',
        reportSubtype: 'list',
        enableColumnSettings: false,
        showColumnSettingsButton: false,
        showColumnHeaders: false,
        defaultSortBy: 'document_date',
        defaultSortDesc: true,
        dataRowHeight: _mobileInvoiceRowHeight,
        padding: const EdgeInsets.all(8),
        columns: [
          CustomColumn(
            'summary',
            'فاکتور',
            sortable: false,
            searchable: false,
            width: ColumnWidth.extraLarge,
            builder: (dynamic item, int index) => _buildMobileInvoiceSummaryCard(item as InvoiceListItem),
          ),
        ],
        searchFields: const ['code', 'description', 'counterparty'],
        filterFields: const ['document_type'],
        dateRangeField: 'document_date',
        showSearch: true,
        showFilters: true,
        showPagination: true,
        showColumnSearch: false,
        showRefreshButton: true,
        showClearFiltersButton: true,
        showExportButtons: true,
        // Selection/Actions are moved inside card for mobile to avoid UI clutter and layout glitches
        enableRowSelection: false,
        enableMultiRowSelection: false,
        defaultPageSize: 20,
        pageSizeOptions: const [10, 20, 50, 100],
        additionalParams: {
          'document_type': _selectedInvoiceType,
          if (_fromDate != null) 'from_date': HesabixDateUtils.formatForApiDate(_fromDate!),
          if (_toDate != null) 'to_date': HesabixDateUtils.formatForApiDate(_toDate!),
          if (_isProforma != null) 'is_proforma': _isProforma,
          if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
          if (_selectedProjectId != null) 'project_id': _selectedProjectId,
          if (_selectedTagIds.isNotEmpty) 'tag_ids': _selectedTagIds,
          'tag_match': _tagMatch,
        },
        // موبایل: منوی عملیات داخل کارت است؛ onRowTap سطر با PopupMenu تداخل دارد (مثل لیست کالاها که ActionColumn جدا دارد).
        onRowTap: null,
        emptyStateMessage: t.noInvoicesFound,
        loadingMessage: t.loadingInvoices,
        errorMessage: t.errorLoadingInvoices,
        customHeaderActions: [
          Tooltip(
            message: 'ایمپورت فاکتورها از فایل Excel',
            child: IconButton(
              onPressed: _onImport,
              icon: const Icon(Icons.upload_file),
              tooltip: 'ایمپورت از اکسل',
            ),
          ),
        ],
        footerTotals: { 'total_amount': 'جمع مبلغ این صفحه' },
        expandBodyHeightToFitRows: true,
        onAllFiltersCleared: _onDataTableAllFiltersCleared,
      );
    }

    return DataTableConfig<InvoiceListItem>(
      endpoint: '/invoices/business/${widget.businessId}/search',
      // avoid duplicate titles (page already has its own header)
      title: null,
      excelEndpoint: '/invoices/business/${widget.businessId}/export/excel',
      pdfEndpoint: '/invoices/business/${widget.businessId}/export/pdf',
      businessId: widget.businessId,
      persistTableFiltersPageId: ListFilterPageIds.invoicesListTable,
      reportModuleKey: 'invoices',
      reportSubtype: 'list',
      defaultSortBy: 'document_date',
      defaultSortDesc: true,
      padding: const EdgeInsets.all(12),
      columns: [
        // عملیات
        ActionColumn(
          'actions',
          t.actions,
          actions: [
            DataTableAction(
              icon: Icons.visibility,
              label: t.view,
              onTap: (item) async {
                final invoice = item as InvoiceListItem;
                await showDialog(
                  context: context,
                  builder: (_) => DocumentDetailsDialog(
                    documentId: invoice.id,
                    calendarController: widget.calendarController,
                  ),
                );
              },
            ),
            DataTableAction(
              icon: Icons.picture_as_pdf,
              label: t.printPdf,
              onTap: (item) async {
                final invoice = item as InvoiceListItem;
                if (!mounted) return;
                await _printInvoicePdfFromList(invoice);
              },
            ),
            if (widget.authStore.canWriteSection('invoices'))
              DataTableAction(
                icon: Icons.edit,
                label: t.edit,
                onTap: (item) async {
                  final invoice = item as InvoiceListItem;
                  if (!mounted) return;
                  await BusinessNamedRoutes.pushNamed(
                    context,
                    businessId: widget.businessId,
                    routeName: 'business_edit_invoice',
                    pathParameters: {
                      'business_id': widget.businessId.toString(),
                      'invoice_id': invoice.id.toString(),
                    },
                  );
                  if (!mounted) return;
                  _refreshData();
                },
              ),
            if (widget.authStore.canWriteSection('invoices'))
              DataTableAction(
                icon: Icons.copy_outlined,
                label: t.invoiceCopyOpenNew,
                onTap: (item) async {
                  final invoice = item as InvoiceListItem;
                  if (!mounted) return;
                  await BusinessNamedRoutes.pushNamed(
                    context,
                    businessId: widget.businessId,
                    routeName: 'business_new_invoice',
                    pathParameters: {
                      'business_id': widget.businessId.toString(),
                    },
                    queryParameters: {
                      'copy_from': '${invoice.id}',
                    },
                  );
                  if (!mounted) return;
                  _refreshData();
                },
              ),
            if (widget.authStore.canWriteSection('invoices'))
              DataTableAction(
                icon: Icons.delete,
                label: t.delete,
                onTap: (item) async {
                  final invoice = item as InvoiceListItem;
                  await _onDelete(invoice);
                },
                isDestructive: true,
              ),
            if (widget.authStore.canWriteSection('invoices'))
              DataTableAction(
                icon: Icons.drive_folder_upload,
                label: t.taxAddToWorkspaceSingle,
                onTap: (item) async {
                  final invoice = item as InvoiceListItem;
                  await _onAddToTaxWorkspace(invoice);
                },
              ),
            if (widget.authStore.canWriteSection('invoices'))
              DataTableAction(
                icon: Icons.folder_off,
                label: t.taxRemoveFromWorkspaceSingle,
                onTap: (item) async {
                  final invoice = item as InvoiceListItem;
                  await _onRemoveFromTaxWorkspace(invoice);
                },
              ),
          ],
        ),
        // کد سند
        TextColumn('code', t.code, formatter: (item) => item.code, width: ColumnWidth.small),
        // نوع (نمایش خوانا؛ و استفاده از فیلد document_type_name برای خروجی‌ها)
        TextColumn(
          'document_type_name',
          t.type,
          width: ColumnWidth.medium,
          formatter: (item) {
            final it = item as InvoiceListItem;
            final friendly = (it.documentTypeName).trim();
            if (friendly.isNotEmpty && friendly != it.documentType) {
              return friendly;
            }
            switch (it.documentType) {
              case 'invoice_sales':
                return t.invoiceTypeSales;
              case 'invoice_sales_return':
                return t.invoiceTypeSalesReturn;
              case 'invoice_purchase':
                return t.invoiceTypePurchase;
              case 'invoice_purchase_return':
                return t.invoiceTypePurchaseReturn;
              case 'invoice_direct_consumption':
                return t.invoiceTypeDirectConsumption;
              case 'invoice_production':
                return t.invoiceTypeProduction;
              case 'invoice_waste':
                return t.invoiceTypeWaste;
              default:
                return it.documentType;
            }
          },
        ),
        // طرف حساب
        TextColumn(
          'counterparty',
          'طرف حساب',
          width: ColumnWidth.medium,
          formatter: (item) {
            final it = item as InvoiceListItem;
            return (it.counterparty == null || it.counterparty!.trim().isEmpty) ? t.unknown : it.counterparty!;
          },
        ),
        // شرح فاکتور
        TextColumn(
          'description',
          t.invoiceHeaderDescriptionLabel,
          width: ColumnWidth.large,
          sortable: false,
          formatter: (item) {
            final it = item as InvoiceListItem;
            final d = (it.description ?? '').trim();
            return d.isEmpty ? '-' : d;
          },
          maxLines: 2,
          overflow: true,
        ),
        // تاریخ سند
        DateColumn(
          'document_date',
          t.documentDate,
          width: ColumnWidth.medium,
          formatter: (item) => HesabixDateUtils.formatForDisplay(item.documentDate, widget.calendarController.isJalali),
        ),
        // مبلغ کل
        TextColumn(
          'total_amount',
          t.totalAmount,
          width: ColumnWidth.large,
          formatter: (item) => item.totalAmount != null ? '${formatWithThousands(item.totalAmount!, decimalPlaces: 2)} ${item.currencyCode ?? 'ریال'}' : '-',
        ),
        // مبلغ پرداخت‌شده فاکتور
        TextColumn(
          'paid_amount',
          t.invoicePaidAmount,
          width: ColumnWidth.large,
          formatter: (item) => item.paidAmount != null ? '${formatWithThousands(item.paidAmount!, decimalPlaces: 2)} ${item.currencyCode ?? 'ریال'}' : '-',
        ),
        // مبلغ باقی‌مانده فاکتور
        TextColumn(
          'remaining_amount',
          t.invoiceRemainingAmount,
          width: ColumnWidth.large,
          formatter: (item) => item.remainingAmount != null ? '${formatWithThousands(item.remainingAmount!, decimalPlaces: 2)} ${item.currencyCode ?? 'ریال'}' : '-',
        ),
        // سود
        CustomColumn(
          'total_profit',
          'سود',
          sortable: true,
          searchable: false,
          width: ColumnWidth.medium,
          builder: (dynamic item, int index) {
            final invoice = item as InvoiceListItem;
            // استفاده از total_profit (که می‌تواند gross یا net باشد) یا fallback به gross_profit
            final profit = invoice.totalProfit ?? invoice.grossProfit;
            final profitPercent = invoice.totalProfitPercent ?? invoice.grossProfitPercent;
            
            if (profit == null) {
              return const Text('-');
            }
            
            final profitValue = profit;
            final profitPercentValue = profitPercent ?? 0;
            
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      formatWithThousands(profitValue),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: profitValue >= 0 ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (profitPercentValue != 0)
                      Text(
                        '${profitPercentValue.toStringAsFixed(1)}%',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: profitValue >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
        // اقساطی؟
        CustomColumn(
          'is_installment_sale',
          t.installmentColumn,
          width: ColumnWidth.small,
          sortable: false,
          searchable: false,
          builder: (dynamic item, int index) {
            final invoice = item as InvoiceListItem;
            if (!invoice.isInstallmentSale) {
              return const SizedBox.shrink();
            }
            return const Center(
              child: Icon(Icons.check_circle, color: Colors.green, size: 18),
            );
          },
          tooltip: t.installmentsTitle,
        ),
        // ارز
        TextColumn('currency_code', t.currency, formatter: (item) => item.currencyCode ?? t.unknown, width: ColumnWidth.small),
        // ایجادکننده
        TextColumn('created_by_name', t.createdBy, formatter: (item) => item.createdByName ?? t.unknown, width: ColumnWidth.medium),
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
        CustomColumn(
          'tags_display',
          'برچسب‌ها',
          width: ColumnWidth.large,
          sortable: false,
          searchable: false,
          builder: (dynamic item, int index) {
            final inv = item as InvoiceListItem;
            if (inv.tags.isEmpty) {
              return Text(
                inv.tagsDisplay?.trim().isNotEmpty == true ? inv.tagsDisplay! : '—',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              );
            }
            return Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final tg in inv.tags)
                  Chip(
                    label: Text(tg.name, style: const TextStyle(fontSize: 12)),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            );
          },
        ),
        // پیش‌فاکتور (تیک برای true، خالی برای false)
        CustomColumn(
          'is_proforma',
          t.proforma,
          width: ColumnWidth.small,
          sortable: false,
          searchable: false,
          builder: (dynamic item, int index) {
            final invoice = item as InvoiceListItem;
            return invoice.isProforma
                ? const Icon(Icons.check, size: 18, color: Colors.black87)
                : const SizedBox.shrink();
          },
          tooltip: t.proforma,
        ),
      ],
      searchFields: const ['code', 'description', 'counterparty'],
      filterFields: const ['document_type'],
      dateRangeField: 'document_date',
      showSearch: true,
      showFilters: true,
      showPagination: true,
      showColumnSearch: true,
      showRefreshButton: true,
      showClearFiltersButton: true,
      showExportButtons: true,
      enableRowSelection: true,
      enableMultiRowSelection: true,
      defaultPageSize: 20,
      pageSizeOptions: const [10, 20, 50, 100],
      onRowSelectionChanged: (rows) {
        setState(() {
          _selectedCount = rows.length;
        });
      },
      additionalParams: {
        'document_type': _selectedInvoiceType,
        if (_fromDate != null) 'from_date': HesabixDateUtils.formatForApiDate(_fromDate!),
        if (_toDate != null) 'to_date': HesabixDateUtils.formatForApiDate(_toDate!),
        if (_isProforma != null) 'is_proforma': _isProforma,
        if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
        if (_selectedProjectId != null) 'project_id': _selectedProjectId,
        if (_selectedTagIds.isNotEmpty) 'tag_ids': _selectedTagIds,
        'tag_match': _tagMatch,
      },
      onRowTap: (item) => _onView(item as InvoiceListItem),
      emptyStateMessage: t.noInvoicesFound,
      loadingMessage: t.loadingInvoices,
      errorMessage: t.errorLoadingInvoices,
      customHeaderActions: [
        if (widget.authStore.canWriteSection('invoices'))
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
        if (widget.authStore.hasBusinessPermission('inventory', 'write')) ...[
          Tooltip(
            message: 'ایجاد پیش‌نویس حواله انبار برای فاکتورهای انتخاب‌شده (موجودی باقی‌مانده)',
            child: FilledButton.tonalIcon(
              onPressed: _selectedCount > 0 ? _onBulkCreateWarehouseDraft : null,
              icon: const Icon(Icons.add_box_outlined),
              label: Text('پیش‌نویس حواله ($_selectedCount)'),
            ),
          ),
          Tooltip(
            message: 'قطعی کردن پیش‌نویس حواله‌ها؛ در دیالوگ، نسبت به حواله‌های قبلاً صادرشده سیاست انتخاب کنید',
            child: FilledButton.tonalIcon(
              onPressed: _selectedCount > 0 ? _onBulkPostWarehouseDocuments : null,
              icon: const Icon(Icons.check_circle_outline),
              label: Text('صدور حواله ($_selectedCount)'),
            ),
          ),
          Tooltip(
            message: 'حذف پیش‌نویس‌ها یا لغو حواله‌های قطعی مرتبط با فاکتور (در صورت وجود حواله وابسته ابتدا آن را لغو کنید)',
            child: FilledButton.tonalIcon(
              onPressed: _selectedCount > 0 ? _onBulkRemoveInvoiceWarehouseDocuments : null,
              icon: const Icon(Icons.inventory_2_outlined),
              label: Text('حذف حواله‌های مرتبط ($_selectedCount)'),
            ),
          ),
        ],
        Tooltip(
          message: 'ایمپورت فاکتورها از فایل Excel',
          child: IconButton(
            onPressed: _onImport,
            icon: const Icon(Icons.upload_file),
            tooltip: 'ایمپورت از اکسل',
          ),
        ),
      ],
      footerTotals: {
        'total_amount': 'جمع مبلغ این صفحه',
        'paid_amount': t.invoicePaidAmount,
        'remaining_amount': t.invoiceRemainingAmount,
      },
      expandBodyHeightToFitRows: true,
      onAllFiltersCleared: _onDataTableAllFiltersCleared,
    );
  }

  Widget _buildMobileInvoiceSummaryCard(InvoiceListItem invoice) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    final amount = invoice.totalAmount != null
        ? '${formatWithThousands(invoice.totalAmount!, decimalPlaces: 2)} ${invoice.currencyCode ?? 'ریال'}'
        : '-';
    final paidStr = invoice.paidAmount != null
        ? '${formatWithThousands(invoice.paidAmount!, decimalPlaces: 2)} ${invoice.currencyCode ?? 'ریال'}'
        : null;
    final remainingStr = invoice.remainingAmount != null
        ? '${formatWithThousands(invoice.remainingAmount!, decimalPlaces: 2)} ${invoice.currencyCode ?? 'ریال'}'
        : null;
    final dateText = HesabixDateUtils.formatForDisplay(invoice.documentDate, widget.calendarController.isJalali);
    final typeText = (invoice.documentTypeName).trim().isNotEmpty ? invoice.documentTypeName : _invoiceTypeLabel(t, invoice.documentType);
    final counterparty = (invoice.counterparty == null || invoice.counterparty!.trim().isEmpty) ? t.unknown : invoice.counterparty!;
    final project = invoice.projectName ?? '-';
    final createdBy = invoice.createdByName ?? t.unknown;
    final desc = (invoice.description ?? '').trim();
    final tax = (invoice.taxStatus ?? '').trim();

    List<_InvoiceActionItem> buildActions() {
      final actions = <_InvoiceActionItem>[
        _InvoiceActionItem(
          icon: Icons.visibility,
          label: t.view,
          onTap: () => _onView(invoice),
        ),
        _InvoiceActionItem(
          icon: Icons.picture_as_pdf,
          label: t.printPdf,
          onTap: () => _printInvoicePdfFromList(invoice),
        ),
      ];
      if (widget.authStore.canWriteSection('invoices')) {
        actions.addAll([
          _InvoiceActionItem(
            icon: Icons.edit,
            label: t.edit,
            onTap: () => _onEdit(invoice),
          ),
          _InvoiceActionItem(
            icon: Icons.copy_outlined,
            label: t.invoiceCopyOpenNew,
            onTap: () async {
              if (!mounted) return;
              await BusinessNamedRoutes.pushNamed(
                context,
                businessId: widget.businessId,
                routeName: 'business_new_invoice',
                pathParameters: {
                  'business_id': widget.businessId.toString(),
                },
                queryParameters: {
                  'copy_from': '${invoice.id}',
                },
              );
              if (!mounted) return;
              _refreshData();
            },
          ),
          _InvoiceActionItem(
            icon: Icons.delete,
            label: t.delete,
            isDestructive: true,
            onTap: () => _onDelete(invoice),
          ),
          _InvoiceActionItem(
            icon: Icons.drive_folder_upload,
            label: t.taxAddToWorkspaceSingle,
            onTap: () => _onAddToTaxWorkspace(invoice),
          ),
          _InvoiceActionItem(
            icon: Icons.folder_off,
            label: t.taxRemoveFromWorkspaceSingle,
            onTap: () => _onRemoveFromTaxWorkspace(invoice),
          ),
        ]);
      }
      return actions;
    }

    Widget badge({required IconData icon, required String text}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              text,
              style: theme.textTheme.labelMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ],
        ),
      );
    }

    // Constrain the card to stay within the row height so badges never spill into next row.
    final cardHeight = _mobileInvoiceRowHeight - (_mobileInvoiceCardVPadding * 2);

    final badges = <Widget>[
      badge(icon: Icons.event, text: dateText),
      badge(icon: Icons.folder_open, text: project),
      if (invoice.tags.isNotEmpty)
        badge(
          icon: Icons.label_outline,
          text: invoice.tags.length <= 2
              ? invoice.tags.map((e) => e.name).join('، ')
              : '${invoice.tags.take(2).map((e) => e.name).join('، ')} +${invoice.tags.length - 2}',
        ),
      badge(icon: Icons.person, text: createdBy),
      if (paidStr != null) badge(icon: Icons.payments, text: '${t.invoicePaidAmount}: $paidStr'),
      if (remainingStr != null) badge(icon: Icons.account_balance_wallet, text: '${t.invoiceRemainingAmount}: $remainingStr'),
      if (invoice.isProforma) badge(icon: Icons.description_outlined, text: t.proforma),
      if (invoice.isInstallmentSale) badge(icon: Icons.calendar_month, text: t.installmentColumn),
      if (tax.isNotEmpty) badge(icon: Icons.verified_outlined, text: tax),
      if (desc.isNotEmpty) badge(icon: Icons.notes, text: desc),
    ];

    return SizedBox(
      height: cardHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: _mobileInvoiceCardVPadding),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _onView(invoice),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                invoice.code,
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              amount,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          typeText,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          counterparty,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (int i = 0; i < badges.length; i++) ...[
                                if (i > 0) const SizedBox(width: 6),
                                badges[i],
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<int>(
                  tooltip: t.actions,
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (idx) {
                    final actions = buildActions();
                    if (idx >= 0 && idx < actions.length) actions[idx].onTap();
                  },
                  itemBuilder: (context) {
                    final actions = buildActions();
                    return List.generate(actions.length, (i) {
                      final a = actions[i];
                      return PopupMenuItem<int>(
                        value: i,
                        child: Row(
                          children: [
                            Icon(
                              a.icon,
                              size: 18,
                              color: a.isDestructive ? theme.colorScheme.error : null,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(a.label, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      );
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onImport() async {
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => InvoiceImportDialog(
        businessId: widget.businessId,
      ),
    );
    if (result == true && mounted) {
      _refreshData();
    }
  }

  Future<void> _onAddNew() async {
    if (!mounted) return;
    await BusinessNamedRoutes.pushNamed(
      context,
      businessId: widget.businessId,
      routeName: 'business_new_invoice',
      pathParameters: {
        'business_id': widget.businessId.toString(),
      },
    );
    if (!mounted) return;
    _refreshData();
  }

  Future<void> _onView(InvoiceListItem item) async {
    await showDialog(
      context: context,
      builder: (_) => DocumentDetailsDialog(
        documentId: item.id,
        calendarController: widget.calendarController,
      ),
    );
  }

  Future<void> _printInvoicePdfFromList(InvoiceListItem invoice) async {
    if (!mounted) return;
    await InvoicePdfPrintFlow.showPrintOptionsSheetAndDownload(
      context: context,
      businessId: widget.businessId,
      invoiceId: invoice.id,
      invoiceCode: invoice.code,
      documentType: invoice.documentType,
    );
  }

  Future<void> _onEdit(InvoiceListItem item) async {
    if (!mounted) return;
    await BusinessNamedRoutes.pushNamed(
      context,
      businessId: widget.businessId,
      routeName: 'business_edit_invoice',
      pathParameters: {
        'business_id': widget.businessId.toString(),
        'invoice_id': item.id.toString(),
      },
    );
    if (!mounted) return;
    _refreshData();
  }

  Future<void> _onBulkDelete() async {
    if (!mounted) return;
    final state = _tableKey.currentState;
    if (state == null) return;

    List<dynamic> selectedItems = const [];
    try {
      // ignore: avoid_dynamic_calls
      selectedItems = (state as dynamic).getSelectedItems();
    } catch (_) {}

    if (selectedItems.isEmpty) return;

    final items = selectedItems.cast<InvoiceListItem>();
    final ids = items.map((e) => e.id).toList();
    final codes = items.map((e) => e.code).toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('تأیید حذف گروهی'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('تعداد فاکتورهای انتخاب‌شده: ${ids.length}'),
              const SizedBox(height: 8),
              const Text('این عملیات غیرقابل بازگشت است. ادامه می‌دهید؟'),
              if (codes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'نمونه کدها: ${codes.take(5).join(', ')}${codes.length > 5 ? ' ...' : ''}',
                ),
              ],
            ],
          ),
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
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final rootNavigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await _invoiceService.deleteMultiple(
        businessId: widget.businessId,
        invoiceIds: ids,
      );
      if (!mounted) return;

      rootNavigator.pop();

      if (!mounted) return;
      setState(() {
        _selectedCount = 0;
      });

      final deletedList = result['deleted'] as List<dynamic>? ?? [];
      final deleted = deletedList.map((e) => (e is num) ? e.toInt() : int.tryParse(e.toString()) ?? 0).where((e) => e > 0).toList();
      final skippedList = result['skipped'] as List<dynamic>? ?? [];

      if (deleted.isNotEmpty) {
        SnackBarHelper.showSuccess(
          context,
          message: '${deleted.length} فاکتور با موفقیت حذف شد',
        );
      }
      if (skippedList.isNotEmpty) {
        final sample = skippedList.take(3).map((s) {
          final m = s is Map ? s : <String, dynamic>{};
          return '${m['code']}: ${m['reason']}';
        }).join('؛ ');
        SnackBarHelper.showWarning(
          context,
          message: '${skippedList.length} فاکتور حذف نشد: $sample',
        );
      }
      if (deleted.isEmpty && skippedList.isEmpty) {
        SnackBarHelper.show(context, message: 'عملیات انجام شد.');
      }

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _refreshData();
        });
      }
    } catch (e) {
      if (!mounted) return;
      rootNavigator.pop();
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
  }

  List<InvoiceListItem>? _getSelectedInvoiceItems() {
    final state = _tableKey.currentState;
    if (state == null) return null;
    try {
      // ignore: avoid_dynamic_calls
      final raw = (state as dynamic).getSelectedItems() as List<dynamic>;
      if (raw.isEmpty) return null;
      return raw.cast<InvoiceListItem>();
    } catch (_) {
      return null;
    }
  }

  Future<void> _onBulkPostWarehouseDocuments() async {
    final items = _getSelectedInvoiceItems();
    if (items == null || items.isEmpty) return;

    String policy = 'post_drafts_only';
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: const Text('صدور گروهی حواله انبار'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'برای هر فاکتور، در صورت وجود حوالهٔ قطعی از قبل، یکی از سیاست‌ها اعمال می‌شود. '
                    'گزینهٔ سوم همان قوانین امن «حذف حواله‌های مرتبط» را اجرا می‌کند، سپس پیش‌نویس تازه می‌سازد و قطعی می‌کند.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  RadioListTile<String>(
                    title: const Text('رد فاکتور اگر حواله قطعی دارد'),
                    subtitle: const Text('آن فاکتور در صدور گروهی نادیده گرفته می‌شود'),
                    value: 'skip',
                    groupValue: policy,
                    onChanged: (v) {
                      if (v != null) setLocal(() => policy = v);
                    },
                  ),
                  RadioListTile<String>(
                    title: const Text('فقط پیش‌نویس‌ها را قطعی کن'),
                    subtitle: const Text('حواله‌های قطعی قبلی دست نمی‌خورند'),
                    value: 'post_drafts_only',
                    groupValue: policy,
                    onChanged: (v) {
                      if (v != null) setLocal(() => policy = v);
                    },
                  ),
                  RadioListTile<String>(
                    title: const Text('حذف امن همه حواله‌های قبلی، سپس پیش‌نویس جدید و صدور'),
                    subtitle: const Text('در صورت مانع انبار، همان فاکتور خطا می‌گیرد و بقیه مستقل‌اند'),
                    value: 'remove_all_then_create_and_post',
                    groupValue: policy,
                    onChanged: (v) {
                      if (v != null) setLocal(() => policy = v);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, policy),
                child: const Text('ادامه'),
              ),
            ],
          );
        },
      ),
    );
    if (chosen == null || !mounted) return;

    await _confirmAndRunBulkWarehouse(
      title: 'صدور گروهی حواله',
      confirmMessage: '',
      operation: 'post_drafts',
      existingPostedPolicy: chosen,
      skipConfirmDialog: true,
    );
  }

  Future<void> _confirmAndRunBulkWarehouse({
    required String title,
    required String confirmMessage,
    required String operation,
    String? existingPostedPolicy,
    bool skipConfirmDialog = false,
  }) async {
    final items = _getSelectedInvoiceItems();
    if (items == null || items.isEmpty) return;

    if (!skipConfirmDialog) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Text(confirmMessage),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ادامه'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final rootNav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final idToCode = {for (final it in items) it.id: it.code};

    try {
      final data = await _warehouseBulkService.bulkWarehouseOperations(
        businessId: widget.businessId,
        operation: operation,
        invoiceIds: items.map((e) => e.id).toList(),
        existingPostedPolicy: existingPostedPolicy,
      );
      if (!mounted) return;
      rootNav.pop();

      final rawResults = data['results'] as List<dynamic>? ?? [];
      var okCount = 0;
      var failCount = 0;
      for (final r in rawResults) {
        if (r is Map && r['ok'] == true) {
          okCount++;
        } else {
          failCount++;
        }
      }

      if (mounted) {
        setState(() => _selectedCount = 0);
        _refreshData();
      }

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: const Text('نتیجه عملیات انبار (به‌ازای هر فاکتور)'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'موفق: $okCount — ناموفق/رد شده: $failCount',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  ...rawResults.map((r) {
                    final m = r is Map ? Map<String, dynamic>.from(r as Map) : <String, dynamic>{};
                    final id = m['invoice_id'];
                    final code = id != null ? idToCode[(id is num) ? id.toInt() : int.tryParse(id.toString()) ?? 0] : null;
                    final success = m['ok'] == true;
                    final msg = m['message']?.toString();
                    final codeErr = m['code']?.toString();
                    final blockWh = m['blocking_warehouse_code']?.toString();
                    final hint = m['hint']?.toString();
                    final postedWh = m['posted_warehouse_document_ids'];
                    final lines = <String>[
                      if (code != null && code.isNotEmpty) 'کد فاکتور: $code',
                      if (codeErr != null && codeErr.isNotEmpty) 'کد خطا: $codeErr',
                      if (msg != null && msg.isNotEmpty) msg,
                      if (postedWh != null && success) 'حواله‌های صادرشده: $postedWh',
                      if (blockWh != null && blockWh.isNotEmpty) 'حواله: $blockWh',
                      if (hint != null && hint.isNotEmpty) hint,
                    ];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                        ),
                        leading: Icon(
                          success ? Icons.check_circle : Icons.warning_amber_rounded,
                          color: success ? Colors.green : Colors.deepOrange,
                        ),
                        title: Text('شناسه فاکتور: ${id ?? "-"}'),
                        subtitle: Text(lines.where((e) => e.isNotEmpty).join('\n')),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('بستن'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      rootNav.pop();
      SnackBarHelper.showError(
        context,
        message: 'خطا در عملیات انبار: ${ErrorExtractor.forContext(e, context)}',
      );
    }
  }

  Future<void> _onBulkCreateWarehouseDraft() async {
    await _confirmAndRunBulkWarehouse(
      title: 'ثبت پیش‌نویس حواله انبار',
      confirmMessage:
          'برای هر فاکتور انتخاب‌شده، در صورت وجود کالای قابل رهگیری و ماندهٔ قابل ثبت، یک یا چند حوالهٔ پیش‌نویس ایجاد می‌شود.\n'
          'اگر برای یک فاکتور خطا رخ دهد، بقیهٔ فاکتورها همچنان پردازش می‌شوند.',
      operation: 'create_draft',
    );
  }

  Future<void> _onBulkRemoveInvoiceWarehouseDocuments() async {
    await _confirmAndRunBulkWarehouse(
      title: 'حذف / لغو حواله‌های مرتبط با فاکتور',
      confirmMessage:
          'پیش‌نویس‌ها حذف می‌شوند. برای حواله‌های قطعی، ابتدا حوالهٔ معکوس ساخته و ثبت می‌شود.\n'
          'اگر به‌خاطر حواله‌های بعدی (مثلاً انتقال) امکان لغو نباشد، آن فاکتور رد می‌شود و پیام راهنما نمایش داده می‌شود؛ بقیهٔ فاکتورها مستقل پردازش می‌شوند.',
      operation: 'remove_linked',
    );
  }

  Future<void> _onDelete(InvoiceListItem item) async {
    final t = AppLocalizations.of(context);
    
    // دریافت اطلاعات حذف
    Map<String, dynamic>? deleteInfo;
    try {
      deleteInfo = await _invoiceService.getInvoiceDeleteInfo(
        businessId: widget.businessId,
        invoiceId: item.id,
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: 'خطا در دریافت اطلاعات: ${ErrorExtractor.forContext(e, context)}',
      );
      return;
    }
    
    // بررسی کارپوشه مودیان
    if (deleteInfo['is_in_tax_workspace'] == true) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: t.deleteInvoiceTaxWorkspaceError);
      return;
    }
    
    // ساخت محتوای هشدار
    final List<Widget> warningWidgets = [
      Text(t.deleteInvoiceConfirm(item.code)),
      const SizedBox(height: 16),
    ];
    
    // نمایش اطلاعات اسناد دریافت/پرداخت
    final receiptPayments = deleteInfo['receipt_payment_documents'] as List<dynamic>?;
    if (receiptPayments != null && receiptPayments.isNotEmpty) {
      final nonZeroPayments = receiptPayments.where((p) => p['is_zero'] != true).toList();
      if (nonZeroPayments.isNotEmpty) {
        warningWidgets.add(
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.payment, size: 20, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Text(
                      t.deleteInvoiceReceiptPaymentsWarning,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...nonZeroPayments.take(3).map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${p['code']} (${p['type'] == 'receipt' ? 'دریافت' : 'پرداخت'}): ${formatWithThousands(p['amount'] ?? 0)}',
                    style: TextStyle(fontSize: 12),
                  ),
                )),
                if (nonZeroPayments.length > 3)
                  Text(
                    'و ${nonZeroPayments.length - 3} سند دیگر...',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
              ],
            ),
          ),
        );
        warningWidgets.add(const SizedBox(height: 12));
      }
    }
    
    // نمایش اطلاعات حواله‌های انبار
    final warehouseDocs = deleteInfo['warehouse_documents'] as List<dynamic>?;
    if (warehouseDocs != null && warehouseDocs.isNotEmpty) {
      final finalizedWarehouses = warehouseDocs.where((w) => w['is_finalized'] == true).toList();
      if (finalizedWarehouses.isNotEmpty) {
        warningWidgets.add(
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.inventory_2, size: 20, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Text(
                      t.deleteInvoiceWarehouseWarning,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...finalizedWarehouses.take(3).map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${w['code']}',
                    style: TextStyle(fontSize: 12),
                  ),
                )),
              ],
            ),
          ),
        );
        warningWidgets.add(const SizedBox(height: 12));
      }
    }
    
    // نمایش اطلاعات اقساط
    if (deleteInfo['has_installments'] == true) {
      final installmentInfo = deleteInfo['installment_info'] as Map<String, dynamic>?;
      if (installmentInfo != null) {
        warningWidgets.add(
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, size: 20, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.deleteInvoiceInstallmentsWarning(
                      installmentInfo['count']?.toString() ?? '0',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        warningWidgets.add(const SizedBox(height: 12));
      }
    }
    
    // نمایش dialog تأیید
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: Text(t.deleteConfirmTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: warningWidgets,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(t.delete),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // نمایش لودینگ
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final success = await _invoiceService.deleteInvoice(
        businessId: widget.businessId,
        invoiceId: item.id,
      );

      // همیشه ابتدا لودینگ را ببندیم (حتی اگر mounted=false شده باشد)
      // از navigator از پیش گرفته‌شده استفاده می‌کنیم تا pop روی route درست انجام شود
      if (navigator.canPop()) {
        navigator.pop();
      }

      if (!mounted) return;

      if (success) {
        SnackBarHelper.showSuccess(context, message: t.deletedInvoiceSuccess(item.code));
        _refreshData();
      } else {
        throw Exception(t.deleteInvoiceError);
      }
    } catch (e) {
      // اطمینان از بسته شدن لودینگ در صورت بروز خطا
      if (navigator.canPop()) {
        navigator.pop();
      }
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: t.deleteInvoiceErrorWithMessage(
          ErrorExtractor.forContext(e, context),
        ),
      );
    }
  }

  Future<void> _onAddToTaxWorkspace(InvoiceListItem item) async {
    final t = AppLocalizations.of(context);

    // فقط برای فاکتورهای فروش و برگشت از فروش و غیر پیش‌نویس
    final isSalesOrReturn = item.documentType == 'invoice_sales' || item.documentType == 'invoice_sales_return';
    if (!isSalesOrReturn || item.isProforma) {
      SnackBarHelper.showWarning(context, message: t.taxAddToWorkspaceNotAllowed);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.taxAddToWorkspaceDialogTitle),
        content: Text(t.taxAddToWorkspaceDialogMessage(item.code)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.drive_folder_upload),
            label: Text(t.confirm),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final success = await _invoiceService.addToTaxWorkspace(
        businessId: widget.businessId,
        invoiceId: item.id,
      );

      if (navigator.canPop()) {
        navigator.pop();
      }

      if (!mounted) return;

      if (success) {
        SnackBarHelper.showSuccess(context, message: t.taxAddToWorkspaceSuccess(item.code));
        _refreshData();
      } else {
        throw Exception(t.taxAddToWorkspaceError);
      }
    } catch (e) {
      if (navigator.canPop()) {
        navigator.pop();
      }
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: t.taxAddToWorkspaceErrorWithMessage(
          ErrorExtractor.forContext(e, context),
        ),
      );
    }
  }

  Future<void> _onRemoveFromTaxWorkspace(InvoiceListItem item) async {
    final t = AppLocalizations.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.taxRemoveFromWorkspaceDialogTitle),
        content: Text(t.taxRemoveFromWorkspaceDialogMessage(item.code)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.folder_off),
            label: Text(t.confirm),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final success = await _invoiceService.removeFromTaxWorkspace(
        businessId: widget.businessId,
        invoiceId: item.id,
      );

      if (navigator.canPop()) {
        navigator.pop();
      }

      if (!mounted) return;

      if (success) {
        SnackBarHelper.showSuccess(context, message: t.taxRemoveFromWorkspaceSuccess);
        _refreshData();
      } else {
        throw Exception(t.taxRemoveFromWorkspaceError);
      }
    } catch (e) {
      if (navigator.canPop()) {
        navigator.pop();
      }
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: t.taxRemoveFromWorkspaceErrorWithMessage(
          ErrorExtractor.forContext(e, context),
        ),
      );
    }
  }
}

class _InvoiceActionItem {
  final IconData icon;
  final String label;
  final bool isDestructive;
  final VoidCallback onTap;
  const _InvoiceActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });
}


