import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/services/business_user_service.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/utils/web/web_utils.dart' as web_utils;
import 'package:hesabix_ui/widgets/crm/crm_ai_assistant_widget.dart';
import 'package:hesabix_ui/widgets/crm/crm_delete_confirm_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_responsive_dialog.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/widgets/crm/crm_section_card.dart';
import 'package:hesabix_ui/widgets/jalali_date_picker.dart';
import 'package:hesabix_ui/widgets/permission/permission_widgets.dart';

/// صفحه لیست سرنخ‌های CRM
class CrmLeadsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController? calendarController;

  const CrmLeadsPage({
    super.key,
    required this.businessId,
    required this.authStore,
    this.calendarController,
  });

  @override
  State<CrmLeadsPage> createState() => _CrmLeadsPageState();
}

class _CrmLeadsPageState extends State<CrmLeadsPage> {
  final CrmService _crmService = CrmService(apiClient: ApiClient());
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _processDefs = [];
  List<Map<String, dynamic>> _stages = [];
  List<Map<String, dynamic>> _leadSources = [];
  List<Map<String, dynamic>> _filterUsers = [];
  int? _filterProcessDefinitionId;
  int? _filterStageId;
  int? _filterAssignedToUserId;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _loading = true;
  String? _error;
  int _total = 0;
  int _page = 1;
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
    _loadLeadSources();
    _loadFilterUsers();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFilterUsers() async {
    try {
      final service = BusinessUserService(ApiClient());
      final res = await service.getBusinessUsers(widget.businessId);
      if (!mounted) return;
      setState(() {
        _filterUsers = res.users.map((u) => <String, dynamic>{'id': u.userId, 'name': u.userName}).toList();
      });
    } catch (_) {}
  }

  Future<void> _loadLeadSources() async {
    try {
      final result = await _crmService.listProcessDefinitions(
        businessId: widget.businessId,
        processType: 'lead_source',
        isActive: true,
      );
      if (!mounted) return;
      final list = result is List ? result : (result is Map && result['data'] is List ? result['data'] as List : <dynamic>[]);
      final List<Map<String, dynamic>> sources = [];
      for (final p in list) {
        final proc = p as Map<String, dynamic>?;
        if (proc == null) continue;
        final procName = proc['name']?.toString() ?? '';
        final stages = proc['stages'] as List<dynamic>? ?? [];
        for (final s in stages) {
          final stage = s as Map<String, dynamic>?;
          if (stage == null) continue;
          final code = stage['stage_code']?.toString() ?? '';
          final name = stage['name']?.toString() ?? '';
          if (code.isNotEmpty) {
            sources.add({'code': code, 'label': procName.isNotEmpty ? '$procName - $name' : name});
          }
        }
      }
      setState(() => _leadSources = sources);
    } catch (_) {}
  }

  Future<void> _loadProcessDefinitions() async {
    try {
      final result = await _crmService.listProcessDefinitions(
        businessId: widget.businessId,
        processType: 'lead_funnel',
        isActive: true,
      );
      final list = result is List ? result : (result is Map && result['data'] is List ? result['data'] as List : <dynamic>[]);
      if (!mounted) return;
      setState(() {
        _processDefs = list.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (_) {}
  }

  Future<void> _load({bool resetPage = false}) async {
    if (!mounted) return;
    if (resetPage) _page = 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _crmService.listLeads(
        businessId: widget.businessId,
        processDefinitionId: _filterProcessDefinitionId,
        stageId: _kanbanView ? null : _filterStageId,
        assignedToUserId: _filterAssignedToUserId,
        search: _searchQuery.isEmpty ? null : _searchQuery,
        page: _kanbanView ? 1 : _page,
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
        _error = e.toString();
        _loading = false;
      });
      SnackBarHelper.show(context, message: 'خطا در بارگذاری: $e', isError: true);
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
      final result = await _crmService.listLeads(
        businessId: widget.businessId,
        processDefinitionId: _filterProcessDefinitionId,
        stageId: _filterStageId,
        assignedToUserId: _filterAssignedToUserId,
        search: _searchQuery.isEmpty ? null : _searchQuery,
        page: 1,
        limit: 5000,
      );
      final data = result is Map<String, dynamic> ? result : <String, dynamic>{};
      final items = data['items'] is List ? (data['items'] as List).cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
      final headers = ['کد', 'نام', 'شرکت', 'موبایل', 'ایمیل', 'منبع', 'مرحله', 'تخصیص به', 'یادآوری بعدی', 'تاریخ ایجاد'];
      final sb = StringBuffer();
      sb.writeln('\uFEFF${headers.map(_csvEscape).join(',')}');
      for (final e in items) {
        final nextAt = e['next_follow_up_at']?.toString();
        final created = e['created_at']?.toString();
        sb.writeln([
          _csvEscape(e['code']?.toString()),
          _csvEscape(e['name']?.toString()),
          _csvEscape(e['company_name']?.toString()),
          _csvEscape(e['mobile']?.toString()),
          _csvEscape(e['email']?.toString()),
          _csvEscape(e['source_code']?.toString()),
          _csvEscape(e['stage_name']?.toString()),
          _csvEscape(e['assigned_to_name']?.toString()),
          _csvEscape(nextAt != null && nextAt.isNotEmpty ? nextAt.substring(0, nextAt.length > 19 ? 19 : nextAt.length) : null),
          _csvEscape(created != null && created.isNotEmpty ? created.substring(0, created.length > 19 ? 19 : created.length) : null),
        ].join(','));
      }
      final bytes = utf8.encode(sb.toString());
      await web_utils.saveBytesAsFileWeb(bytes, 'leads.csv', mimeType: 'text/csv; charset=utf-8');
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'فایل leads.csv ذخیره شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا در صادرات: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.authStore.canReadSection('crm')) {
      return AccessDeniedPage(message: 'شما دسترسی لازم برای مشاهده CRM را ندارید');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('سرنخ‌ها'),
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
              tooltip: 'سرنخ جدید',
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
                          hintText: 'نام، شرکت، موبایل، ایمیل',
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
                  Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      value: _filterProcessDefinitionId,
                      decoration: const InputDecoration(labelText: 'فانل سرنخ'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('همه')),
                        ..._processDefs.map((p) => DropdownMenuItem<int?>(
                              value: p['id'] as int?,
                              child: Text(p['name']?.toString() ?? ''),
                            )),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _filterProcessDefinitionId = v;
                          _filterStageId = null;
                          _stages = [];
                          if (v != null) {
                            final proc = _processDefs.firstWhere((e) => e['id'] == v, orElse: () => <String, dynamic>{});
                            _stages = (proc['stages'] is List ? (proc['stages'] as List).cast<Map<String, dynamic>>() : <Map<String, dynamic>>[]);
                          }
                        });
                        _load(resetPage: true);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_stages.isNotEmpty)
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        value: _filterStageId,
                        decoration: const InputDecoration(labelText: 'مرحله'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('همه')),
                          ..._stages.map((s) => DropdownMenuItem<int?>(
                                value: s['id'] as int?,
                                child: Text(s['name']?.toString() ?? ''),
                              )),
                        ],
                        onChanged: (v) {
                          setState(() => _filterStageId = v);
                          _load(resetPage: true);
                        },
                      ),
                    ),
                  if (_filterUsers.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        value: _filterAssignedToUserId,
                        decoration: const InputDecoration(labelText: 'تخصیص به', isDense: true),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('همه')),
                          ..._filterUsers.map((u) => DropdownMenuItem<int?>(
                                value: (u['id'] as num?)?.toInt(),
                                child: Text(u['name']?.toString() ?? ''),
                              )),
                        ],
                        onChanged: (v) {
                          setState(() => _filterAssignedToUserId = v);
                          _load(resetPage: true);
                        },
                      ),
                    ),
                  ],
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
                                Icon(Icons.contact_phone_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
                                const SizedBox(height: 16),
                                Text(
                                  _kanbanView && _filterProcessDefinitionId == null
                                      ? 'برای مشاهده نمای کانبان، ابتدا یک فانل سرنخ انتخاب کنید.'
                                      : 'هنوز سرنخی ثبت نشده است.',
                                ),
                                if (_processDefs.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      'ابتدا از منوی «فرایندها و زون ارجاعات» یک فرایند از نوع فانل سرنخ تعریف کنید.',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  )
                                else if (!_kanbanView && widget.authStore.hasBusinessPermission('crm', 'write')) ...[
                                  const SizedBox(height: 8),
                                  FilledButton.icon(
                                    onPressed: _onAdd,
                                    icon: const Icon(Icons.add),
                                    label: const Text('افزودن سرنخ'),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : _kanbanView
                            ? _buildLeadsKanbanView()
                            : RefreshIndicator(
                            onRefresh: () => _load(resetPage: true),
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _items.length,
                              itemBuilder: (context, index) {
                                final item = _items[index];
                                final name = item['name']?.toString() ?? '';
                                final code = item['code']?.toString() ?? '';
                                final stageName = item['stage_name']?.toString() ?? '';
                                final mobile = item['mobile']?.toString() ?? '';
                                final companyName = item['company_name']?.toString() ?? '';
                                final id = item['id'] as int?;
                                final convertedAt = item['converted_at'];
                                final personId = item['person_id'] as int?;
                                final personName = item['person_name']?.toString();
                                final isConverted = convertedAt != null || personId != null;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: isConverted ? Colors.green.shade100 : Theme.of(context).colorScheme.primaryContainer,
                                      child: Icon(
                                        isConverted ? Icons.check_circle : Icons.contact_phone,
                                        color: isConverted ? Colors.green : Theme.of(context).colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(child: Text(name)),
                                        if (isConverted)
                                          Chip(
                                            label: Text(personName ?? 'تبدیل شده', style: const TextStyle(fontSize: 12)),
                                            visualDensity: VisualDensity.compact,
                                            backgroundColor: Colors.green.shade50,
                                          ),
                                      ],
                                    ),
                                    subtitle: Text([if (code.isNotEmpty) code, companyName.isNotEmpty ? companyName : null, mobile.isNotEmpty ? mobile : null, stageName].whereType<String>().join(' · ')),
                                    trailing: widget.authStore.hasBusinessPermission('crm', 'write')
                                        ? PopupMenuButton<String>(
                                            onSelected: (v) {
                                              if (v == 'edit') _onEdit(item);
                                              if (v == 'convert' && id != null && !isConverted) _onConvertToCustomer(id, name);
                                              if (v == 'delete' && id != null) _onDelete(id, name);
                                            },
                                            itemBuilder: (_) => [
                                              const PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                                              if (!isConverted) const PopupMenuItem(value: 'convert', child: Text('تبدیل به مشتری')),
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
              tooltip: 'سرنخ جدید',
            )
          : null,
    );
  }

  Widget _buildLeadsKanbanView() {
    if (_filterProcessDefinitionId == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_kanban, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            const Text('برای مشاهده نمای کانبان، یک فانل سرنخ انتخاب کنید.'),
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
    for (final l in _items) {
      final sid = l['stage_id'] as int?;
      if (sid != null) {
        byStage.putIfAbsent(sid, () => []).add(l);
      }
    }
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
            final leads = sid != null ? (byStage[sid] ?? []) : [];
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
                            label: Text('${leads.length}'),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: leads.map<Widget>((l) {
                            final name = l['name']?.toString() ?? '';
                            final companyName = l['company_name']?.toString() ?? '';
                            final mobile = l['mobile']?.toString() ?? '';
                            final id = l['id'] as int?;
                            final isConverted = l['converted_at'] != null || l['person_id'] != null;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: isConverted ? Colors.green.shade100 : Theme.of(context).colorScheme.primaryContainer,
                                  child: Icon(
                                    isConverted ? Icons.check_circle : Icons.person_outline,
                                    size: 20,
                                    color: isConverted ? Colors.green.shade700 : Theme.of(context).colorScheme.onPrimaryContainer,
                                  ),
                                ),
                                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                  [if (companyName.isNotEmpty) companyName, if (mobile.isNotEmpty) mobile].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: widget.authStore.hasBusinessPermission('crm', 'write') && !isConverted
                                    ? PopupMenuButton<String>(
                                        onSelected: (v) {
                                          if (v == 'edit') _onEdit(l);
                                          if (v == 'convert' && id != null) _onConvertToCustomer(id, name);
                                          if (v == 'delete' && id != null) _onDelete(id, name);
                                        },
                                        itemBuilder: (_) => [
                                          const PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                                          const PopupMenuItem(value: 'convert', child: Text('تبدیل به مشتری')),
                                          const PopupMenuItem(value: 'delete', child: Text('حذف')),
                                        ],
                                      )
                                    : widget.authStore.hasBusinessPermission('crm', 'write')
                                        ? PopupMenuButton<String>(
                                            onSelected: (v) {
                                              if (v == 'edit') _onEdit(l);
                                              if (v == 'delete' && id != null) _onDelete(id, name);
                                            },
                                            itemBuilder: (_) => [
                                              const PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                                              const PopupMenuItem(value: 'delete', child: Text('حذف')),
                                            ],
                                          )
                                        : null,
                                onTap: () => _onEdit(l),
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
      builder: (ctx) => _LeadFormDialog(
        businessId: widget.businessId,
        processDefs: _processDefs,
        leadSources: _leadSources,
        crmService: _crmService,
        onSaved: () => _load(resetPage: true),
      ),
    );
  }

  void _onEdit(Map<String, dynamic> item) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _LeadFormDialog(
        businessId: widget.businessId,
        processDefs: _processDefs,
        leadSources: _leadSources,
        crmService: _crmService,
        initial: item,
        onSaved: () => _load(resetPage: true),
      ),
    );
  }


  Future<void> _onConvertToCustomer(int id, String name) async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) => _ConvertLeadDialog(
        businessId: widget.businessId,
        leadId: id,
        leadName: name,
        crmService: _crmService,
      ),
    );
    if (result == null || !mounted) return;
    try {
      final createDeal = result['create_deal'] as Map<String, dynamic>?;
      await _crmService.convertLeadToCustomer(
        businessId: widget.businessId,
        leadId: id,
        createDeal: createDeal?.isNotEmpty == true ? createDeal : null,
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'سرنخ به مشتری تبدیل شد${createDeal != null ? ' و فرصت فروش ایجاد شد' : ''}');
      _load(resetPage: true);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: $e', isError: true);
    }
  }

  Future<void> _onDelete(int id, String name) async {
    final t = AppLocalizations.of(context);
    final ok = await showCrmDeleteConfirmDialog(
      context,
      title: t.crmDeleteLeadTitle,
      message: t.crmDeleteLeadMessage(name),
    );
    if (ok != true || !mounted) return;
    try {
      await _crmService.deleteLead(businessId: widget.businessId, leadId: id);
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'سرنخ حذف شد');
      _load(resetPage: true);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: $e', isError: true);
    }
  }
}

/// دیالوگ تبدیل سرنخ به مشتری با گزینه ایجاد همزمان فرصت فروش
class _ConvertLeadDialog extends StatefulWidget {
  final int businessId;
  final int leadId;
  final String leadName;
  final CrmService crmService;

  const _ConvertLeadDialog({
    required this.businessId,
    required this.leadId,
    required this.leadName,
    required this.crmService,
  });

  @override
  State<_ConvertLeadDialog> createState() => _ConvertLeadDialogState();
}

class _ConvertLeadDialogState extends State<_ConvertLeadDialog> {
  bool _createDeal = false;
  List<Map<String, dynamic>> _pipelineDefs = [];
  List<Map<String, dynamic>> _stages = [];
  int? _selectedProcessId;
  int? _selectedStageId;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _amountController = TextEditingController(text: '0');
  bool _loadingPipelines = false;
  bool _loadingStages = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadPipelines();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadPipelines() async {
    setState(() => _loadingPipelines = true);
    try {
      final res = await widget.crmService.listProcessDefinitions(
        businessId: widget.businessId,
        processType: 'sales_pipeline',
        isActive: true,
      );
      if (!mounted) return;
      final list = res is List ? res : (res is Map && res['data'] is List ? res['data'] as List : <dynamic>[]);
      setState(() {
        _pipelineDefs = list.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loadingPipelines = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPipelines = false);
    }
  }

  Future<void> _loadStagesFor(int definitionId) async {
    setState(() { _loadingStages = true; _stages = []; _selectedStageId = null; });
    try {
      final res = await widget.crmService.listStages(businessId: widget.businessId, definitionId: definitionId);
      if (!mounted) return;
      final List<dynamic> data = res is List ? res as List : (res is Map && res['data'] is List ? res['data'] as List : <dynamic>[]);
      final list = data.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() {
        _stages = list;
        _loadingStages = false;
        if (_stages.isNotEmpty) _selectedStageId = _stages.first['id'] as int?;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingStages = false);
    }
  }

  void _onConfirm() {
    if (_createDeal) {
      final pid = _selectedProcessId;
      final sid = _selectedStageId;
      final title = _titleController.text.trim();
      final amountStr = _amountController.text.trim();
      if (pid == null || sid == null || title.isEmpty) {
        SnackBarHelper.show(context, message: 'پایپلاین، مرحله و عنوان فرصت فروش را وارد کنید.', isError: true);
        return;
      }
      final amount = int.tryParse(amountStr.replaceAll(',', '')) ?? 0;
      if (amount < 0) {
        SnackBarHelper.show(context, message: 'مبلغ نامعتبر است.', isError: true);
        return;
      }
      Navigator.of(context).pop(<String, dynamic>{
        'create_deal': <String, dynamic>{
          'process_definition_id': pid,
          'stage_id': sid,
          'title': title,
          'amount': amount,
        },
      });
    } else {
      Navigator.of(context).pop(<String, dynamic>{});
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return CrmResponsiveDialog(
      title: t.crmConvertLeadTitle,
      subtitle: t.crmConvertLeadSubtitle,
      maxWidth: 520,
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.of(context).pop(null), child: Text(t.cancel)),
        FilledButton(
          onPressed: _submitting ? null : _onConfirm,
          child: _submitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(t.crmConvertSubmit),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: cs.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('«${widget.leadName}»', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(t.crmConvertLeadIntro, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            value: _createDeal,
            onChanged: (v) {
              setState(() => _createDeal = v ?? false);
              if (v == true && _pipelineDefs.isNotEmpty && _selectedProcessId == null) {
                _selectedProcessId = _pipelineDefs.first['id'] as int?;
                if (_selectedProcessId != null) _loadStagesFor(_selectedProcessId!);
              }
            },
            title: Text(t.crmConvertWithDealLabel),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          if (_createDeal) ...[
            const SizedBox(height: 8),
            if (_loadingPipelines)
              const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else if (_pipelineDefs.isEmpty)
              ListTile(
                leading: Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
                title: Text(
                  t.crmConvertNoPipeline,
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onErrorContainer),
                ),
                tileColor: cs.errorContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              )
            else ...[
              DropdownButtonFormField<int>(
                value: _selectedProcessId,
                decoration: InputDecoration(labelText: t.crmConvertPipelineLabel, border: const OutlineInputBorder()),
                items: _pipelineDefs.map((e) {
                  final id = e['id'] as int?;
                  final name = e['name']?.toString() ?? '${e['code'] ?? id}';
                  return DropdownMenuItem<int>(value: id, child: Text(name));
                }).toList(),
                onChanged: (id) {
                  if (id != null) {
                    setState(() => _selectedProcessId = id);
                    _loadStagesFor(id);
                  }
                },
              ),
              const SizedBox(height: 12),
              if (_loadingStages)
                const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              else
                DropdownButtonFormField<int>(
                  value: _selectedStageId,
                  decoration: InputDecoration(labelText: t.crmConvertStageLabel, border: const OutlineInputBorder()),
                  items: _stages.map((e) {
                    final id = e['id'] as int?;
                    final name = e['name']?.toString() ?? '${e['code'] ?? id}';
                    return DropdownMenuItem<int>(value: id, child: Text(name));
                  }).toList(),
                  onChanged: (id) => setState(() => _selectedStageId = id),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(labelText: t.crmConvertDealTitleLabel, border: const OutlineInputBorder()),
                maxLength: 255,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                decoration: InputDecoration(labelText: t.crmConvertAmountLabel, border: const OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _LeadFormDialog extends StatefulWidget {
  final int businessId;
  final List<Map<String, dynamic>> processDefs;
  final List<Map<String, dynamic>> leadSources;
  final CrmService crmService;
  final Map<String, dynamic>? initial;
  final VoidCallback onSaved;

  const _LeadFormDialog({
    required this.businessId,
    required this.processDefs,
    required this.leadSources,
    required this.crmService,
    this.initial,
    required this.onSaved,
  });

  @override
  State<_LeadFormDialog> createState() => _LeadFormDialogState();
}

class _LeadFormDialogState extends State<_LeadFormDialog> {
  late TextEditingController _nameController;
  late TextEditingController _companyController;
  late TextEditingController _mobileController;
  late TextEditingController _emailController;
  late TextEditingController _descController;
  late TextEditingController _codeController;
  bool _codeAuto = true;
  int? _selectedProcessId;
  int? _selectedStageId;
  String? _selectedSourceCode;
  int? _selectedAssignedToUserId;
  DateTime? _nextFollowUpAt;
  List<Map<String, dynamic>> _stages = [];
  List<Map<String, dynamic>> _businessUsers = [];
  List<dynamic> _changeHistory = [];
  bool _historyLoading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _nameController = TextEditingController(text: i?['name']?.toString() ?? '');
    _codeController = TextEditingController(text: i?['code']?.toString() ?? '');
    _codeAuto = i == null;
    _companyController = TextEditingController(text: i?['company_name']?.toString() ?? '');
    _mobileController = TextEditingController(text: i?['mobile']?.toString() ?? '');
    _emailController = TextEditingController(text: i?['email']?.toString() ?? '');
    _descController = TextEditingController(text: i?['description']?.toString() ?? '');
    final nextAt = i?['next_follow_up_at']?.toString();
    if (nextAt != null && nextAt.isNotEmpty) {
      _nextFollowUpAt = DateTime.tryParse(nextAt);
    }
    if (i != null) {
      _selectedProcessId = i['process_definition_id'] as int?;
      _selectedStageId = i['stage_id'] as int?;
      _selectedSourceCode = i['source_code']?.toString();
      _selectedAssignedToUserId = (i['assigned_to_user_id'] as num?)?.toInt();
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
    _loadBusinessUsers();
  }

  Future<void> _loadBusinessUsers() async {
    try {
      final service = BusinessUserService(ApiClient());
      final res = await service.getBusinessUsers(widget.businessId);
      if (!mounted) return;
      setState(() {
        _businessUsers = res.users.map((u) => <String, dynamic>{'id': u.userId, 'name': u.userName}).toList();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _companyController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    final t = AppLocalizations.of(context);
    return CrmResponsiveDialog(
      title: isEdit ? 'ویرایش سرنخ' : 'سرنخ جدید',
      subtitle: t.crmLeadFormSubtitle,
      actions: [
        if (isEdit &&
            widget.initial != null &&
            widget.initial!['person_id'] == null &&
            widget.initial!['converted_at'] == null &&
            widget.initial!['id'] != null)
          TextButton.icon(
            onPressed: _saving ? null : () => _convertAndClose(),
            icon: const Icon(Icons.person_add, size: 18),
            label: const Text('تبدیل به مشتری'),
          ),
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('انصراف')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('ذخیره'),
        ),
      ],
      child: Form(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
              if (isEdit && (widget.initial!['id'] as int?) != null)
                CrmAIAssistantWidget(
                  businessId: widget.businessId,
                  crmService: widget.crmService,
                  leadId: widget.initial!['id'] as int?,
                ),
              if (isEdit && (widget.initial!['person_id'] != null || widget.initial!['converted_at'] != null))
                Builder(
                  builder: (ctx) {
                    final cs = Theme.of(ctx).colorScheme;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: cs.tertiaryContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.onTertiaryContainer.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, color: cs.onTertiaryContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'تبدیل شده به مشتری${widget.initial!['person_name'] != null ? ': ${widget.initial!['person_name']}' : ''}',
                              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                                    color: cs.onTertiaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              CrmSectionCard(
                title: t.crmSectionFunnel,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.leadSources.isNotEmpty)
                      DropdownButtonFormField<String?>(
                        value: _selectedSourceCode,
                        decoration: const InputDecoration(labelText: 'منبع سرنخ', isDense: true, border: OutlineInputBorder()),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('انتخاب نشده')),
                          ...widget.leadSources.map((s) => DropdownMenuItem<String?>(
                                value: s['code'] as String?,
                                child: Text(s['label']?.toString() ?? s['code']?.toString() ?? ''),
                              )),
                        ],
                        onChanged: (v) => setState(() => _selectedSourceCode = v),
                      ),
                    if (widget.leadSources.isNotEmpty) const SizedBox(height: 12),
                    DropdownButtonFormField<int?>(
                      value: _selectedProcessId,
                      decoration: const InputDecoration(labelText: 'فانل سرنخ', border: OutlineInputBorder()),
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
                      onChanged: (v) => setState(() => _selectedStageId = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CrmSectionCard(
                title: t.crmSectionIdentityContact,
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
                          decoration: const InputDecoration(labelText: 'کد دستی', hintText: 'مثال: L-001', border: OutlineInputBorder()),
                          textCapitalization: TextCapitalization.characters,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'نام *', border: OutlineInputBorder()),
                      validator: (v) => v == null || v.trim().isEmpty ? 'الزامی' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _companyController,
                      decoration: const InputDecoration(labelText: 'نام شرکت', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _mobileController,
                      decoration: const InputDecoration(labelText: 'موبایل', border: OutlineInputBorder()),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(labelText: 'ایمیل', border: OutlineInputBorder()),
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CrmSectionCard(
                title: t.crmSectionDescription,
                child: TextFormField(
                  controller: _descController,
                  decoration: const InputDecoration(labelText: 'توضیحات', border: OutlineInputBorder()),
                  maxLines: 2,
                ),
              ),
              const SizedBox(height: 16),
              CrmSectionCard(
                title: t.crmSectionAssignmentFollowup,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_businessUsers.isNotEmpty)
                      DropdownButtonFormField<int?>(
                        value: _selectedAssignedToUserId,
                        decoration: const InputDecoration(labelText: 'تخصیص به', isDense: true, border: OutlineInputBorder()),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('انتخاب نشده')),
                          ..._businessUsers.map((u) => DropdownMenuItem<int?>(
                                value: (u['id'] as num?)?.toInt(),
                                child: Text(u['name']?.toString() ?? ''),
                              )),
                        ],
                        onChanged: (v) => setState(() => _selectedAssignedToUserId = v),
                      ),
                    if (_businessUsers.isNotEmpty) const SizedBox(height: 12),
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
                  ],
                ),
              ),
              if (isEdit && (widget.initial!['id'] as int?) != null) ...[
                const SizedBox(height: 16),
                ExpansionTile(
                  title: const Text('تاریخچه تغییرات'),
                  initiallyExpanded: false,
                  onExpansionChanged: (exp) {
                    if (exp && _changeHistory.isEmpty && !_historyLoading) _loadLeadHistory();
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
      ),
    );
  }

  Future<void> _loadLeadHistory() async {
    final id = widget.initial?['id'] as int?;
    if (id == null) return;
    setState(() => _historyLoading = true);
    try {
      final list = await widget.crmService.getLeadHistory(businessId: widget.businessId, leadId: id);
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
    if (_nameController.text.trim().isEmpty) {
      SnackBarHelper.show(context, message: 'نام الزامی است', isError: true);
      return;
    }
    if (_selectedProcessId == null || _selectedStageId == null) {
      SnackBarHelper.show(context, message: 'فانل و مرحله الزامی است', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.initial != null) {
        final id = widget.initial!['id'] as int?;
        if (id == null) throw Exception('شناسه نامعتبر');
        await widget.crmService.updateLead(
          businessId: widget.businessId,
          leadId: id,
          stageId: _selectedStageId,
          code: _codeController.text.trim().isEmpty ? null : _codeController.text.trim(),
          name: _nameController.text.trim(),
          sourceCode: _selectedSourceCode,
          companyName: _companyController.text.trim().isEmpty ? null : _companyController.text.trim(),
          mobile: _mobileController.text.trim().isEmpty ? null : _mobileController.text.trim(),
          email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          assignedToUserId: _selectedAssignedToUserId,
          nextFollowUpAt: _nextFollowUpAt,
        );
      } else {
        await widget.crmService.createLead(
          businessId: widget.businessId,
          processDefinitionId: _selectedProcessId!,
          stageId: _selectedStageId!,
          name: _nameController.text.trim(),
          code: _codeAuto ? null : (_codeController.text.trim().isEmpty ? null : _codeController.text.trim()),
          sourceCode: _selectedSourceCode,
          companyName: _companyController.text.trim().isEmpty ? null : _companyController.text.trim(),
          mobile: _mobileController.text.trim().isEmpty ? null : _mobileController.text.trim(),
          email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          assignedToUserId: _selectedAssignedToUserId,
          nextFollowUpAt: _nextFollowUpAt,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
      SnackBarHelper.show(context, message: 'ذخیره شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _convertAndClose() async {
    final id = widget.initial?['id'] as int?;
    final name = widget.initial?['name']?.toString() ?? '';
    if (id == null) return;
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) => _ConvertLeadDialog(
        businessId: widget.businessId,
        leadId: id,
        leadName: name,
        crmService: widget.crmService,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final createDeal = result['create_deal'] as Map<String, dynamic>?;
      await widget.crmService.convertLeadToCustomer(
        businessId: widget.businessId,
        leadId: id,
        createDeal: createDeal?.isNotEmpty == true ? createDeal : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
      SnackBarHelper.show(context, message: 'سرنخ به مشتری تبدیل شد${createDeal != null ? ' و فرصت فروش ایجاد شد' : ''}');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
