import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/services/business_user_service.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/crm/crm_delete_confirm_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_global_search_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_kanban_draggable.dart';
import 'package:hesabix_ui/widgets/crm/crm_saved_view_bar.dart';
import 'package:hesabix_ui/widgets/crm/crm_lead_form_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_lead_quick_create_dialog.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/widgets/permission/permission_widgets.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/services/bytes_export/bytes_export_service.dart';
import 'package:hesabix_ui/core/hesabix_back.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

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
  bool _filtersInSheet = false;
  List<Map<String, dynamic>> _savedViews = [];
  int? _activeViewId;

  @override
  void initState() {
    super.initState();
    final qp = GoRouterState.of(context).uri.queryParameters;
    final openAdd = qp['openAdd'] == '1';
    final leadIdRaw = qp['leadId'] ?? qp['lead_id'];
    final deepLeadId = leadIdRaw != null ? int.tryParse(leadIdRaw) : null;
    _loadProcessDefinitions().then((_) {
      if (!mounted) return;
      if (deepLeadId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.go('/business/${widget.businessId}/crm/leads/$deepLeadId');
        });
        return;
      }
      // پیش‌فرض فانل برای کانبان
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
    _loadLeadSources();
    _loadFilterUsers();
    _loadSavedViews();
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

  Future<void> _loadSavedViews() async {
    try {
      final views = await _crmService.listSavedViews(businessId: widget.businessId, entityType: 'lead');
      if (!mounted) return;
      setState(() => _savedViews = views);
    } catch (_) {}
  }

  Map<String, dynamic> _currentLeadFilters() {
    return {
      if (_filterProcessDefinitionId != null) 'process_definition_id': _filterProcessDefinitionId,
      if (_filterStageId != null) 'stage_id': _filterStageId,
      if (_filterAssignedToUserId != null) 'assigned_to_user_id': _filterAssignedToUserId,
      if (_searchQuery.isNotEmpty) 'search': _searchQuery,
      'kanban': _kanbanView,
    };
  }

  void _syncStagesForProcess() {
    _stages = [];
    if (_filterProcessDefinitionId == null) return;
    final proc = _processDefs.cast<Map<String, dynamic>?>().firstWhere(
          (e) => e?['id'] == _filterProcessDefinitionId,
          orElse: () => <String, dynamic>{},
        );
    final stagesRaw = proc?['stages'];
    _stages = stagesRaw is List ? stagesRaw.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
  }

  void _applySavedView(Map<String, dynamic> view) {
    final filters = view['filters'] is Map ? Map<String, dynamic>.from(view['filters'] as Map) : <String, dynamic>{};
    setState(() {
      _activeViewId = (view['id'] as num?)?.toInt();
      _filterProcessDefinitionId = (filters['process_definition_id'] as num?)?.toInt();
      _filterStageId = (filters['stage_id'] as num?)?.toInt();
      _filterAssignedToUserId = (filters['assigned_to_user_id'] as num?)?.toInt();
      _kanbanView = filters['kanban'] == true;
      _searchQuery = filters['search']?.toString() ?? '';
      _searchController.text = _searchQuery;
      _syncStagesForProcess();
    });
    _load(resetPage: true);
  }

  Future<void> _saveCurrentView() async {
    final nameController = TextEditingController();
    var shared = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('ذخیره نما'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'نام نما'),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('مشترک با تیم'),
                value: shared,
                onChanged: (v) => setLocal(() => shared = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('ذخیره')),
          ],
        ),
      ),
    );
    final name = nameController.text.trim();
    nameController.dispose();
    if (saved != true || name.isEmpty || !mounted) return;
    try {
      await _crmService.createSavedView(
        businessId: widget.businessId,
        entityType: 'lead',
        name: name,
        filters: _currentLeadFilters(),
        isShared: shared,
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'نما ذخیره شد');
      await _loadSavedViews();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: ErrorExtractor.forContext(e, context), isError: true);
    }
  }

  Future<void> _deleteSavedView(int id) async {
    try {
      await _crmService.deleteSavedView(businessId: widget.businessId, viewId: id);
      if (!mounted) return;
      setState(() {
        if (_activeViewId == id) _activeViewId = null;
      });
      await _loadSavedViews();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: ErrorExtractor.forContext(e, context), isError: true);
    }
  }

  void _openGlobalSearch() {
    CrmGlobalSearchDialog.show(context, businessId: widget.businessId, crmService: _crmService);
  }

  void _shortcutNew() {
    if (widget.authStore.hasBusinessPermission('crm', 'write') && _processDefs.isNotEmpty) {
      _onAdd();
    }
  }

  void _closeFilterSheetIfOpen() {
    if (_filtersInSheet) Navigator.of(context).pop();
  }

  Widget _withWorkspaceShortcuts(Widget child) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): _openGlobalSearch,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _openGlobalSearch,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _shortcutNew,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _shortcutNew,
      },
      child: Focus(autofocus: true, child: child),
    );
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
      final exportResult = await BytesExportService.export(
        bytes: bytes,
        filename: 'leads.csv',
        mimeType: 'text/csv; charset=utf-8',
      );
      if (!mounted) return;
      BytesExportService.showFeedback(
        context,
        exportResult,
        successOverride: 'فایل leads.csv ذخیره شد',
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

    return _withWorkspaceShortcuts(Scaffold(
      appBar: AppBar(
        title: const Text('سرنخ‌ها'),
        leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
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
            icon: const Icon(Icons.manage_search),
            tooltip: 'جست‌وجوی CRM (Ctrl+K)',
            onPressed: _openGlobalSearch,
          ),
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
                CrmSavedViewBar(
                  views: _savedViews,
                  activeId: _activeViewId,
                  canSave: widget.authStore.hasBusinessPermission('crm', 'write'),
                  onSave: _saveCurrentView,
                  onApply: _applySavedView,
                  onDelete: _deleteSavedView,
                ),
                const SizedBox(height: 8),
                if (_processDefs.isNotEmpty)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final fields = Row(
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
                        _closeFilterSheetIfOpen();
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
                          _closeFilterSheetIfOpen();
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
                          _closeFilterSheetIfOpen();
                        },
                      ),
                    ),
                  ],
                ],
                );
                      if (constraints.maxWidth >= 720) return fields;
                      return Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            setState(() => _filtersInSheet = true);
                            await showModalBottomSheet<void>(
                              context: context,
                              showDragHandle: true,
                              isScrollControlled: true,
                              builder: (ctx) => SafeArea(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                  child: fields,
                                ),
                              ),
                            );
                            if (mounted) setState(() => _filtersInSheet = false);
                          },
                          icon: const Icon(Icons.tune),
                          label: const Text('فیلتر فانل'),
                        ),
                      );
                    },
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
                                      'ابتدا از منوی «فرایندها و مراحل قیف» یک فرایند از نوع فانل سرنخ تعریف کنید.',
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
                                final score = (item['score'] as num?)?.toInt();
                                final slaDueRaw = item['sla_due_at']?.toString();
                                final slaDue = (slaDueRaw != null && slaDueRaw.isNotEmpty) ? DateTime.tryParse(slaDueRaw) : null;
                                final slaOverdue = slaDue != null && slaDue.isBefore(DateTime.now()) && !isConverted;
                                final subtitleLine = [if (code.isNotEmpty) code, companyName.isNotEmpty ? companyName : null, mobile.isNotEmpty ? mobile : null, stageName].whereType<String>().join(' · ');
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: isConverted ? SemanticColorResolver.positive(context).withValues(alpha: 0.18) : Theme.of(context).colorScheme.primaryContainer,
                                      child: Icon(
                                        isConverted ? Icons.check_circle : Icons.contact_phone,
                                        color: isConverted ? SemanticColorResolver.positive(context) : Theme.of(context).colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(child: Text(name)),
                                        if (score != null && score > 0)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 4),
                                            child: Chip(
                                              avatar: Icon(Icons.local_fire_department, size: 16, color: Theme.of(context).colorScheme.primary),
                                              label: Text('$score', style: TextStyle(fontSize: 12)),
                                              visualDensity: VisualDensity.compact,
                                            ),
                                          ),
                                        if (isConverted)
                                          Chip(
                                            label: Text(personName ?? 'تبدیل شده', style: TextStyle(fontSize: 12)),
                                            visualDensity: VisualDensity.compact,
                                            backgroundColor: SemanticColorResolver.positive(context).withValues(alpha: 0.12),
                                          ),
                                      ],
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (subtitleLine.isNotEmpty) Text(subtitleLine),
                                        if (slaOverdue)
                                          Text(
                                            'مهلت SLA گذشته است',
                                            style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                                          ),
                                      ],
                                    ),
                                    trailing: widget.authStore.hasBusinessPermission('crm', 'write')
                                        ? PopupMenuButton<String>(
                                            onSelected: (v) {
                                              if (v == 'edit') _openRecord(item);
                                              if (v == 'convert' && id != null && !isConverted) _onConvertToCustomer(id, name);
                                              if (v == 'delete' && id != null) _onDelete(id, name);
                                            },
                                            itemBuilder: (_) => [
                                              const PopupMenuItem(value: 'edit', child: Text('مشاهده / ویرایش')),
                                              if (!isConverted) const PopupMenuItem(value: 'convert', child: Text('تبدیل به مشتری')),
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
              tooltip: 'سرنخ جدید',
            )
          : null,
    ));
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
            final leads = sid != null ? (byStage[sid] ?? []) : [];
            return SizedBox(
              width: 280,
              child: DragTarget<Map<String, dynamic>>(
                onWillAcceptWithDetails: (details) {
                  final from = details.data['stage_id'] as int?;
                  return canWrite && sid != null && from != sid && details.data['converted_at'] == null && details.data['person_id'] == null;
                },
                onAcceptWithDetails: (details) {
                  if (sid != null) _moveLeadToStage(details.data, sid);
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
                              Chip(label: Text('${leads.length}'), visualDensity: VisualDensity.compact),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              children: [
                                ...leads.map<Widget>((l) {
                                  final name = l['name']?.toString() ?? '';
                                  final companyName = l['company_name']?.toString() ?? '';
                                  final mobile = l['mobile']?.toString() ?? '';
                                  final id = l['id'] as int?;
                                  final isConverted = l['converted_at'] != null || l['person_id'] != null;
                                  final card = Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      dense: true,
                                      leading: Icon(
                                        isConverted ? Icons.check_circle : Icons.drag_indicator,
                                        size: 20,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      subtitle: Text(
                                        [if (companyName.isNotEmpty) companyName, if (mobile.isNotEmpty) mobile].join(' · '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      onTap: () => _openRecord(l),
                                    ),
                                  );
                                  if (!canWrite || isConverted || id == null) return card;
                                  return CrmKanbanDraggable(data: l, feedbackTitle: name, child: card);
                                }),
                                if (canWrite)
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

  Future<void> _moveLeadToStage(Map<String, dynamic> lead, int stageId) async {
    final id = lead['id'] as int?;
    if (id == null) return;
    final prev = lead['stage_id'];
    setState(() => lead['stage_id'] = stageId);
    try {
      await _crmService.updateLead(businessId: widget.businessId, leadId: id, stageId: stageId);
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'مرحله سرنخ به‌روز شد');
      await _load(resetPage: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => lead['stage_id'] = prev);
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }

  void _openRecord(Map<String, dynamic> item) {
    final id = item['id'] as int?;
    if (id == null) return;
    context.go('/business/${widget.businessId}/crm/leads/$id');
  }

  void _onAdd({int? stageId}) {
    if (!widget.authStore.hasBusinessPermission('crm', 'write') || _processDefs.isEmpty) return;
    showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) => CrmLeadQuickCreateDialog(
        businessId: widget.businessId,
        processDefs: _processDefs,
        leadSources: _leadSources,
        crmService: _crmService,
        calendarController: widget.calendarController,
        initialProcessDefinitionId: _filterProcessDefinitionId,
        initialStageId: stageId ?? _filterStageId,
        onSaved: () => _load(resetPage: true),
      ),
    ).then((created) {
      if (!mounted) return;
      final id = (created?['id'] as num?)?.toInt();
      if (id != null) {
        context.go('/business/${widget.businessId}/crm/leads/$id');
      }
    });
  }

  Future<void> _onConvertToCustomer(int id, String name) async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) => CrmConvertLeadDialog(
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
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
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
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }
}
