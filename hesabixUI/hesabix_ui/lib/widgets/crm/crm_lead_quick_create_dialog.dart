import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/services/business_user_service.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/crm/crm_follow_up_field.dart';
import 'package:hesabix_ui/widgets/crm/crm_responsive_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_section_card.dart';

/// ایجاد سریع سرنخ: نام، موبایل، شرکت، منبع، مرحله، مسئول، پیگیری.
class CrmLeadQuickCreateDialog extends StatefulWidget {
  final int businessId;
  final List<Map<String, dynamic>> processDefs;
  final List<Map<String, dynamic>> leadSources;
  final CrmService crmService;
  final CalendarController? calendarController;
  final VoidCallback onSaved;
  final int? initialProcessDefinitionId;
  final int? initialStageId;

  const CrmLeadQuickCreateDialog({
    super.key,
    required this.businessId,
    required this.processDefs,
    required this.leadSources,
    required this.crmService,
    required this.onSaved,
    this.calendarController,
    this.initialProcessDefinitionId,
    this.initialStageId,
  });

  @override
  State<CrmLeadQuickCreateDialog> createState() => _CrmLeadQuickCreateDialogState();
}

class _CrmLeadQuickCreateDialogState extends State<CrmLeadQuickCreateDialog> {
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  int? _processId;
  int? _stageId;
  String? _sourceCode;
  int? _assigneeId;
  DateTime? _followUp;
  List<Map<String, dynamic>> _stages = [];
  List<Map<String, dynamic>> _users = [];
  bool _saving = false;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    if (widget.processDefs.isNotEmpty) {
      final preferred = widget.initialProcessDefinitionId != null
          ? widget.processDefs.cast<Map<String, dynamic>?>().firstWhere(
                (p) => p?['id'] == widget.initialProcessDefinitionId,
                orElse: () => null,
              )
          : null;
      final proc = preferred ?? widget.processDefs.first;
      _processId = proc['id'] as int?;
      _stages = (proc['stages'] is List ? (proc['stages'] as List).cast<Map<String, dynamic>>() : <Map<String, dynamic>>[]);
      _stages.sort((a, b) => ((a['order_index'] ?? 0) as num).compareTo((b['order_index'] ?? 0) as num));
      if (widget.initialStageId != null && _stages.any((s) => s['id'] == widget.initialStageId)) {
        _stageId = widget.initialStageId;
      } else {
        _stageId = _stages.isNotEmpty ? _stages.first['id'] as int? : null;
      }
    }
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final res = await BusinessUserService(ApiClient()).getBusinessUsers(widget.businessId);
      if (!mounted) return;
      setState(() {
        _users = res.users.map((u) => <String, dynamic>{'id': u.userId, 'name': u.userName}).toList();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _companyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      SnackBarHelper.show(context, message: 'نام الزامی است', isError: true);
      return;
    }
    if (_processId == null || _stageId == null) {
      SnackBarHelper.show(context, message: 'فانل و مرحله الزامی است', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final created = await widget.crmService.createLead(
        businessId: widget.businessId,
        processDefinitionId: _processId!,
        stageId: _stageId!,
        name: _nameCtrl.text.trim(),
        mobile: _mobileCtrl.text.trim().isEmpty ? null : _mobileCtrl.text.trim(),
        companyName: _companyCtrl.text.trim().isEmpty ? null : _companyCtrl.text.trim(),
        sourceCode: _sourceCode,
        assignedToUserId: _assigneeId,
        nextFollowUpAt: _followUp,
      );
      if (!mounted) return;
      Navigator.of(context).pop(created);
      widget.onSaved();
      SnackBarHelper.show(context, message: 'سرنخ ایجاد شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CrmResponsiveDialog(
      title: 'سرنخ جدید',
      subtitle: 'حداقل نام را وارد کنید؛ بقیه را بعداً تکمیل کنید.',
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('انصراف')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('ایجاد'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CrmSectionCard(
            title: 'اطلاعات تماس',
            child: Column(
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'نام *', border: OutlineInputBorder()),
                  textInputAction: TextInputAction.next,
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _mobileCtrl,
                  decoration: const InputDecoration(labelText: 'موبایل', border: OutlineInputBorder()),
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _companyCtrl,
                  decoration: const InputDecoration(labelText: 'نام شرکت', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CrmSectionCard(
            title: 'مرحله و پیگیری',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.leadSources.isNotEmpty) ...[
                  DropdownButtonFormField<String?>(
                    value: _sourceCode,
                    decoration: const InputDecoration(labelText: 'منبع', border: OutlineInputBorder(), isDense: true),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('انتخاب نشده')),
                      ...widget.leadSources.map((s) => DropdownMenuItem<String?>(
                            value: s['code'] as String?,
                            child: Text(s['label']?.toString() ?? s['code']?.toString() ?? ''),
                          )),
                    ],
                    onChanged: (v) => setState(() => _sourceCode = v),
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.processDefs.length > 1) ...[
                  DropdownButtonFormField<int?>(
                    value: _processId,
                    decoration: const InputDecoration(labelText: 'فانل', border: OutlineInputBorder()),
                    items: widget.processDefs
                        .map((p) => DropdownMenuItem<int?>(value: p['id'] as int?, child: Text(p['name']?.toString() ?? '')))
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _processId = v;
                        final proc = widget.processDefs.firstWhere((e) => e['id'] == v, orElse: () => <String, dynamic>{});
                        _stages = (proc['stages'] is List ? (proc['stages'] as List).cast<Map<String, dynamic>>() : <Map<String, dynamic>>[]);
                        _stages.sort((a, b) => ((a['order_index'] ?? 0) as num).compareTo((b['order_index'] ?? 0) as num));
                        _stageId = _stages.isNotEmpty ? _stages.first['id'] as int? : null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<int?>(
                  value: _stageId,
                  decoration: const InputDecoration(labelText: 'مرحله', border: OutlineInputBorder()),
                  items: _stages
                      .map((s) => DropdownMenuItem<int?>(value: s['id'] as int?, child: Text(s['name']?.toString() ?? '')))
                      .toList(),
                  onChanged: (v) => setState(() => _stageId = v),
                ),
                if (_users.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: _assigneeId,
                    decoration: const InputDecoration(labelText: 'تخصیص به', border: OutlineInputBorder(), isDense: true),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('انتخاب نشده')),
                      ..._users.map((u) => DropdownMenuItem<int?>(
                            value: (u['id'] as num?)?.toInt(),
                            child: Text(u['name']?.toString() ?? ''),
                          )),
                    ],
                    onChanged: (v) => setState(() => _assigneeId = v),
                  ),
                ],
                const SizedBox(height: 12),
                CrmFollowUpField(
                  value: _followUp,
                  onChanged: (v) => setState(() => _followUp = v),
                  calendarController: widget.calendarController,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
            icon: Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more),
            label: Text(_showAdvanced ? 'بستن گزینه‌های بیشتر' : 'گزینه‌های بیشتر (ویرایش کامل بعد از ایجاد)'),
          ),
          if (_showAdvanced)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'برای توضیحات، برچسب و کد دستی، پس از ایجاد از صفحه رکورد «ویرایش» را بزنید.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}
