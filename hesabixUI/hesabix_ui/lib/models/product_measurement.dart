import '../utils/number_normalizer.dart';

enum ProductMeasurementUnit {
  um('میکرومتر', '0.001'),
  mm('میلی‌متر', '1'),
  cm('سانتی‌متر', '10'),
  dm('دسی‌متر', '100'),
  m('متر', '1000'),
  km('کیلومتر', '1000000'),
  inch('اینچ', '25.4', code: 'in'),
  ft('فوت', '304.8'),
  yd('یارد', '914.4'),
  mi('مایل', '1609344'),
  ug('میکروگرم', '0.000001'),
  mg('میلی‌گرم', '0.001'),
  g('گرم', '1'),
  kg('کیلوگرم', '1000'),
  t('تن متریک', '1000000'),
  oz('اونس', '28.349523125'),
  lb('پوند', '453.59237');

  const ProductMeasurementUnit(this.label, this._factor, {String? code})
    : _code = code;

  static const dimensionUnits = [um, mm, cm, dm, m, km, inch, ft, yd, mi];
  static const weightUnits = [ug, mg, g, kg, t, oz, lb];

  static ProductMeasurementUnit dimensionFromCode(String code) =>
      dimensionUnits.firstWhere((unit) => unit.code == code);

  static ProductMeasurementUnit weightFromCode(String code) =>
      weightUnits.firstWhere((unit) => unit.code == code);

  final String label;
  final String _factor;
  final String? _code;

  String get code => _code ?? name;

  String display(String? baseValue) => format(baseValue).value;

  ({String value, bool approximate}) format(String? baseValue) {
    if (baseValue == null) return (value: '', approximate: false);
    final base = _readDecimal(baseValue);
    final factor = _readDecimal(_factor);
    final places = _storageScale + _factor.split('.').first.length;
    final numerator = base.coefficient * _powerOfTen(factor.scale + places);
    final divisor = factor.coefficient * _powerOfTen(base.scale);
    final remainder = numerator.remainder(divisor);
    final quotient = numerator ~/ divisor;
    final rounded = remainder * BigInt.two >= divisor
        ? quotient + BigInt.one
        : quotient;
    return (
      value: _decimalText(rounded, places),
      approximate: remainder != BigInt.zero,
    );
  }

  /// Re-entering the displayed value of an existing measurement keeps its exact base value.
  String? toBaseValue(String input, {String? original}) {
    final value = _normalizedInput(input);
    if (value.isEmpty) return null;
    if (!_decimalPattern.hasMatch(value)) {
      throw const FormatException('عدد صحیح یا اعشاری غیرمنفی وارد کنید.');
    }

    final entered = _readDecimal(value);
    if (original != null &&
        _decimalText(entered.coefficient, entered.scale) == display(original)) {
      return original;
    }

    final factor = _readDecimal(_factor);
    final base = _decimalText(
      entered.coefficient * factor.coefficient,
      entered.scale + factor.scale,
    );
    final parts = base.split('.');
    if (parts.first.length > 12) {
      throw const FormatException(
        'مقدار در واحد پایه باید کمتر از ۱٬۰۰۰٬۰۰۰٬۰۰۰٬۰۰۰ باشد.',
      );
    }
    if (parts.length == 2 && parts.last.length > _storageScale) {
      throw const FormatException(
        'مقدار در واحد پایه حداکثر می‌تواند ۱۵ رقم اعشار داشته باشد.',
      );
    }
    return base;
  }
}

enum ProductMeasurement {
  length('length_mm', 'طول'),
  width('width_mm', 'عرض'),
  height('height_mm', 'ارتفاع'),
  weight('weight_g', 'وزن');

  const ProductMeasurement(this.apiKey, this.label);

  final String apiKey;
  final String label;
}

final _decimalPattern = RegExp(r'^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$');
final _trailingZeros = RegExp(r'0+$');
const _storageScale = 15;

String _normalizedInput(String input) =>
    toEnglishDigits(input.trim()).replaceAll('٫', '.');

BigInt _powerOfTen(int exponent) => BigInt.from(10).pow(exponent);

({BigInt coefficient, int scale}) _readDecimal(String value) {
  final parts = value.split('.');
  return (
    coefficient: BigInt.parse(parts.join()),
    scale: parts.length == 2 ? parts.last.length : 0,
  );
}

String _decimalText(BigInt coefficient, int scale) {
  final digits = coefficient.toString().padLeft(scale + 1, '0');
  final split = digits.length - scale;
  final whole = digits.substring(0, split);
  final fraction = digits.substring(split).replaceFirst(_trailingZeros, '');
  return fraction.isEmpty ? whole : '$whole.$fraction';
}
