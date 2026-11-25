import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../../core/api_client.dart';
import '../../core/calendar_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../date_input_field.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

/// جدول پرداخت صورت‌حسابی که از طریق معتمد آسا ارسال شده و ثبت ردیف‌های تازه در کارپوشه سامانه مودیان.
class MotamedAsaPaymentsDialog extends StatefulWidget {
  final int businessId;
  final int invoiceId;
  final String invoiceCode;
  final ApiClient apiClient;
  final CalendarController calendarController;

  const MotamedAsaPaymentsDialog({
    super.key,
    required this.businessId,
    required this.invoiceId,
    required this.invoiceCode,
    required this.apiClient,
    required this.calendarController,
  });

  static Future<void> show(
    BuildContext context, {
    required int businessId,
    required int invoiceId,
    required String invoiceCode,
    required ApiClient apiClient,
    required CalendarController calendarController,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MotamedAsaPaymentsDialog(
        businessId: businessId,
        invoiceId: invoiceId,
        invoiceCode: invoiceCode,
        apiClient: apiClient,
        calendarController: calendarController,
      ),
    );
  }

  @override
  State<MotamedAsaPaymentsDialog> createState() => _MotamedAsaPaymentsDialogState();
}

class _NewPaymentRow {
  int? type;
  DateTime? date;
  TimeOfDay time = TimeOfDay.now();
  final amount = TextEditingController();
  final traceNo = TextEditingController();
  final terminal = TextEditingController();
  final description = TextEditingController();

  void dispose() {
    amount.dispose();
    traceNo.dispose();
    terminal.dispose();
    description.dispose();
  }
}

class _MotamedAsaPaymentsDialogState extends State<MotamedAsaPaymentsDialog> {
  static final _amountFormat = NumberFormat.decimalPattern();
  final _formKey = GlobalKey<FormState>();
  final List<_NewPaymentRow> _rows = [];

  Map<String, dynamic>? _state;
  String? _loadError;
  bool _loading = true;
  bool _submitting = false;
  bool _resultUnknown = false;

  String get _path =>
      '/tax-settings/business/${widget.businessId}/motamed-asa/invoices/${widget.invoiceId}/payments';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final response = await widget.apiClient.get<Map<String, dynamic>>(_path);
      final data = response.data?['data'];
      if (!mounted) return;
      setState(() => _state = data is Map ? Map<String, dynamic>.from(data) : const {});
    } catch (e) {
      if (mounted) setState(() => _loadError = ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _latinDigits(String value) {
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    final buffer = StringBuffer();
    for (final char in value.split('')) {
      final p = persian.indexOf(char);
      final a = arabic.indexOf(char);
      buffer.write(p >= 0 ? '$p' : a >= 0 ? '$a' : char);
    }
    return buffer.toString();
  }

  static String _digitsOnly(String value) =>
      _latinDigits(value).replaceAll(RegExp(r'[\s,٬،]'), '');

  void _addRow() {
    setState(() => _rows.add(_NewPaymentRow()..date = DateTime.now()));
  }

  void _removeRow(_NewPaymentRow row) {
    setState(() => _rows.remove(row));
    row.dispose();
  }

  Future<void> _pickTime(_NewPaymentRow row) async {
    final picked = await showTimePicker(context: context, initialTime: row.time);
    if (picked != null && mounted) setState(() => row.time = picked);
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    if (_rows.isEmpty || !(_formKey.currentState?.validate() ?? false)) return;
    for (final row in _rows) {
      if (row.date == null) {
        SnackBarHelper.showError(context, message: t.motamedAsaPaymentDateRequired);
        return;
      }
    }
    final payments = _rows.map((row) {
      final date = row.date!;
      final moment = DateTime(date.year, date.month, date.day, row.time.hour, row.time.minute);
      return <String, dynamic>{
        'type': row.type,
        'timestamp': moment.millisecondsSinceEpoch,
        'price': int.parse(_digitsOnly(row.amount.text)),
        if (row.traceNo.text.trim().isNotEmpty) 'trace_no': _digitsOnly(row.traceNo.text),
        if (row.terminal.text.trim().isNotEmpty) 'terminal_number': _digitsOnly(row.terminal.text),
        if (row.description.text.trim().isNotEmpty) 'description': row.description.text.trim(),
      };
    }).toList();

    setState(() => _submitting = true);
    try {
      final response = await widget.apiClient.post<Map<String, dynamic>>(
        _path,
        data: {'payments': payments},
      );
      final data = response.data?['data'];
      if (!mounted) return;
      final state = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      setState(() {
        _state = state;
        _resultUnknown = state['result_unknown'] == true;
        for (final row in _rows) {
          row.dispose();
        }
        _rows.clear();
      });
      if (_resultUnknown) {
        SnackBarHelper.showWarning(context, message: t.motamedAsaPaymentsResultUnknown);
      } else {
        SnackBarHelper.showSuccess(context, message: t.motamedAsaPaymentsRegistered);
      }
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _typeLabel(AppLocalizations t, Object? type) {
    switch (int.tryParse(type?.toString() ?? '')) {
      case 1:
        return t.motamedAsaPaymentTypeCheque;
      case 2:
        return t.motamedAsaPaymentTypeBarter;
      case 3:
        return t.motamedAsaPaymentTypeCash;
      case 4:
        return t.motamedAsaPaymentTypePos;
      case 5:
        return t.motamedAsaPaymentTypeInternet;
      case 6:
        return t.motamedAsaPaymentTypeCard;
      case 7:
        return t.motamedAsaPaymentTypeTransfer;
      case 8:
        return t.motamedAsaPaymentTypeOther;
      default:
        return type?.toString() ?? '-';
    }
  }

  ({String label, Color color}) _registration(AppLocalizations t, ColorScheme cs, Object? status) {
    switch (status?.toString()) {
      case 'registered':
        return (label: t.motamedAsaPaymentStatusRegistered, color: SemanticColorResolver.positive(context));
      case 'sentWithInvoice':
        return (label: t.motamedAsaPaymentStatusSentWithInvoice, color: SemanticColorResolver.positive(context));
      case 'queued':
        return (label: t.motamedAsaPaymentStatusQueued, color: SemanticColorResolver.warning(context));
      case 'notRegistered':
        return (label: t.motamedAsaPaymentStatusNotRegistered, color: SemanticColorResolver.warning(context));
      case 'unknown':
        return (label: t.motamedAsaPaymentStatusUnknown, color: SemanticColorResolver.warning(context));
      case 'rejected':
        return (label: t.motamedAsaPaymentStatusRejected, color: cs.error);
      case 'failed':
        return (label: t.motamedAsaPaymentStatusFailed, color: cs.error);
      case 'notApplicable':
        return (label: t.motamedAsaPaymentStatusNotApplicable, color: cs.onSurfaceVariant);
      default:
        return (label: status?.toString() ?? '-', color: cs.onSurfaceVariant);
    }
  }

  String _money(Object? value) {
    final number = num.tryParse(value?.toString() ?? '');
    return number == null ? '-' : _amountFormat.format(number);
  }

  Widget _existingPayment(AppLocalizations t, Map<String, dynamic> payment) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = _registration(t, cs, payment['registration_status']);
    final message = payment['registration_message']?.toString();
    final registeredAmount = payment['registered_amount'];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outline.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_typeLabel(t, payment['type'])} · ${payment['date_time'] ?? '-'}',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(_money(payment['price'])),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(status.label, style: theme.textTheme.bodySmall?.copyWith(color: status.color)),
              ),
              if (registeredAmount != null)
                Text('${t.motamedAsaPaymentRegisteredAmount}: ${_money(registeredAmount)}',
                    style: theme.textTheme.bodySmall),
              if (payment['trace_no'] != null)
                Text('${t.motamedAsaPaymentTraceNo}: ${payment['trace_no']}', style: theme.textTheme.bodySmall),
              if (payment['locked'] == true) Icon(Icons.lock_outline, size: 16, color: cs.onSurfaceVariant),
            ],
          ),
          if (message != null && message.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(message, style: theme.textTheme.bodySmall?.copyWith(color: cs.error)),
          ],
        ],
      ),
    );
  }

  Widget _newPayment(AppLocalizations t, _NewPaymentRow row) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    String? digits(String? value, int max) {
      final text = _digitsOnly(value ?? '');
      if (text.isEmpty) return null;
      if (!RegExp(r'^\d+$').hasMatch(text) || text.length > max) return t.motamedAsaPaymentDigitsInvalid;
      return null;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: row.type,
                  decoration: InputDecoration(labelText: t.motamedAsaPaymentType, isDense: true),
                  items: [
                    for (var type = 1; type <= 8; type++)
                      DropdownMenuItem(value: type, child: Text(_typeLabel(t, type))),
                  ],
                  onChanged: (value) => setState(() => row.type = value),
                  validator: (value) => value == null ? t.required : null,
                ),
              ),
              IconButton(
                tooltip: t.motamedAsaPaymentRemoveRow,
                onPressed: () => _removeRow(row),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DateInputField(
                  value: row.date,
                  labelText: t.motamedAsaPaymentDate,
                  calendarController: widget.calendarController,
                  lastDate: DateTime.now(),
                  isDense: true,
                  onChanged: (value) => setState(() => row.date = value),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _pickTime(row),
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(row.time.format(context)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: row.amount,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: t.motamedAsaPaymentAmount, isDense: true),
            validator: (value) {
              final amount = int.tryParse(_digitsOnly(value ?? ''));
              return amount == null || amount <= 0 ? t.motamedAsaPaymentAmountInvalid : null;
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: row.traceNo,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: t.motamedAsaPaymentTraceNo, isDense: true),
                  validator: (value) => digits(value, 14),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: row.terminal,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: t.motamedAsaPaymentTerminal, isDense: true),
                  validator: (value) => digits(value, 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: row.description,
            maxLength: 500,
            decoration: InputDecoration(labelText: t.motamedAsaPaymentDescription, isDense: true, counterText: ''),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final state = _state ?? const <String, dynamic>{};
    final eligible = state['eligible'] == true;
    final reason = state['reason']?.toString();
    final payments = (state['payments'] is List ? state['payments'] as List : const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_loadError != null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_loadError!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(t.reload)),
        ],
      );
    } else {
      body = Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.motamedAsaPaymentsDescription, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            if (!eligible)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: SemanticColorResolver.warning(context).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  [t.motamedAsaPaymentsNotEligible, if (reason != null && reason.isNotEmpty) reason].join(' '),
                ),
              ),
            if (_resultUnknown)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: SemanticColorResolver.warning(context).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(t.motamedAsaPaymentsResultUnknown),
              ),
            if (payments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(t.motamedAsaPaymentsEmpty, style: TextStyle(color: cs.onSurfaceVariant)),
              )
            else
              ...payments.map((payment) => _existingPayment(t, payment)),
            if (eligible) ...[
              const SizedBox(height: 8),
              for (final row in _rows) _newPayment(t, row),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _submitting || _rows.length >= 50 ? null : _addRow,
                  icon: const Icon(Icons.add),
                  label: Text(t.motamedAsaPaymentsAddRow),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return AlertDialog(
      title: Text('${t.motamedAsaPaymentsTitle} ${widget.invoiceCode}'.trim()),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(child: body),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: Text(t.close),
        ),
        if (eligible && _rows.isNotEmpty)
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(t.motamedAsaPaymentsRegister),
          ),
      ],
    );
  }
}
