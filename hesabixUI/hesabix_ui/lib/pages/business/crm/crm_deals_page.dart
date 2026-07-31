import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import 'package:hesabix_ui/services/person_service.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/crm/crm_ai_assistant_widget.dart';
import 'package:hesabix_ui/widgets/crm/crm_delete_confirm_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_responsive_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_section_card.dart';
import 'package:hesabix_ui/widgets/crm/crm_tag_selector.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/jalali_date_picker.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/product_combobox_widget.dart';
import 'package:hesabix_ui/widgets/permission/permission_widgets.dart';
import 'package:intl/intl.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/services/bytes_export/bytes_export_service.dart';

/// صفحه لیست فرصت‌های فروش CRM
class CrmDealsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController? calendarController;

  const CrmDealsPage({
    super.key,
    required this.businessId,
    required this.authStore,
    this.calendarController,
  });

  @override
  State<CrmDealsPage> createState() => _CrmDealsPageState();
}

class _CrmDealsPageState extends State<CrmDealsPage> {
  final CrmService _crmService = CrmService(apiClient: ApiClient());
  final PersonService _personService = PersonService(apiClient: ApiClient());
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _processDefs = [];
  List<Map<String, dynamic>> _stages = [];
  List<Map<String, dynamic>> _filterPersons = [];
  int? _filterProcessDefinitionId;
  int? _filterStageId;
  int? _filterPersonId;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _loading = true;
  String? _error;
  int _total = 0;
  bool _kanbanView = false;

  @override
  void initState() {
    super.initState();
    final openAdd = GoRouterState.of(context).uri.queryParameters['openAdd'] == '1';
    _loadProcessDefinitions().then((_) {
      if (mounted && openAdd) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _onAdd();
        });
      }
    });
    _loadFilterPersons();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFilterPersons() async {
    try {
      final result = await _personService.getPersons(
        businessId: widget.businessId,
        page: 1,
        limit: 500,
      );
      if (!mounted) return;
      final data = result is Map ? result : <String, dynamic>{};
      final list = data['items'] ?? [];
      setState(() {
        _filterPersons = list is List
            ? list.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList()
            : <Map<String, dynamic>>[];
      });
    } catch (_) {}
  }

  Future<void> _loadProcessDefinitions() async {
    try {
      final result = await _crmService.listProcessDefinitions(
        businessId: widget.businessId,
        processType: 'sales_pipeline',
        isActive: true,
      );
      final list = result is List ? result : (result is Map && result['data'] is List ? result['data'] as List : <dynamic>[]);
      if (!mounted) return;
      setState(() {
        _processDefs = list.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
        if (_filterProcessDefinitionId != null) {
          final proc = _processDefs.cast<Map<String, dynamic>?>().firstWhere(
                (e) => e?['id'] == _filterProcessDefinitionId,
                orElse: () => <String, dynamic>{},
              );
          final stagesRaw = proc?['stages'];
          _stages = (stagesRaw is List)
              ? (stagesRaw as List).cast<Map<String, dynamic>>()
              : <Map<String, dynamic>>[];
        } else {
          _stages = [];
        }
      });
    } catch (_) {}
  }

  Future<void> _load({bool resetPage = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _crmService.listDeals(
        businessId: widget.businessId,
        processDefinitionId: _filterProcessDefinitionId,
        stageId: _kanbanView ? null : _filterStageId,
        personId: _filterPersonId,
        search: _searchQuery.isEmpty ? null : _searchQuery,
        page: resetPage ? 1 : 1,
        limit: _kanbanView ? 200 : 50,
      );
      if (!mounted) return;
      final data = result is Map<String, dynamic> ? result : <String, dynamic>{};
      final items = data['items'] is List ? (data['items'] as List).cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
      final total = data['total'] is int ? data['total'] as int : items.length;
      setState(() {
        _items = items;
        _total = total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
      SnackBarHelper.show(
        context,
        message: 'خطا در بارگذاری: ${ErrorExtractor.forContext(e, context)}',
        isError: true,
      );
    }
  }

  static String _csvEscape(String? s) {
    if (s == null) return '';
    final t = s.replaceAll('"', '""');
    if (t.contains(',') || t.contains('\n') || t.contains('"')) return '"$t"';
    return t;
  }

  Future<void> _exportCsv() async {
    try {
      final result = await _crmService.listDeals(
        businessId: widget.businessId,
        processDefinitionId: _filterProcessDefinitionId,
        stageId: _filterStageId,
        personId: _filterPersonId,
        search: _searchQuery.isEmpty ? null : _searchQuery,
        page: 1,
        limit: 5000,
      );
      final data = result is Map<String, dynamic> ? result : <String, dynamic>{};
      final items = data['items'] is List ? (data['items'] as List).cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
      final headers = ['عنوان', 'مشتری', 'مرحله', 'مبلغ (ریال)', 'احتمال %', 'تاریخ بستن پیش‌بینیشده', 'تخصیص به', 'تاریخ ایجاد'];
      final sb = StringBuffer();
      sb.writeln('\uFEFF${headers.map(_csvEscape).join(',')}');
      for (final e in items) {
        final amt = (e['amount'] as num?)?.toInt() ?? 0;
        final expClose = e['expected_close_date']?.toString();
        final created = e['created_at']?.toString();
        sb.writeln([
          _csvEscape(e['title']?.toString()),
          _csvEscape(e['person_name']?.toString()),
          _csvEscape(e['stage_name']?.toString()),
          _csvEscape(amt.toString()),
          _csvEscape(e['probability_percent']?.toString()),
          _csvEscape(expClose),
          _csvEscape(e['assigned_to_name']?.toString()),
          _csvEscape(created != null && created.isNotEmpty ? created.substring(0, created.length > 19 ? 19 : created.length) : null),
        ].join(','));
      }
      final bytes = utf8.encode(sb.toString());
      final exportResult = await BytesExportService.export(
        bytes: bytes,
        filename: 'deals.csv',
        mimeType: 'text/csv; charset=utf-8',
      );
      if (!mounted) return;
      BytesExportService.showFeedback(
        context,
        exportResult,
        successOverride: 'فایل deals.csv ذخیره شد',
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: 'خطا در صادرات: ${ErrorExtractor.forContext(e, context)}',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.authStore.canReadSection('crm')) {
      return AccessDeniedPage(message: 'شما دسترسی لازم برای مشاهده CRM را ندارید');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('فرصت‌های فروش'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) context.pop();
          },
        ),
        actions: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.list), label: Text('لیست')),
              ButtonSegment(value: true, icon: Icon(Icons.view_kanban), label: Text('کانبان')),
            ],
            selected: {_kanbanView},
            onSelectionChanged: (v) {
              setState(() {
                _kanbanView = v.first;
                _load(resetPage: true);
              });
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportCsv,
            tooltip: 'صادرات CSV',
          ),
          if (widget.authStore.hasBusinessPermission('crm', 'write'))
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _processDefs.isEmpty ? null : _onAdd,
              tooltip: 'فرصت فروش جدید',
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          labelText: 'جستجو',
                          hintText: 'عنوان، نام مشتری',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (v) {
                          setState(() {
                            _searchQuery = v.trim();
                            _load(resetPage: true);
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () {
                        setState(() {
                          _searchQuery = _searchController.text.trim();
                          _load(resetPage: true);
                        });
                      },
                      child: const Text('جستجو'),
                    ),
                    if (_searchQuery.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _load(resetPage: true);
                          });
                        },
                        tooltip: 'پاک کردن',
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_processDefs.isNotEmpty)
                  Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<int?>(
                      value: _filterProcessDefinitionId,
                      decoration: const InputDecoration(labelText: 'پایپلاین فروش', isDense: true),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('همه')),
                        ..._processDefs.map((p) => DropdownMenuItem<int?>(
                              value: p['id'] as int?,
                              child: Text(p['name']?.toString() ?? '', overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _filterProcessDefinitionId = v;
                          _filterStageId = null;
                          _stages = [];
                          if (v != null) {
                            final proc = _processDefs.cast<Map<String, dynamic>?>().firstWhere(
                                  (e) => e?['id'] == v,
                                  orElse: () => <String, dynamic>{},
                                );
                            final stagesRaw = proc?['stages'];
                            _stages = (stagesRaw is List)
                                ? (stagesRaw as List).cast<Map<String, dynamic>>()
                                : <Map<String, dynamic>>[];
                          }
                        });
                        _load(resetPage: true);
                      },
                    ),
                  ),
                  if (_stages.isNotEmpty)
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<int?>(
                        value: _filterStageId,
                        decoration: const InputDecoration(labelText: 'مرحله', isDense: true),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('همه')),
                          ..._stages.map((s) => DropdownMenuItem<int?>(
                                value: s['id'] as int?,
                                child: Text(s['name']?.toString() ?? '', overflow: TextOverflow.ellipsis),
                              )),
                        ],
                        onChanged: (v) {
                          setState(() => _filterStageId = v);
                          _load(resetPage: true);
                        },
                      ),
                    ),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<int?>(
                      value: _filterPersonId,
                      decoration: const InputDecoration(labelText: 'مشتری', isDense: true),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('همه')),
                        ..._filterPersons.map((p) => DropdownMenuItem<int?>(
                              value: p['id'] as int?,
                              child: Text(
                                p['display_name']?.toString() ?? p['name']?.toString() ?? '-',
                                overflow: TextOverflow.ellipsis,
                              ),
                            )),
                      ],
                      onChanged: (v) {
                        setState(() => _filterPersonId = v);
                        _load(resetPage: true);
                      },
                    ),
                  ),
                ],
              ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: () => _load(resetPage: true),
                              icon: const Icon(Icons.refresh),
                              label: const Text('تلاش مجدد'),
                            ),
                          ],
                        ),
                      )
                    : _items.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.trending_up_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
                                const SizedBox(height: 16),
                                Text(
                                  _kanbanView && _filterProcessDefinitionId == null
                                      ? 'برای مشاهده نمای کانبان، ابتدا یک پایپلاین فروش انتخاب کنید.'
                                      : 'هنوز فرصت فروشی ثبت نشده است.',
                                ),
                                if (_processDefs.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      'ابتدا از منوی «فرایندها و زون ارجاعات» یک فرایند از نوع پایپلاین فروش تعریف کنید.',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  )
                                else if (!_kanbanView && widget.authStore.hasBusinessPermission('crm', 'write')) ...[
                                  const SizedBox(height: 8),
                                  FilledButton.icon(
                                    onPressed: _onAdd,
                                    icon: const Icon(Icons.add),
                                    label: const Text('افزودن فرصت فروش'),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : _kanbanView
                            ? _buildKanbanView()
                            : RefreshIndicator(
                            onRefresh: () => _load(resetPage: true),
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _items.length,
                              itemBuilder: (context, index) {
                                final item = _items[index];
                                final title = item['title']?.toString() ?? '';
                                final code = item['code']?.toString() ?? '';
                                final personName = item['person_name']?.toString() ?? '';
                                final stageName = item['stage_name']?.toString() ?? '';
                                final amount = (item['amount'] is num) ? (item['amount'] as num).toDouble() : 0.0;
                                final formatter = NumberFormat('#,##0');
                                final id = item['id'] as int?;
                                final wonReason = item['won_reason_code']?.toString();
                                final lostReason = item['lost_reason_code']?.toString();
                                final tags = item['tags'] is List ? (item['tags'] as List) : const [];
                                String? reasonLine;
                                if (wonReason != null && wonReason.isNotEmpty) {
                                  reasonLine = 'برد: $wonReason';
                                } else if (lostReason != null && lostReason.isNotEmpty) {
                                  reasonLine = 'باخت: $lostReason';
                                }
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    isThreeLine: tags.isNotEmpty || reasonLine != null,
                                    leading: CircleAvatar(
                                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                      child: Icon(Icons.trending_up, color: Theme.of(context).colorScheme.onPrimaryContainer),
                                    ),
                                    title: Text(title),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text([if (code.isNotEmpty) code, personName, stageName, '${formatter.format(amount)} ریال'].join(' · ')),
                                        if (reasonLine != null)
                                          Text(reasonLine, style: Theme.of(context).textTheme.bodySmall),
                                        if (tags.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Wrap(
                                              spacing: 4,
                                              runSpacing: 4,
                                              children: tags.map<Widget>((tg) {
                                                final m = tg is Map ? Map<String, dynamic>.from(tg) : <String, dynamic>{};
                                                return _DealTagChip(name: m['name']?.toString() ?? '', colorHex: m['color']?.toString());
                                              }).toList(),
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: widget.authStore.hasBusinessPermission('crm', 'write')
                                        ? PopupMenuButton<String>(
                                            onSelected: (v) {
                                              if (v == 'edit') _onEdit(item);
                                              if (v == 'delete' && id != null) _onDelete(id, title);
                                            },
                                            itemBuilder: (_) => [
                                              const PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                                              const PopupMenuItem(value: 'delete', child: Text('حذف')),
                                            ],
                                          )
                                        : null,
                                    onTap: () => _onEdit(item),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
          ],
      ),
      floatingActionButton: widget.authStore.hasBusinessPermission('crm', 'write') && _processDefs.isNotEmpty && _items.isNotEmpty
          ? FloatingActionButton(
              onPressed: _onAdd,
              child: const Icon(Icons.add),
              tooltip: 'فرصت فروش جدید',
            )
          : null,
    );
  }

  Widget _buildKanbanView() {
    if (_filterProcessDefinitionId == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_kanban, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            const Text('برای مشاهده نمای کانبان، یک پایپلاین فروش انتخاب کنید.'),
          ],
        ),
      );
    }
    List<Map<String, dynamic>> stages = [];
    for (final p in _processDefs) {
      if (p['id'] == _filterProcessDefinitionId) {
        final s = p['stages'] as List<dynamic>? ?? [];
        stages = s.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
        stages.sort((a, b) => ((a['order_index'] ?? 0) as int).compareTo((b['order_index'] ?? 0) as int));
        break;
      }
    }
    final Map<int, List<Map<String, dynamic>>> byStage = {};
    for (final d in _items) {
      final sid = d['stage_id'] as int?;
      if (sid != null) {
        byStage.putIfAbsent(sid, () => []).add(d);
      }
    }
    final formatter = NumberFormat('#,##0');
    final height = MediaQuery.of(context).size.height - 280;
    return RefreshIndicator(
      onRefresh: () => _load(resetPage: true),
      child: SizedBox(
        height: height > 300 ? height : 400,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(16),
        children: stages.map((stage) {
          final sid = stage['id'] as int?;
          final stageName = stage['name']?.toString() ?? '';
          final colorHex = stage['color']?.toString();
          Color? col;
          if (colorHex != null && colorHex.isNotEmpty) {
            try {
              col = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
            } catch (_) {}
          }
          final deals = sid != null ? (byStage[sid] ?? []) : [];
          return SizedBox(
            width: 280,
            child: Card(
              margin: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (col ?? Theme.of(context).colorScheme.primaryContainer).withOpacity(0.3),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            stageName,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Chip(
                          label: Text('${deals.length}'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: deals.map<Widget>((d) {
                          final title = d['title']?.toString() ?? '';
                          final personName = d['person_name']?.toString() ?? '';
                          final amount = (d['amount'] is num) ? (d['amount'] as num).toDouble() : 0.0;
                          final id = d['id'] as int?;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              dense: true,
                              title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text('$personName · ${formatter.format(amount)} ریال', maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: widget.authStore.hasBusinessPermission('crm', 'write')
                                  ? PopupMenuButton<String>(
                                      onSelected: (v) {
                                        if (v == 'edit') _onEdit(d);
                                        if (v == 'delete' && id != null) _onDelete(id, title);
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                                        const PopupMenuItem(value: 'delete', child: Text('حذف')),
                                      ],
                                    )
                                  : null,
                              onTap: () => _onEdit(d),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
        ),
      ),
    );
  }

  void _onAdd() {
    if (!widget.authStore.hasBusinessPermission('crm', 'write') || _processDefs.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => _DealFormDialog(
        businessId: widget.businessId,
        authStore: widget.authStore,
        processDefs: _processDefs,
        crmService: _crmService,
        personService: _personService,
        calendarController: widget.calendarController,
        onSaved: () => _load(resetPage: true),
      ),
    );
  }

  void _onEdit(Map<String, dynamic> item) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _DealFormDialog(
        businessId: widget.businessId,
        authStore: widget.authStore,
        processDefs: _processDefs,
        crmService: _crmService,
        personService: _personService,
        calendarController: widget.calendarController,
        initial: item,
        onSaved: () => _load(resetPage: true),
      ),
    );
  }

  Future<void> _onDelete(int id, String title) async {
    final t = AppLocalizations.of(context);
    final ok = await showCrmDeleteConfirmDialog(
      context,
      title: t.crmDeleteDealTitle,
      message: t.crmDeleteDealMessage(title),
    );
    if (ok != true || !mounted) return;
    try {
      await _crmService.deleteDeal(businessId: widget.businessId, dealId: id);
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'فرصت فروش حذف شد');
      _load(resetPage: true);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }
}

class _DealTagChip extends StatelessWidget {
  final String name;
  final String? colorHex;
  const _DealTagChip({required this.name, this.colorHex});

  @override
  Widget build(BuildContext context) {
    Color? col;
    if (colorHex != null && colorHex!.isNotEmpty) {
      try {
        col = Color(int.parse(colorHex!.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }
    final base = col ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: base.withValues(alpha: 0.4)),
      ),
      child: Text(name, style: const TextStyle(fontSize: 11)),
    );
  }
}

/// شخص حداقلی برای نمایش در انتخاب‌گر (فقط id و نام)
Person _minimalPersonForDisplay(int businessId, int? id, String? name) {
  return Person(
    id: id,
    businessId: businessId,
    aliasName: name?.trim().isNotEmpty == true ? name! : 'مشتری',
    personTypes: [PersonType.customer],
    createdAt: DateTime(2020, 1, 1),
    updatedAt: DateTime(2020, 1, 1),
  );
}

class _DealFormDialog extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final List<Map<String, dynamic>> processDefs;
  final CrmService crmService;
  final PersonService personService;
  final CalendarController? calendarController;
  final Map<String, dynamic>? initial;
  final VoidCallback onSaved;

  const _DealFormDialog({
    required this.businessId,
    required this.authStore,
    required this.processDefs,
    required this.crmService,
    required this.personService,
    this.calendarController,
    this.initial,
    required this.onSaved,
  });

  @override
  State<_DealFormDialog> createState() => _DealFormDialogState();
}

class _DealFormDialogState extends State<_DealFormDialog> {
  late TextEditingController _titleController;
  late TextEditingController _amountController;
  late TextEditingController _descController;
  late TextEditingController _documentIdController;
  late TextEditingController _codeController;
  bool _codeAuto = true;
  int? _selectedProcessId;
  int? _selectedStageId;
  int? _selectedPersonId;
  Person? _selectedPerson;
  List<Map<String, dynamic>> _stages = [];
  List<Map<String, dynamic>> _personDocuments = [];
  List<Map<String, dynamic>> _currencies = [];
  int? _selectedCurrencyId;
  bool _loadingProbability = false;
  int? _probabilityPercent;
  DateTime? _expectedCloseDate;
  DateTime? _nextFollowUpAt;
  bool _saving = false;
  bool _loadingDocuments = false;
  int? _selectedDocumentId;
  List<dynamic> _changeHistory = [];
  bool _historyLoading = false;
  List<int> _selectedTagIds = [];
  List<_DealLineDraft> _lines = [];
  bool _loadingLines = false;
  String? _wonReasonCode;
  String? _lostReasonCode;
  String? _competitorName;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null && i['tags'] is List) {
      _selectedTagIds = (i['tags'] as List)
          .map((e) => (e is Map ? (e['id'] as num?)?.toInt() : null))
          .whereType<int>()
          .toList();
    }
    _wonReasonCode = i?['won_reason_code']?.toString();
    _lostReasonCode = i?['lost_reason_code']?.toString();
    _competitorName = i?['competitor_name']?.toString();
    _titleController = TextEditingController(text: i?['title']?.toString() ?? '');
    _codeController = TextEditingController(text: i?['code']?.toString() ?? '');
    _codeAuto = i == null;
    _amountController = TextEditingController(text: (i?['amount'] is num) ? '${i!['amount']}' : '');
    _descController = TextEditingController(text: i?['description']?.toString() ?? '');
    final docId = i?['document_id'];
    _documentIdController = TextEditingController(
      text: docId is num ? '$docId' : (docId?.toString() ?? ''),
    );
    if (i != null) {
      _selectedProcessId = i['process_definition_id'] as int?;
      _selectedStageId = i['stage_id'] as int?;
      final pid = (i['person_id'] as num?)?.toInt();
      _selectedPersonId = pid;
      final pName = i['person_name']?.toString();
      if (pid != null) _selectedPerson = _minimalPersonForDisplay(widget.businessId, pid, pName);
      _selectedCurrencyId = (i['currency_id'] as num?)?.toInt();
      _probabilityPercent = (i['probability_percent'] as num?)?.toInt();
      final expDate = i['expected_close_date'];
      _expectedCloseDate = expDate != null ? DateTime.tryParse(expDate.toString()) : null;
      final nextAt = i['next_follow_up_at']?.toString();
      _nextFollowUpAt = nextAt != null && nextAt.isNotEmpty ? DateTime.tryParse(nextAt) : null;
      if (_selectedProcessId != null) {
        final proc = widget.processDefs.firstWhere((e) => e['id'] == _selectedProcessId, orElse: () => <String, dynamic>{});
        _stages = (proc['stages'] is List ? (proc['stages'] as List).cast<Map<String, dynamic>>() : <Map<String, dynamic>>[]);
      }
    } else if (widget.processDefs.isNotEmpty) {
      _selectedProcessId = widget.processDefs.first['id'] as int?;
      final proc = widget.processDefs.first;
      _stages = (proc['stages'] is List ? (proc['stages'] as List).cast<Map<String, dynamic>>() : <Map<String, dynamic>>[]);
      _selectedStageId = _stages.isNotEmpty ? _stages.first['id'] as int? : null;
    }
    _loadCurrencies();
    if (i != null && i['closed_at'] == null && (i['person_id'] as int?) != null) {
      _loadPersonDocuments((i['person_id'] as int?)!);
      _selectedDocumentId = (i['document_id'] as num?)?.toInt();
    }
    if (i != null && (i['id'] as num?) != null) {
      _loadLines((i['id'] as num).toInt());
    }
  }

  Future<void> _loadLines(int dealId) async {
    setState(() => _loadingLines = true);
    try {
      final lines = await widget.crmService.getDealLines(businessId: widget.businessId, dealId: dealId);
      if (!mounted) return;
      setState(() {
        _lines = lines
            .map((l) {
              final pid = (l['product_id'] as num?)?.toInt();
              final desc = l['description']?.toString() ?? '';
              Map<String, dynamic>? product;
              if (pid != null) {
                product = {
                  'id': pid,
                  'name': desc.isNotEmpty ? desc : 'کالا #$pid',
                };
              }
              return _DealLineDraft(
                productId: pid,
                product: product,
                description: desc,
                quantity: (l['quantity'] as num?)?.toDouble() ?? 1,
                unitPrice: (l['unit_price'] as num?)?.toDouble() ?? 0,
              );
            })
            .toList();
        _loadingLines = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingLines = false);
    }
  }

  bool _isWinStage(int? stageId) {
    if (stageId == null) return false;
    final s = _stages.cast<Map<String, dynamic>?>().firstWhere((e) => e?['id'] == stageId, orElse: () => null);
    return s?['is_win'] == true;
  }

  bool _isLostStage(int? stageId) {
    if (stageId == null) return false;
    final s = _stages.cast<Map<String, dynamic>?>().firstWhere((e) => e?['id'] == stageId, orElse: () => null);
    return s?['is_lost'] == true;
  }

  Future<void> _onStageChanged(int? v) async {
    setState(() => _selectedStageId = v);
    if (_isWinStage(v)) {
      await _pickCloseReason(isWon: true);
    } else if (_isLostStage(v)) {
      await _pickCloseReason(isWon: false);
    }
  }

  Future<void> _pickCloseReason({required bool isWon}) async {
    List<Map<String, dynamic>> reasons = [];
    try {
      reasons = await widget.crmService.listCloseReasons(
        businessId: widget.businessId,
        reasonType: isWon ? 'won' : 'lost',
      );
    } catch (_) {}
    if (!mounted) return;
    String? selectedCode = isWon ? _wonReasonCode : _lostReasonCode;
    final competitorController = TextEditingController(text: _competitorName ?? '');
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        String? localCode = selectedCode;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(isWon ? 'دلیل برد' : 'دلیل باخت'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (reasons.isEmpty)
                  const Text('دلیلی تعریف نشده است. می‌توانید از تنظیمات CRM اضافه کنید.')
                else
                  DropdownButtonFormField<String?>(
                    value: localCode,
                    decoration: const InputDecoration(labelText: 'دلیل', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('انتخاب نشده')),
                      ...reasons.map((r) => DropdownMenuItem<String?>(
                            value: r['code']?.toString(),
                            child: Text(r['name']?.toString() ?? r['code']?.toString() ?? ''),
                          )),
                    ],
                    onChanged: (v) => setLocal(() => localCode = v),
                  ),
                if (!isWon) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: competitorController,
                    decoration: const InputDecoration(labelText: 'نام رقیب (اختیاری)', border: OutlineInputBorder()),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('انصراف')),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop({'code': localCode, 'competitor': competitorController.text.trim()}),
                child: const Text('تأیید'),
              ),
            ],
          ),
        );
      },
    );
    competitorController.dispose();
    if (result == null || !mounted) return;
    setState(() {
      if (isWon) {
        _wonReasonCode = result['code']?.toString();
      } else {
        _lostReasonCode = result['code']?.toString();
        _competitorName = (result['competitor']?.toString().isEmpty ?? true) ? null : result['competitor']?.toString();
      }
    });
  }

  Future<void> _issueProforma() async {
    final id = widget.initial?['id'] as int?;
    if (id == null) return;
    setState(() => _saving = true);
    try {
      final result = await widget.crmService.convertDealToInvoice(
        businessId: widget.businessId,
        dealId: id,
        isProforma: true,
        closeAsWon: false,
      );
      if (!mounted) return;
      final invoice = result['invoice'];
      final invCode = invoice is Map ? (invoice['code']?.toString() ?? invoice['id']?.toString()) : null;
      SnackBarHelper.show(context, message: 'پیش‌فاکتور صادر شد${invCode != null ? ' ($invCode)' : ''}');
      Navigator.of(context).pop();
      widget.onSaved();
    } catch (e) {
      if (!mounted) return;
      final msg = ErrorExtractor.forContext(e, context);
      final display = msg.contains('CRM_DEAL_NO_INVOICEABLE_LINES') || msg.contains('خط دارای کالا')
          ? 'برای صدور پیش‌فاکتور، حداقل یک خط دارای کالا لازم است. ابتدا خطوط فرصت فروش را با کالا کامل کنید.'
          : 'خطا: $msg';
      SnackBarHelper.show(context, message: display, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadPersonDocuments(int personId) async {
    setState(() => _loadingDocuments = true);
    try {
      final docs = await widget.crmService.listDocumentsForPerson(
        businessId: widget.businessId,
        personId: personId,
        limit: 100,
      );
      if (!mounted) return;
      setState(() {
        _personDocuments = docs;
        _loadingDocuments = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDocuments = false);
    }
  }

  Future<void> _loadCurrencies() async {
    try {
      final currencyService = CurrencyService(ApiClient());
      final list = await currencyService.listBusinessCurrencies(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _currencies = list;
        if (_selectedCurrencyId == null && list.isNotEmpty) {
          final def = list.cast<Map<String, dynamic>?>().firstWhere(
            (c) => c?['is_default'] == true,
            orElse: () => list.first,
          );
          _selectedCurrencyId = (def?['id'] as num?)?.toInt();
        }
      });
    } catch (_) {}
  }

  Future<void> _suggestDealProbability() async {
    final id = widget.initial?['id'] as int?;
    if (id == null) return;
    setState(() => _loadingProbability = true);
    try {
      final data = await widget.crmService.aiSuggestDealProbability(
        businessId: widget.businessId,
        dealId: id,
      );
      if (!mounted) return;
      final prob = (data is Map && data['probability_percent'] != null) ? (data['probability_percent'] as num).toInt() : null;
      setState(() {
        _loadingProbability = false;
        if (prob != null) _probabilityPercent = prob;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingProbability = false);
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _codeController.dispose();
    _amountController.dispose();
    _descController.dispose();
    _documentIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    final cal = widget.calendarController;
    final t = AppLocalizations.of(context);
    return CrmResponsiveDialog(
      title: isEdit ? 'ویرایش فرصت فروش' : 'فرصت فروش جدید',
      subtitle: t.crmDealFormSubtitle,
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('انصراف')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('ذخیره'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isEdit && (widget.initial!['id'] as int?) != null)
            CrmAIAssistantWidget(
              businessId: widget.businessId,
              crmService: widget.crmService,
              dealId: widget.initial!['id'] as int?,
            ),
          if (isEdit && (widget.initial!['id'] as int?) != null) const SizedBox(height: 12),
          CrmSectionCard(
            title: t.crmSectionDealCustomer,
            child: PersonComboboxWidget(
              businessId: widget.businessId,
              label: 'مشتری (شخص)',
              hintText: 'جست‌وجو و انتخاب مشتری',
              isRequired: true,
              personTypes: [PersonType.customer.persianName],
              selectedPerson: _selectedPerson,
              onChanged: (p) {
                setState(() {
                  _selectedPerson = p;
                  _selectedPersonId = p?.id;
                });
                if (p?.id != null) _loadPersonDocuments(p!.id!);
              },
            ),
          ),
          const SizedBox(height: 16),
          CrmSectionCard(
            title: t.crmSectionDealPipeline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isEdit)
                  TextFormField(
                    controller: _codeController,
                    decoration: const InputDecoration(labelText: 'کد', border: OutlineInputBorder()),
                    textCapitalization: TextCapitalization.characters,
                  ),
                if (isEdit) const SizedBox(height: 12),
                if (!isEdit) ...[
                  SwitchListTile(
                    title: const Text('کد خودکار'),
                    subtitle: Text(_codeAuto ? 'کد به صورت خودکار تولید می‌شود' : 'کد دستی وارد کنید'),
                    value: _codeAuto,
                    onChanged: (v) => setState(() => _codeAuto = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (!_codeAuto) ...[
                    TextFormField(
                      controller: _codeController,
                      decoration: const InputDecoration(labelText: 'کد دستی', hintText: 'مثال: D-001', border: OutlineInputBorder()),
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
                DropdownButtonFormField<int?>(
                  value: _selectedProcessId,
                  decoration: const InputDecoration(labelText: 'پایپلاین فروش', border: OutlineInputBorder()),
                  items: widget.processDefs.map((p) => DropdownMenuItem<int?>(value: p['id'] as int?, child: Text(p['name']?.toString() ?? ''))).toList(),
                  onChanged: isEdit
                      ? null
                      : (v) {
                          setState(() {
                            _selectedProcessId = v;
                            _selectedStageId = null;
                            if (v != null) {
                              final proc = widget.processDefs.firstWhere((e) => e['id'] == v, orElse: () => <String, dynamic>{});
                              _stages = (proc['stages'] is List ? (proc['stages'] as List).cast<Map<String, dynamic>>() : <Map<String, dynamic>>[]);
                              _selectedStageId = _stages.isNotEmpty ? _stages.first['id'] as int? : null;
                            } else {
                              _stages = [];
                            }
                          });
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  value: _selectedStageId,
                  decoration: const InputDecoration(labelText: 'مرحله', border: OutlineInputBorder()),
                  items: _stages.map((s) => DropdownMenuItem<int?>(value: s['id'] as int?, child: Text(s['name']?.toString() ?? ''))).toList(),
                  onChanged: (v) => _onStageChanged(v),
                ),
                if (_wonReasonCode != null && _wonReasonCode!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Chip(
                      avatar: const Icon(Icons.emoji_events_outlined, size: 16),
                      label: Text('دلیل برد: $_wonReasonCode'),
                      onDeleted: () => setState(() => _wonReasonCode = null),
                    ),
                  ),
                ],
                if (_lostReasonCode != null && _lostReasonCode!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Chip(
                      avatar: const Icon(Icons.sentiment_dissatisfied_outlined, size: 16),
                      label: Text('دلیل باخت: $_lostReasonCode${_competitorName != null ? ' · رقیب: $_competitorName' : ''}'),
                      onDeleted: () => setState(() {
                        _lostReasonCode = null;
                        _competitorName = null;
                      }),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'عنوان *', border: OutlineInputBorder()),
                  validator: (v) => v == null || v.trim().isEmpty ? 'الزامی' : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CrmSectionCard(
            title: t.crmSectionDealMoney,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _amountController,
                  decoration: const InputDecoration(labelText: 'مبلغ', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                if (_currencies.isNotEmpty)
                  DropdownButtonFormField<int?>(
                    value: _selectedCurrencyId,
                    decoration: const InputDecoration(labelText: 'ارز', isDense: true, border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('پیش‌فرض')),
                      ..._currencies.map((c) => DropdownMenuItem<int?>(
                            value: (c['id'] as num?)?.toInt(),
                            child: Text(c['code']?.toString() ?? c['title']?.toString() ?? ''),
                          )),
                    ],
                    onChanged: (v) => setState(() => _selectedCurrencyId = v),
                  ),
                if (_currencies.isNotEmpty) const SizedBox(height: 12),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    showValueIndicator: ShowValueIndicator.always,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('احتمال موفقیت: ${_probabilityPercent ?? 0}%', style: Theme.of(context).textTheme.bodySmall),
                          if (isEdit && (widget.initial!['id'] as int?) != null)
                            TextButton.icon(
                              onPressed: _loadingProbability ? null : _suggestDealProbability,
                              icon: _loadingProbability ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome, size: 16),
                              label: Text(_loadingProbability ? '...' : 'پیشنهاد AI'),
                              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                            ),
                        ],
                      ),
                      Slider(
                        value: (_probabilityPercent ?? 0).toDouble(),
                        min: 0,
                        max: 100,
                        divisions: 10,
                        label: '${_probabilityPercent ?? 0}%',
                        onChanged: (v) => setState(() => _probabilityPercent = v.round()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (cal != null)
                  DateInputField(
                    calendarController: cal,
                    labelText: 'تاریخ پیش‌بینی بسته شدن',
                    hintText: 'انتخاب تاریخ',
                    value: _expectedCloseDate,
                    onChanged: (v) => setState(() => _expectedCloseDate = v),
                  )
                else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                    title: Text('تاریخ پیش‌بینی بسته شدن'),
                    subtitle: Text(
                      _expectedCloseDate != null
                          ? HesabixDateUtils.formatForDisplay(
                              _expectedCloseDate,
                              widget.calendarController?.isJalali ??
                                  ApiClient.getCalendarController()?.isJalali ??
                                  true,
                            )
                          : 'انتخاب نشده',
                    ),
                    trailing: TextButton.icon(
                      onPressed: () async {
                        final picked = await showAdaptiveDatePicker(
                          context: context,
                          calendarController: widget.calendarController,
                          initialDate: _expectedCloseDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setState(() => _expectedCloseDate = picked);
                      },
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(_expectedCloseDate != null ? 'تغییر' : 'انتخاب'),
                    ),
                  ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                  title: Text(
                    _nextFollowUpAt == null
                        ? 'یادآور پیگیری: تعیین نشده'
                        : 'یادآور پیگیری: ${HesabixDateUtils.formatDateTime(
                            _nextFollowUpAt,
                            widget.calendarController?.isJalali ??
                                ApiClient.getCalendarController()?.isJalali ??
                                true,
                          )}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () async {
                          final date = await showAdaptiveDatePicker(
                            context: context,
                            calendarController: widget.calendarController,
                            initialDate: _nextFollowUpAt ?? DateTime.now(),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (date == null || !mounted) return;
                          final time = await showTimePicker(
                            context: context,
                            initialTime: _nextFollowUpAt != null ? TimeOfDay.fromDateTime(_nextFollowUpAt!) : TimeOfDay.now(),
                          );
                          if (time != null && mounted) {
                            setState(() => _nextFollowUpAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                          }
                        },
                        child: const Text('انتخاب'),
                      ),
                      if (_nextFollowUpAt != null)
                        TextButton(
                          onPressed: () => setState(() => _nextFollowUpAt = null),
                          child: const Text('پاک کردن'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descController,
                  decoration: const InputDecoration(labelText: 'توضیحات', border: OutlineInputBorder()),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CrmSectionCard(
            title: 'برچسب‌ها',
            child: CrmTagSelector(
              businessId: widget.businessId,
              crmService: widget.crmService,
              initialTagIds: _selectedTagIds,
              onChanged: (ids) => _selectedTagIds = ids,
            ),
          ),
          if (isEdit) ...[
            const SizedBox(height: 16),
            CrmSectionCard(
              title: 'خطوط فرصت فروش',
              subtitle: 'برای صدور پیش‌فاکتور، حداقل یک خط دارای کالا لازم است.',
              child: _loadingLines
                  ? const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_lines.isEmpty)
                          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('خطی اضافه نشده است.'))
                        else
                          ...List.generate(_lines.length, (index) {
                            final line = _lines[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ProductComboboxWidget(
                                          businessId: widget.businessId,
                                          authStore: widget.authStore,
                                          selectedProduct: line.product,
                                          label: 'کالا/خدمت',
                                          onChanged: (p) {
                                            setState(() {
                                              line.product = p;
                                              line.productId = (p?['id'] as num?)?.toInt();
                                              final name = p?['name']?.toString() ?? p?['title']?.toString() ?? '';
                                              if (name.isNotEmpty) line.description = name;
                                              final price = p?['sale_price'] ?? p?['price'] ?? p?['unit_price'];
                                              if (price is num && line.unitPrice == 0) {
                                                line.unitPrice = price.toDouble();
                                              }
                                            });
                                          },
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () => setState(() => _lines.removeAt(index)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    initialValue: line.description,
                                    decoration: const InputDecoration(labelText: 'شرح', isDense: true, border: OutlineInputBorder()),
                                    onChanged: (v) => line.description = v,
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          initialValue: line.quantity == line.quantity.roundToDouble() ? line.quantity.toInt().toString() : line.quantity.toString(),
                                          decoration: const InputDecoration(labelText: 'تعداد', isDense: true, border: OutlineInputBorder()),
                                          keyboardType: TextInputType.number,
                                          onChanged: (v) => line.quantity = double.tryParse(v.trim()) ?? line.quantity,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextFormField(
                                          initialValue: line.unitPrice == 0 ? '' : line.unitPrice.toInt().toString(),
                                          decoration: const InputDecoration(labelText: 'قیمت واحد', isDense: true, border: OutlineInputBorder()),
                                          keyboardType: TextInputType.number,
                                          onChanged: (v) => line.unitPrice = double.tryParse(v.trim()) ?? 0,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => setState(() => _lines.add(_DealLineDraft(quantity: 1, unitPrice: 0))),
                              icon: const Icon(Icons.add),
                              label: const Text('افزودن خط'),
                            ),
                            const Spacer(),
                            FilledButton.tonalIcon(
                              onPressed: _saving ? null : _issueProforma,
                              icon: const Icon(Icons.request_quote_outlined, size: 18),
                              label: const Text('صدور پیش‌فاکتور'),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
              if (isEdit && widget.initial!['closed_at'] == null) ...[
                const SizedBox(height: 16),
                const Divider(),
                Text('بستن معامله و اتصال به فاکتور', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (_loadingDocuments)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                  )
                else if (_personDocuments.isNotEmpty)
                  DropdownButtonFormField<int?>(
                    value: _selectedDocumentId,
                    decoration: const InputDecoration(labelText: 'انتخاب سند/فاکتور (اختیاری)', isDense: true),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('بدون اتصال به سند')),
                      ..._personDocuments.map((d) {
                        final id = d['id'] as int?;
                        final code = d['document_code']?.toString() ?? '';
                        final date = d['document_date']?.toString() ?? '';
                        final type = d['document_type_name'] ?? d['document_type'] ?? '';
                        final label = [code, date, type].where((x) => x.isNotEmpty).join(' · ');
                        return DropdownMenuItem<int?>(
                          value: id,
                          child: Text(label.isEmpty ? 'سند #$id' : label, overflow: TextOverflow.ellipsis),
                        );
                      }),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _selectedDocumentId = v;
                        _documentIdController.text = v?.toString() ?? '';
                      });
                    },
                  )
                else
                  TextFormField(
                    controller: _documentIdController,
                    decoration: const InputDecoration(
                      labelText: 'شناسه سند/فاکتور (اختیاری)',
                      hintText: 'در صورت اتصال به فاکتور، شناسه سند را وارد کنید',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _saving ? null : _closeDeal,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('بستن معامله'),
                ),
              ],
              if (isEdit && widget.initial!['closed_at'] != null)
                Builder(
                  builder: (ctx) {
                    final cs = Theme.of(ctx).colorScheme;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(top: 12),
                      decoration: BoxDecoration(
                        color: cs.tertiaryContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.onTertiaryContainer.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, color: cs.onTertiaryContainer),
                          const SizedBox(width: 8),
                          Text(
                            'معامله بسته شده',
                            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                                  color: cs.onTertiaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              if (isEdit && (widget.initial!['id'] as int?) != null) ...[
                const SizedBox(height: 16),
                ExpansionTile(
                  title: const Text('تاریخچه تغییرات'),
                  initiallyExpanded: false,
                  onExpansionChanged: (exp) {
                    if (exp && _changeHistory.isEmpty && !_historyLoading) _loadDealHistory();
                  },
                  children: [
                    if (_historyLoading)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                      )
                    else if (_changeHistory.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('تغییری ثبت نشده است.', style: TextStyle(fontSize: 13)),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _changeHistory.map<Widget>((h) {
                            final m = h is Map ? Map<String, dynamic>.from(h as Map) : <String, dynamic>{};
                            final changedAt = m['changed_at']?.toString() ?? '';
                            final fieldName = m['field_name']?.toString() ?? '';
                            final oldVal = m['old_value']?.toString() ?? '';
                            final newVal = m['new_value']?.toString() ?? '';
                            final by = m['changed_by_name']?.toString() ?? '';
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('$fieldName: $oldVal → $newVal', style: Theme.of(context).textTheme.bodySmall),
                                    const SizedBox(height: 4),
                                    Text('$changedAt · $by', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ],
            ],
        ),
    );
  }

  Future<void> _loadDealHistory() async {
    final id = widget.initial?['id'] as int?;
    if (id == null) return;
    setState(() => _historyLoading = true);
    try {
      final list = await widget.crmService.getDealHistory(businessId: widget.businessId, dealId: id);
      if (!mounted) return;
      setState(() {
        _changeHistory = list;
        _historyLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      SnackBarHelper.show(context, message: 'عنوان الزامی است', isError: true);
      return;
    }
    if (_selectedPersonId == null) {
      SnackBarHelper.show(context, message: 'انتخاب مشتری الزامی است', isError: true);
      return;
    }
    if (_selectedProcessId == null || _selectedStageId == null) {
      SnackBarHelper.show(context, message: 'پایپلاین و مرحله الزامی است', isError: true);
      return;
    }
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    setState(() => _saving = true);
    try {
      if (widget.initial != null) {
        final id = widget.initial!['id'] as int?;
        if (id == null) throw Exception('شناسه نامعتبر');
        await widget.crmService.updateDeal(
          businessId: widget.businessId,
          dealId: id,
          stageId: _selectedStageId,
          code: _codeController.text.trim().isEmpty ? null : _codeController.text.trim(),
          title: _titleController.text.trim(),
          amount: amount > 0 ? amount : null,
          currencyId: _selectedCurrencyId,
          probabilityPercent: _probabilityPercent,
          expectedCloseDate: _expectedCloseDate,
          nextFollowUpAt: _nextFollowUpAt,
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          wonReasonCode: _wonReasonCode,
          lostReasonCode: _lostReasonCode,
          competitorName: _competitorName,
          tagIds: _selectedTagIds,
        );
        try {
          await widget.crmService.replaceDealLines(
            businessId: widget.businessId,
            dealId: id,
            lines: _lines.map((l) => l.toJson()).toList(),
          );
        } catch (_) {}
      } else {
        await widget.crmService.createDeal(
          businessId: widget.businessId,
          personId: _selectedPersonId!,
          processDefinitionId: _selectedProcessId!,
          stageId: _selectedStageId!,
          title: _titleController.text.trim(),
          amount: amount,
          code: _codeAuto ? null : (_codeController.text.trim().isEmpty ? null : _codeController.text.trim()),
          currencyId: _selectedCurrencyId,
          probabilityPercent: _probabilityPercent,
          expectedCloseDate: _expectedCloseDate,
          nextFollowUpAt: _nextFollowUpAt,
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          tagIds: _selectedTagIds,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
      SnackBarHelper.show(context, message: 'ذخیره شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _closeDeal() async {
    final id = widget.initial?['id'] as int?;
    if (id == null) return;
    int? documentId = _selectedDocumentId;
    if (documentId == null) {
      final docIdStr = _documentIdController.text.trim();
      documentId = docIdStr.isNotEmpty ? int.tryParse(docIdStr) : null;
    }
    setState(() => _saving = true);
    try {
      await widget.crmService.updateDeal(
        businessId: widget.businessId,
        dealId: id,
        stageId: _selectedStageId,
        title: _titleController.text.trim(),
        amount: double.tryParse(_amountController.text.trim()),
        description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
        documentId: documentId,
        closedAt: DateTime.now(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
      SnackBarHelper.show(context, message: 'معامله بسته شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _DealLineDraft {
  int? productId;
  Map<String, dynamic>? product;
  String description;
  double quantity;
  double unitPrice;

  _DealLineDraft({
    this.productId,
    this.product,
    this.description = '',
    this.quantity = 1,
    this.unitPrice = 0,
  });

  Map<String, dynamic> toJson() => {
        if (productId != null) 'product_id': productId,
        'description': description,
        'quantity': quantity,
        'unit_price': unitPrice,
      };
}
