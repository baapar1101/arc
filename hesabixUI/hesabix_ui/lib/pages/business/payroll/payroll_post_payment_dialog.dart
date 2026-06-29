import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../models/account_model.dart';
import '../../../widgets/invoice/account_tree_combobox_widget.dart';

/// دیالوگ انتخاب حساب پرداخت برای ثبت سند پرداخت حقوق.
class PayrollPostPaymentDialog extends StatefulWidget {
  final int businessId;

  const PayrollPostPaymentDialog({super.key, required this.businessId});

  static Future<int?> show(BuildContext context, {required int businessId}) {
    return showDialog<int>(
      context: context,
      builder: (_) => PayrollPostPaymentDialog(businessId: businessId),
    );
  }

  @override
  State<PayrollPostPaymentDialog> createState() => _PayrollPostPaymentDialogState();
}

class _PayrollPostPaymentDialogState extends State<PayrollPostPaymentDialog> {
  Account? _paymentAccount;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.payrollPostPayment),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.payrollPostPaymentHint),
            const SizedBox(height: 12),
            AccountTreeComboboxWidget(
              businessId: widget.businessId,
              selectedAccount: _paymentAccount,
              label: t.payrollPaymentAccount,
              dense: true,
              onChanged: (a) => setState(() => _paymentAccount = a),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        FilledButton(
          onPressed: _paymentAccount == null ? null : () => Navigator.pop(context, _paymentAccount!.id),
          child: Text(t.payrollPostPayment),
        ),
      ],
    );
  }
}
