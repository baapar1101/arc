import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/crm/crm_delete_confirm_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_responsive_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_section_card.dart';
import 'package:hesabix_ui/widgets/permission/permission_widgets.dart';
import 'package:hesabix_ui/core/hesabix_back.dart';

/// عناوین اقدام‌های توالی خودکار
const Map<String, String> kSequenceActionLabels = {
  'create_task': 'ایجاد وظیفه',
  'send_sms': 'ارسال پیامک',
  'notify_assignee': 'اعلان به مسئول',
  'update_lead_stage': 'تغییر مرحله سرنخ',
  'update_deal_stage': 'تغییر مرحله فرصت',
};

/// صفحه توالی‌های خودکار CRM
class CrmSequencesPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const CrmSequencesPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<CrmSequencesPage> createState() => _CrmSequencesPageState();
}

class _CrmSequencesPageState extends State<CrmSequencesPage> {
  final CrmService _crmService = CrmService(apiClient: ApiClient());
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _crmService.listSequences(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.authStore.canReadSection('crm')) {
      return AccessDeniedPage(message: 'شما دسترسی لازم برای مشاهده CRM را ندارید');
    }
    final canWrite = widget.authStore.hasBusinessPermission('crm', 'write');

    return Scaffold(
      appBar: AppBar(
        title: const Text('توالی‌های خودکار'),
        leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
        actions: [
          if (canWrite)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'توالی جدید',
              onPressed: _onAdd,
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
                      TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('تلاش مجدد')),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.timeline_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 16),
                          const Text('هنوز توالی خودکاری تعریف نشده است.'),
                          if (canWrite) ...[
                            const SizedBox(height: 8),
                            FilledButton.icon(onPressed: _onAdd, icon: const Icon(Icons.add), label: const Text('توالی جدید')),
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
                          final seq = _items[index];
                          final steps = seq['steps'] is List ? (seq['steps'] as List) : [];
                          final active = seq['is_active'] == true;
                          final id = (seq['id'] as num?)?.toInt();
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: active
                                    ? Theme.of(context).colorScheme.primaryContainer
                                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                                child: Icon(Icons.timeline, color: Theme.of(context).colorScheme.onPrimaryContainer),
                              ),
                              title: Text(seq['name']?.toString() ?? '-'),
                              subtitle: Text([
                                '${steps.length} گام',
                                if (!active) 'غیرفعال',
                                if (seq['description'] != null && seq['description'].toString().isNotEmpty) seq['description'].toString(),
                              ].join(' · ')),
                              trailing: canWrite
                                  ? PopupMenuButton<String>(
                                      onSelected: (v) {
                                        if (v == 'edit') _onEdit(seq);
                                        if (v == 'delete' && id != null) _onDelete(id, seq['name']?.toString() ?? '');
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                                        const PopupMenuItem(value: 'delete', child: Text('حذف')),
                                      ],
                                    )
                                  : null,
                              onTap: canWrite ? () => _onEdit(seq) : null,
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  void _onAdd() {
    if (!widget.authStore.hasBusinessPermission('crm', 'write')) return;
    showGlassDialog<void>(
      context: context,
      builder: (ctx) => _SequenceFormDialog(
        businessId: widget.businessId,
        crmService: _crmService,
        onSaved: _load,
      ),
    );
  }

  void _onEdit(Map<String, dynamic> seq) {
    showGlassDialog<void>(
      context: context,
      builder: (ctx) => _SequenceFormDialog(
        businessId: widget.businessId,
        crmService: _crmService,
        initial: seq,
        onSaved: _load,
      ),
    );
  }

  Future<void> _onDelete(int id, String name) async {
    final ok = await showCrmDeleteConfirmDialog(
      context,
      title: 'حذف توالی',
      message: 'آیا از حذف توالی «$name» مطمئن هستید؟',
    );
    if (ok != true || !mounted) return;
    try {
      await _crmService.deleteSequence(businessId: widget.businessId, sequenceId: id);
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'توالی حذف شد');
      _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }
}

class _SequenceFormDialog extends StatefulWidget {
  final int businessId;
  final CrmService crmService;
  final Map<String, dynamic>? initial;
  final VoidCallback onSaved;

  const _SequenceFormDialog({
    required this.businessId,
    required this.crmService,
    this.initial,
    required this.onSaved,
  });

  @override
  State<_SequenceFormDialog> createState() => _SequenceFormDialogState();
}

class _SequenceFormDialogState extends State<_SequenceFormDialog> {
  late TextEditingController _nameController;
  late TextEditingController _descController;
  bool _isActive = true;
  bool _saving = false;
  final List<_StepDraft> _steps = [];

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _nameController = TextEditingController(text: i?['name']?.toString() ?? '');
    _descController = TextEditingController(text: i?['description']?.toString() ?? '');
    _isActive = i?['is_active'] != false;
    if (i != null && i['steps'] is List) {
      for (final s in (i['steps'] as List)) {
        final m = Map<String, dynamic>.from(s as Map);
        _steps.add(_StepDraft(
          delayHours: (m['delay_hours'] as num?)?.toInt() ?? 0,
          actionType: m['action_type']?.toString() ?? 'create_task',
        ));
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return CrmResponsiveDialog(
      title: isEdit ? 'ویرایش توالی' : 'توالی جدید',
      subtitle: 'اقدام‌های خودکار زمان‌بندی‌شده روی سرنخ‌ها و فرصت‌ها',
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
          CrmSectionCard(
            title: 'مشخصات',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'نام *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descController,
                  decoration: const InputDecoration(labelText: 'توضیحات', border: OutlineInputBorder()),
                  maxLines: 2,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('فعال'),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CrmSectionCard(
            title: 'گام‌ها',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_steps.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('گامی اضافه نشده است.'),
                  )
                else
                  ...List.generate(_steps.length, (index) {
                    final step = _steps[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          CircleAvatar(radius: 14, child: Text('${index + 1}', style: const TextStyle(fontSize: 12))),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              initialValue: step.delayHours.toString(),
                              decoration: const InputDecoration(labelText: 'تأخیر (ساعت)', isDense: true, border: OutlineInputBorder()),
                              keyboardType: TextInputType.number,
                              onChanged: (v) => step.delayHours = int.tryParse(v.trim()) ?? 0,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              value: step.actionType,
                              decoration: const InputDecoration(labelText: 'اقدام', isDense: true, border: OutlineInputBorder()),
                              items: kSequenceActionLabels.entries
                                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)))
                                  .toList(),
                              onChanged: (v) => setState(() => step.actionType = v ?? step.actionType),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => setState(() => _steps.removeAt(index)),
                          ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _steps.add(_StepDraft(delayHours: 0, actionType: 'create_task'))),
                  icon: const Icon(Icons.add),
                  label: const Text('افزودن گام'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      SnackBarHelper.show(context, message: 'نام الزامی است', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final steps = <Map<String, dynamic>>[];
      for (var i = 0; i < _steps.length; i++) {
        steps.add({
          'step_order': i,
          'delay_hours': _steps[i].delayHours,
          'action_type': _steps[i].actionType,
        });
      }
      final id = (widget.initial?['id'] as num?)?.toInt();
      if (id != null) {
        await widget.crmService.updateSequence(
          businessId: widget.businessId,
          sequenceId: id,
          name: _nameController.text.trim(),
          description: _descController.text.trim(),
          isActive: _isActive,
          steps: steps,
        );
      } else {
        await widget.crmService.createSequence(
          businessId: widget.businessId,
          name: _nameController.text.trim(),
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          isActive: _isActive,
          steps: steps,
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
}

class _StepDraft {
  int delayHours;
  String actionType;
  _StepDraft({required this.delayHours, required this.actionType});
}
