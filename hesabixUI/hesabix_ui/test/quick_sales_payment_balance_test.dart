import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/invoice_transaction.dart';
import 'package:hesabix_ui/utils/quick_sales_payment_balance.dart';

InvoiceTransaction _tx({
  required String id,
  required TransactionType type,
  required num amount,
  String? bankId,
  String? cashRegisterId,
}) {
  return InvoiceTransaction(
    id: id,
    type: type,
    bankId: bankId,
    cashRegisterId: cashRegisterId,
    transactionDate: DateTime.utc(2026, 9, 6),
    amount: amount,
  );
}

void main() {
  group('canAddQuickSalesPaymentLine', () {
    test('allows a second bank when remaining is already settled', () {
      final payments = [
        _tx(
          id: 'b1',
          type: TransactionType.bank,
          amount: 800000,
          bankId: '10',
        ),
      ];
      expect(
        canAddQuickSalesPaymentLine(
          payments: payments,
          enabled: true,
          epsilon: 0.5,
        ),
        isTrue,
      );
    });

    test('blocks stacking another empty line', () {
      final payments = [
        _tx(id: 'b1', type: TransactionType.bank, amount: 500000, bankId: '10'),
        _tx(id: 'b2', type: TransactionType.bank, amount: 0, bankId: '10'),
      ];
      expect(
        canAddQuickSalesPaymentLine(
          payments: payments,
          enabled: true,
          epsilon: 0.5,
        ),
        isFalse,
      );
    });
  });

  group('applyQuickSalesPaymentAmount', () {
    test('splits a full bank receipt into two same-type receipts', () {
      final payments = [
        _tx(id: 'b1', type: TransactionType.bank, amount: 800000, bankId: '10'),
        _tx(id: 'b2', type: TransactionType.bank, amount: 0, bankId: '11'),
      ];

      final next = applyQuickSalesPaymentAmount(
        payments: payments,
        index: 1,
        amount: 300000,
        invoiceTotal: 800000,
        decimalPlaces: 0,
      );

      expect(next, hasLength(2));
      expect(next[0].id, 'b1');
      expect(next[0].type, TransactionType.bank);
      expect(next[0].amount, 500000);
      expect(next[1].id, 'b2');
      expect(next[1].type, TransactionType.bank);
      expect(next[1].amount, 300000);
      expect(
        next.fold<num>(0, (sum, p) => sum + p.amount),
        800000,
      );
    });

    test('reduces cash when a bank line is typed against a settled sale', () {
      final payments = [
        _tx(
          id: 'c1',
          type: TransactionType.cashRegister,
          amount: 800000,
          cashRegisterId: '3',
        ),
        _tx(id: 'b1', type: TransactionType.bank, amount: 0, bankId: '10'),
      ];

      final next = applyQuickSalesPaymentAmount(
        payments: payments,
        index: 1,
        amount: 300000,
        invoiceTotal: 800000,
        decimalPlaces: 0,
      );

      expect(next[0].type, TransactionType.cashRegister);
      expect(next[0].amount, 500000);
      expect(next[1].type, TransactionType.bank);
      expect(next[1].amount, 300000);
    });

    test('drops other lines that fall to zero so bank can replace cash', () {
      final payments = [
        _tx(
          id: 'c1',
          type: TransactionType.cashRegister,
          amount: 800000,
          cashRegisterId: '3',
        ),
        _tx(id: 'b1', type: TransactionType.bank, amount: 0, bankId: '10'),
      ];

      final next = applyQuickSalesPaymentAmount(
        payments: payments,
        index: 1,
        amount: 800000,
        invoiceTotal: 800000,
        decimalPlaces: 0,
      );

      expect(next, hasLength(1));
      expect(next.single.id, 'b1');
      expect(next.single.amount, 800000);
    });

    test('caps a single line so payments cannot exceed the invoice', () {
      final payments = [
        _tx(
          id: 'c1',
          type: TransactionType.cashRegister,
          amount: 800000,
          cashRegisterId: '3',
        ),
      ];

      final next = applyQuickSalesPaymentAmount(
        payments: payments,
        index: 0,
        amount: 900000,
        invoiceTotal: 800000,
        decimalPlaces: 0,
      );

      expect(next.single.amount, 800000);
    });
  });
}
