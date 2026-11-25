import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/widgets/quick_sales/quick_sales_product_chip_strip.dart';

void main() {
  testWidgets('pinned products render before recents and stay visible with a cart', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: QuickSalesProductChipStrip(
            pinnedProducts: const [
              {'id': 1, 'name': 'نان', 'base_sales_price': 1000},
            ],
            recentProducts: const [
              {'id': 1, 'name': 'نان', 'base_sales_price': 1000},
              {'id': 2, 'name': 'شیر', 'base_sales_price': 2000},
            ],
            showRecents: false,
            compact: true,
            formatPrice: (product) => '${product['base_sales_price']}',
            onAdd: (_) {},
            onPin: (_) {},
            onUnpin: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('نان'), findsOneWidget);
    expect(find.text('شیر'), findsNothing);
    expect(find.text('کالاهای ثابت من'), findsOneWidget);
  });
}
