import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/utils/quick_sales_customer_balance.dart';

void main() {
  group('quickSalesPaymentTarget', () {
    test('keeps invoice total when balance is not applied', () {
      expect(
        quickSalesPaymentTarget(
          invoiceTotal: 5000000,
          customerBalance: -2000000,
          applyBalance: false,
        ),
        5000000,
      );
    });

    test('adds prior debt to the amount to collect', () {
      expect(
        quickSalesPaymentTarget(
          invoiceTotal: 5000000,
          customerBalance: -2000000,
          applyBalance: true,
        ),
        7000000,
      );
    });

    test('uses prior credit against the invoice', () {
      expect(
        quickSalesPaymentTarget(
          invoiceTotal: 5000000,
          customerBalance: 2000000,
          applyBalance: true,
        ),
        3000000,
      );
    });

    test('never produces a negative payment target', () {
      expect(
        quickSalesPaymentTarget(
          invoiceTotal: 5000000,
          customerBalance: 7000000,
          applyBalance: true,
        ),
        0,
      );
    });
  });
}
