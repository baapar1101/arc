import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart' as Hd;
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/business_user_model.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/services/business_user_service.dart';
import 'package:hesabix_ui/services/bytes_export/bytes_export_service.dart';
import 'package:hesabix_ui/services/distribution_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/distribution/distribution_ui_helpers.dart';
import 'package:hesabix_ui/widgets/invoice/cash_register_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/bank_account_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/widgets/jalali_date_picker.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

/// تب تسویه روزانه ویزیتور.
class DistributionSettlementPanel extends StatefulWidget {
  final int businessId;
  final DistributionService service;
  final CalendarController calendarController;
  final bool canManage;
  final bool canSettle;
  final int? currentUserId;

  const DistributionSettlementPanel({
    super.key,
    required this.businessId,
    required this.service,
    required this.calendarController,
    required this.canManage,
    this.canSettle = false,
    this.currentUserId,
  });

  @override
  State<DistributionSettlementPanel> createState() => _DistributionSettlementPanelState();
}

class _ChequeRow {
  Person? person;
  final amount = TextEditingController();
  final checkNumber = TextEditingController();
  final dueDate = TextEditingController();
  final bankName = TextEditingController();

  void dispose() {
    amount.dispose();
    checkNumber.dispose();
    dueDate.dispose();
    bankName.dispose();
  }
}

class _DistributionSettlementPanelState extends State<DistributionSettlementPanel> {
  DateTime _day = DateTime.now();
  int? _userId;
  Map<String, dynamic>? _preview;
  bool _loading = false;
  final _cashCtl = TextEditingController(text: '0');
  final _chequeCtl = TextEditingController(text: '0');
  final _cardCtl = TextEditingController(text: '0');
  final _otherCtl = TextEditingController(text: '0');
  final _expenseCtl = TextEditingController(text: '0');
  final _notesCtl = TextEditingController();
  final List<_ChequeRow> _chequeRows = [];
  int? _cashRegisterId;
  int? _bankId;
  bool _createReceipt = false;
  bool _allowVariance = false;

  bool get _canConfirm => widget.canManage || widget.canSettle;

  bool get _jalali => widget.calendarController.isJalali;

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  double _parseAmt(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  @override
  void initState() {
    super.initState();
    _userId = widget.currentUserId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreview());
  }

  @override
  void dispose() {
    _cashCtl.dispose();
    _chequeCtl.dispose();
    _cardCtl.dispose();
    _otherCtl.dispose();
    _expenseCtl.dispose();
    _notesCtl.dispose();
    for (final r in _chequeRows) {
      r.dispose();
    }
    super.dispose();
  }

  void _addChequeRow() {
    setState(() {
      final row = _ChequeRow();
      row.dueDate.text = _iso(_day);
      _chequeRows.add(row);
    });
  }

  List<Map<String, dynamic>>? _buildChequeItems() {
    if (_parseAmt(_chequeCtl) <= 0) return null;
    final items = <Map<String, dynamic>>[];
    for (final r in _chequeRows) {
      final pid = r.person?.id;
      final amt = double.tryParse(r.amount.text.trim().replaceAll(',', '.')) ?? 0;
      final num = r.checkNumber.text.trim();
      if (pid == null || pid <= 0 || amt <= 0 || num.isEmpty) continue;
      items.add({
        'person_id': pid,
        'amount': amt,
        'check_number': num,
        'issue_date': _iso(_day),
        'due_date': r.dueDate.text.trim().isEmpty ? _iso(_day) : r.dueDate.text.trim(),
        if (r.bankName.text.trim().isNotEmpty) 'bank_name': r.bankName.text.trim(),
      });
    }
    return items;
  }

  Future<void> _loadPreview() async {
    setState(() => _loading = true);
    try {
      final d = await widget.service.previewSettlement(
        businessId: widget.businessId,
        settlementDate: _iso(_day),
        targetUserId: _userId,
      );
      if (!mounted) return;
      final existing = d['existing'];
      if (existing is Map) {
        _cashCtl.text = '${existing['cash_collected'] ?? 0}';
        _chequeCtl.text = '${existing['cheque_collected'] ?? 0}';
        _cardCtl.text = '${existing['card_collected'] ?? 0}';
        _otherCtl.text = '${existing['other_collected'] ?? 0}';
        _expenseCtl.text = '${existing['expenses'] ?? 0}';
        _notesCtl.text = existing['notes']?.toString() ?? '';
        final cr = existing['cash_register_id'];
        if (cr != null) _cashRegisterId = int.tryParse('$cr');
      } else {
        // پیش‌فرض نقد = فروش مورد انتظار
        _cashCtl.text = '${d['expected_sales'] ?? 0}';
      }
      setState(() => _preview = d);
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save({bool confirm = false}) async {
    final t = AppLocalizations.of(context);
    final variance = _parseAmt(_cashCtl) +
        _parseAmt(_chequeCtl) +
        _parseAmt(_cardCtl) +
        _parseAmt(_otherCtl) -
        (double.tryParse('${_preview?['expected_sales'] ?? 0}') ?? 0) -
        _parseAmt(_expenseCtl);
    if (confirm && variance.abs() >= 0.01 && !_allowVariance) {
      SnackBarHelper.showError(context, message: t.distributionVarianceMustBeZero);
      return;
    }
    if (confirm && _allowVariance && !widget.canManage) {
      SnackBarHelper.showError(context, message: t.distributionVarianceOverrideManageOnly);
      return;
    }
    if (confirm && _createReceipt) {
      if (_parseAmt(_cashCtl) > 0 && _cashRegisterId == null) {
        SnackBarHelper.showError(context, message: t.distributionCashRegisterRequired);
        return;
      }
      if (_parseAmt(_cardCtl) > 0 && _bankId == null) {
        SnackBarHelper.showError(context, message: t.distributionBankRequired);
        return;
      }
      if (_parseAmt(_chequeCtl) > 0) {
        final items = _buildChequeItems();
        if (items == null || items.isEmpty) {
          SnackBarHelper.showError(context, message: t.distributionChequeItemsRequired);
          return;
        }
        final sum = items.fold<double>(0, (a, b) => a + (b['amount'] as double));
        if ((sum - _parseAmt(_chequeCtl)).abs() >= 0.02) {
          SnackBarHelper.showError(context, message: t.distributionChequeItemsMismatch);
          return;
        }
      }
    }
    try {
      final saved = await widget.service.upsertSettlement(
        businessId: widget.businessId,
        payload: {
          if (_userId != null) 'user_id': _userId,
          'settlement_date': _iso(_day),
          'cash_collected': _parseAmt(_cashCtl),
          'cheque_collected': _parseAmt(_chequeCtl),
          'card_collected': _parseAmt(_cardCtl),
          'other_collected': _parseAmt(_otherCtl),
          'expenses': _parseAmt(_expenseCtl),
          if (_notesCtl.text.trim().isNotEmpty) 'notes': _notesCtl.text.trim(),
          if (_cashRegisterId != null) 'cash_register_id': _cashRegisterId,
        },
      );
      if (confirm) {
        if (!_canConfirm) {
          SnackBarHelper.showSuccess(context, message: t.distributionDraftAwaitingConfirm);
          await _loadPreview();
          return;
        }
        final id = int.parse('${saved['id']}');
        await widget.service.confirmSettlement(
          businessId: widget.businessId,
          settlementId: id,
          createReceipt: _createReceipt,
          cashRegisterId: _cashRegisterId,
          bankId: _bankId,
          allowVariance: _allowVariance,
          chequeItems: _createReceipt ? _buildChequeItems() : null,
        );
      }
      if (mounted) {
        SnackBarHelper.showSuccess(
          context,
          message: confirm ? t.distributionSettlementConfirmed : t.distributionSettingsSaved,
        );
      }
      await _loadPreview();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    }
  }

  Future<void> _printExisting() async {
    final existing = _preview?['existing'];
    if (existing is! Map || existing['id'] == null) return;
    final t = AppLocalizations.of(context);
    try {
      final bytes = await widget.service.downloadSettlementPdf(
        businessId: widget.businessId,
        settlementId: int.parse('${existing['id']}'),
      );
      await BytesExportService.export(
        bytes: bytes,
        filename: 'distribution_settlement_${existing['id']}.pdf',
        mimeType: 'application/pdf',
      );
      if (mounted) SnackBarHelper.showSuccess(context, message: t.distributionPdfExported);
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final expected = _preview?['expected_sales'] ?? 0;
    final snapshot = (_preview?['visit_snapshot'] as List?) ?? [];
    final existing = _preview?['existing'];
    final confirmed = existing is Map && existing['status'] == 'confirmed';
    final collected =
        _parseAmt(_cashCtl) + _parseAmt(_chequeCtl) + _parseAmt(_cardCtl) + _parseAmt(_otherCtl);
    final variance = collected - (double.tryParse('$expected') ?? 0) - _parseAmt(_expenseCtl);

    return RefreshIndicator(
      onRefresh: _loadPreview,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final d = await showAdaptiveDatePicker(
                    context: context,
                    calendarController: widget.calendarController,
                    initialDate: _day,
                  );
                  if (d != null) {
                    setState(() => _day = d);
                    await _loadPreview();
                  }
                },
                icon: const Icon(Icons.calendar_month),
                label: Text(Hd.HesabixDateUtils.formatForDisplay(_day, _jalali)),
              ),
              if (widget.canManage) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: FutureBuilder<BusinessUsersResponse>(
                    future: BusinessUserService(ApiClient()).getBusinessUsers(widget.businessId),
                    builder: (context, snap) {
                      final users = snap.data?.users ?? const <BusinessUser>[];
                      return DropdownButtonFormField<int?>(
                        value: _userId,
                        isDense: true,
                        decoration: InputDecoration(
                          labelText: t.distributionSelectVisitor,
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('—')),
                          ...users.map(
                            (u) => DropdownMenuItem<int?>(
                              value: u.userId,
                              child: Text(u.userName.isNotEmpty ? u.userName : '${u.userId}'),
                            ),
                          ),
                        ],
                        onChanged: (v) async {
                          setState(() => _userId = v);
                          await _loadPreview();
                        },
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const LinearProgressIndicator()
          else ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: Text(t.distributionExpectedSales),
                trailing: Text('$expected'),
                subtitle: Text('${snapshot.length} ${t.distributionTabVisits}'),
              ),
            ),
            const SizedBox(height: 8),
            _amtField(t.distributionCashCollected, _cashCtl),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                t.distributionCashPrefillHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            _amtField(t.distributionChequeCollected, _chequeCtl),
            if (_parseAmt(_chequeCtl) > 0) ...[
              Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        t.distributionChequeItemsTitle,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.distributionChequeItemsHint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      ..._chequeRows.asMap().entries.map((e) {
                        final r = e.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                            children: [
                              PersonComboboxWidget(
                                businessId: widget.businessId,
                                selectedPerson: r.person,
                                label: t.distributionSelectPerson,
                                hintText: t.distributionSelectPerson,
                                isRequired: true,
                                onChanged: (p) => setState(() => r.person = p),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: r.amount,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: InputDecoration(
                                        labelText: t.distributionChequeAmount,
                                        border: const OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => setState(() {
                                      r.dispose();
                                      _chequeRows.removeAt(e.key);
                                    }),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: r.checkNumber,
                                      decoration: InputDecoration(
                                        labelText: t.distributionChequeNumber,
                                        border: const OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: r.dueDate,
                                      decoration: InputDecoration(
                                        labelText: t.distributionChequeDueDate,
                                        border: const OutlineInputBorder(),
                                        isDense: true,
                                        hintText: 'YYYY-MM-DD',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                      OutlinedButton.icon(
                        onPressed: _addChequeRow,
                        icon: Icon(Icons.add),
                        label: Text(t.distributionAddChequeItem),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            _amtField(t.distributionCardCollected, _cardCtl),
            _amtField(t.distributionOtherCollected, _otherCtl),
            _amtField(t.distributionSettlementExpenses, _expenseCtl),
            SizedBox(height: 8),
            ListTile(
              title: Text(t.distributionSettlementVariance),
              trailing: Text(
                variance.toStringAsFixed(2),
                style: TextStyle(
                  color: variance.abs() < 0.01
                      ? SemanticColorResolver.positive(context)
                      : Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                t.distributionVarianceFormula,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            TextField(
              controller: _notesCtl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: t.distributionNotesLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            if (!confirmed) ...[
              SwitchListTile(
                title: Text(t.distributionCreateReceiptOnConfirm),
                subtitle: Text(t.distributionCreateReceiptHint),
                value: _createReceipt,
                onChanged: (v) => setState(() => _createReceipt = v),
              ),
              if (_createReceipt) ...[
                CashRegisterComboboxWidget(
                  businessId: widget.businessId,
                  label: t.distributionCashRegister,
                  isRequired: _parseAmt(_cashCtl) > 0,
                  onChanged: (opt) {
                    final id = int.tryParse(opt?.id ?? '');
                    setState(() => _cashRegisterId = id);
                  },
                ),
                if (_parseAmt(_cardCtl) > 0) ...[
                  const SizedBox(height: 8),
                  BankAccountComboboxWidget(
                    businessId: widget.businessId,
                    label: t.distributionBankForCard,
                    isRequired: true,
                    onChanged: (opt) {
                      final id = int.tryParse(opt?.id ?? '');
                      setState(() => _bankId = id);
                    },
                  ),
                ],
              ],
              if (widget.canManage && variance.abs() >= 0.01)
                SwitchListTile(
                  title: Text(t.distributionAllowVariance),
                  subtitle: Text(t.distributionAllowVarianceHint),
                  value: _allowVariance,
                  onChanged: (v) => setState(() => _allowVariance = v),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _save(confirm: false),
                      child: Text(t.distributionSaveDraft),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _canConfirm ? () => _save(confirm: true) : null,
                      child: Text(
                        _canConfirm
                            ? t.distributionConfirmSettlement
                            : t.distributionSaveDraftOnly,
                      ),
                    ),
                  ),
                ],
              ),
              if (!_canConfirm)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    t.distributionConfirmNeedsManager,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ] else
              Chip(
                avatar: const Icon(Icons.lock_outline, size: 16),
                label: Text(t.distributionSettlementConfirmed),
              ),
            if (existing is Map && existing['id'] != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _printExisting,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(t.distributionPrintSettlement),
              ),
            ],
            const SizedBox(height: 16),
            Text(t.distributionTabVisits, style: Theme.of(context).textTheme.titleSmall),
            ...snapshot.map((raw) {
              final m = Map<String, dynamic>.from(raw as Map);
              return ListTile(
                dense: true,
                title: Text(m['person_name']?.toString() ?? '${m['person_id']}'),
                subtitle: Text(
                  '${distributionVisitStatusLabel(t, m['status']?.toString())}'
                  ' · ${distributionOutcomeLabel(t, m['outcome']?.toString())}'
                  '${m['document_id'] != null ? ' · #${m['document_id']}' : ''}',
                ),
                trailing: Text('${m['amount'] ?? '—'}'),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _amtField(String label, TextEditingController ctl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (_) => setState(() {}),
        enabled: !(_preview?['existing'] is Map && _preview!['existing']['status'] == 'confirmed'),
      ),
    );
  }
}
