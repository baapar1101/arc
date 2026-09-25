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
  int maxLines = 6,
}) {
  if (!enabled) return false;
  if (payments.length >= maxLines) return false;
  for (final p in payments) {
    if (p.amount <= epsilon) return false;
  }
  return true;
}

/// اعمال مبلغ روی یک ردیف و حفظ تراز با فاکتور.
///
/// اگر جمع از مبلغ فاکتور بیشتر شود، از ردیف‌های دیگر (از آخر)
/// کم می‌شود تا دفاتر از حد فاکتور رد نشوند. ردیف‌های دیگر که صفر
/// شدند حذف می‌شوند. ردیف در حال ویرایش حتی با مبلغ صفر می‌ماند.
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

  final epsilon = quickSalesPaymentEpsilon(decimalPlaces);
  final next = List<InvoiceTransaction>.from(payments);
  final safe = amount < 0 ? 0 : roundQuickSalesMoney(amount, decimalPlaces);
  next[index] = next[index].copyWith(amount: safe);

  var paid = next.fold<num>(0, (sum, p) => sum + p.amount);
  if (paid > invoiceTotal + epsilon) {
    var excess = roundQuickSalesMoney(paid - invoiceTotal, decimalPlaces);
    for (var i = next.length - 1; i >= 0; i--) {
      if (i == index) continue;
      if (excess <= epsilon) break;
      final reducible = next[i].amount;
      if (reducible <= epsilon) continue;
      final take = reducible < excess ? reducible : excess;
      next[i] = next[i].copyWith(
        amount: roundQuickSalesMoney(next[i].amount - take, decimalPlaces),
      );
      excess = roundQuickSalesMoney(excess - take, decimalPlaces);
    }
    if (excess > epsilon) {
      final capped = roundQuickSalesMoney(
        next[index].amount - excess,
        decimalPlaces,
      );
      next[index] = next[index].copyWith(amount: capped < 0 ? 0 : capped);
    }
  }

  final editedId = next[index].id;
  next.removeWhere((p) => p.id != editedId && p.amount <= epsilon);
  return next;
}
