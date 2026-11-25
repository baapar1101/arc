import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/models/customer_model.dart';
import 'package:hesabix_ui/services/customer_service.dart';
import 'package:hesabix_ui/widgets/invoice/customer_combobox_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CustomerService extends CustomerService {
  _CustomerService() : super(ApiClient());
  final result = Completer<Map<String, dynamic>>();
  int creates = 0;
  String? receivedMobile;

  @override
  Future<Map<String, dynamic>> searchCustomers({
    required int businessId,
    String? searchQuery,
    int page = 1,
    int limit = 20,
  }) async => {'customers': <Customer>[], 'hasMore': false};

  @override
  Future<Map<String, dynamic>> quickResolveCustomer({
    required int businessId,
    String? aliasName,
    String? mobile,
  }) {
    creates++;
    receivedMobile = mobile;
    return result.future;
  }
}

void main() {
  testWidgets(
    'mobile customer submit works with keyboard and blocks duplicate taps',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      final service = _CustomerService();
      Customer? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomerComboboxWidget(
              businessId: 5,
              authStore: AuthStore(),
              enableQuickCreateOnSubmit: true,
              quickCreateHint: 'ثبت در گروه پیش‌فرض',
              service: service,
              onCustomerChanged: (value) => selected = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '09121234567 علی رضایی');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.ensureVisible(find.text('یافتن / ثبت و انتخاب'));
      await tester.tap(find.text('یافتن / ثبت و انتخاب'));
      await tester.pump();
      expect(service.creates, 1);
      expect(service.receivedMobile, '09121234567');
      expect(find.text('در حال یافتن / ثبت مشتری…'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
      service.result.complete({
        'created': true,
        'customers': [
          const Customer(id: 42, name: 'علی رضایی', phone: '09121234567'),
        ],
      });
      await tester.pumpAndSettle();
      expect(selected?.id, 42);
      expect(find.text('یافتن / ثبت و انتخاب'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
