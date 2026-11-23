import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/product_measurement.dart';

void main() {
  test('each display unit converts both ways without rounding', () {
    const cases = [
      (ProductMeasurementUnit.um, '0.1255', '125.5'),
      (ProductMeasurementUnit.mm, '125.5', '125.5'),
      (ProductMeasurementUnit.cm, '125.5', '12.55'),
      (ProductMeasurementUnit.dm, '125.5', '1.255'),
      (ProductMeasurementUnit.m, '125.5', '0.1255'),
      (ProductMeasurementUnit.km, '125.5', '0.0001255'),
      (ProductMeasurementUnit.inch, '31.3580018', '1.234567'),
      (ProductMeasurementUnit.ft, '457.2', '1.5'),
      (ProductMeasurementUnit.yd, '1371.6', '1.5'),
      (ProductMeasurementUnit.mi, '402336', '0.25'),
      (ProductMeasurementUnit.ug, '0.0012505', '1250.5'),
      (ProductMeasurementUnit.mg, '1.2505', '1250.5'),
      (ProductMeasurementUnit.g, '1250.5', '1250.5'),
      (ProductMeasurementUnit.kg, '1250.5', '1.2505'),
      (ProductMeasurementUnit.t, '1250.5', '0.0012505'),
      (ProductMeasurementUnit.oz, '34.999385715861875', '1.234567'),
      (ProductMeasurementUnit.lb, '559.99017145379', '1.234567'),
    ];
    for (final (unit, base, entered) in cases) {
      expect(unit.format(base), (value: entered, approximate: false));
      expect(unit.toBaseValue(entered), base);
    }
  });

  test('the storage limits follow the unit and significant decimal places', () {
    for (final unit in ProductMeasurementUnit.values) {
      for (final base in [
        '0.000000000000001',
        '999999999999.999999999999999',
      ]) {
        final display = unit.format(base);
        expect(display.value, isNot('0'));
        expect(unit.toBaseValue(display.value, original: base), base);
        if (!display.approximate) expect(unit.toBaseValue(display.value), base);
      }
    }
    expect(ProductMeasurementUnit.t.toBaseValue('.000000000001'), '0.000001');
    expect(ProductMeasurementUnit.mm.toBaseValue(' ۱۲۵٫۵۰۰۰۰۰۰۰ '), '125.5');
    expect(ProductMeasurementUnit.g.toBaseValue(''), isNull);
    expect(ProductMeasurementUnit.g.toBaseValue('0'), '0');
    for (final input in [
      '-1',
      '-0',
      '1.2.3',
      'NaN',
      '1e2',
      'abc',
      '1,500',
      '1000000000000',
      '0.0000000000000001',
    ]) {
      expect(
        () => ProductMeasurementUnit.g.toBaseValue(input),
        throwsFormatException,
      );
    }
  });

  test(
    'a recurring imperial display preserves the original until the input changes',
    () {
      const unit = ProductMeasurementUnit.inch;
      const base = '125.500000000000000';
      final approximate = unit.format(base);
      expect(approximate.approximate, isTrue);
      expect(unit.toBaseValue(approximate.value, original: base), base);
      expect(unit.toBaseValue('${approximate.value}0', original: base), base);
      expect(unit.toBaseValue('5', original: base), '127');
      expect(unit.toBaseValue('', original: base), isNull);
      expect(ProductMeasurementUnit.dimensionFromCode('in'), unit);
      expect(
        () => ProductMeasurementUnit.oz.toBaseValue('1.2345671'),
        throwsFormatException,
      );
      expect(
        ProductMeasurementUnit.oz.toBaseValue('1.2345678'),
        '34.999408395480375',
      );
    },
  );
}
