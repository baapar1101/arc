import 'dart:math' as math;

import '../models/business_models.dart';
import '../models/invoice_line_item.dart';
import 'invoice_money_format.dart';

/// نتیجهٔ محاسبهٔ جمع فاکتور با تخفیف کلی (هم‌راستا با بک‌اند)
class InvoiceGlobalDiscountTotals {
  final num sumSubtotal;
  final num sumLineDiscount;
  final num globalDiscountAmount;
  final num sumTax;
  final num sumTotal;

  const InvoiceGlobalDiscountTotals({
    required this.sumSubtotal,
    required this.sumLineDiscount,
    required this.globalDiscountAmount,
    required this.sumTax,
    required this.sumTotal,
  });
}


/// تنظیمات تخفیف کلی از [BusinessResponse] یا مقادیر پیش‌فرض
class InvoiceGlobalDiscountPolicy {
  final String percentBasis;
  final String taxMode;
  final double? maxPercent;
  final double? maxAmount;

  const InvoiceGlobalDiscountPolicy({
    this.percentBasis = 'subtotal_after_line_discount',
    this.taxMode = 'recalculate_tax_proportional',
    this.maxPercent,
    this.maxAmount,
  });

  factory InvoiceGlobalDiscountPolicy.fromBusiness(BusinessResponse? b) {
    if (b == null) return const InvoiceGlobalDiscountPolicy();
    return InvoiceGlobalDiscountPolicy(
      percentBasis: b.invoiceGlobalDiscountPercentBasis,
      taxMode: b.invoiceGlobalDiscountTaxMode,
      maxPercent: b.invoiceGlobalDiscountMaxPercent,
      maxAmount: b.invoiceGlobalDiscountMaxAmount,
    );
  }
}

/// فقط برای فاکتورهای فروش/خرید/برگشت با طرف حساب
bool invoiceTypeSupportsGlobalDiscount(String? invoiceTypeValue) {
  const allowed = {'sales', 'purchase', 'sales_return', 'purchase_return'};
  return invoiceTypeValue != null && allowed.contains(invoiceTypeValue);
}

InvoiceGlobalDiscountTotals computeInvoiceTotalsWithGlobalDiscount({
  required List<InvoiceLineItem> lines,
  required String globalType,
  required num globalValue,
  required InvoiceGlobalDiscountPolicy policy,
  int decimalPlaces = 2,
  bool roundMonetaryAmounts = true,
}) {
  num q(num v) => roundInvoiceMoney(
        v,
        decimalPlaces: decimalPlaces,
        roundMonetary: roundMonetaryAmounts,
      );

  num sumGross = 0;
  num sumLineDisc = 0;
  final taxables = <num>[];
  final rates = <num>[];
  num t0 = 0;

  for (final e in lines) {
    sumGross += e.subtotal;
    sumLineDisc += e.discountAmount;
    taxables.add(e.taxableAmount);
    rates.add(e.taxRate);
    t0 += e.taxAmount;
  }

  final n0 = taxables.fold<num>(0, (a, b) => a + b);

  num basis;
  switch (policy.percentBasis) {
    case 'gross_before_line_discount':
      basis = sumGross;
      break;
    case 'total_after_lines_including_tax':
      basis = n0 + t0;
      break;
    default:
      basis = n0;
  }

  if (basis <= 0 || globalValue <= 0) {
    return InvoiceGlobalDiscountTotals(
      sumSubtotal: sumGross,
      sumLineDiscount: sumLineDisc,
      globalDiscountAmount: 0,
      sumTax: t0,
      sumTotal: lines.fold<num>(0, (a, e) => a + e.total),
    );
  }

  num raw;
  if (globalType == 'percent') {
    var pct = globalValue.toDouble();
    final mp = policy.maxPercent;
    if (mp != null && mp > 0) {
      pct = math.min(pct, mp);
    }
    raw = q(basis * (pct / 100.0));
  } else {
    raw = q(globalValue);
  }

  var gDisc = math.min(raw, basis);
  final mp = policy.maxPercent;
  if (mp != null && mp > 0) {
    final capPct = q(basis * (mp / 100.0));
    gDisc = math.min(gDisc, capPct);
  }
  final ma = policy.maxAmount;
  if (ma != null && ma > 0) {
    gDisc = math.min(gDisc, ma);
  }

  if (gDisc <= 0) {
    return InvoiceGlobalDiscountTotals(
      sumSubtotal: sumGross,
      sumLineDiscount: sumLineDisc,
      globalDiscountAmount: 0,
      sumTax: t0,
      sumTotal: lines.fold<num>(0, (a, e) => a + e.total),
    );
  }

  final n1 = math.max(0, n0 - gDisc);

  if (policy.taxMode == 'keep_line_taxes') {
    final total = q(n1 + t0);
    return InvoiceGlobalDiscountTotals(
      sumSubtotal: sumGross,
      sumLineDiscount: sumLineDisc,
      globalDiscountAmount: gDisc,
      sumTax: t0,
      sumTotal: total,
    );
  }

  final factor = n0 > 0 ? n1 / n0 : 0.0;
  final newTaxables = taxables.map((tx) => q(tx * factor)).toList();
  var drift = n1 - newTaxables.fold<num>(0, (a, b) => a + b);
  if (newTaxables.isNotEmpty && drift != 0) {
    var idx = 0;
    num maxT = newTaxables[0];
    for (var i = 1; i < newTaxables.length; i++) {
      if (newTaxables[i] > maxT) {
        maxT = newTaxables[i];
        idx = i;
      }
    }
    newTaxables[idx] = q(newTaxables[idx] + drift);
  }

  num t1 = 0;
  for (var i = 0; i < newTaxables.length; i++) {
    final tr = rates[i];
    if (newTaxables[i] <= 0 || tr <= 0) continue;
    t1 += q(newTaxables[i] * (tr / 100.0));
  }

  final grand = q(n1 + t1);
  return InvoiceGlobalDiscountTotals(
    sumSubtotal: sumGross,
    sumLineDiscount: sumLineDisc,
    globalDiscountAmount: gDisc,
    sumTax: t1,
    sumTotal: grand,
  );
}
