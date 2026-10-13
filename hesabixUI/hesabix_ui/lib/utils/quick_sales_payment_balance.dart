import '../models/invoice_transaction.dart';

/// گرد کردن مبلغ پرداخت فروش سریع مطابق تعداد اعشار ارز فاکتور.
num roundQuickSalesMoney(num value, int decimalPlaces) {
  if (decimalPlaces <= 0) return value.round();
  var f = 1;
  for (var i = 0; i < decimalPlaces; i++) {
    f *= 10;
  }
  return (value * f).round() / f;
}

num quickSalesPaymentEpsilon(int decimalPlaces) {
  if (decimalPlaces <= 0) return 0.5;
  var e = 1.0;
  for (var i = 0; i < decimalPlaces; i++) {
    e /= 10;
  }
  return e / 2;
}

/// آیا می‌توان ردیف پرداخت جدیدی اضافه کرد.
///
/// ماندهٔ صفر مانع نیست تا صندوق‌دار بتواند چند دریافت هم‌نوع
/// (مثلاً دو بانک/کارت) بسازد. ردیف خالیِ قبلی باید اول پر شود.
bool canAddQuickSalesPaymentLine({
  required List<InvoiceTransaction> payments,
  required bool enabled,
  required num epsilon,
  int maxLines = 50,
}) {
  if (!enabled) return false;
  if (payments.length >= maxLines) return false;
  for (final p in payments) {
    if (p.amount <= epsilon) return false;
  }
  return true;
}

/// اعمال مبلغ روی یک ردیف پرداخت.
///
/// پرداخت‌ها مستقل از یکدیگر نگه داشته می‌شوند. جمع بیشتر از مبلغ
/// فاکتور مجاز است و در فروش سریع به صورت وجه برگشتی ثبت می‌شود.
List<InvoiceTransaction> applyQuickSalesPaymentAmount({
  required List<InvoiceTransaction> payments,
  required int index,
  required num amount,
  required num invoiceTotal,
  required int decimalPlaces,
}) {
  if (index < 0 || index >= payments.length) {
    return List<InvoiceTransaction>.from(payments);
  }

  final next = List<InvoiceTransaction>.from(payments);
  final safe = amount < 0 ? 0 : roundQuickSalesMoney(amount, decimalPlaces);
  next[index] = next[index].copyWith(amount: safe);
  return next;
}
