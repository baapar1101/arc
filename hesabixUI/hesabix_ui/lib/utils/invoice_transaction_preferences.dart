import 'package:shared_preferences/shared_preferences.dart';

import '../models/invoice_transaction.dart';

/// آخرین «نوع/روش تراکنش» انتخاب‌شده در فاکتور، دریافت/پرداخت و … (به‌ازای هر کسب‌وکار).
class InvoiceTransactionPreferences {
  InvoiceTransactionPreferences._();

  static String _storageKey(int businessId) =>
      'invoice_tx_last_type_$businessId';

  /// انواع مجاز در دیالوگ تراکنش جزئیات سند (بدون خرج چک).
  static const List<TransactionType> receiptPaymentDialogTypes = [
    TransactionType.bank,
    TransactionType.cashRegister,
    TransactionType.pettyCash,
    TransactionType.check,
    TransactionType.person,
    TransactionType.account,
  ];

  /// اگر ذخیره‌شده داخل [allowed] نباشد یا نباشد: [TransactionType.bank] در صورت وجود در لیست، وگرنه اولین مورد.
  static Future<TransactionType> resolveInitialTransactionType(
    int businessId,
    List<TransactionType> allowed,
  ) async {
    if (allowed.isEmpty) return TransactionType.bank;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey(businessId));
    final parsed = raw != null ? TransactionType.fromValue(raw) : null;
    if (parsed != null && allowed.contains(parsed)) return parsed;

    if (allowed.contains(TransactionType.bank)) return TransactionType.bank;
    return allowed.first;
  }

  static Future<void> setLastUsedTransactionType(
    int businessId,
    TransactionType type,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey(businessId), type.value);
  }
}
