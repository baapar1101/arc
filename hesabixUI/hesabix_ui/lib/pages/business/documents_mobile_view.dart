import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/document_model.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/services/document_service.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/utils/number_formatters.dart' show formatWithThousands;
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/project/project_selector_widget.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';

/// نمای موبایل برای لیست اسناد (نمایش کارت‌ها + فیلتر BottomSheet + سرچ + Load more)
class DocumentsMobileView extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final AuthStore authStore;
  final ApiClient apiClient;
  final DocumentService service;

  final Future<void> Function() onCreateNew;
  final Future<void> Function(DocumentModel doc) onShowDetails;
  final Future<void> Function(DocumentModel doc) onEdit;
  final Future<void> Function(DocumentModel doc) onDelete;
  final Future<void> Function(List<int> documentIds) onBulkDelete;

  const DocumentsMobileView({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.authStore,
    required this.apiClient,
    required this.service,
    required this.onCreateNew,
    required this.onShowDetails,
    required this.onEdit,
    required this.onDelete,
    required this.onBulkDelete,
  });

  @override
  State<DocumentsMobileView> createState() => _DocumentsMobileViewState();
}

class _DocumentsMobileViewState extends State<DocumentsMobileView> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  final ScrollController _scrollCtrl = ScrollController();

  late final BusinessDashboardService _dashboardService =
      BusinessDashboardService(widget.apiClient);

  // Query state
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;

  int _page = 1;
  int _perPage = 20;
  int _totalPages = 0;

  String? _documentType; // null = all
  DateTime? _fromDate;
  DateTime? _toDate;

  int? _fiscalYearId;
  List<Map<String, dynamic>> _fiscalYears = [];
  int? _projectId;
  Person? _filterPerson;
  List<Map<String, dynamic>> _projectItems = [];

  final List<DocumentModel> _items = [];

  // Selection state
  final Set<int> _selectedIds = <int>{};
  bool get _selectionMode => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _searchCtrl.addListener(_onSearchChanged);
    widget.calendarController.addListener(_onCalendarChanged);
    _loadFiscalYears();
    _loadProjectLabels();
    _fetch(reset: true);
  }

  Future<void> _loadProjectLabels() async {
    try {
      final response = await widget.apiClient.post(
        '/businesses/${widget.businessId}/projects/search',
        data: {'take': 1000, 'skip': 0, 'is_active': true},
      );
      if (response.data['success'] == true) {
        final items = response.data['data']['items'] as List? ?? [];
        if (mounted) {
          setState(() {
            _projectItems = items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadFiscalYears() async {
    try {
      final items = await _dashboardService.listFiscalYears(widget.businessId);
      if (!mounted) return;
      setState(() {
        _fiscalYears = items;
        if (_fiscalYearId == null && _fiscalYears.isNotEmpty) {
          final current = _fiscalYears.firstWhere(
            (fy) => fy['is_current'] == true,
            orElse: () => _fiscalYears.first,
          );
          _fiscalYearId = current['id'] as int?;
        }
      });
    } catch (_) {}
  }

  void _onCalendarChanged() {
    if (!mounted) return;
    // رندر مجدد تاریخ‌ها و چیپ‌های وابسته به تقویم
    setState(() {});
  }

  @override
  void dispose() {
    widget.calendarController.removeListener(_onCalendarChanged);
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      _fetch(reset: true);
    });
  }

  void _onScroll() {
    if (_loading || _loadingMore) return;
    if (_totalPages != 0 && _page >= _totalPages) return;
    // When close to bottom, load more
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 320) {
      _fetch(reset: false);
    }
  }

  Future<void> _fetch({required bool reset}) async {
    if (_loading || _loadingMore) return;

    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _totalPages = 0;
        _items.clear();
        _selectedIds.clear();
      });
    } else {
      setState(() {
        _loadingMore = true;
        _error = null;
      });
    }

    try {
      final res = await widget.service.listDocuments(
        businessId: widget.businessId,
        documentType: _documentType,
        fiscalYearId: _fiscalYearId,
        fromDate: _fromDate == null ? null : HesabixDateUtils.formatForApiDate(_fromDate!),
        toDate: _toDate == null ? null : HesabixDateUtils.formatForApiDate(_toDate!),
        projectId: _projectId,
        personId: _filterPerson?.id,
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        page: _page,
        perPage: _perPage,
        sortBy: 'document_date',
        sortDesc: true,
      );

      final items = (res['items'] as List<DocumentModel>?) ?? const <DocumentModel>[];
      final pagination = res['pagination'] as Map<String, dynamic>?;
      final totalPages = (pagination?['total_pages'] as num?)?.toInt() ?? 0;

      if (!mounted) return;
      setState(() {
        _items.addAll(items);
        _totalPages = totalPages;
        // اگر total_pages ناموجود باشد، با طول items تصمیم می‌گیریم
        if (totalPages == 0 && items.length < _perPage) {
          _totalPages = _page; // no more pages
        }
        _page += 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _openFiltersSheet() async {
    final t = AppLocalizations.of(context);
    String? draftType = _documentType;
    DateTime? draftFrom = _fromDate;
    DateTime? draftTo = _toDate;
    int? draftFiscal = _fiscalYearId;
    int? draftProject = _projectId;
    Person? draftPerson = _filterPerson;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  Row(
                    children: [
                      Text('فیلترها', style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setModalState(() {
                            draftType = null;
                            draftFrom = null;
                            draftTo = null;
                            draftProject = null;
                            draftPerson = null;
                          });
                        },
                        child: Text(t.clear),
                      ),
                    ],
                  ),
                          DropdownButtonFormField<String?>(
                            value: draftType,
                            decoration: const InputDecoration(
                              labelText: 'نوع سند',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text('همه'),
                              ),
                              DropdownMenuItem<String?>(
                                value: 'manual',
                                child: Text('سند دستی'),
                              ),
                              DropdownMenuItem<String?>(
                                value: 'expense',
                                child: Text('هزینه'),
                              ),
                              DropdownMenuItem<String?>(
                                value: 'income',
                                child: Text('درآمد'),
                              ),
                              DropdownMenuItem<String?>(
                                value: 'receipt',
                                child: Text('دریافت'),
                              ),
                              DropdownMenuItem<String?>(
                                value: 'payment',
                                child: Text('پرداخت'),
                              ),
                              DropdownMenuItem<String?>(
                                value: 'transfer',
                                child: Text('انتقال'),
                              ),
                              DropdownMenuItem<String?>(
                                value: 'invoice',
                                child: Text('فاکتور'),
                              ),
                            ],
                            onChanged: (v) => setModalState(() => draftType = v),
                          ),
                          if (_fiscalYears.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<int>(
                              value: draftFiscal,
                              decoration: InputDecoration(
                                labelText: t.fiscalYear,
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: _fiscalYears.map<DropdownMenuItem<int>>((fy) {
                                final id = fy['id'] as int?;
                                final title = (fy['title'] ?? '').toString();
                                return DropdownMenuItem<int>(
                                  value: id,
                                  child: Text(
                                    title.isNotEmpty ? title : 'FY ${id ?? ''}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (v) => setModalState(() => draftFiscal = v),
                            ),
                          ],
                          const SizedBox(height: 12),
                          ProjectSelectorWidget(
                            businessId: widget.businessId,
                            apiClient: widget.apiClient,
                            selectedProjectId: draftProject,
                            onChanged: (v) => setModalState(() => draftProject = v),
                            authStore: widget.authStore,
                            calendarController: widget.calendarController,
                            allowNull: true,
                            labelText: 'پروژه',
                          ),
                          const SizedBox(height: 12),
                          PersonComboboxWidget(
                            businessId: widget.businessId,
                            selectedPerson: draftPerson,
                            onChanged: (v) => setModalState(() => draftPerson = v),
                            label: 'شخص',
                            hintText: 'همه اشخاص',
                            searchHint: 'جست‌وجو در اشخاص...',
                          ),
                          const SizedBox(height: 12),
                          DateInputField(
                            calendarController: widget.calendarController,
                            onChanged: (d) => setModalState(() => draftFrom = d),
                            labelText: t.dateFrom,
                            hintText: t.selectDate,
                            value: draftFrom,
                          ),
                          const SizedBox(height: 12),
                          DateInputField(
                            calendarController: widget.calendarController,
                            onChanged: (d) => setModalState(() => draftTo = d),
                            labelText: t.dateTo,
                            hintText: t.selectDate,
                            value: draftTo,
                          ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _documentType = draftType;
                        _fromDate = draftFrom;
                        _toDate = draftTo;
                        _fiscalYearId = draftFiscal;
                        _projectId = draftProject;
                        _filterPerson = draftPerson;
                      });
                      Navigator.pop(context);
                      _fetch(reset: true);
                    },
                    icon: const Icon(Icons.check),
                    label: Text(t.confirm),
                  ),
                ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _typeLabel(String? type) {
    switch (type) {
      case 'manual':
        return 'سند دستی';
      case 'expense':
        return 'هزینه';
      case 'income':
        return 'درآمد';
      case 'receipt':
        return 'دریافت';
      case 'payment':
        return 'پرداخت';
      case 'transfer':
        return 'انتقال';
      case 'invoice':
        return 'فاکتور';
      default:
        return 'همه';
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'manual':
        return Colors.blue;
      case 'expense':
        return Colors.red;
      case 'income':
        return Colors.green;
      case 'receipt':
        return Colors.teal;
      case 'payment':
        return Colors.orange;
      case 'transfer':
        return Colors.purple;
      case 'invoice':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  Widget _buildActiveFilterChips() {
    final t = AppLocalizations.of(context);
    final chips = <Widget>[];
    if (_documentType != null) {
      chips.add(
        InputChip(
          label: Text('نوع: ${_typeLabel(_documentType)}'),
          onDeleted: () {
            setState(() => _documentType = null);
            _fetch(reset: true);
          },
        ),
      );
    }
    if (_fiscalYearId != null && _fiscalYears.isNotEmpty) {
      final fy =
          _fiscalYears.where((e) => (e['id'] as int?) == _fiscalYearId).toList();
      final title = fy.isNotEmpty ? (fy.first['title'] ?? '').toString() : '';
      chips.add(
        InputChip(
          label: Text(title.isNotEmpty
              ? title
              : '${t.fiscalYear}: $_fiscalYearId'),
          onDeleted: () {
            setState(() => _fiscalYearId = null);
            _fetch(reset: true);
          },
        ),
      );
    }
    if (_projectId != null) {
      var lab = 'پروژه: $_projectId';
      for (final p in _projectItems) {
        if (p['id'] == _projectId) {
          lab = p['name']?.toString() ?? lab;
          break;
        }
      }
      chips.add(
        InputChip(
          label: Text(lab),
          onDeleted: () {
            setState(() => _projectId = null);
            _fetch(reset: true);
          },
        ),
      );
    }
    if (_filterPerson != null) {
      chips.add(
        InputChip(
          label: Text(_filterPerson!.displayName),
          onDeleted: () {
            setState(() => _filterPerson = null);
            _fetch(reset: true);
          },
        ),
      );
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
      chips.add(
        InputChip(
          label: Text('${t.documentDate}: $from → $to'),
          onDeleted: () {
            setState(() {
              _fromDate = null;
              _toDate = null;
            });
            _fetch(reset: true);
          },
        ),
      );
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: chips,
      ),
    );
  }

  void _toggleSelection(DocumentModel doc) {
    setState(() {
      if (_selectedIds.contains(doc.id)) {
        _selectedIds.remove(doc.id);
      } else {
        _selectedIds.add(doc.id);
      }
    });
  }

  Future<void> _confirmBulkDelete() async {
    if (_selectedIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأیید حذف'),
        content: Text('آیا از حذف ${_selectedIds.length} سند انتخاب‌شده اطمینان دارید؟\n\nتوجه: فقط اسناد دستی حذف خواهند شد.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.onBulkDelete(_selectedIds.toList());
    if (!mounted) return;
    await _fetch(reset: true);
  }

  Future<void> _openDocActions(DocumentModel doc) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.visibility),
                title: const Text('مشاهده'),
                onTap: () {
                  Navigator.pop(context);
                  widget.onShowDetails(doc);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('ویرایش'),
                enabled: doc.isEditable,
                onTap: doc.isEditable
                    ? () {
                        Navigator.pop(context);
                        widget.onEdit(doc);
                      }
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('حذف'),
                enabled: doc.isDeletable,
                onTap: doc.isDeletable
                    ? () {
                        Navigator.pop(context);
                        widget.onDelete(doc);
                      }
                    : null,
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCard(DocumentModel doc) {
    final theme = Theme.of(context);
    final selected = _selectedIds.contains(doc.id);
    final currency = doc.currencyCode ?? 'ریال';

    return Card(
      color: selected ? theme.colorScheme.primary.withValues(alpha: 0.06) : null,
      shape: RoundedRectangleBorder(
        side: selected
            ? BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.35))
            : BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (_selectionMode) {
            _toggleSelection(doc);
          } else {
            widget.onShowDetails(doc);
          }
        },
        onLongPress: () => _toggleSelection(doc),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'سند ${doc.code}',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                  Text(
                    HesabixDateUtils.formatForDisplay(doc.documentDate, widget.calendarController.isJalali),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'عملیات',
                    onPressed: () => _openDocActions(doc),
                    icon: const Icon(Icons.more_vert),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _typeColor(doc.documentType).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _typeColor(doc.documentType).withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      doc.getDocumentTypeName(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _typeColor(doc.documentType),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: doc.isProforma ? Colors.orange.withValues(alpha: 0.10) : Colors.green.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      doc.statusText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: doc.isProforma ? Colors.orange : Colors.green,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _AmountLine(
                      label: 'بدهکار',
                      value: '${formatWithThousands(doc.totalDebit.toInt())} $currency',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _AmountLine(
                      label: 'بستانکار',
                      value: '${formatWithThousands(doc.totalCredit.toInt())} $currency',
                    ),
                  ),
                ],
              ),
              if ((doc.projectName ?? '').trim().isNotEmpty || (doc.description ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                if ((doc.projectName ?? '').trim().isNotEmpty)
                  Text(
                    'پروژه: ${doc.projectName}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if ((doc.description ?? '').trim().isNotEmpty)
                  Text(
                    doc.description!.trim(),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(_selectionMode ? '${_selectedIds.length} انتخاب شد' : 'اسناد حسابداری'),
        actions: _selectionMode
            ? [
                IconButton(
                  tooltip: 'حذف',
                  onPressed: _confirmBulkDelete,
                  icon: const Icon(Icons.delete_forever),
                ),
                IconButton(
                  tooltip: 'لغو انتخاب',
                  onPressed: () => setState(() => _selectedIds.clear()),
                  icon: const Icon(Icons.clear),
                ),
              ]
            : [
                IconButton(
                  tooltip: t.refresh,
                  onPressed: () => _fetch(reset: true),
                  icon: const Icon(Icons.refresh),
                ),
              ],
      ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton(
              onPressed: () async {
                await widget.onCreateNew();
                if (!mounted) return;
                await _fetch(reset: true);
              },
              child: const Icon(Icons.add),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, size: 18),
                      hintText: 'جستجو در شماره سند و توضیحات…',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'فیلترها',
                  onPressed: _openFiltersSheet,
                  icon: const Icon(Icons.filter_alt),
                ),
              ],
            ),
          ),
          _buildActiveFilterChips(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _fetch(reset: true),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? ListView(
                          children: [
                            const SizedBox(height: 80),
                            Icon(Icons.error_outline, size: 52, color: theme.colorScheme.error),
                            const SizedBox(height: 12),
                            Center(
                              child: Text(
                                'خطا در بارگذاری: $_error',
                                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: FilledButton.icon(
                                onPressed: () => _fetch(reset: true),
                                icon: const Icon(Icons.refresh),
                                label: Text(t.refresh),
                              ),
                            ),
                          ],
                        )
                      : _items.isEmpty
                          ? ListView(
                              children: [
                                const SizedBox(height: 80),
                                Icon(Icons.inbox_outlined, size: 56, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                                const SizedBox(height: 12),
                                Center(
                                  child: Text(
                                    t.noDataFound,
                                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Center(
                                  child: OutlinedButton.icon(
                                    onPressed: _openFiltersSheet,
                                    icon: const Icon(Icons.filter_alt),
                                    label: const Text('فیلترها'),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              controller: _scrollCtrl,
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                              itemBuilder: (context, index) {
                                if (index == _items.length) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    child: Center(
                                      child: _loadingMore
                                          ? const CircularProgressIndicator()
                                          : (_totalPages != 0 && _page > _totalPages)
                                              ? Text('پایان لیست', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))
                                              : const SizedBox.shrink(),
                                    ),
                                  );
                                }
                                final doc = _items[index];
                                return _buildCard(doc);
                              },
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemCount: _items.length + 1,
                            ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountLine extends StatelessWidget {
  final String label;
  final String value;
  const _AmountLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          '$label:',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}


