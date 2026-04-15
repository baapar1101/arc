import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/crm/crm_delete_confirm_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_responsive_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_section_card.dart';
import 'package:hesabix_ui/widgets/permission/permission_widgets.dart';

/// صفحه لیست فرایندهای CRM (فانل سرنخ، pipeline فروش و ...)
class CrmProcessDefinitionsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const CrmProcessDefinitionsPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<CrmProcessDefinitionsPage> createState() => _CrmProcessDefinitionsPageState();
}

class _CrmProcessDefinitionsPageState extends State<CrmProcessDefinitionsPage> {
  final CrmService _crmService = CrmService(apiClient: ApiClient());
  List<dynamic> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final openAdd = GoRouterState.of(context).uri.queryParameters['openAdd'] == '1';
    if (openAdd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onAdd();
      });
    }
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _crmService.listProcessDefinitions(businessId: widget.businessId);
      if (!mounted) return;
      final list = result is List ? result : (result['data'] is List ? result['data'] as List : <dynamic>[]);
      setState(() {
        _items = List<dynamic>.from(list);
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
        title: const Text('فرایندها و زون ارجاعات'),
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
              onPressed: _onAdd,
              tooltip: 'فرایند جدید',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: _load,
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
                          Icon(Icons.account_tree_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 16),
                          const Text('هنوز فرایندی تعریف نشده است.'),
                          if (widget.authStore.hasBusinessPermission('crm', 'write')) ...[
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed: _onAdd,
                              icon: const Icon(Icons.add),
                              label: const Text('تعریف فرایند'),
                            ),
                          ],
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index] as Map<String, dynamic>?;
                          if (item == null) return const SizedBox.shrink();
                          final id = item['id'] as int?;
                          final name = item['name'] as String? ?? '';
                          final code = item['code'] as String? ?? '';
                          final processType = item['process_type'] as String? ?? '';
                          final stages = item['stages'] as List<dynamic>? ?? [];
                          final isActive = item['is_active'] == true;
                          final typeLabel = _processTypeLabel(processType);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isActive ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                                child: Icon(Icons.account_tree, color: isActive ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.outline),
                              ),
                              title: Text(name),
                              subtitle: Text('$typeLabel · $code · ${stages.length} مرحله'),
                              trailing: widget.authStore.hasBusinessPermission('crm', 'write')
                                  ? PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'edit') _onEdit(item);
                                        if (value == 'stages') _onManageStages(item);
                                        if (value == 'delete') _onDelete(id, name);
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                                        const PopupMenuItem(value: 'stages', child: Text('مدیریت مراحل')),
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
      floatingActionButton: widget.authStore.hasBusinessPermission('crm', 'write') && _items.isNotEmpty
          ? FloatingActionButton(
              onPressed: _onAdd,
              child: const Icon(Icons.add),
              tooltip: 'فرایند جدید',
            )
          : null,
    );
  }

  String _processTypeLabel(String type) {
    switch (type) {
      case 'lead_funnel':
        return 'فانل سرنخ';
      case 'sales_pipeline':
        return 'پایپلاین فروش';
      case 'activity_type':
        return 'نوع فعالیت';
      case 'lead_source':
        return 'منبع سرنخ';
      default:
        return type;
    }
  }

  void _onAdd() {
    if (!widget.authStore.hasBusinessPermission('crm', 'write')) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => _ProcessDefinitionFormDialog(
        businessId: widget.businessId,
        onSaved: () {
          _load();
        },
      ),
    );
  }

  void _onEdit(Map<String, dynamic> item) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _ProcessDefinitionFormDialog(
        businessId: widget.businessId,
        initial: item,
        onSaved: () {
          _load();
        },
      ),
    );
  }

  void _onManageStages(Map<String, dynamic> item) {
    final defId = item['id'] as int?;
    if (defId == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => _StagesManagementDialog(
        businessId: widget.businessId,
        definitionId: defId,
        processName: item['name']?.toString() ?? '',
        stages: List<Map<String, dynamic>>.from(
          (item['stages'] is List) ? (item['stages'] as List).map((e) => Map<String, dynamic>.from(e as Map)) : [],
        ),
        crmService: _crmService,
        canWrite: widget.authStore.hasBusinessPermission('crm', 'write'),
        onSaved: () => _load(),
      ),
    );
  }

  Future<void> _onDelete(int? id, String name) async {
    if (id == null) return;
    final t = AppLocalizations.of(context);
    final ok = await showCrmDeleteConfirmDialog(
      context,
      title: t.crmDeleteProcessTitle,
      message: t.crmDeleteProcessMessage(name),
    );
    if (ok != true || !mounted) return;
    try {
      await _crmService.deleteProcessDefinition(businessId: widget.businessId, definitionId: id);
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'فرایند حذف شد');
      _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: $e', isError: true);
    }
  }
}

/// دیالوگ ایجاد/ویرایش فرایند
class _ProcessDefinitionFormDialog extends StatefulWidget {
  final int businessId;
  final Map<String, dynamic>? initial;
  final VoidCallback onSaved;

  const _ProcessDefinitionFormDialog({
    required this.businessId,
    this.initial,
    required this.onSaved,
  });

  @override
  State<_ProcessDefinitionFormDialog> createState() => _ProcessDefinitionFormDialogState();
}

class _StageInput {
  final TextEditingController code;
  final TextEditingController name;
  int orderIndex;
  _StageInput({required this.code, required this.name, this.orderIndex = 0});
}

class _ProcessDefinitionFormDialogState extends State<_ProcessDefinitionFormDialog> {
  final CrmService _crmService = CrmService(apiClient: ApiClient());
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _codeController;
  late TextEditingController _nameController;
  late TextEditingController _descController;
  String _processType = 'lead_funnel';
  bool _isDefault = false;
  bool _isActive = true;
  bool _saving = false;
  final List<_StageInput> _stageInputs = [];

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _codeController = TextEditingController(text: i?['code']?.toString() ?? '');
    _nameController = TextEditingController(text: i?['name']?.toString() ?? '');
    _descController = TextEditingController(text: i?['description']?.toString() ?? '');
    _processType = i?['process_type']?.toString() ?? 'lead_funnel';
    _isDefault = i?['is_default'] == true;
    _isActive = i?['is_active'] != false;
  }

  void _addStageInput() {
    setState(() {
      _stageInputs.add(_StageInput(
        code: TextEditingController(),
        name: TextEditingController(),
        orderIndex: _stageInputs.length,
      ));
    });
  }

  void _removeStageInput(int index) {
    setState(() {
      final s = _stageInputs.removeAt(index);
      s.code.dispose();
      s.name.dispose();
      for (var i = 0; i < _stageInputs.length; i++) {
        _stageInputs[i].orderIndex = i;
      }
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _descController.dispose();
    for (final s in _stageInputs) {
      s.code.dispose();
      s.name.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    final t = AppLocalizations.of(context);
    return CrmResponsiveDialog(
      title: isEdit ? 'ویرایش فرایند' : 'فرایند جدید',
      subtitle: t.crmProcessFormSubtitle,
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: Text(t.cancel)),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('ذخیره'),
        ),
      ],
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CrmSectionCard(
              title: t.crmProcessSectionMain,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!isEdit)
                    DropdownButtonFormField<String>(
                      value: _processType,
                      decoration: const InputDecoration(labelText: 'نوع فرایند', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'lead_funnel', child: Text('فانل سرنخ')),
                        DropdownMenuItem(value: 'sales_pipeline', child: Text('پایپلاین فروش')),
                        DropdownMenuItem(value: 'activity_type', child: Text('نوع فعالیت')),
                        DropdownMenuItem(value: 'lead_source', child: Text('منبع سرنخ')),
                      ],
                      onChanged: (v) => setState(() => _processType = v ?? _processType),
                    ),
                  if (!isEdit) const SizedBox(height: 12),
                  TextFormField(
                    controller: _codeController,
                    decoration: const InputDecoration(labelText: 'کد', border: OutlineInputBorder()),
                    readOnly: isEdit,
                    validator: (v) => v == null || v.trim().isEmpty ? 'الزامی' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'نام', border: OutlineInputBorder()),
                    validator: (v) => v == null || v.trim().isEmpty ? 'الزامی' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descController,
                    decoration: const InputDecoration(labelText: 'توضیحات', border: OutlineInputBorder()),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    title: const Text('فعال'),
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v ?? true),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    title: const Text('پیش‌فرض برای این نوع'),
                    value: _isDefault,
                    onChanged: (v) => setState(() => _isDefault = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            if (!isEdit) ...[
              const SizedBox(height: 16),
              CrmSectionCard(
                title: t.crmProcessSectionStages,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                        onPressed: _addStageInput,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('افزودن مرحله'),
                      ),
                    ),
                    ...List.generate(_stageInputs.length, (i) {
                      final s = _stageInputs[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: s.code,
                                decoration: const InputDecoration(labelText: 'کد', isDense: true, border: OutlineInputBorder()),
                                textCapitalization: TextCapitalization.none,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: s.name,
                                decoration: const InputDecoration(labelText: 'نام', isDense: true, border: OutlineInputBorder()),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => _removeStageInput(i),
                              tooltip: 'حذف',
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (widget.initial != null) {
        final id = widget.initial!['id'] as int?;
        if (id == null) throw Exception('شناسه فرایند نامعتبر');
        await _crmService.updateProcessDefinition(
          businessId: widget.businessId,
          definitionId: id,
          name: _nameController.text.trim(),
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          isDefault: _isDefault,
          isActive: _isActive,
        );
      } else {
        final stages = <Map<String, dynamic>>[];
        for (var i = 0; i < _stageInputs.length; i++) {
          final s = _stageInputs[i];
          final code = s.code.text.trim();
          final name = s.name.text.trim();
          if (code.isNotEmpty && name.isNotEmpty) {
            stages.add({'stage_code': code, 'name': name, 'order_index': i});
          }
        }
        await _crmService.createProcessDefinition(
          businessId: widget.businessId,
          processType: _processType,
          code: _codeController.text.trim(),
          name: _nameController.text.trim(),
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          isDefault: _isDefault,
          isActive: _isActive,
          stages: stages,
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
}

/// دیالوگ مدیریت مراحل یک فرایند
class _StagesManagementDialog extends StatefulWidget {
  final int businessId;
  final int definitionId;
  final String processName;
  final List<Map<String, dynamic>> stages;
  final CrmService crmService;
  final bool canWrite;
  final VoidCallback onSaved;

  const _StagesManagementDialog({
    required this.businessId,
    required this.definitionId,
    required this.processName,
    required this.stages,
    required this.crmService,
    required this.canWrite,
    required this.onSaved,
  });

  @override
  State<_StagesManagementDialog> createState() => _StagesManagementDialogState();
}

class _StagesManagementDialogState extends State<_StagesManagementDialog> {
  late List<Map<String, dynamic>> _stages;

  @override
  void initState() {
    super.initState();
    _stages = List.from(widget.stages);
  }

  Future<void> _loadStages() async {
    try {
      final result = await widget.crmService.listStages(
        businessId: widget.businessId,
        definitionId: widget.definitionId,
      );
      if (!mounted) return;
      List<dynamic> list = [];
      if (result is List) {
        list = List<dynamic>.from(result as List);
      } else if (result is Map) {
        final d = result['data'];
        final i = result['items'];
        if (d is List) {
          list = List<dynamic>.from(d);
        } else if (i is List) {
          list = List<dynamic>.from(i);
        }
      }
      setState(() {
        _stages = list.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (_) {}
  }

  Future<void> _onAddStage() async {
    final code = TextEditingController();
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('افزودن مرحله'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: code,
              decoration: const InputDecoration(labelText: 'کد مرحله'),
              textCapitalization: TextCapitalization.none,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'نام'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('افزودن')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (code.text.trim().isEmpty || name.text.trim().isEmpty) {
      SnackBarHelper.show(context, message: 'کد و نام الزامی است', isError: true);
      return;
    }
    try {
      await widget.crmService.createStage(
        businessId: widget.businessId,
        definitionId: widget.definitionId,
        stageCode: code.text.trim(),
        name: name.text.trim(),
        orderIndex: _stages.length,
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'مرحله اضافه شد');
      _loadStages();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: $e', isError: true);
    }
  }

  Future<void> _onDeleteStage(Map<String, dynamic> stage) async {
    final id = stage['id'] as int?;
    if (id == null) return;
    final stageName = stage['name']?.toString() ?? '';
    final t = AppLocalizations.of(context);
    final ok = await showCrmDeleteConfirmDialog(
      context,
      title: t.crmDeleteStageTitle,
      message: t.crmDeleteStageMessage(stageName),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.crmService.deleteStage(
        businessId: widget.businessId,
        definitionId: widget.definitionId,
        stageId: id,
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'مرحله حذف شد');
      _loadStages();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('مراحل فرایند: ${widget.processName}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.canWrite)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilledButton.icon(
                  onPressed: _onAddStage,
                  icon: const Icon(Icons.add),
                  label: const Text('افزودن مرحله'),
                ),
              ),
            Flexible(
              child: _stages.isEmpty
                  ? const Center(child: Text('مرحله‌ای تعریف نشده'))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _stages.length,
                      itemBuilder: (context, index) {
                        final s = _stages[index];
                        final name = s['name']?.toString() ?? '';
                        final code = s['stage_code']?.toString() ?? '';
                        final id = s['id'] as int?;
                        return ListTile(
                          leading: CircleAvatar(child: Text('${index + 1}')),
                          title: Text(name),
                          subtitle: Text(code),
                          trailing: widget.canWrite && id != null
                              ? IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _onDeleteStage(s),
                                  tooltip: 'حذف',
                                )
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onSaved();
            Navigator.of(context).pop();
          },
          child: const Text('بستن'),
        ),
      ],
    );
  }
}
