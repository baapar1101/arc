import 'dart:math' as math;

/// محدود کردن تعداد اعشار ارز (هم‌تراز با بک‌اند: ۰…۸).
int clampInvoiceDecimalPlaces(int? v) {
  final n = v ?? 2;
  if (n < 0) return 0;
  if (n > 8) return 8;
  return n;
}

/// گرد کردن مبلغ مطابق تنظیمات ارز (هم‌خوان با سرویس تخفیف کلی در Python).
/// اگر [roundMonetary] false باشد، فقط به ۸ رقم اعشار گرد می‌شود (دقت موقت).
num roundInvoiceMoney(num v, {required int decimalPlaces, required bool roundMonetary}) {
  if (v.isNaN || v.isInfinite) return 0;
  if (!roundMonetary) {
    const p = 100000000;
    return (v * p).round() / p;
  }
  final dp = clampInvoiceDecimalPlaces(decimalPlaces);
  if (dp <= 0) return v.round();
  final p = math.pow(10, dp);
  return (v * p).round() / p;
}
