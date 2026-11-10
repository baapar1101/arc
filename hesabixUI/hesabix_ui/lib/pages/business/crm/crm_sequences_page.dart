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
          if (widget.authStore.hasBusinessPermission('workflows', 'add'))
            IconButton(
              icon: const Icon(Icons.rule_folder_outlined),
              tooltip: 'پیش‌نویس تأیید تخفیف',
              onPressed: _installDiscountTemplate,
            ),
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
                                        if (v == 'preview' && id != null) _onDryRun(id);
                                        if (v == 'delete' && id != null) _onDelete(id, seq['name']?.toString() ?? '');
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                                        const PopupMenuItem(value: 'preview', child: Text('پیش‌نمایش بدون ارسال')),
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
    showDialog<void>(
      context: context,
      builder: (ctx) => _SequenceFormDialog(
        businessId: widget.businessId,
        crmService: _crmService,
        onSaved: _load,
      ),
    );
  }

  void _onEdit(Map<String, dynamic> seq) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _SequenceFormDialog(
        businessId: widget.businessId,
        crmService: _crmService,
        initial: seq,
        onSaved: _load,
      ),
    );
  }

  Future<void> _installDiscountTemplate() async {
    try {
      final result = await _crmService.installDiscountApprovalTemplate(businessId: widget.businessId);
      if (!mounted) return;
      final created = result['created'] == true;
      final id = (result['id'] as num?)?.toInt();
      SnackBarHelper.show(
        context,
        message: created ? 'پیش‌نویس گردش‌کار تأیید تخفیف ساخته شد' : 'این پیش‌نویس از قبل وجود دارد',
      );
      if (id != null) {
        context.push('/business/${widget.businessId}/workflows/$id/edit');
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }

  Future<void> _onDryRun(int id) async {
    try {
      final result = await _crmService.dryRunSequence(businessId: widget.businessId, sequenceId: id);
      if (!mounted) return;
      final steps = result['steps'] is List ? result['steps'] as List : const [];
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('پیش‌نمایش بدون ارسال'),
          content: SizedBox(
            width: 420,
            child: steps.isEmpty
                ? const Text('گامی برای پیش‌نمایش نیست.')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final raw in steps)
                        if (raw is Map)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              '${kSequenceActionLabels[raw['action_type']] ?? raw['action_type']}\n${raw['message'] ?? raw['subject'] ?? raw['title'] ?? ''}',
                            ),
                          ),
                    ],
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('بستن'))],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
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
  late TextEditingController _capController;
  bool _isActive = true;
  bool _stopOnReply = true;
  bool _stopOnClose = true;
  bool _saving = false;
  bool _stagesLoading = true;
  String? _stagesError;
  final List<_StepDraft> _steps = [];
  List<Map<String, dynamic>> _leadStages = [];
  List<Map<String, dynamic>> _dealStages = [];
  List<Map<String, dynamic>> _wonReasons = [];
  List<Map<String, dynamic>> _lostReasons = [];

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _nameController = TextEditingController(text: i?['name']?.toString() ?? '');
    _descController = TextEditingController(text: i?['description']?.toString() ?? '');
    _capController = TextEditingController(text: i?['sms_daily_cap']?.toString() ?? '');
    _isActive = i?['is_active'] != false;
    _stopOnReply = i?['stop_on_reply'] != false;
    _stopOnClose = i?['stop_on_close'] != false;
    if (i != null && i['steps'] is List) {
      for (final s in (i['steps'] as List)) {
        final m = Map<String, dynamic>.from(s as Map);
        final config = m['action_config'] is Map ? Map<String, dynamic>.from(m['action_config'] as Map) : null;
        _steps.add(_StepDraft(
          delayHours: (m['delay_hours'] as num?)?.toInt() ?? 0,
          actionType: m['action_type']?.toString() ?? 'create_task',
          config: config,
        ));
      }
    }
    _loadStageChoices();
  }

  Future<void> _loadStageChoices({bool refresh = false}) async {
    if (refresh && mounted) {
      setState(() {
        _stagesLoading = true;
        _stagesError = null;
      });
    }
    try {
      final raw = await widget.crmService.listProcessDefinitions(businessId: widget.businessId);
      final won = await widget.crmService.listCloseReasons(businessId: widget.businessId, reasonType: 'won');
      final lost = await widget.crmService.listCloseReasons(businessId: widget.businessId, reasonType: 'lost');
      final items = raw is List ? raw : (raw is Map && raw['items'] is List ? raw['items'] as List : const []);
      final leads = <Map<String, dynamic>>[];
      final deals = <Map<String, dynamic>>[];
      for (final item in items) {
        if (item is! Map) continue;
        final process = Map<String, dynamic>.from(item);
        final stages = process['stages'];
        if (stages is! List) continue;
        final kind = process['process_type']?.toString();
        final bucket = kind == 'lead_funnel' ? leads : kind == 'sales_pipeline' ? deals : null;
        if (bucket == null) continue;
        final processName = process['name']?.toString() ?? '';
        for (final stage in stages) {
          if (stage is! Map) continue;
          final row = Map<String, dynamic>.from(stage);
          row['process_name'] = processName;
          bucket.add(row);
        }
      }
      leads.sort((a, b) => ((a['order_index'] as num?) ?? 0).compareTo((b['order_index'] as num?) ?? 0));
      deals.sort((a, b) => ((a['order_index'] as num?) ?? 0).compareTo((b['order_index'] as num?) ?? 0));
      if (!mounted) return;
      setState(() {
        _leadStages = leads;
        _dealStages = deals;
        _wonReasons = won.where((row) => row['is_active'] != false).toList();
        _lostReasons = lost.where((row) => row['is_active'] != false).toList();
        _stagesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stagesLoading = false;
        _stagesError = 'فهرست مرحله‌ها بارگذاری نشد.';
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _capController.dispose();
    for (final step in _steps) {
      step.dispose();
    }
    super.dispose();
  }

  String _localPreview(String template) {
    return template.replaceAllMapped(RegExp(r'\{\{\s*([a-zA-Z0-9_]+)\s*\}\}'), (match) {
      const samples = {
        'name': 'مشتری نمونه',
        'company': 'شرکت نمونه',
        'mobile': '09120000000',
        'title': 'فرصت نمونه',
        'code': 'CRM-0',
      };
      return samples[match.group(1)] ?? '';
    });
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
                TextField(
                  controller: _capController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'سقف پیامک روزانه',
                    helperText: 'خالی یعنی بدون سقف. رسیدن به سقف، گام را یک ساعت به تعویق می‌اندازد.',
                    border: OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('توقف با پاسخ مشتری'),
                  subtitle: const Text('اگر مشتری در گفت‌وگوی وب پاسخ دهد، ثبت‌نام فعال لغو می‌شود.'),
                  value: _stopOnReply,
                  onChanged: (v) => setState(() => _stopOnReply = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('توقف با بستن فرصت'),
                  subtitle: const Text('بستن فرصت فروش، ادامه توالی همان فرصت را متوقف می‌کند.'),
                  value: _stopOnClose,
                  onChanged: (v) => setState(() => _stopOnClose = v),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
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
                                onPressed: () {
                                  step.dispose();
                                  setState(() => _steps.removeAt(index));
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (step.actionType == 'send_sms') ...[
                            TextField(
                              controller: step.message,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'متن پیامک',
                                helperText: 'متغیرها: {{name}} {{company}} {{mobile}} {{title}} {{code}}',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            if (step.message.text.trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text('پیش‌نمایش: ${_localPreview(step.message.text)}', style: Theme.of(context).textTheme.bodySmall),
                              ),
                          ],
                          if (step.actionType == 'create_task')
                            TextField(
                              controller: step.subject,
                              decoration: const InputDecoration(labelText: 'موضوع وظیفه', border: OutlineInputBorder()),
                            ),
                          if (step.actionType == 'notify_assignee') ...[
                            TextField(
                              controller: step.title,
                              decoration: const InputDecoration(labelText: 'عنوان اعلان', border: OutlineInputBorder()),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: step.message,
                              decoration: const InputDecoration(labelText: 'متن اعلان', border: OutlineInputBorder()),
                            ),
                          ],
                          if (step.actionType == 'update_lead_stage' || step.actionType == 'update_deal_stage')
                            _stagePicker(step),
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

  Map<String, dynamic>? _stageById(List<Map<String, dynamic>> stages, _StepDraft step) {
    final id = int.tryParse(step.stageId.text.trim());
    for (final stage in stages) {
      if ((stage['id'] as num?)?.toInt() == id) return stage;
    }
    return null;
  }

  Widget _stagePicker(_StepDraft step) {
    if (_stagesLoading) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator());
    }
    if (_stagesError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_stagesError!),
          TextButton(onPressed: () => _loadStageChoices(refresh: true), child: const Text('تلاش دوباره')),
        ],
      );
    }
    final dealStep = step.actionType == 'update_deal_stage';
    final stages = dealStep ? _dealStages : _leadStages;
    if (stages.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dealStep ? 'در پایپلاین فروش مرحله‌ای تعریف نشده است.' : 'در فانل سرنخ مرحله‌ای تعریف نشده است.'),
          TextButton(onPressed: () => _loadStageChoices(refresh: true), child: const Text('بارگذاری دوباره')),
        ],
      );
    }
    final selected = int.tryParse(step.stageId.text.trim());
    final known = stages.any((stage) => (stage['id'] as num?)?.toInt() == selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          value: known ? selected : null,
          decoration: const InputDecoration(labelText: 'مرحله', border: OutlineInputBorder()),
          items: [
            for (final stage in stages)
              if ((stage['id'] as num?) != null)
                DropdownMenuItem(
                  value: (stage['id'] as num).toInt(),
                  child: Text('${stage['process_name']} · ${stage['name']}'),
                ),
          ],
          onChanged: (value) => setState(() {
            step.stageId.text = value?.toString() ?? '';
            final stage = _stageById(stages, step);
            if (stage == null || (stage['is_win'] != true && stage['is_lost'] != true)) {
              step.reason.text = '';
            }
          }),
        ),
        if (dealStep) _reasonPicker(step),
      ],
    );
  }

  Widget _reasonPicker(_StepDraft step) {
    final stage = _stageById(_dealStages, step);
    if (stage == null || (stage['is_win'] != true && stage['is_lost'] != true)) return const SizedBox.shrink();
    final won = stage['is_win'] == true;
    final reasons = won ? _wonReasons : _lostReasons;
    final selected = step.reason.text.trim();
    final known = reasons.any((row) => row['code']?.toString() == selected);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: reasons.isEmpty
          ? const Text('برای این مرحله دلیل برد یا باخت تعریف نشده است.')
          : DropdownButtonFormField<String>(
              value: known ? selected : null,
              decoration: InputDecoration(
                labelText: won ? 'دلیل برد' : 'دلیل باخت',
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final row in reasons)
                  if ((row['code']?.toString() ?? '').isNotEmpty)
                    DropdownMenuItem(
                      value: row['code'].toString(),
                      child: Text(row['name']?.toString().trim().isNotEmpty == true ? row['name'].toString() : row['code'].toString()),
                    ),
              ],
              onChanged: (value) => setState(() => step.reason.text = value ?? ''),
            ),
    );
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      SnackBarHelper.show(context, message: 'نام الزامی است', isError: true);
      return;
    }
    for (final step in _steps) {
      if (step.actionType == 'send_sms' && step.message.text.trim().isEmpty) {
        SnackBarHelper.show(context, message: 'متن پیامک هر گام ارسال را بنویسید', isError: true);
        return;
      }
      if ((step.actionType == 'update_lead_stage' || step.actionType == 'update_deal_stage') && int.tryParse(step.stageId.text.trim()) == null) {
        SnackBarHelper.show(context, message: 'مرحله را برای گام تغییر مرحله انتخاب کنید', isError: true);
        return;
      }
      if (step.actionType == 'update_deal_stage') {
        final stage = _stageById(_dealStages, step);
        if (stage != null && (stage['is_win'] == true || stage['is_lost'] == true) && step.reason.text.trim().isEmpty) {
          SnackBarHelper.show(context, message: 'برای مرحله برد یا باخت یک دلیل انتخاب کنید', isError: true);
          return;
        }
      }
    }
    final capText = _capController.text.trim();
    final cap = capText.isEmpty ? null : int.tryParse(capText);
    if (capText.isNotEmpty && cap == null) {
      SnackBarHelper.show(context, message: 'سقف پیامک باید عدد باشد', isError: true);
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
          'action_config': _steps[i].actionConfig(stage: _steps[i].actionType == 'update_deal_stage' ? _stageById(_dealStages, _steps[i]) : null),
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
          smsDailyCap: cap,
          clearSmsDailyCap: cap == null,
          stopOnReply: _stopOnReply,
          stopOnClose: _stopOnClose,
          steps: steps,
        );
      } else {
        await widget.crmService.createSequence(
          businessId: widget.businessId,
          name: _nameController.text.trim(),
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          isActive: _isActive,
          smsDailyCap: cap,
          stopOnReply: _stopOnReply,
          stopOnClose: _stopOnClose,
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
  final TextEditingController message = TextEditingController();
  final TextEditingController subject = TextEditingController();
  final TextEditingController title = TextEditingController();
  final TextEditingController stageId = TextEditingController();
  final TextEditingController reason = TextEditingController();

  _StepDraft({required this.delayHours, required this.actionType, Map<String, dynamic>? config}) {
    final data = config ?? const <String, dynamic>{};
    message.text = (data['message'] ?? data['text'] ?? '').toString();
    subject.text = (data['subject'] ?? '').toString();
    title.text = (data['title'] ?? '').toString();
    if (data['stage_id'] != null) stageId.text = data['stage_id'].toString();
    reason.text = (data['won_reason_code'] ?? data['lost_reason_code'] ?? '').toString();
  }

  void dispose() {
    message.dispose();
    subject.dispose();
    title.dispose();
    stageId.dispose();
    reason.dispose();
  }

  Map<String, dynamic> actionConfig({Map<String, dynamic>? stage}) {
    switch (actionType) {
      case 'send_sms':
        return {'message': message.text.trim()};
      case 'create_task':
        return {'subject': subject.text.trim().isEmpty ? 'پیگیری' : subject.text.trim(), 'due_in_hours': 24};
      case 'notify_assignee':
        return {
          'title': title.text.trim().isEmpty ? 'یادآوری توالی CRM' : title.text.trim(),
          'message': message.text.trim(),
        };
      case 'update_lead_stage':
        return {'stage_id': int.parse(stageId.text.trim())};
      case 'update_deal_stage':
        final code = reason.text.trim();
        final win = stage?['is_win'] == true;
        final lost = stage?['is_lost'] == true;
        return {
          'stage_id': int.parse(stageId.text.trim()),
          if (win && code.isNotEmpty) 'won_reason_code': code,
          if (lost && code.isNotEmpty) 'lost_reason_code': code,
        };
      default:
        return const {};
    }
  }
}
