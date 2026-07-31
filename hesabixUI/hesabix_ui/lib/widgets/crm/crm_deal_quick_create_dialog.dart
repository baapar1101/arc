import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/crm/crm_follow_up_field.dart';
import 'package:hesabix_ui/widgets/crm/crm_responsive_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_section_card.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';

/// ایجاد سریع فرصت فروش: مشتری، عنوان، مبلغ، پایپلاین/مرحله، پیگیری.
class CrmDealQuickCreateDialog extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final List<Map<String, dynamic>> processDefs;
  final CrmService crmService;
  final CalendarController? calendarController;
  final VoidCallback onSaved;
  final int? initialProcessDefinitionId;
  final int? initialStageId;
  final int? initialPersonId;
  final String? initialPersonName;

  const CrmDealQuickCreateDialog({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.processDefs,
    required this.crmService,
    required this.onSaved,
    this.calendarController,
    this.initialProcessDefinitionId,
    this.initialStageId,
    this.initialPersonId,
    this.initialPersonName,
  });

  @override
  State<CrmDealQuickCreateDialog> createState() => _CrmDealQuickCreateDialogState();
}

class _CrmDealQuickCreateDialogState extends State<CrmDealQuickCreateDialog> {
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController(text: '0');
  int? _processId;
  int? _stageId;
  int? _personId;
  Person? _person;
  DateTime? _followUp;
  List<Map<String, dynamic>> _stages = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialPersonId != null) {
      _personId = widget.initialPersonId;
      _person = Person(
        id: widget.initialPersonId,
        businessId: widget.businessId,
        aliasName: widget.initialPersonName?.trim().isNotEmpty == true
            ? widget.initialPersonName!
            : 'مشتری',
        personTypes: [PersonType.customer],
        createdAt: DateTime(2020, 1, 1),
        updatedAt: DateTime(2020, 1, 1),
      );
    }
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
        final openStages = _stages.where((s) => s['is_win'] != true && s['is_lost'] != true).toList();
        final pickFrom = openStages.isNotEmpty ? openStages : _stages;
        _stageId = pickFrom.isNotEmpty ? pickFrom.first['id'] as int? : null;
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      SnackBarHelper.show(context, message: 'عنوان الزامی است', isError: true);
      return;
    }
    if (_personId == null) {
      SnackBarHelper.show(context, message: 'انتخاب مشتری الزامی است', isError: true);
      return;
    }
    if (_processId == null || _stageId == null) {
      SnackBarHelper.show(context, message: 'پایپلاین و مرحله الزامی است', isError: true);
      return;
    }
    final amount = double.tryParse(_amountCtrl.text.trim().replaceAll(',', '')) ?? 0;
    setState(() => _saving = true);
    try {
      final created = await widget.crmService.createDeal(
        businessId: widget.businessId,
        personId: _personId!,
        processDefinitionId: _processId!,
        stageId: _stageId!,
        title: _titleCtrl.text.trim(),
        amount: amount,
        nextFollowUpAt: _followUp,
      );
      if (!mounted) return;
      Navigator.of(context).pop(created);
      widget.onSaved();
      SnackBarHelper.show(context, message: 'فرصت فروش ایجاد شد');
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
      title: 'فرصت فروش جدید',
      subtitle: 'مشتری، عنوان و مرحله را مشخص کنید.',
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
            title: 'مشتری و عنوان',
            child: Column(
              children: [
                PersonComboboxWidget(
                  businessId: widget.businessId,
                  label: 'مشتری *',
                  hintText: 'جست‌وجو و انتخاب مشتری',
                  isRequired: true,
                  personTypes: [PersonType.customer.persianName],
                  selectedPerson: _person,
                  onChanged: (p) => setState(() {
                    _person = p;
                    _personId = p?.id;
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(labelText: 'عنوان *', border: OutlineInputBorder()),
                  autofocus: widget.initialPersonId != null,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _amountCtrl,
                  decoration: const InputDecoration(labelText: 'مبلغ', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CrmSectionCard(
            title: 'پایپلاین',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.processDefs.length > 1) ...[
                  DropdownButtonFormField<int?>(
                    value: _processId,
                    decoration: const InputDecoration(labelText: 'پایپلاین فروش', border: OutlineInputBorder()),
                    items: widget.processDefs
                        .map((p) => DropdownMenuItem<int?>(value: p['id'] as int?, child: Text(p['name']?.toString() ?? '')))
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _processId = v;
                        final proc = widget.processDefs.firstWhere((e) => e['id'] == v, orElse: () => <String, dynamic>{});
                        _stages = (proc['stages'] is List ? (proc['stages'] as List).cast<Map<String, dynamic>>() : <Map<String, dynamic>>[]);
                        _stages.sort((a, b) => ((a['order_index'] ?? 0) as num).compareTo((b['order_index'] ?? 0) as num));
                        final openStages = _stages.where((s) => s['is_win'] != true && s['is_lost'] != true).toList();
                        final pickFrom = openStages.isNotEmpty ? openStages : _stages;
                        _stageId = pickFrom.isNotEmpty ? pickFrom.first['id'] as int? : null;
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
                const SizedBox(height: 12),
                CrmFollowUpField(
                  value: _followUp,
                  onChanged: (v) => setState(() => _followUp = v),
                  calendarController: widget.calendarController,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
