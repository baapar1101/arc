import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/services/business_user_service.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/crm/crm_ai_assistant_widget.dart';
import 'package:hesabix_ui/widgets/crm/crm_responsive_dialog.dart';
import 'package:hesabix_ui/widgets/permission/permission_widgets.dart';

/// صفحه لیست سرنخ‌های CRM
class CrmLeadsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final dynamic calendarController;

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
        stageId: _filterStageId,
        assignedToUserId: _filterAssignedToUserId,
        search: _searchQuery.isEmpty ? null : _searchQuery,
        page: _page,
        limit: 50,
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
                                const Text('هنوز سرنخی ثبت نشده است.'),
                                if (_processDefs.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      'ابتدا از منوی «فرایندها و زون ارجاعات» یک فرایند از نوع فانل سرنخ تعریف کنید.',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  )
                                else if (widget.authStore.hasBusinessPermission('crm', 'write')) ...[
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تبدیل به مشتری'),
        content: Text('آیا می‌خواهید سرنخ «$name» را به مشتری تبدیل کنید؟ شخص جدید در بخش اشخاص ایجاد می‌شود.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('تبدیل')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _crmService.convertLeadToCustomer(businessId: widget.businessId, leadId: id);
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'سرنخ به مشتری تبدیل شد');
      _load(resetPage: true);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: $e', isError: true);
    }
  }

  Future<void> _onDelete(int id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف سرنخ'),
        content: Text('آیا از حذف سرنخ «$name» اطمینان دارید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('خیر')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('بله، حذف')),
        ],
      ),
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
  List<Map<String, dynamic>> _stages = [];
  List<Map<String, dynamic>> _businessUsers = [];
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
    return CrmResponsiveDialog(
      title: isEdit ? 'ویرایش سرنخ' : 'سرنخ جدید',
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
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تبدیل شده به مشتری${widget.initial!['person_name'] != null ? ': ${widget.initial!['person_name']}' : ''}',
                          style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              if (isEdit)
                TextFormField(
                  controller: _codeController,
                  decoration: const InputDecoration(labelText: 'کد'),
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
                    decoration: const InputDecoration(labelText: 'کد دستی', hintText: 'مثال: L-001'),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
              if (widget.leadSources.isNotEmpty)
                DropdownButtonFormField<String?>(
                  value: _selectedSourceCode,
                  decoration: const InputDecoration(labelText: 'منبع سرنخ', isDense: true),
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
                decoration: const InputDecoration(labelText: 'فانل سرنخ'),
                items: widget.processDefs.map((p) => DropdownMenuItem<int?>(value: p['id'] as int?, child: Text(p['name']?.toString() ?? ''))).toList(),
                onChanged: isEdit ? null : (v) {
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
                decoration: const InputDecoration(labelText: 'مرحله'),
                items: _stages.map((s) => DropdownMenuItem<int?>(value: s['id'] as int?, child: Text(s['name']?.toString() ?? ''))).toList(),
                onChanged: (v) => setState(() => _selectedStageId = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'نام *'),
                validator: (v) => v == null || v.trim().isEmpty ? 'الزامی' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _companyController,
                decoration: const InputDecoration(labelText: 'نام شرکت'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mobileController,
                decoration: const InputDecoration(labelText: 'موبایل'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'ایمیل'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(labelText: 'توضیحات'),
                maxLines: 2,
              ),
              if (_businessUsers.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  value: _selectedAssignedToUserId,
                  decoration: const InputDecoration(labelText: 'تخصیص به', isDense: true),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('انتخاب نشده')),
                    ..._businessUsers.map((u) => DropdownMenuItem<int?>(
                          value: (u['id'] as num?)?.toInt(),
                          child: Text(u['name']?.toString() ?? ''),
                        )),
                  ],
                  onChanged: (v) => setState(() => _selectedAssignedToUserId = v),
                ),
              ],
          ],
        ),
      ),
    );
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
    if (id == null) return;
    setState(() => _saving = true);
    try {
      await widget.crmService.convertLeadToCustomer(businessId: widget.businessId, leadId: id);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved();
      SnackBarHelper.show(context, message: 'سرنخ به مشتری تبدیل شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
