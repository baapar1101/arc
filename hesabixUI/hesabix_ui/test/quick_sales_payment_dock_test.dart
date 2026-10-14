import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/models/invoice_transaction.dart';
import 'package:hesabix_ui/models/quick_sales_payment_button.dart';
import 'package:hesabix_ui/services/quick_sales_service.dart';
import 'package:hesabix_ui/widgets/quick_sales/quick_sales_payment_dock.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeQuickSalesService extends QuickSalesService {
  @override
  Future<List<QuickSalesPaymentButtonModel>> listPaymentButtons({
    required int businessId,
  }) async => const [];
}

void main() {
  testWidgets('desktop payment panel collapses without hiding fixed summary', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    List<InvoiceTransaction>? changedPayments;
    final payment = InvoiceTransaction(
      id: 'payment-1',
      type: TransactionType.cashRegister,
      cashRegisterId: '7',
      cashRegisterName: 'صندوق اصلی',
      transactionDate: DateTime(2026, 10, 14, 16, 45),
      amount: 3500000,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: QuickSalesPaymentDock(
                businessId: 4952,
                authStore: AuthStore(),
                payments: [payment],
                onChanged: (value) => changedPayments = value,
                invoiceTotal: 2800000,
                changeResolution: null,
                onConfigureChange: () async => null,
                defaultCashRegisterId: '7',
                currencyUnit: 'ریال',
                decimalPlaces: 0,
                enabled: true,
                onSave: () {},
                onSaveAndPrint: () {},
                service: _FakeQuickSalesService(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('جمع کل'), findsOneWidget);
    expect(find.text('پرداخت‌شده'), findsOneWidget);
    expect(find.text('ثبت'), findsOneWidget);
    expect(find.text('ثبت و چاپ'), findsOneWidget);
    expect(find.text('پرداخت‌ها (1)'), findsOneWidget);
    expect(find.text('دریافت در صندوق اصلی'), findsNothing);

    final toggleFinder = find.byKey(
      const ValueKey('quick-sales-payment-dock-toggle'),
    );
    final collapsedToggleRect = tester.getRect(toggleFinder);
    await tester.tapAt(
      Offset(collapsedToggleRect.center.dx, collapsedToggleRect.top + 2),
    );
    await tester.pumpAndSettle();

    expect(find.text('دریافت در صندوق اصلی'), findsOneWidget);
    expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);
    expect(find.byTooltip('حذف پرداخت'), findsOneWidget);
    final typeIcon = tester.widget<Icon>(
      find.byIcon(Icons.payments_outlined).first,
    );
    expect(typeIcon.color, Colors.teal);
    final amountRect = tester.getRect(
      find.byKey(const ValueKey('payment-payment-1')),
    );
    final deleteRect = tester.getRect(find.byTooltip('حذف پرداخت'));
    final amountDeleteGap = amountRect.left >= deleteRect.right
        ? amountRect.left - deleteRect.right
        : deleteRect.left - amountRect.right;
    expect(amountDeleteGap, greaterThanOrEqualTo(8));

    await tester.tap(find.byTooltip('حذف پرداخت'));
    expect(changedPayments, isEmpty);

    final expandedToggleRect = tester.getRect(toggleFinder);
    await tester.tapAt(
      Offset(expandedToggleRect.center.dx, expandedToggleRect.top + 2),
    );
    await tester.pumpAndSettle();
    expect(find.text('دریافت در صندوق اصلی'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool('quick_sales_payment_dock_expanded_v1_4952_0'),
      isFalse,
    );
  });
}
