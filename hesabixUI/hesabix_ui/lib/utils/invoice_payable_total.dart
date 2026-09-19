import 'dart:math' as math;

/// مبلغ قابل پرداخت/دریافت فاکتور از `extra_info.totals`.
///
/// `net` جمع خالص ردیف‌ها (شامل مالیات خطی) است؛
/// `adjustments_net` و `adjustments_tax` اضافات/کسورات فاکتور را با علامت لحاظ می‌کنند.
double? invoicePayableTotalFromTotals(Map<String, dynamic>? totals) {
  if (totals == null) return null;

  num? asNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  final net = asNum(totals['net']);
  final adjNet = asNum(totals['adjustments_net']) ?? 0;
  final adjTax = asNum(totals['adjustments_tax']) ?? 0;

  if (net != null) {
    return _roundMoney(net + adjNet + adjTax);
  }

  final gross = asNum(totals['gross']);
  if (gross == null) return null;

  final discount = asNum(totals['discount']) ?? 0;
  final tax = asNum(totals['tax']) ?? 0;
  return _roundMoney(gross - discount + tax + adjNet + adjTax);
}

double? invoicePayableTotalFromExtraInfo(Map<String, dynamic>? extraInfo) {
  if (extraInfo == null) return null;
  final totals = extraInfo['totals'];
  if (totals is Map<String, dynamic>) {
    return invoicePayableTotalFromTotals(totals);
  }
  if (totals is Map) {
    return invoicePayableTotalFromTotals(Map<String, dynamic>.from(totals));
  }
  return null;
}

/// استخراج مبلغ کل فاکتور برای تخصیص دریافت/پرداخت.
double invoicePayableTotalFromInvoiceMap(Map<String, dynamic> invoice) {
  num? asNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  final fromExtra = invoicePayableTotalFromExtraInfo(
    invoice['extra_info'] is Map<String, dynamic>
        ? invoice['extra_info'] as Map<String, dynamic>
        : invoice['extra_info'] is Map
            ? Map<String, dynamic>.from(invoice['extra_info'] as Map)
            : null,
  );
  if (fromExtra != null) return fromExtra;

  final finalPayable = asNum(invoice['final_payable_total']);
  if (finalPayable != null) return finalPayable.toDouble();

  final totalAmount = asNum(invoice['total_amount']);
  if (totalAmount != null) return totalAmount.toDouble();

  final total = asNum(invoice['total']);
  if (total != null) return total.toDouble();

  return 0;
}

double _roundMoney(num value) {
  final factor = math.pow(10, 2).toDouble();
  return (value * factor).round() / factor;
}
