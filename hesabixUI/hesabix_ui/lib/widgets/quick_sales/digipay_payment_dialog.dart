import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/auth_store.dart';
import '../../l10n/app_localizations.dart';
import '../../models/invoice_transaction.dart';
import '../../services/digipay_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/number_formatters.dart';
import '../../utils/number_normalizer.dart';

Future<InvoiceTransaction?> showDigipayPaymentDialog({
  required BuildContext context,
  required int businessId,
  required AuthStore authStore,
  required num remainingAmount,
  required int decimalPlaces,
  required String currencyUnit,
}) {
  return showDialog<InvoiceTransaction>(
    context: context,
    barrierDismissible: false,
    builder: (context) => DigipayPaymentDialog(
      businessId: businessId,
      authStore: authStore,
      remainingAmount: remainingAmount,
      decimalPlaces: decimalPlaces,
      currencyUnit: currencyUnit,
    ),
  );
}

class DigipayPaymentDialog extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final num remainingAmount;
  final int decimalPlaces;
  final String currencyUnit;

  const DigipayPaymentDialog({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.remainingAmount,
    required this.decimalPlaces,
    required this.currencyUnit,
  });

  @override
  State<DigipayPaymentDialog> createState() => _DigipayPaymentDialogState();
}

class _DigipayPaymentDialogState extends State<DigipayPaymentDialog> {
  static const _uuid = Uuid();
  final DigipayService _svc = DigipayService();
  final _amountCtl = TextEditingController();
  final _mobileCtl = TextEditingController();
  final _trackingCtl = TextEditingController();
  String _channel = 'upg';
  bool _busy = false;
  bool _cancelled = false;
  String? _waitHint;
  Map<String, dynamic>? _settings;

  @override
  void initState() {
    super.initState();
    _amountCtl.text = formatWithThousands(
      widget.remainingAmount,
      decimalPlaces: widget.decimalPlaces,
    );
    unawaited(_loadSettings());
  }

  @override
  void dispose() {
    _cancelled = true;
    _amountCtl.dispose();
    _mobileCtl.dispose();
    _trackingCtl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final data = await _svc.getSettings(businessId: widget.businessId);
      if (mounted) setState(() => _settings = data);
    } catch (_) {}
  }

  num get _amount => parseFormattedNumber(_amountCtl.text) ?? 0;

  InvoiceTransaction _toPayment(Map<String, dynamic> purchase) {
    final personId = purchase['person_id'] ?? _settings?['person_id'];
    final personName =
        purchase['person_name']?.toString() ??
        _settings?['person_name']?.toString() ??
        'DigiPay';
    final providerId = purchase['provider_id']?.toString() ?? '';
    return InvoiceTransaction(
      id: _uuid.v4(),
      type: TransactionType.person,
      personId: personId?.toString(),
      personName: personName,
      transactionDate: DateTime.now(),
      amount: _amount,
      description: 'DIGIPAY:$providerId',
      extraInfo: {
        'digipay_provider_id': providerId,
        'digipay_purchase_id': purchase['id'],
        'digipay_channel': _channel,
      },
    );
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context);
    if (_amount <= 0) return;
    setState(() {
      _busy = true;
      _waitHint = null;
    });
    try {
      if (_channel == 'manual') {
        final purchase = await _svc.recordManualPurchase(
          businessId: widget.businessId,
          amount: _amount,
          cellNumber: _mobileCtl.text.trim(),
          trackingCode: _trackingCtl.text.trim(),
          channel: 'qr',
        );
        if (!mounted) return;
        Navigator.pop(context, _toPayment(purchase));
        return;
      }
      if (_mobileCtl.text.trim().isEmpty) {
        setState(() {
          _busy = false;
          _waitHint = t.digipayMobileRequired;
        });
        return;
      }
      final ticket = await _svc.createTicket(
        businessId: widget.businessId,
        amount: _amount,
        cellNumber: _mobileCtl.text.trim(),
      );
      final purchaseId = (ticket['id'] as num?)?.toInt();
      final redirect = ticket['redirect_url']?.toString();
      if (redirect != null && redirect.isNotEmpty) {
        final uri = Uri.tryParse(redirect);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
      if (purchaseId == null) {
        throw StateError('missing purchase id');
      }
      setState(() => _waitHint = t.digipayWaitingForPayment);
      final deadline = DateTime.now().add(const Duration(minutes: 8));
      while (DateTime.now().isBefore(deadline) && mounted && !_cancelled) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted || _cancelled) return;
        final current = await _svc.getPurchase(
          businessId: widget.businessId,
          purchaseId: purchaseId,
        );
        final status = current['status']?.toString();
        if (status == 'verified' || status == 'delivered' || status == 'paid') {
          if (!mounted || _cancelled) return;
          Navigator.pop(context, _toPayment({...ticket, ...current}));
          return;
        }
        if (status == 'failed' || status == 'refunded') {
          throw StateError(t.digipayPaymentFailed);
        }
      }
      if (_cancelled || !mounted) return;
      throw StateError(t.digipayPaymentTimeout);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _waitHint = ErrorExtractor.userMessage(e, t);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.digipayPayButton),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'upg',
                    label: Text(t.digipayChannelUpg),
                    icon: const Icon(Icons.qr_code_2_outlined),
                  ),
                  ButtonSegment(
                    value: 'manual',
                    label: Text(t.digipayChannelManual),
                    icon: const Icon(Icons.point_of_sale_outlined),
                  ),
                ],
                selected: {_channel},
                onSelectionChanged: _busy
                    ? null
                    : (v) => setState(() => _channel = v.first),
              ),
              const SizedBox(height: 12),
              Text(
                t.digipayPaymentHelp,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amountCtl,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: t.digipayAmountLabel,
                  suffixText: widget.currencyUnit,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _mobileCtl,
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: t.digipayMobileLabel),
              ),
              if (_channel == 'manual') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _trackingCtl,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: t.digipayTrackingCodeLabel,
                  ),
                ),
              ],
              if (_waitHint != null) ...[
                const SizedBox(height: 12),
                Text(
                  _waitHint!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _cancelled = true;
            Navigator.pop(context);
          },
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(t.digipayConfirmPayment),
        ),
      ],
    );
  }
}
