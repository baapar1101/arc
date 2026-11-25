import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/invoice_transaction.dart';
import 'package:hesabix_ui/pages/business/settings/business_settings_localization_helper.dart';

void main() {
  test('DigiPay extra_info survives payment payload json', () {
    final tx = InvoiceTransaction(
      id: '1',
      type: TransactionType.person,
      personId: '9',
      personName: 'DigiPay',
      transactionDate: DateTime(2026, 1, 1),
      amount: 150000,
      description: 'DIGIPAY:hx1abc',
      extraInfo: const {'digipay_provider_id': 'hx1abc'},
    );
    final json = tx.toJson();
    expect(json['digipay_provider_id'], 'hx1abc');
    expect(json['extra_info']['digipay_provider_id'], 'hx1abc');
    expect(json['description'], 'DIGIPAY:hx1abc');
    final restored = InvoiceTransaction.fromJson({
      ...json,
      'id': '1',
      'type': 'person',
    });
    expect(restored.extraInfo?['digipay_provider_id'], 'hx1abc');
  });

  test('settings search matches DigiPay with or without ZWNJ', () {
    final foldedTitle =
        BusinessSettingsLocalizationHelper.normalizeSettingsQuery(
          'پرداخت اعتباری دیجی‌پی',
        );
    final foldedQuery =
        BusinessSettingsLocalizationHelper.normalizeSettingsQuery('دیجی پی');
    expect(foldedTitle.contains(foldedQuery), isTrue);
    expect(
      BusinessSettingsLocalizationHelper.normalizeSettingsQuery('digipay'),
      'digipay',
    );
  });
}
