import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/crm/crm_responsive_dialog.dart';
import 'package:hesabix_ui/widgets/crm/crm_section_card.dart';

/// ویزارد جداگانه بستن فرصت فروش (برد / باخت).
Future<bool> showCrmCloseDealDialog(
  BuildContext context, {
  required int businessId,
  required int dealId,
  required CrmService crmService,
  required List<Map<String, dynamic>> stages,
  int? currentStageId,
  int? documentId,
  VoidCallback? onClosed,
}) async {
  final result = await showGlassDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _CrmCloseDealDialog(
      businessId: businessId,
      dealId: dealId,
      crmService: crmService,
      stages: stages,
      currentStageId: currentStageId,
      documentId: documentId,
    ),
  );
  if (result == true) onClosed?.call();
  return result == true;
}

class _CrmCloseDealDialog extends StatefulWidget {
  final int businessId;
  final int dealId;
  final CrmService crmService;
  final List<Map<String, dynamic>> stages;
  final int? currentStageId;
  final int? documentId;

  const _CrmCloseDealDialog({
    required this.businessId,
    required this.dealId,
    required this.crmService,
    required this.stages,
    this.currentStageId,
    this.documentId,
  });

  @override
  State<_CrmCloseDealDialog> createState() => _CrmCloseDealDialogState();
}

class _CrmCloseDealDialogState extends State<_CrmCloseDealDialog> {
  bool _isWon = true;
  int? _stageId;
  String? _reasonCode;
  final _competitorCtrl = TextEditingController();
  List<Map<String, dynamic>> _reasons = [];
  bool _loadingReasons = true;
  bool _saving = false;

  List<Map<String, dynamic>> get _winStages =>
      widget.stages.where((s) => s['is_win'] == true).toList();
  List<Map<String, dynamic>> get _lostStages =>
      widget.stages.where((s) => s['is_lost'] == true).toList();

  @override
  void initState() {
    super.initState();
    final win = _winStages;
    final lost = _lostStages;
    if (win.isNotEmpty) {
      _stageId = win.first['id'] as int?;
    } else if (lost.isNotEmpty) {
      _isWon = false;
      _stageId = lost.first['id'] as int?;
    }
    _loadReasons();
  }

  @override
  void dispose() {
    _competitorCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReasons() async {
    setState(() => _loadingReasons = true);
    try {
      final list = await widget.crmService.listCloseReasons(
        businessId: widget.businessId,
        reasonType: _isWon ? 'won' : 'lost',
      );
      if (!mounted) return;
      setState(() {
        _reasons = list;
        _reasonCode = null;
        _loadingReasons = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingReasons = false);
    }
  }

  Future<void> _submit() async {
    if (_stageId == null) {
      SnackBarHelper.show(context, message: 'مرحله بستن تعریف نشده است', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.crmService.updateDeal(
        businessId: widget.businessId,
        dealId: widget.dealId,
        stageId: _stageId,
        documentId: widget.documentId,
        closedAt: DateTime.now(),
        wonReasonCode: _isWon ? _reasonCode : null,
        lostReasonCode: !_isWon ? _reasonCode : null,
        competitorName: !_isWon && _competitorCtrl.text.trim().isNotEmpty
            ? _competitorCtrl.text.trim()
            : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      SnackBarHelper.show(context, message: _isWon ? 'فرصت به‌عنوان برد بسته شد' : 'فرصت به‌عنوان باخت بسته شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final outcomeStages = _isWon ? _winStages : _lostStages;
    return CrmResponsiveDialog(
      title: 'بستن فرصت فروش',
      subtitle: 'نتیجه معامله و دلیل را مشخص کنید.',
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('انصراف')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_isWon ? 'ثبت برد' : 'ثبت باخت'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CrmSectionCard(
            title: 'نتیجه',
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('برد'), icon: Icon(Icons.emoji_events_outlined, size: 18)),
                ButtonSegment(value: false, label: Text('باخت'), icon: Icon(Icons.sentiment_dissatisfied_outlined, size: 18)),
              ],
              selected: {_isWon},
              onSelectionChanged: (s) {
                if (s.isEmpty) return;
                setState(() {
                  _isWon = s.first;
                  final stages = _isWon ? _winStages : _lostStages;
                  _stageId = stages.isNotEmpty ? stages.first['id'] as int? : null;
                });
                _loadReasons();
              },
            ),
          ),
          const SizedBox(height: 16),
          CrmSectionCard(
            title: 'مرحله پایانی',
            child: outcomeStages.isEmpty
                ? const Text('مرحله برد/باخت در پایپلاین تعریف نشده است. از «فرایندها و مراحل قیف» اضافه کنید.')
                : DropdownButtonFormField<int?>(
                    value: _stageId,
                    decoration: const InputDecoration(labelText: 'مرحله', border: OutlineInputBorder()),
                    items: outcomeStages
                        .map((s) => DropdownMenuItem<int?>(
                              value: s['id'] as int?,
                              child: Text(s['name']?.toString() ?? ''),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _stageId = v),
                  ),
          ),
          const SizedBox(height: 16),
          CrmSectionCard(
            title: _isWon ? 'دلیل برد' : 'دلیل باخت',
            child: _loadingReasons
                ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_reasons.isEmpty)
                        const Text('دلیلی تعریف نشده. می‌توانید از تنظیمات CRM اضافه کنید.')
                      else
                        DropdownButtonFormField<String?>(
                          value: _reasonCode,
                          decoration: const InputDecoration(labelText: 'دلیل', border: OutlineInputBorder()),
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('انتخاب نشده')),
                            ..._reasons.map((r) => DropdownMenuItem<String?>(
                                  value: r['code']?.toString(),
                                  child: Text(r['name']?.toString() ?? r['code']?.toString() ?? ''),
                                )),
                          ],
                          onChanged: (v) => setState(() => _reasonCode = v),
                        ),
                      if (!_isWon) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _competitorCtrl,
                          decoration: const InputDecoration(
                            labelText: 'نام رقیب (اختیاری)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
