import 'package:hesabix_ui/utils/number_formatters.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';

/// برچسب کوتاه برای tooltip و suffix مبلغ از نقشهٔ ارز کسب‌کار (API): نماد، یا کد، یا عنوان.
String currencyUnitLabelFromBusinessCurrencyMap(
  Map<String, dynamic> currency, {
  String fallback = 'ریال',
}) {
  for (final key in ['symbol', 'code', 'title']) {
    final v = currency[key]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return fallback;
}

/// اگر ارز با [currencyId] در [cache] پیدا شود برچسب را برمی‌گرداند؛ وگرنه `null`.
String? currencyUnitLabelForBusinessCurrencyIdOrNull(
  int? currencyId,
  List<dynamic>? cache,
) {
  if (currencyId == null || cache == null || cache.isEmpty) return null;
  for (final raw in cache) {
    if (raw is! Map) continue;
    final c = Map<String, dynamic>.from(raw);
    if ((c['id'] as num?)?.toInt() == currencyId) {
      final label = currencyUnitLabelFromBusinessCurrencyMap(c, fallback: '');
      return label.isEmpty ? null : label;
    }
  }
  return null;
}

/// مبلغ + واحد: `1,000 $` یا `۱۶۰,۰۰۰,۰۰۰ ریال`
String formatAmountWithCurrencyUnit(
  dynamic amount, {
  required String unit,
  int decimalPlaces = 0,
}) {
  final n = formatWithThousands(amount, decimalPlaces: decimalPlaces);
  final u = unit.trim();
  if (u.isEmpty || n == '-') return n;
  return '$n $u';
}

/// قالب یکسان نمایش دوگانه:
/// `۱۶۰,۰۰۰,۰۰۰ ریال (100 $)`
///
/// اگر مبلغ اصلی خالی/صفر و بدون واحد باشد، فقط پایه برگردانده می‌شود.
String formatDualCurrencyAmount({
  required dynamic baseAmount,
  required String baseUnit,
  dynamic originalAmount,
  String? originalUnit,
  int baseDecimalPlaces = 0,
  int originalDecimalPlaces = 2,
  bool showOriginalEvenIfZero = false,
}) {
  final base = formatAmountWithCurrencyUnit(
    baseAmount,
    unit: baseUnit,
    decimalPlaces: baseDecimalPlaces,
  );

  final origUnit = (originalUnit ?? '').trim();
  if (origUnit.isEmpty) return base;

  num? origNum;
  if (originalAmount is num) {
    origNum = originalAmount;
  } else if (originalAmount != null) {
    origNum = num.tryParse(originalAmount.toString().replaceAll(',', ''));
  }
  if (origNum == null) return base;
  if (!showOriginalEvenIfZero && origNum == 0) return base;

  final orig = formatAmountWithCurrencyUnit(
    origNum,
    unit: origUnit,
    decimalPlaces: originalDecimalPlaces,
  );
  return '$base ($orig)';
}

/// قالب پرداخت بین‌ارزی مطابق درخواست کاربر:
/// `100$ (۱۶۰,۰۰۰,۰۰۰ ریال با نرخ ۱,۶۰۰,۰۰۰)`
String formatCrossCurrencyPaymentDisplay({
  required dynamic settlesAmount,
  required String invoiceCurrencyUnit,
  required dynamic paymentAmount,
  required String paymentCurrencyUnit,
  dynamic fxRate,
  int settlesDecimalPlaces = 2,
  int paymentDecimalPlaces = 0,
  String? rateDisplayUnit,
  String? baseCurrencyCode,
}) {
  final settles = formatAmountWithCurrencyUnit(
    settlesAmount,
    unit: invoiceCurrencyUnit,
    decimalPlaces: settlesDecimalPlaces,
  );

  final paid = formatAmountWithCurrencyUnit(
    paymentAmount,
    unit: paymentCurrencyUnit,
    decimalPlaces: paymentDecimalPlaces,
  );

  if (fxRate == null) {
    return '$settles ($paid)';
  }

  final rateStr = formatFxRateForDisplay(
    fxRate,
    rateDisplayUnit: rateDisplayUnit,
    baseCurrencyCode: baseCurrencyCode,
  );
  return '$settles ($paid با نرخ $rateStr)';
}

/// برچسب وضعیت بدهکار/بستانکار/تسویه برای مانده.
String personBalanceStatusLabel(String? status) {
  final s = (status ?? '').trim();
  if (s.isEmpty) return '';
  // API ممکن است فارسی یا انگلیسی بدهد
  switch (s.toLowerCase()) {
    case 'debtor':
    case 'بدهکار':
      return 'بدهکار';
    case 'creditor':
    case 'بستانکار':
      return 'بستانکار';
    case 'settled':
    case 'balanced':
    case 'صفر':
    case 'تسویه':
    case 'بالانس':
      return 'تسویه';
    case 'no_transaction':
    case 'بدون تراکنش':
      return 'بدون تراکنش';
    default:
      return s;
  }
}

num? tryParseAmount(dynamic value) {
  if (value == null) return null;
  if (value is num) return value;
  return num.tryParse(value.toString().replaceAll(',', ''));
}

num absAmount(dynamic value) => (tryParseAmount(value) ?? 0).abs();

String personBalanceStatusFromSignedAmount(dynamic balance) {
  final n = tryParseAmount(balance) ?? 0;
  if (n > 0) return 'بستانکار';
  if (n < 0) return 'بدهکار';
  return 'تسویه';
}

/// مانده شخص برای هدر/کارت: قدر مطلق + واحد + وضعیت.
/// نمونه: `۱۲,۰۰۰,۰۰۰ ریال — بدهکار`
String formatPersonNetBalanceDisplay({
  required dynamic balance,
  String? status,
  String unit = '',
  int decimalPlaces = 0,
}) {
  final st = personBalanceStatusLabel(status);
  if (st == 'بدون تراکنش') return st;
  final amount = formatAmountWithCurrencyUnit(
    absAmount(balance),
    unit: unit,
    decimalPlaces: decimalPlaces,
  );
  final label = st.isNotEmpty ? st : personBalanceStatusFromSignedAmount(balance);
  if (label.isEmpty || label == 'بدون تراکنش') return amount;
  return '$amount — $label';
}

/// تراز متحرک کارت حساب: قدر مطلق + بدهکار/بستانکار/تسویه.
String formatPersonRunningBalanceDisplay({
  required dynamic runningBalance,
  String unit = '',
  int decimalPlaces = 0,
}) {
  return formatPersonNetBalanceDisplay(
    balance: runningBalance,
    status: personBalanceStatusFromSignedAmount(runningBalance),
    unit: unit,
    decimalPlaces: decimalPlaces,
  );
}

/// مبلغ ستون گزارش وقتی «همه ارزها» انتخاب شده:
/// پایه همیشه؛ اگر سند ارزی بود اصل مبلغ در پرانتز.
String formatReportLedgerAmount({
  required dynamic amount,
  required bool amountsInBase,
  dynamic nativeAmount,
  String? documentCurrencyUnit,
  String baseUnit = 'ریال',
  int baseDecimalPlaces = 0,
  int nativeDecimalPlaces = 2,
}) {
  if (!amountsInBase) {
    return formatAmountWithCurrencyUnit(
      amount,
      unit: documentCurrencyUnit ?? '',
      decimalPlaces: nativeDecimalPlaces,
    );
  }

  final unit = (documentCurrencyUnit ?? '').trim();
  num? nativeNum;
  if (nativeAmount is num) {
    nativeNum = nativeAmount;
  } else if (nativeAmount != null) {
    nativeNum = num.tryParse(nativeAmount.toString().replaceAll(',', ''));
  }

  // اگر واحد سند همان پایه است یا مبلغ اصلی با پایه یکی است، فقط پایه
  if (unit.isEmpty || nativeNum == null) {
    return formatAmountWithCurrencyUnit(
      amount,
      unit: baseUnit,
      decimalPlaces: baseDecimalPlaces,
    );
  }

  num? baseNum;
  if (amount is num) {
    baseNum = amount;
  } else if (amount != null) {
    baseNum = num.tryParse(amount.toString().replaceAll(',', ''));
  }
  if (baseNum != null && (baseNum - nativeNum).abs() < 0.0000001) {
    return formatAmountWithCurrencyUnit(
      amount,
      unit: baseUnit,
      decimalPlaces: baseDecimalPlaces,
    );
  }

  return formatDualCurrencyAmount(
    baseAmount: amount,
    baseUnit: baseUnit,
    originalAmount: nativeNum,
    originalUnit: unit,
    baseDecimalPlaces: baseDecimalPlaces,
    originalDecimalPlaces: nativeDecimalPlaces,
    showOriginalEvenIfZero: false,
  );
}

/// مانده به تفکیک ارز با معادل پایه:
/// `۱۶۰,۰۰۰,۰۰۰ ریال (100 $) — بدهکار`
String formatPersonCurrencyBalanceLine({
  required dynamic balance,
  required String currencyUnit,
  required String status,
  dynamic baseEquivalent,
  String? baseUnit,
  bool isBaseCurrency = false,
  int balanceDecimalPlaces = 2,
  int baseDecimalPlaces = 0,
}) {
  final st = personBalanceStatusLabel(status);
  final nativeAbs = absAmount(balance);
  final native = formatAmountWithCurrencyUnit(
    nativeAbs,
    unit: currencyUnit,
    decimalPlaces: balanceDecimalPlaces,
  );

  if (isBaseCurrency || baseEquivalent == null || (baseUnit ?? '').trim().isEmpty) {
    return st.isEmpty ? native : '$native — $st';
  }

  final dual = formatDualCurrencyAmount(
    baseAmount: absAmount(baseEquivalent),
    baseUnit: baseUnit!,
    originalAmount: nativeAbs,
    originalUnit: currencyUnit,
    baseDecimalPlaces: baseDecimalPlaces,
    originalDecimalPlaces: balanceDecimalPlaces,
    showOriginalEvenIfZero: true,
  );
  return st.isEmpty ? dual : '$dual — $st';
}
