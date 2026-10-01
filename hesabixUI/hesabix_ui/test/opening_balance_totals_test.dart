import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/utils/opening_balance_totals.dart';

void main() {
  test('keeps raw difference when auto balance is disabled', () {
    final totals = applyOpeningBalanceAutoBalance(
      debit: 100,
      credit: 0,
      autoBalanceEnabled: false,
      hasEquityAccount: true,
    );

    expect(totals.debit, 100);
    expect(totals.credit, 0);
    expect(totals.difference, 100);
  });

  test('keeps raw difference when equity account is missing', () {
    final totals = applyOpeningBalanceAutoBalance(
      debit: 100,
      credit: 0,
      autoBalanceEnabled: true,
      hasEquityAccount: false,
    );

    expect(totals.debit, 100);
    expect(totals.credit, 0);
    expect(totals.difference, 100);
  });

  test('adds debit-heavy difference to displayed credit', () {
    final totals = applyOpeningBalanceAutoBalance(
      debit: 8528542630.50,
      credit: 0,
      autoBalanceEnabled: true,
      hasEquityAccount: true,
    );

    expect(totals.debit, 8528542630.50);
    expect(totals.credit, 8528542630.50);
    expect(totals.difference, 0);
  });

  test('adds credit-heavy difference to displayed debit', () {
    final totals = applyOpeningBalanceAutoBalance(
      debit: 20,
      credit: 80,
      autoBalanceEnabled: true,
      hasEquityAccount: true,
    );

    expect(totals.debit, 80);
    expect(totals.credit, 80);
    expect(totals.difference, 0);
  });
}
