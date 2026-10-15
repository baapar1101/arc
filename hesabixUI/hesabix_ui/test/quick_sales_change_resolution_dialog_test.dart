import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/quick_sales_change_resolution.dart';
import 'package:hesabix_ui/widgets/quick_sales/quick_sales_change_resolution_dialog.dart';

void main() {
  Future<void> openDialog(
    WidgetTester tester, {
    required bool isAnonymousCustomer,
    required ValueChanged<QuickSalesChangeResolution?> onResult,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              final result = await showDialog<QuickSalesChangeResolution>(
                context: context,
                builder: (_) => QuickSalesChangeResolutionDialog(
                  businessId: 1,
                  currencyId: 1,
                  overpaymentAmount: 500000,
                  currencyUnit: 'ریال',
                  decimalPlaces: 0,
                  customerName: isAnonymousCustomer ? 'مشتری ناشناس' : 'زارع',
                  customerId: isAnonymousCustomer ? 1 : 2,
                  isAnonymousCustomer: isAnonymousCustomer,
                ),
              );
              onResult(result);
            },
            child: const Text('باز کردن'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('باز کردن'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'identified customer can explicitly continue with full customer credit',
    (tester) async {
      QuickSalesChangeResolution? result;
      await openDialog(
        tester,
        isAnonymousCustomer: false,
        onResult: (value) => result = value,
      );

      expect(find.text('ادامه بدون تعیین تکلیف'), findsOneWidget);
      await tester.tap(find.text('ادامه بدون تعیین تکلیف'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.returnedAmount, 0);
      expect(result!.creditAmount, 500000);
      expect(result!.allocations, isEmpty);
    },
  );

  testWidgets('anonymous customer cannot continue without resolution', (
    tester,
  ) async {
    await openDialog(tester, isAnonymousCustomer: true, onResult: (_) {});

    expect(find.text('ادامه بدون تعیین تکلیف'), findsNothing);
    expect(find.text('تأیید تعیین تکلیف'), findsOneWidget);
    await tester.tap(find.text('انصراف'));
    await tester.pumpAndSettle();
  });
}
