import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/widgets/quick_sales/quick_sales_stock_shortage_dialog.dart';

void main() {
  for (final unique in [false, true]) {
    testWidgets('phone shortage dialog scrolls many lines; unique=$unique', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var parked = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => QuickSalesStockShortageDialog(
                    shortages: [
                      for (var i = 0; i < 30; i++)
                        {
                          'product_name': 'کالای $i',
                          'inventory_mode': unique ? 'unique' : 'bulk',
                          'warehouse_name': 'انبار فروشگاه',
                          'available_quantity': 0,
                          'requested_quantity': 2,
                          'shortage_quantity': 2,
                        },
                    ],
                    workflowEnabled: true,
                    canOverride: true,
                    canCorrect: true,
                    correctionAlreadyApplied: true,
                    onCancel: () {},
                    onPark: () => parked = true,
                    onCorrect: () {},
                    onOverride: () {},
                  ),
                ),
                child: const Text('بازکردن'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('بازکردن'));
      await tester.pumpAndSettle();
      expect(
        find.text('ثبت با موجودی منفی'),
        unique ? findsNothing : findsOneWidget,
      );
      expect(find.text('اصلاح موجودی'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -4000),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('پارک فروش'));
      await tester.tap(find.text('پارک فروش'));
      expect(parked, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
