import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/utils/api_datetime_display.dart';
import 'package:hesabix_ui/utils/number_formatters.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/document/document_details_dialog.dart';

class PayPagePaymentDetailsDialog extends StatefulWidget {
  final Map<String, dynamic> payment;

  const PayPagePaymentDetailsDialog({
    super.key,
    required this.payment,
  });

  @override
  State<PayPagePaymentDetailsDialog> createState() =>
      _PayPagePaymentDetailsDialogState();
}

class _PayPagePaymentDetailsDialogState
    extends State<PayPagePaymentDetailsDialog> {
  static const _hiddenVerifyKeys = {
    'card_num',
    'card_pan',
    'cardNum',
    'ref_id',
    'rrn',
    'gateway_ref_id',
    'factor_id',
    'factorId',
  };

  CalendarController? _calendarController;

  Map<String, dynamic> get _payment => widget.payment;

  int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  String _text(dynamic value) {
    if (value == null) return '';
    return '$value'.trim();
  }

  String _statusLabel(AppLocalizations t) {
    switch (_text(_payment['status']).toLowerCase()) {
      case 'succeeded':
        return t.payPageStatusSucceeded;
      case 'failed':
        return t.payPageStatusFailed;
      case 'pending':
        return t.payPageStatusPending;
      default:
        return _text(_payment['status']);
    }
  }

  String _paidAt(BuildContext context) {
    final display = resolveApiDateTimeDisplay(_payment, 'created_at');
    if (display.isNotEmpty) return display;
    return HesabixDateUtils.formatApiDateForDisplay(
      _payment['created_at'],
      Localizations.localeOf(context).languageCode == 'fa',
    );
  }

  String _amountText() {
    final n = _payment['amount'];
    return formatWithThousands(
      (n is num) ? n.toDouble() : double.tryParse('$n') ?? 0,
    );
  }

  String _feeText() {
    final n = _payment['fee_amount'];
    if (n == null) return '';
    return formatWithThousands(
      (n is num) ? n.toDouble() : double.tryParse('$n') ?? 0,
    );
  }

  Future<void> _copy(String value) async {
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    SnackBarHelper.show(context, message: AppLocalizations.of(context).copied);
  }

  Future<void> _openDocument() async {
    final docId = _asInt(_payment['document_id']);
    if (docId == null) return;
    _calendarController ??= await CalendarController.load();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => DocumentDetailsDialog(
        documentId: docId,
        calendarController: _calendarController!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final docId = _asInt(_payment['document_id']);
    final cardNum = _text(_payment['card_num']);
    final tracking = _text(_payment['external_ref']);
    final gatewayRef = _text(_payment['gateway_ref_id']);
    final factorId = _text(_payment['factor_id']);
    final receiptToken = _text(_payment['receipt_token']);
    final provider = _text(_payment['provider']);
    final customer = _text(_payment['person_name']).isEmpty
        ? t.payPageAnonymousCustomer
        : _text(_payment['person_name']);
    final extraVerify = _payment['gateway_verify'];
    final extraRows = <MapEntry<String, String>>[];
    if (extraVerify is Map) {
      for (final entry in extraVerify.entries) {
        final key = '${entry.key}';
        if (_hiddenVerifyKeys.contains(key)) continue;
        final value = _text(entry.value);
        if (value.isEmpty) continue;
        extraRows.add(MapEntry(key, value));
      }
    }

    return AlertDialog(
      title: Text(t.payPagePaymentDetails),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _row(t.payPagePaidAt, _paidAt(context)),
              _row(t.payPageAmount, _amountText()),
              if (_feeText().isNotEmpty) _row(t.feeAmount, _feeText()),
              _row(t.payPageStatus, _statusLabel(t)),
              _row(t.payPagePayerName, _text(_payment['payer_name'])),
              _row(t.payPagePayerMobile, _text(_payment['payer_mobile'])),
              _row(t.payPagePayerNote, _text(_payment['payer_note'])),
              _row(t.payPageCustomer, customer),
              _row(t.cardNumber, cardNum, copyable: true),
              _row(t.payPageTrackingRef, tracking, copyable: true),
              if (gatewayRef.isNotEmpty && gatewayRef != tracking)
                _row(t.payPageGatewayRef, gatewayRef, copyable: true),
              if (factorId.isNotEmpty)
                _row(t.payPageFactorId, factorId, copyable: true),
              if (receiptToken.isNotEmpty)
                _row(t.payPageReceiptToken, receiptToken, copyable: true),
              if (provider.isNotEmpty) _row(t.payPageGateway, provider),
              _row(t.transactionId, _text(_payment['id']), copyable: true),
              for (final extra in extraRows)
                _row(extra.key, extra.value, copyable: true),
              if (docId == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    t.payPageNoAccountingDocument,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (docId != null)
          FilledButton.icon(
            onPressed: _openDocument,
            icon: const Icon(Icons.description_outlined),
            label: Text(t.viewDocument),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.close),
        ),
      ],
    );
  }

  Widget _row(String label, String value, {bool copyable = false}) {
    final display = value.isEmpty ? '—' : value;
    return ListTile(
      dense: true,
      title: Text(label),
      subtitle: SelectableText(display),
      trailing: copyable && value.isNotEmpty
          ? IconButton(
              tooltip: AppLocalizations.of(context).copied,
              onPressed: () => _copy(value),
              icon: const Icon(Icons.copy_outlined, size: 18),
            )
          : null,
    );
  }
}
