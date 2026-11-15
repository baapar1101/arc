import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/utils/account_detail_type.dart';

void main() {
  test('جاری شرکا and code 20503 need person tafsili', () {
    expect(
      isPersonControlAccount(name: 'جاری شرکا', code: '20503'),
      isTrue,
    );
    expect(
      accountDetailTypeFor(name: '20503 - جاری شرکا', code: '20503'),
      'person',
    );
    expect(isPersonControlAccount(code: '20503'), isTrue);
  });

  test('named tafsili leaf under partners does not force another person', () {
    expect(
      isPersonControlAccount(name: 'محمد', code: '2050301'),
      isFalse,
    );
    expect(
      accountDetailTypeFor(name: '2050301 - محمد', code: '2050301'),
      isNull,
    );
  });

  test('display name of parent still needs person tafsili', () {
    expect(
      accountDetailTypeFor(name: '20503 - جاری شرکا', code: '20503'),
      'person',
    );
  });

  test('receivable and payable still need person detail', () {
    expect(isPersonControlAccount(name: 'حساب‌های پرداختنی'), isTrue);
    expect(isPersonControlAccount(accountType: 'person'), isTrue);
  });
}
