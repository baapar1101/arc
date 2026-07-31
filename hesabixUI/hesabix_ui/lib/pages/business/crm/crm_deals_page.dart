import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/services/person_service.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/crm/crm_deal_quick_create_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_close_deal_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_delete_confirm_dialog.dart';
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
    final qp = GoRouterState.of(context).uri.queryParameters;
    final openAdd = qp['openAdd'] == '1';
    final dealIdRaw = qp['dealId'] ?? qp['deal_id'];
    final deepDealId = dealIdRaw != null ? int.tryParse(dealIdRaw) : null;
    _loadProcessDefinitions().then((_) {
      if (!mounted) return;
      if (deepDealId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.go('/business/${widget.businessId}/crm/deals/$deepDealId');
        });
        return;
      }
      if (_processDefs.isNotEmpty && _filterProcessDefinitionId == null) {
        final def = _processDefs.cast<Map<String, dynamic>?>().firstWhere(
              (p) => p?['is_default'] == true,
              orElse: () => _processDefs.first,
            );
        setState(() {
          _filterProcessDefinitionId = def?['id'] as int?;
          _stages = (def?['stages'] is List
                  ? (def!['stages'] as List).cast<Map<String, dynamic>>()
                  : <Map<String, dynamic>>[]);
        });
      }
      if (openAdd) {
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
                                      'ابتدا از منوی «فرایندها و مراحل قیف» یک فرایند از نوع پایپلاین فروش تعریف کنید.',
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
                                              if (v == 'edit') _openRecord(item);
                                              if (v == 'delete' && id != null) _onDelete(id, title);
                                            },
                                            itemBuilder: (_) => [
                                              const PopupMenuItem(value: 'edit', child: Text('مشاهده / ویرایش')),
                                              const PopupMenuItem(value: 'delete', child: Text('حذف')),
                                            ],
                                          )
                                        : null,
                                    onTap: () => _openRecord(item),
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
    final canWrite = widget.authStore.hasBusinessPermission('crm', 'write');
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
            final isWin = stage['is_win'] == true;
            final isLost = stage['is_lost'] == true;
            return SizedBox(
              width: 280,
              child: DragTarget<Map<String, dynamic>>(
                onWillAcceptWithDetails: (details) {
                  final from = details.data['stage_id'] as int?;
                  return canWrite && sid != null && from != sid && details.data['closed_at'] == null;
                },
                onAcceptWithDetails: (details) {
                  if (sid != null) _moveDealToStage(details.data, sid, isTerminal: isWin || isLost);
                },
                builder: (context, candidate, rejected) {
                  final highlight = candidate.isNotEmpty;
                  return Card(
                    margin: const EdgeInsets.only(right: 12),
                    color: highlight ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35) : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: (col ?? Theme.of(context).colorScheme.primaryContainer).withValues(alpha: 0.3),
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
                              Chip(label: Text('${deals.length}'), visualDensity: VisualDensity.compact),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              children: [
                                ...deals.map<Widget>((d) {
                                  final title = d['title']?.toString() ?? '';
                                  final personName = d['person_name']?.toString() ?? '';
                                  final amount = (d['amount'] is num) ? (d['amount'] as num).toDouble() : 0.0;
                                  final id = d['id'] as int?;
                                  final closed = d['closed_at'] != null;
                                  final card = Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      dense: true,
                                      leading: Icon(
                                        closed ? Icons.lock_outline : Icons.drag_indicator,
                                        size: 20,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      subtitle: Text('$personName · ${formatter.format(amount)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                                      onTap: () => _openRecord(d),
                                    ),
                                  );
                                  if (!canWrite || closed || id == null) return card;
                                  return LongPressDraggable<Map<String, dynamic>>(
                                    data: d,
                                    feedback: Material(
                                      elevation: 6,
                                      borderRadius: BorderRadius.circular(12),
                                      child: SizedBox(
                                        width: 240,
                                        child: Card(
                                          child: ListTile(
                                            dense: true,
                                            title: Text(title, maxLines: 1),
                                            subtitle: const Text('رها کنید روی مرحله مقصد'),
                                          ),
                                        ),
                                      ),
                                    ),
                                    childWhenDragging: Opacity(opacity: 0.35, child: card),
                                    child: card,
                                  );
                                }),
                                if (canWrite && !isWin && !isLost)
                                  TextButton.icon(
                                    onPressed: () => _onAdd(stageId: sid),
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('افزودن'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _moveDealToStage(Map<String, dynamic> deal, int stageId, {required bool isTerminal}) async {
    final id = deal['id'] as int?;
    if (id == null) return;
    if (isTerminal) {
      List<Map<String, dynamic>> stages = [];
      for (final p in _processDefs) {
        if (p['id'] == _filterProcessDefinitionId) {
          stages = (p['stages'] is List ? (p['stages'] as List).cast<Map<String, dynamic>>() : <Map<String, dynamic>>[]);
          break;
        }
      }
      await showCrmCloseDealDialog(
        context,
        businessId: widget.businessId,
        dealId: id,
        crmService: _crmService,
        stages: stages,
        currentStageId: stageId,
        documentId: (deal['document_id'] as num?)?.toInt(),
        onClosed: () => _load(resetPage: true),
      );
      return;
    }
    final prev = deal['stage_id'];
    setState(() => deal['stage_id'] = stageId);
    try {
      await _crmService.updateDeal(businessId: widget.businessId, dealId: id, stageId: stageId);
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'مرحله فرصت به‌روز شد');
      await _load(resetPage: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => deal['stage_id'] = prev);
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }

  void _openRecord(Map<String, dynamic> item) {
    final id = item['id'] as int?;
    if (id == null) return;
    context.go('/business/${widget.businessId}/crm/deals/$id');
  }

  void _onAdd({int? stageId}) {
    if (!widget.authStore.hasBusinessPermission('crm', 'write') || _processDefs.isEmpty) return;
    showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) => CrmDealQuickCreateDialog(
        businessId: widget.businessId,
        authStore: widget.authStore,
        processDefs: _processDefs,
        crmService: _crmService,
        calendarController: widget.calendarController,
        initialProcessDefinitionId: _filterProcessDefinitionId,
        initialStageId: stageId ?? _filterStageId,
        onSaved: () => _load(resetPage: true),
      ),
    ).then((created) {
      if (!mounted) return;
      final id = (created?['id'] as num?)?.toInt();
      if (id != null) context.go('/business/${widget.businessId}/crm/deals/$id');
    });
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
