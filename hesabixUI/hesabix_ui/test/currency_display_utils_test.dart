import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/utils/currency_display_utils.dart';

void main() {
  test('personBalanceStatusLabel maps بالانس to تسویه', () {
    expect(personBalanceStatusLabel('بالانس'), 'تسویه');
    expect(personBalanceStatusLabel('بدهکار'), 'بدهکار');
    expect(personBalanceStatusLabel('بستانکار'), 'بستانکار');
  });

  test('formatPersonNetBalanceDisplay uses absolute amount with status', () {
    expect(
      formatPersonNetBalanceDisplay(balance: -10000000, status: 'بدهکار', unit: 'ریال'),
      '10,000,000 ریال — بدهکار',
    );
    expect(
      formatPersonNetBalanceDisplay(balance: 5000000, status: 'بستانکار', unit: 'ریال'),
      '5,000,000 ریال — بستانکار',
    );
  });

  test('formatPersonCurrencyBalanceLine hides minus sign for debtor FX balance', () {
    final line = formatPersonCurrencyBalanceLine(
      balance: -100,
      currencyUnit: r'$',
      status: 'بدهکار',
      baseEquivalent: -160000000,
      baseUnit: 'ریال',
      isBaseCurrency: false,
      balanceDecimalPlaces: 2,
      baseDecimalPlaces: 0,
    );
    expect(line.contains('-'), isFalse);
    expect(line, contains('بدهکار'));
    expect(line, contains('100'));
    expect(line, contains('160,000,000'));
  });

  test('formatPersonRunningBalanceDisplay labels negative as بدهکار', () {
    expect(
      formatPersonRunningBalanceDisplay(runningBalance: -2500, unit: 'ریال'),
      '2,500 ریال — بدهکار',
    );
    expect(
      formatPersonRunningBalanceDisplay(runningBalance: 0),
      '0 — تسویه',
    );
  });
}
