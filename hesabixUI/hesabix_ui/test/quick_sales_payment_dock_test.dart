import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/models/invoice_transaction.dart';
import 'package:hesabix_ui/models/quick_sales_payment_button.dart';
import 'package:hesabix_ui/services/quick_sales_service.dart';
import 'package:hesabix_ui/widgets/quick_sales/quick_sales_payment_dock.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeQuickSalesService extends QuickSalesService {
  final List<QuickSalesPaymentButtonModel> buttons;

  _FakeQuickSalesService({this.buttons = const []});

  @override
  Future<List<QuickSalesPaymentButtonModel>> listPaymentButtons({
    required int businessId,
  }) async => buttons;
}

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('mobile payments split and delete at width $width', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(Size(width, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final buttons = [
        for (final target in ['cash_register', 'bank', 'person'])
          QuickSalesPaymentButtonModel.fromJson({
            'id': target,
            'business_id': 4952,
            'scope': 'user',
            'target_type': target,
            'target_id': 7,
            'target_currency_id': 1,
            'target_name': target,
            'label': target,
          }),
      ];
      var payments = <InvoiceTransaction>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return SingleChildScrollView(
                    child: QuickSalesPaymentDock(
                      mobile: true,
                      businessId: 4952,
                      authStore: AuthStore(),
                      payments: payments,
                      onChanged: (value) => setState(() => payments = value),
                      invoiceTotal: 10000000,
                      paymentTarget: 10000000,
                      changeResolution: null,
                      onConfigureChange: () async => null,
                      defaultCashRegisterId: '7',
                      currencyUnit: 'ریال',
                      currencyId: 1,
                      decimalPlaces: 0,
                      enabled: true,
                      onSave: () {},
                      onSaveAndPrint: () {},
                      service: _FakeQuickSalesService(buttons: buttons),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        payments,
        isEmpty,
      ); // No automatic cash receipt on opening checkout.
      expect(find.text('چک'), findsNothing);
      expect(find.text('person'), findsOneWidget);
      final amountField = find.widgetWithText(TextField, 'مبلغ پرداخت');
      await tester.enterText(amountField, '4000000');
      await tester.tap(find.text('cash_register'));
      await tester.pumpAndSettle();
      expect(payments.single.amount, 4000000);
      expect(payments.single.type, TransactionType.cashRegister);
      final field = tester.widget<TextField>(amountField);
      expect(field.controller!.text.replaceAll(',', ''), '6000000');
      await tester.tap(find.text('bank'));
      await tester.pumpAndSettle();
      expect(payments, hasLength(2));
      expect(payments.last.amount, 6000000);
      expect(payments.last.type, TransactionType.bank);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byTooltip('حذف پرداخت').last);
      await tester.tap(find.byTooltip('حذف پرداخت').last);
      await tester.pumpAndSettle();
      expect(payments, hasLength(1));
      expect(field.controller!.text.replaceAll(',', ''), '6000000');
      expect(tester.takeException(), isNull);
    });
  }

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
                paymentTarget: 2800000,
                changeResolution: null,
                onConfigureChange: () async => null,
                defaultCashRegisterId: '7',
                currencyUnit: 'ریال',
                currencyId: 1,
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
    expect(
      tester
          .getSize(find.byKey(const ValueKey('quick-sales-payment-summary')))
          .height,
      QuickSalesPaymentDock.desktopSummaryHeight,
    );
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
