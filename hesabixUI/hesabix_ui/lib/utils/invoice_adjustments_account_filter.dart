import '../models/account_model.dart';

/// نگاشت مرکزی نوع فاکتور/نوع ردیف به فیلتر درخت حساب.
///
/// مبنا:
/// - گروه 6 در چارت حساب‌ها: درآمد
/// - گروه 7 در چارت حساب‌ها: هزینه
String adjustmentAccountDocumentType({
  required String? invoiceTypeValue,
  required String kind,
  Map<String, dynamic>? serverRules,
}) {
  final fromServer = _resolveFromServerRules(
    invoiceTypeValue: invoiceTypeValue,
    kind: kind,
    serverRules: serverRules,
  );
  if (fromServer != null) return fromServer;

  final type = (invoiceTypeValue ?? '').toLowerCase();
  final isDeduction = kind == 'deduction';

  // فروش و برگشت از خرید: «اضافه» درآمدی، «کسر» هزینه‌ای
  if (type == 'sales' || type == 'purchase_return') {
    return isDeduction ? 'expense' : 'income';
  }

  // خرید و برگشت از فروش: «اضافه» هزینه‌ای، «کسر» درآمدی
  if (type == 'purchase' || type == 'sales_return') {
    return isDeduction ? 'income' : 'expense';
  }

  // پیش‌فرض امن
  return isDeduction ? 'expense' : 'income';
}

Map<String, dynamic>? extractInvoiceAdjustmentAccountFilterRules(Map<String, dynamic>? businessRaw) {
  if (businessRaw == null) return null;
  final direct = businessRaw['invoice_adjustments_account_filters'];
  if (direct is Map) return Map<String, dynamic>.from(direct as Map);

  final extraInfo = businessRaw['extra_info'];
  if (extraInfo is Map) {
    final nested = extraInfo['invoice_adjustments_account_filters'];
    if (nested is Map) return Map<String, dynamic>.from(nested as Map);
  }
  return null;
}

String? _resolveFromServerRules({
  required String? invoiceTypeValue,
  required String kind,
  Map<String, dynamic>? serverRules,
}) {
  if (serverRules == null || serverRules.isEmpty) return null;
  final typeKey = (invoiceTypeValue ?? '').toLowerCase();
  final kindKey = kind == 'deduction' ? 'deduction' : 'addition';

  final rawByType = serverRules[typeKey];
  if (rawByType is! Map) return null;
  final byType = Map<String, dynamic>.from(rawByType as Map);
  final raw = byType[kindKey];
  if (raw is! String) return null;
  final normalized = raw.toLowerCase().trim();
  if (normalized == 'income' || normalized == 'expense') return normalized;
  return null;
}

/// اعتبارسنجی حساب بر اساس فیلتر درخت.
bool isAdjustmentAccountAllowedForDocumentType(Account? account, String documentType) {
  if (account == null) return false;
  final accountType = account.accountType.toLowerCase();
  final code = account.code;

  if (documentType == 'expense') {
    if (accountType.contains('expense') || accountType.contains('cost')) return true;
    return code.startsWith('7');
  }

  if (accountType.contains('income') || accountType.contains('revenue')) return true;
  return code.startsWith('6');
}
