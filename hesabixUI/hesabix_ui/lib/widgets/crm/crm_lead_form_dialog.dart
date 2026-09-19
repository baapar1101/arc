import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/services/business_user_service.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/crm/crm_ai_assistant_widget.dart';
import 'package:hesabix_ui/widgets/crm/crm_responsive_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_section_card.dart';
import 'package:hesabix_ui/widgets/crm/crm_tag_selector.dart';
import 'package:hesabix_ui/widgets/jalali_date_picker.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';

/// دیالوگ تبدیل سرنخ به مشتری با گزینه ایجاد همزمان فرصت فروش
class CrmConvertLeadDialog extends StatefulWidget {
  final int businessId;
  final int leadId;
  final String leadName;
  final CrmService crmService;

  const CrmConvertLeadDialog({
    required this.businessId,
    required this.leadId,
    required this.leadName,
    required this.crmService,
  });

  @override
  State<CrmConvertLeadDialog> createState() => _CrmConvertLeadDialogState();
}

class _CrmConvertLeadDialogState extends State<CrmConvertLeadDialog> {
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

class CrmLeadFormDialog extends StatefulWidget {
  final int businessId;
  final List<Map<String, dynamic>> processDefs;
  final List<Map<String, dynamic>> leadSources;
  final CrmService crmService;
  final Map<String, dynamic>? initial;
  final VoidCallback onSaved;
  final CalendarController? calendarController;

  const CrmLeadFormDialog({
    required this.businessId,
    required this.processDefs,
    required this.leadSources,
    required this.crmService,
    this.initial,
    required this.onSaved,
    this.calendarController,
  });

  @override
  State<CrmLeadFormDialog> createState() => _CrmLeadFormDialogState();
}

class _CrmLeadFormDialogState extends State<CrmLeadFormDialog> {
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
  List<int> _selectedTagIds = [];

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
                title: 'برچسب‌ها',
                child: CrmTagSelector(
                  businessId: widget.businessId,
                  crmService: widget.crmService,
                  initialTagIds: _selectedTagIds,
                  onChanged: (ids) => _selectedTagIds = ids,
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
          tagIds: _selectedTagIds,
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

  Future<void> _convertAndClose() async {
    final id = widget.initial?['id'] as int?;
    final name = widget.initial?['name']?.toString() ?? '';
    if (id == null) return;
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) => CrmConvertLeadDialog(
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
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
