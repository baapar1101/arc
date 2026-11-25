import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/business_dashboard_models.dart';
import 'package:hesabix_ui/models/product_measurement.dart';
import 'package:hesabix_ui/pages/business/business_info_settings_page.dart';
import 'package:hesabix_ui/pages/business/products_page.dart';
import 'package:hesabix_ui/widgets/product/product_form_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'product forms and read-only details use exact measurements across units',
    (tester) async {
      final originalHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = originalHttpOverrides);
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(1280, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final auth = AuthStore();
      ApiClient.bindAuthStore(auth);
      final client = ApiClient();
      await tester.runAsync(() => auth.saveApiKey('measurement-fixture-1'));

      Future<void> units(String dimension, String weight) async {
        await tester.runAsync(
          () => client.put(
            '/api/v1/businesses/1',
            data: {
              'product_dimension_unit': dimension,
              'product_weight_unit': weight,
            },
          ),
        );
      }

      Future<void> waitFor(bool Function() condition) async {
        for (var attempt = 0; attempt < 400; attempt++) {
          await tester.pump(const Duration(milliseconds: 30));
          if (condition()) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 35)),
          );
        }
        expect(condition(), isTrue);
        await tester.pumpAndSettle();
      }

      var productId = 0;
      final router = GoRouter(
        initialLocation: '/business/1/settings',
        routes: [
          GoRoute(
            path: '/business/1/settings',
            builder: (context, _) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () async {
                      final id = await showDialog<Object>(
                        context: context,
                        builder: (_) => ProductFormDialog(
                          businessId: 1,
                          authStore: auth,
                          product: productId == 0 ? null : {'id': productId},
                        ),
                      );
                      if (id is int) productId = id;
                    },
                    child: const Text('Open product'),
                  ),
                  TextButton(
                    onPressed: () => context.go('/business/1/business-info'),
                    child: const Text('Open settings'),
                  ),
                ],
              ),
            ),
          ),
          GoRoute(
            path: '/business/1/business-info',
            builder: (_, _) => const BusinessInfoSettingsPage(businessId: 1),
          ),
          GoRoute(
            path: '/business/1/products',
            builder: (_, _) => ProductsPage(businessId: 1, authStore: auth),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          locale: const Locale('fa'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      );
      await tester.pumpAndSettle();

      const keys = ['length_mm', 'width_mm', 'height_mm', 'weight_g'];
      Finder field(String key) => find.byKey(ValueKey(key));
      String read(String key) => tester
          .widget<EditableText>(
            find.descendant(
              of: field(key),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text;

      Future<void> enter(Finder field, String value) async {
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        await tester.enterText(field, value);
        await tester.pump();
      }

      Future<void> open() async {
        await tester.tap(find.text('Open product'));
        await waitFor(() => field('length_mm').evaluate().isNotEmpty);
      }

      Future<void> save() async {
        await tester.tap(find.widgetWithText(FilledButton, 'ذخیره'));
        await waitFor(() => find.byType(ProductFormDialog).evaluate().isEmpty);
      }

      Future<void> dismiss() async {
        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
        expect(find.byType(ProductFormDialog), findsNothing);
      }

      Future<void> chooseUnitsInSettings(
        ProductMeasurementUnit dimension,
        ProductMeasurementUnit weight,
      ) async {
        await tester.tap(find.text('Open settings'));
        final dropdowns = find.byWidgetPredicate(
          (widget) => widget is DropdownButtonFormField<ProductMeasurementUnit>,
        );
        await waitFor(() => dropdowns.evaluate().length == 2);
        for (final (index, unit) in [dimension, weight].indexed) {
          final field = dropdowns.at(index);
          await tester.ensureVisible(field);
          await tester.pumpAndSettle();
          await tester.tap(field);
          await tester.pumpAndSettle();
          await tester.tap(find.text(unit.label).last);
          await tester.pumpAndSettle();
        }
        final save = find.ancestor(
          of: find.text('ذخیره'),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        );
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await waitFor(() => find.text('Open product').evaluate().isNotEmpty);
      }

      void expectValues(List<String> expected) {
        expect(keys.map(read).toList(), expected);
      }

      final title = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'عنوان',
      );
      await units('mm', 'g');
      await open();
      expectValues(['', '', '', '']);
      await enter(title, 'UI physical product');
      await enter(field('length_mm'), '-1');
      await tester.tap(find.widgetWithText(FilledButton, 'ذخیره'));
      await tester.pump();
      expect(find.text('عدد صحیح یا اعشاری غیرمنفی وارد کنید.'), findsWidgets);
      const entered = ['125.5', '22.375', '3.0625', '1250.5'];
      for (var index = 0; index < keys.length; index++) {
        await enter(field(keys[index]), entered[index]);
      }
      await save();
      expect(productId, greaterThan(0));

      await open();
      expectValues(entered);
      await enter(field('width_mm'), '22.8125');
      await save();

      await chooseUnitsInSettings(
        ProductMeasurementUnit.cm,
        ProductMeasurementUnit.kg,
      );
      await open();
      expectValues(['12.55', '2.28125', '0.30625', '1.2505']);
      await enter(field('height_mm'), '0.3125');
      await enter(field('weight_g'), '1.250625');
      await units('m', 't');
      expectValues(['12.55', '2.28125', '0.3125', '1.250625']);
      await save();

      await open();
      expectValues(['0.1255', '0.0228125', '0.003125', '0.001250625']);
      final productName = 'UI physical product edited $productId';
      await enter(title, productName);
      await save();

      await chooseUnitsInSettings(
        ProductMeasurementUnit.mm,
        ProductMeasurementUnit.g,
      );
      await open();
      expectValues(['125.5', '22.8125', '3.125', '1250.625']);
      await dismiss();

      await units('m', 't');
      await open();
      await enter(field('height_mm'), '0.0031875');
      await enter(field('weight_g'), '0.00125075');
      await save();
      await units('mm', 'g');
      await open();
      expectValues(['125.5', '22.8125', '3.1875', '1250.75']);
      await dismiss();

      await tester.runAsync(() async {
        final response = await client.get('/api/v1/businesses/1');
        await auth.setCurrentBusiness(
          BusinessWithPermission.fromJson({
            ...Map<String, dynamic>.from(response.data['data'] as Map),
            'is_owner': true,
            'role': 'owner',
          }),
        );
      });
      await units('cm', 'kg');
      router.go('/business/1/products');
      final row = find.text(productName);
      await waitFor(() => row.evaluate().isNotEmpty);
      await tester.ensureVisible(row);
      await tester.tap(row);
      await waitFor(() => find.text('1.25075 کیلوگرم').evaluate().isNotEmpty);
      expect(find.text('12.55 سانتی‌متر'), findsOneWidget);
      expect(find.text('2.28125 سانتی‌متر'), findsOneWidget);
      expect(find.text('0.31875 سانتی‌متر'), findsOneWidget);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      await units('mm', 'g');
      await tester.ensureVisible(row);
      await tester.tap(row);
      await waitFor(() => find.text('1250.75 گرم').evaluate().isNotEmpty);
      expect(find.text('125.5 میلی‌متر'), findsOneWidget);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      router.go('/business/1/settings');
      await tester.pumpAndSettle();
      await chooseUnitsInSettings(
        ProductMeasurementUnit.inch,
        ProductMeasurementUnit.oz,
      );
      await open();
      expect(find.text('نمایش تقریبی'), findsWidgets);
      // A re-entered approximation and an unrelated title edit keep the stored length.
      await enter(field('length_mm'), '${read('length_mm')}0');
      final imperialProductName = '$productName imperial';
      await enter(title, imperialProductName);
      await enter(field('weight_g'), '1.234567');
      await save();

      await open();
      expect(read('weight_g'), '1.234567');
      await dismiss();
      router.go('/business/1/products');
      final imperialRow = find.text(imperialProductName);
      await waitFor(() => imperialRow.evaluate().isNotEmpty);
      await tester.ensureVisible(imperialRow);
      await tester.tap(imperialRow);
      await waitFor(() => find.text('1.234567 اونس').evaluate().isNotEmpty);
      expect(
        find.text('≈ ${ProductMeasurementUnit.inch.display('125.5')} اینچ'),
        findsOneWidget,
      );

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      await units('mm', 'g');
      router.go('/business/1/settings');
      await tester.pumpAndSettle();
      await open();
      expectValues(['125.5', '22.8125', '3.1875', '34.999385715861875']);
      await dismiss();

      await tester.pumpWidget(const SizedBox.shrink());
      // Let Dart's HTTP keep-alive timers expire on the widget test clock.
      await tester.pump(const Duration(seconds: 4));
    },
    skip: !const bool.fromEnvironment(
      'HESABIX_TEST_PRODUCT_MEASUREMENT_DIALOG',
    ),
  );
}
