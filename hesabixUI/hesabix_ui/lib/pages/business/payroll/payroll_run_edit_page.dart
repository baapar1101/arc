import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart';
import '../../../services/payroll_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/date_input_field.dart';
import '../../../widgets/invoice/invoice_pdf_print_flow.dart';
import 'payroll_calendar_utils.dart';
import 'payroll_post_payment_dialog.dart';
import 'payroll_run_import_dialog.dart';
import 'payroll_ui.dart';
import 'package:hesabix_ui/services/bytes_export/bytes_export_service.dart';

/// ایجاد یا ویرایش سند حقوق (اجرای حقوق).
class PayrollRunEditPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;
  final int? runId;

  const PayrollRunEditPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
    this.runId,
  });

  bool get isNew => runId == null;

  @override
  State<PayrollRunEditPage> createState() => _PayrollRunEditPageState();
}

class _PayrollRunEditPageState extends State<PayrollRunEditPage> {
  final PayrollService _svc = PayrollService();
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;
  bool _generatingPdf = false;
  Map<String, dynamic>? _deptSummary;

  Map<String, dynamic>? _run;
  List<Map<String, dynamic>> _periods = [];
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _items = [];

  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;

  DateTime? _runDate;

  int? _periodId;
  final Set<int> _selectedEmployeeIds = {};
  final Map<String, TextEditingController> _amountControllers = {};

  bool get _canOperate =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('payroll', 'operate');

  bool get _canPost =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('payroll', 'post');

  bool get _canApprove =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('payroll', 'approve');

  bool get _isDraft => _run == null || _run!['status'] == 'draft';

  List<Map<String, dynamic>> get _documentLinks {
    final raw = _run?['document_links'];
    if (raw is! List) return const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  bool get _hasAccrualLink => _documentLinks.any((l) => l['link_type'] == 'accrual');

  bool get _hasPaymentLink => _documentLinks.any((l) => l['link_type'] == 'payment');

  bool get _isJalali => widget.calendarController.isJalali;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _descCtrl = TextEditingController();
    _runDate = DateTime.now();
    widget.calendarController.addListener(_onCalendarChanged);
    _load();
  }

  void _onCalendarChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.calendarController.removeListener(_onCalendarChanged);
    _titleCtrl.dispose();
    _descCtrl.dispose();
    for (final c in _amountControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _amountKey(int employeeId, int itemId) => '$employeeId:$itemId';

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final futures = <Future>[
        _svc.listPeriods(businessId: widget.businessId),
        _svc.listEmployees(businessId: widget.businessId),
        _svc.listItems(businessId: widget.businessId),
      ];
      if (widget.runId != null) {
        futures.add(_svc.getRun(businessId: widget.businessId, runId: widget.runId!));
      }
      final results = await Future.wait(futures);
      if (!mounted) return;

      _periods = List<Map<String, dynamic>>.from(results[0] as List);
      _employees = List<Map<String, dynamic>>.from(results[1] as List);
      _items = List<Map<String, dynamic>>.from(results[2] as List);

      if (widget.runId != null) {
        _run = Map<String, dynamic>.from(results[3] as Map);
        _titleCtrl.text = '${_run!['title'] ?? ''}';
        _descCtrl.text = '${_run!['description'] ?? ''}';
        _runDate = HesabixDateUtils.parseApiDate(_run!['run_date']) ?? DateTime.now();
        _periodId = (_run!['period_id'] as num?)?.toInt();
        _bindLineControllers(_run!);
        if (_run!['status'] != 'draft' && _run!['status'] != 'cancelled') {
          try {
            _deptSummary = await _svc.getDepartmentSummary(
              businessId: widget.businessId,
              runId: widget.runId,
            );
          } catch (_) {
            _deptSummary = null;
          }
        }
      } else {
        _selectedEmployeeIds.addAll(
          _employees.map((e) => (e['id'] as num).toInt()),
        );
      }
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  void _bindLineControllers(Map<String, dynamic> run) {
    for (final c in _amountControllers.values) {
      c.dispose();
    }
    _amountControllers.clear();
    final lines = _asLines(run);
    for (final line in lines) {
      final empId = (line['employee_id'] as num).toInt();
      _selectedEmployeeIds.add(empId);
      final items = (line['items'] as List?) ?? [];
      for (final item in items) {
        final m = Map<String, dynamic>.from(item as Map);
        final itemId = (m['item_definition_id'] as num).toInt();
        final key = _amountKey(empId, itemId);
        _amountControllers[key] = TextEditingController(
          text: m['amount'] != null ? PayrollUi.formatInputValue(m['amount']) : '',
        );
      }
    }
  }

  List<Map<String, dynamic>> _asLines(Map<String, dynamic> run) {
    final raw = run['lines'];
    if (raw is! List) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  TextEditingController _controllerFor(int employeeId, int itemId) {
    final key = _amountKey(employeeId, itemId);
    return _amountControllers.putIfAbsent(key, () => TextEditingController());
  }

  Map<String, dynamic> _buildLinesPayload() {
    final lines = <Map<String, dynamic>>[];
    for (final empId in _selectedEmployeeIds) {
      final items = <Map<String, dynamic>>[];
      for (final item in _items) {
        final itemId = (item['id'] as num).toInt();
        final ctrl = _amountControllers[_amountKey(empId, itemId)];
        final text = ctrl?.text.trim() ?? '';
        if (text.isEmpty) continue;
        final amount = PayrollUi.parseMoneyInput(text);
        if (amount == null) continue;
        items.add({'item_definition_id': itemId, 'amount': amount});
      }
      lines.add({'employee_id': empId, 'items': items});
    }
    return {'lines': lines};
  }

  Future<void> _save({bool finalize = false}) async {
    if (!_canOperate || !_isDraft) return;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedEmployeeIds.isEmpty) {
      SnackBarHelper.showError(
        context,
        message: AppLocalizations.of(context).payrollSelectEmployees,
      );
      return;
    }
    if (_runDate == null) {
      SnackBarHelper.showError(
        context,
        message: AppLocalizations.of(context).required,
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final base = <String, dynamic>{
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'run_date': HesabixDateUtils.formatForApiDate(_runDate!),
        'period_id': _periodId,
      };

      if (widget.isNew) {
        base['employee_ids'] = _selectedEmployeeIds.toList();
      } else {
        base.addAll(_buildLinesPayload());
      }

      Map<String, dynamic> result;
      if (widget.isNew) {
        result = await _svc.createRun(businessId: widget.businessId, payload: base);
        final runId = (result['id'] as num).toInt();
        if (finalize) {
          result = await _svc.finalizeRun(businessId: widget.businessId, runId: runId);
        }
        if (!mounted) return;
        SnackBarHelper.show(context, message: AppLocalizations.of(context).saved);
        context.go(context.businessPanelUrl(widget.businessId, 'payroll/$runId'));
        return;
      }

      result = await _svc.updateRun(
        businessId: widget.businessId,
        runId: widget.runId!,
        payload: base,
      );
      if (finalize) {
        result = await _svc.finalizeRun(
          businessId: widget.businessId,
          runId: widget.runId!,
        );
      }

      if (!mounted) return;
      SnackBarHelper.show(context, message: AppLocalizations.of(context).saved);
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _finalizeExisting() async {
    if (widget.runId == null || !_isDraft) return;
    setState(() => _saving = true);
    try {
      await _svc.finalizeRun(businessId: widget.businessId, runId: widget.runId!);
      if (!mounted) return;
      SnackBarHelper.show(context, message: AppLocalizations.of(context).payrollRunFinalized);
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _approveRun() async {
    if (widget.runId == null || !_canApprove) return;
    setState(() => _saving = true);
    try {
      await _svc.approveRun(businessId: widget.businessId, runId: widget.runId!);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).payrollRunApproved);
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _rejectRun() async {
    if (widget.runId == null || !_canApprove) return;
    final t = AppLocalizations.of(context);
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.payrollRejectRun),
        content: TextField(
          controller: reasonCtrl,
          decoration: InputDecoration(labelText: t.payrollRejectReason),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.payrollRejectRun)),
        ],
      ),
    );
    if (ok != true) {
      reasonCtrl.dispose();
      return;
    }
    setState(() => _saving = true);
    try {
      await _svc.rejectRun(
        businessId: widget.businessId,
        runId: widget.runId!,
        reason: reasonCtrl.text,
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: t.payrollRunRejected);
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      reasonCtrl.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _postAccounting() async {
    if (widget.runId == null || !_canPost) return;
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.payrollPostAccounting),
        content: Text(t.payrollPostAccountingConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.confirm)),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await _svc.postRun(businessId: widget.businessId, runId: widget.runId!);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: t.payrollPostedSuccess);
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _postPayment() async {
    if (widget.runId == null || !_canPost || !_hasAccrualLink || _hasPaymentLink) return;
    final accountId = await PayrollPostPaymentDialog.show(context, businessId: widget.businessId);
    if (accountId == null) return;
    setState(() => _saving = true);
    try {
      await _svc.postRunPayment(
        businessId: widget.businessId,
        runId: widget.runId!,
        paymentAccountId: accountId,
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).payrollPaymentPosted);
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _downloadPayslip() async {
    if (widget.runId == null) return;
    setState(() => _generatingPdf = true);
    try {
      final bytes = await _svc.downloadPayslipPdf(
        businessId: widget.businessId,
        runId: widget.runId!,
      );
      final code = '${_run?['code'] ?? widget.runId}';
      final result = await InvoicePdfPrintFlow.savePdfBytesWeb(bytes, 'payslip_$code');
      if (!mounted) return;
      BytesExportService.showFeedback(
        context,
        result,
        successOverride: AppLocalizations.of(context).payrollPayslipSaved,
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  Future<void> _copyRun() async {
    if (widget.runId == null || !_canOperate) return;
    final t = AppLocalizations.of(context);
    final openPeriods = _periods.where((p) => p['status'] != 'closed').toList();
    int? targetPeriodId = _periodId;
    if (openPeriods.isNotEmpty) {
      targetPeriodId = await showDialog<int?>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(t.payrollPeriod),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, _periodId),
              child: Text(t.payrollCopyRun),
            ),
            ...openPeriods.map(
              (p) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, (p['id'] as num).toInt()),
                child: Text(PayrollCalendarUtils.periodTitle(p, _isJalali)),
              ),
            ),
          ],
        ),
      );
    }
    if (!mounted) return;
    try {
      setState(() => _saving = true);
      final result = await _svc.copyRun(
        businessId: widget.businessId,
        runId: widget.runId!,
        payload: {if (targetPeriodId != null) 'period_id': targetPeriodId},
      );
      if (!mounted) return;
      final newId = (result['id'] as num).toInt();
      SnackBarHelper.showSuccess(context, message: t.payrollCopyRunSuccess);
      context.go(context.businessPanelUrl(widget.businessId, 'payroll/$newId'));
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _importLines() async {
    if (widget.runId == null || !_isDraft) return;
    final ok = await PayrollRunImportDialog.show(
      context,
      businessId: widget.businessId,
      runId: widget.runId!,
    );
    if (ok == true) await _load();
  }

  Future<void> _deleteRun() async {
    if (widget.runId == null || !_isDraft) return;
    final t = AppLocalizations.of(context);
    final ok = await PayrollUi.showConfirmDialog(
      context: context,
      title: t.delete,
      message: t.payrollDeleteRunConfirm,
      icon: Icons.delete_outline,
      destructive: true,
      confirmLabel: t.delete,
    );
    if (ok != true) return;
    try {
      await _svc.deleteRun(businessId: widget.businessId, runId: widget.runId!);
      if (!mounted) return;
      context.go(context.businessPanelUrl(widget.businessId, 'payroll'));
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final status = _run?['status'] as String?;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? t.payrollNewRun : t.payrollEditRun),
        actions: [
          if (!widget.isNew && _canOperate)
            IconButton(
              icon: const Icon(Icons.content_copy_outlined),
              tooltip: t.payrollCopyRun,
              onPressed: _saving ? null : _copyRun,
            ),
          if (!widget.isNew)
            IconButton(
              icon: _generatingPdf
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
              tooltip: t.payrollDownloadPayslip,
              onPressed: _generatingPdf ? null : _downloadPayslip,
            ),
          if (_isDraft && _canOperate && !widget.isNew)
            IconButton(
              icon: const Icon(Icons.upload_file_outlined),
              tooltip: t.payrollImportRunLines,
              onPressed: _importLines,
            ),
          if (_run != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Center(
                child: PayrollUi.statusChip(
                  context,
                  PayrollUi.runStatusLabel(t, status),
                  color: PayrollUi.runStatusColor(context, status),
                ),
              ),
            ),
          if (_isDraft && _canOperate && !widget.isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: t.delete,
              onPressed: _deleteRun,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: PayrollUi.pagePadding,
                children: [
                  PayrollUi.sectionCard(
                    context: context,
                    title: t.payrollRunTitle,
                    icon: Icons.description_outlined,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _titleCtrl,
                          enabled: _isDraft,
                          decoration: PayrollUi.fieldDecoration(context, t.payrollRunTitle, prefixIcon: Icons.title),
                          validator: (v) => (v == null || v.trim().isEmpty) ? t.required : null,
                        ),
                        const SizedBox(height: 12),
                        DateInputField(
                          value: _runDate,
                          enabled: _isDraft,
                          calendarController: widget.calendarController,
                          labelText: t.payrollRunDate,
                          validator: (v) => (v == null || v.trim().isEmpty) ? t.required : null,
                          onChanged: _isDraft ? (d) => setState(() => _runDate = d) : null,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int?>(
                          initialValue: _periodId,
                          decoration: PayrollUi.fieldDecoration(context, t.payrollPeriod, prefixIcon: Icons.calendar_month),
                          items: [
                            DropdownMenuItem<int?>(value: null, child: Text('—')),
                            ..._periods.map(
                              (p) => DropdownMenuItem<int?>(
                                value: (p['id'] as num).toInt(),
                                child: Text(PayrollCalendarUtils.periodTitle(p, _isJalali)),
                              ),
                            ),
                          ],
                          onChanged: _isDraft ? (v) => setState(() => _periodId = v) : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _descCtrl,
                          enabled: _isDraft,
                          maxLines: 2,
                          decoration: PayrollUi.fieldDecoration(context, t.description, prefixIcon: Icons.notes),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_run != null) ...[
                    _TotalsBar(run: _run!),
                    const SizedBox(height: 16),
                    if (_documentLinks.isNotEmpty)
                      _AccountingLinksCard(
                        links: _documentLinks,
                        t: t,
                        isJalali: _isJalali,
                      ),
                    if (_documentLinks.isNotEmpty) const SizedBox(height: 16),
                    if (_deptSummary != null) _DepartmentSummaryCard(summary: _deptSummary!, t: t),
                    if (_deptSummary != null) const SizedBox(height: 16),
                  ],
                  PayrollUi.sectionCard(
                    context: context,
                    title: t.payrollEmployeesTab,
                    icon: Icons.people_outline,
                    child: Column(
                      children: [
                        if (widget.isNew)
                          ..._employees.map((emp) {
                            final id = (emp['id'] as num).toInt();
                            final selected = _selectedEmployeeIds.contains(id);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Material(
                                color: selected
                                    ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35)
                                    : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(12),
                                child: CheckboxListTile(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  value: selected,
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selectedEmployeeIds.add(id);
                                      } else {
                                        _selectedEmployeeIds.remove(id);
                                      }
                                    });
                                  },
                                  title: Text('${emp['person_name'] ?? emp['employee_code']}'),
                                  subtitle: Text('${emp['employee_code']}'),
                                ),
                              ),
                            );
                          }),
                        if (!widget.isNew) ..._buildEmployeeLineEditors(t),
                      ],
                    ),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
      bottomNavigationBar: _buildBottomBar(t),
    );
  }

  Widget? _buildBottomBar(AppLocalizations t) {
    if (_run != null && _run!['status'] == 'pending_approval' && _canApprove) {
      return PayrollUi.bottomActionBar(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : _rejectRun,
              child: Text(t.payrollRejectRun),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _saving ? null : _approveRun,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t.payrollApproveRun),
            ),
          ),
        ],
      );
    }

    if (_run != null &&
        _run!['status'] == 'finalized' &&
        !_hasAccrualLink &&
        _canPost) {
      return PayrollUi.bottomActionBar(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: _saving ? null : _postAccounting,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t.payrollPostAccounting),
            ),
          ),
        ],
      );
    }

    if (_run != null && _hasAccrualLink && !_hasPaymentLink && _canPost) {
      return PayrollUi.bottomActionBar(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: _saving ? null : _postPayment,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t.payrollPostPayment),
            ),
          ),
        ],
      );
    }

    if (_isDraft && _canOperate) {
      return PayrollUi.bottomActionBar(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : () => _save(),
              child: Text(t.save),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _saving
                  ? null
                  : () => widget.isNew ? _save(finalize: true) : _finalizeExisting(),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(t.payrollFinalizeRun),
            ),
          ),
        ],
      );
    }
    return null;
  }

  List<Widget> _buildEmployeeLineEditors(AppLocalizations t) {
    final lines = _asLines(_run!);
    return lines.map((line) {
      final empId = (line['employee_id'] as num).toInt();
      final name = line['person_name'] ?? line['employee_code'] ?? '';
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(PayrollUi.cardRadius),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PayrollUi.cardRadius),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            child: ExpansionTile(
              leading: CircleAvatar(
                radius: 18,
                child: Text(name.toString().isNotEmpty ? name.toString().substring(0, 1) : '?'),
              ),
              title: Text('$name'),
              subtitle: Text('${t.payrollNetAmount}: ${PayrollUi.formatMoney(line['net_amount'])}'),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    children: _items.map((item) {
                      final itemId = (item['id'] as num).toInt();
                      final ctrl = _controllerFor(empId, itemId);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TextFormField(
                          controller: ctrl,
                          enabled: _isDraft,
                          keyboardType: TextInputType.number,
                          inputFormatters: PayrollUi.numericInputFormatters(),
                          decoration: PayrollUi.fieldDecoration(context, '${item['name']}'),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }
}

class _AccountingLinksCard extends StatelessWidget {
  final List<Map<String, dynamic>> links;
  final AppLocalizations t;
  final bool isJalali;

  const _AccountingLinksCard({
    required this.links,
    required this.t,
    required this.isJalali,
  });

  String _linkLabel(String? type) {
    switch (type) {
      case 'accrual':
        return t.payrollLinkAccrual;
      case 'payment':
        return t.payrollLinkPayment;
      default:
        return type ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PayrollUi.sectionCard(
      context: context,
      title: t.payrollAccountingLinks,
      icon: Icons.account_balance_outlined,
      child: Column(
        children: links.map((link) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(
              link['link_type'] == 'payment' ? Icons.payments_outlined : Icons.account_balance_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(_linkLabel(link['link_type'] as String?)),
            subtitle: Text(
              [
                '${link['document_code'] ?? link['document_id']}',
                if (link['document_date'] != null)
                  PayrollCalendarUtils.formatRowDate(link, 'document_date', isJalali),
              ].join(' · '),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _DepartmentSummaryCard extends StatelessWidget {
  final Map<String, dynamic> summary;
  final AppLocalizations t;

  const _DepartmentSummaryCard({required this.summary, required this.t});

  @override
  Widget build(BuildContext context) {
    final items = (summary['items'] as List?) ?? [];
    if (items.isEmpty) return const SizedBox.shrink();
    return PayrollUi.sectionCard(
      context: context,
      title: t.payrollDepartmentSummary,
      icon: Icons.apartment_outlined,
      child: Column(
        children: items.map((raw) {
          final row = Map<String, dynamic>.from(raw as Map);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(child: Text('${row['department_name'] ?? '—'}')),
                Text('${PayrollUi.formatCount(row['employee_count'] ?? 0)}'),
                const SizedBox(width: 12),
                Text(PayrollUi.formatMoney(row['net_total'])),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TotalsBar extends StatelessWidget {
  final Map<String, dynamic> run;

  const _TotalsBar({required this.run});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return PayrollUi.sectionCard(
      context: context,
      title: t.payrollGrossTotal,
      icon: Icons.summarize_outlined,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _totalChip(context, t.payrollGrossTotal, run['gross_total'], Icons.trending_up),
          _totalChip(context, t.payrollDeductionTotal, run['deduction_total'], Icons.remove_circle_outline),
          _totalChip(context, t.payrollNetTotal, run['net_total'], Icons.payments_outlined),
        ],
      ),
    );
  }

  Widget _totalChip(BuildContext context, String label, dynamic value, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text(
                PayrollUi.formatMoney(value),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
