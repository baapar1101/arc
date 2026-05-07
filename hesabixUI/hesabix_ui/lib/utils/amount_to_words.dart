import 'package:hesabix_ui/utils/number_normalizer.dart';

const _scalesFa = <String>[
  '',
  'هزار',
  'میلیون',
  'میلیارد',
  'بیلیون',
  'بیلیارد',
  'تریلیون',
  'کواژیلیون',
  'کوانتیلیون',
];

const _scalesEn = <String>[
  '',
  'thousand',
  'million',
  'billion',
  'trillion',
  'quadrillion',
  'quintillion',
  'sextillion',
  'septillion',
];

const _onesFa = <String>[
  '',
  'یک',
  'دو',
  'سه',
  'چهار',
  'پنج',
  'شش',
  'هفت',
  'هشت',
  'نه',
];

const _teensFa = <String>[
  'ده',
  'یازده',
  'دوازده',
  'سیزده',
  'چهارده',
  'پانزده',
  'شانزده',
  'هفده',
  'هجده',
  'نوزده',
];

const _tensFa = <String>[
  '',
  '',
  'بیست',
  'سی',
  'چهل',
  'پنجاه',
  'شصت',
  'هفتاد',
  'هشتاد',
  'نود',
];

const _hundredsFa = <String>[
  '',
  'یکصد',
  'دویست',
  'سیصد',
  'چهارصد',
  'پانصد',
  'ششصد',
  'هفتصد',
  'هشتصد',
  'نهصد',
];

const _onesEn = <String>[
  '',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'eleven',
  'twelve',
  'thirteen',
  'fourteen',
  'fifteen',
  'sixteen',
  'seventeen',
  'eighteen',
  'nineteen',
];

const _tensEn = <String>[
  '',
  '',
  'twenty',
  'thirty',
  'forty',
  'fifty',
  'sixty',
  'seventy',
  'eighty',
  'ninety',
];

String _persianUnder100(int n) {
  assert(n >= 0 && n < 100);
  if (n < 10) return _onesFa[n];
  if (n < 20) return _teensFa[n - 10];
  final t = n ~/ 10;
  final u = n % 10;
  if (u == 0) return _tensFa[t];
  return '${_tensFa[t]} و ${_onesFa[u]}';
}

String _persianUnder1000(int n) {
  assert(n >= 0 && n < 1000);
  if (n == 0) return '';
  final h = n ~/ 100;
  final rem = n % 100;
  final parts = <String>[];
  if (h > 0) {
    parts.add(_hundredsFa[h]);
  }
  if (rem == 0) {
    return parts.join(' و ');
  }
  parts.add(_persianUnder100(rem));
  return parts.join(' و ');
}

String _englishUnder100(int n) {
  assert(n >= 0 && n < 100);
  if (n < 10) return _onesEn[n];
  if (n < 20) return _onesEn[n];
  final t = n ~/ 10;
  final u = n % 10;
  if (u == 0) return _tensEn[t];
  return '${_tensEn[t]}-${_onesEn[u]}';
}

String _englishUnder1000(int n) {
  assert(n >= 0 && n < 1000);
  if (n == 0) return '';
  final h = n ~/ 100;
  final rem = n % 100;
  final parts = <String>[];
  if (h > 0) {
    parts.add('${_onesEn[h]} hundred');
  }
  if (rem == 0) {
    return parts.join(' ');
  }
  if (h > 0) {
    parts.add(_englishUnder100(rem));
  } else {
    parts.add(_englishUnder100(rem));
  }
  return parts.join(' ');
}

String _integerToPersianWords(BigInt n) {
  if (n == BigInt.zero) return 'صفر';
  if (n < BigInt.zero) {
    return 'منفی ${_integerToPersianWords(-n)}';
  }
  final groups = <int>[];
  var x = n;
  while (x > BigInt.zero) {
    groups.add((x % BigInt.from(1000)).toInt());
    x ~/= BigInt.from(1000);
  }
  final parts = <String>[];
  for (var i = groups.length - 1; i >= 0; i--) {
    final t = groups[i];
    if (t == 0) continue;
    final w = _persianUnder1000(t);
    final scale = i < _scalesFa.length ? _scalesFa[i] : '';
    if (scale.isEmpty) {
      parts.add(w);
    } else {
      parts.add('$w $scale');
    }
  }
  return parts.join(' و ');
}

String _integerToEnglishWords(BigInt n) {
  if (n == BigInt.zero) return 'zero';
  if (n < BigInt.zero) {
    return 'negative ${_integerToEnglishWords(-n)}';
  }
  final groups = <int>[];
  var x = n;
  while (x > BigInt.zero) {
    groups.add((x % BigInt.from(1000)).toInt());
    x ~/= BigInt.from(1000);
  }
  final parts = <String>[];
  for (var i = groups.length - 1; i >= 0; i--) {
    final t = groups[i];
    if (t == 0) continue;
    final w = _englishUnder1000(t);
    final scale = i < _scalesEn.length ? _scalesEn[i] : '';
    if (scale.isEmpty) {
      parts.add(w);
    } else {
      parts.add('$w $scale');
    }
  }
  return parts.join(', ');
}

/// تجزیهٔ رشتهٔ ورودی فیلد مبلغ (با کاما و ارقام فارسی) به بخش صحیح و صدم‌ها (۰–۹۹).
({BigInt integer, int cents})? _parseAmountParts(String raw) {
  var s = toEnglishDigits(raw).replaceAll(',', '').trim();
  if (s.isEmpty) return null;

  var negative = false;
  if (s.startsWith('-')) {
    negative = true;
    s = s.substring(1).trim();
  }
  if (s.isEmpty) return null;

  final dot = s.indexOf('.');
  var intStr = dot == -1 ? s : s.substring(0, dot);
  var fracStr = dot == -1 ? '' : s.substring(dot + 1);

  intStr = intStr.replaceAll(RegExp(r'^0+(?=\d)'), '');
  if (intStr.isEmpty && (dot == -1 || fracStr.isEmpty)) {
    intStr = '0';
  }
  if (intStr.isEmpty && fracStr.isNotEmpty) {
    intStr = '0';
  }

  fracStr = fracStr.replaceAll(RegExp(r'[^\d]'), '');
  var cents = 0;
  if (fracStr.isNotEmpty) {
    if (fracStr.length == 1) {
      cents = (int.tryParse(fracStr) ?? 0) * 10;
    } else {
      cents = int.tryParse(fracStr.substring(0, 2)) ?? 0;
    }
  }

  final bi = BigInt.tryParse(intStr);
  if (bi == null) return null;

  return (integer: negative ? -bi : bi, cents: cents);
}

/// تبدیل متن فیلد مبلغ به جملهٔ قابل نمایش در tooltip؛ در صورت نامعتبر بودن ورودی `null`.
String? amountFormattedInputToWords(
  String input, {
  required bool usePersian,
  required String currencyUnit,
}) {
  final parsed = _parseAmountParts(input);
  if (parsed == null) return null;

  final trimmedUnit = currencyUnit.trim();
  final unitSuffix = trimmedUnit.isEmpty ? '' : ' $trimmedUnit';

  var absInt = parsed.integer.abs();
  final signNegative = parsed.integer < BigInt.zero;

  String core;
  if (usePersian) {
    core = _integerToPersianWords(absInt);
    if (parsed.cents > 0) {
      final frac = _persianUnder100(parsed.cents);
      core = '$core و $frac صدم';
    }
  } else {
    core = _integerToEnglishWords(absInt);
    if (parsed.cents > 0) {
      final frac = _englishUnder100(parsed.cents);
      core = '$core and $frac hundredths';
    }
  }

  if (signNegative) {
    core = usePersian ? 'منفی $core' : 'negative $core';
  }

  if (unitSuffix.isEmpty) return core;
  return '$core$unitSuffix';
}
