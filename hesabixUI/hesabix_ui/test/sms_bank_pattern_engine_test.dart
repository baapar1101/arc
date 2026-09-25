import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/services/sms_bank/sms_bank_match_policy.dart';
import 'package:hesabix_ui/services/sms_bank/sms_bank_models.dart';
import 'package:hesabix_ui/services/sms_bank/sms_bank_pattern_engine.dart';
import 'package:hesabix_ui/services/sms_bank/sms_bank_seed_patterns.dart';

void main() {
  final seeds = SmsBankSeedPatterns.build(businessId: 1);

  group('SmsBankMatchPolicy', () {
    test('rejects empty hints', () {
      expect(
        SmsBankMatchPolicy.senderHintsAllowMatch(
          sender: 'Tejarat',
          body: 'برداشت',
          hints: const [],
        ),
        isFalse,
      );
    });

    test('short body hints do not match promo text', () {
      expect(
        SmsBankMatchPolicy.hintMatchesBody(
          'وام بانک با نرخ ویژه',
          const ['بانک'],
        ),
        isFalse,
      );
    });

    test('senderLooksLikeBank recognizes known tokens', () {
      expect(SmsBankMatchPolicy.senderLooksLikeBank('Tejarat'), isTrue);
      expect(SmsBankMatchPolicy.senderLooksLikeBank('BMELLAT'), isTrue);
      expect(SmsBankMatchPolicy.senderLooksLikeBank('OTP-Service'), isFalse);
    });
  });

  group('SmsBankPatternEngine', () {
    test('matches Tejarat classic SMS', () {
      const body = '''
*بانک تجارت*
حساب: 1234××××5678
برداشت: 1,500,000 ریال
از طريق: پایا
مانده: 10,000,000 ریال
1403/01/15
12:30 REF123
''';
      final match = SmsBankPatternEngine.match(
        body: body,
        sender: 'Tejarat',
        patterns: seeds,
      );
      expect(match.matched, isTrue);
      expect(match.direction, SmsBankDirection.debit);
      expect(match.amount, 1500000);
      expect(match.confidence, greaterThanOrEqualTo(SmsBankMatchPolicy.minAcceptConfidence));
    });

    test('rejects promotional SMS mentioning بانک', () {
      const body = '''
پیشنهاد ویژه بانک برای دریافت وام
مبلغ: 50,000,000 ریال
برای ثبت نام کلیک کنید
''';
      final match = SmsBankPatternEngine.match(
        body: body,
        sender: 'PromoAds',
        patterns: seeds,
      );
      expect(match.matched, isFalse);
    });

    test('rejects OTP-like SMS with ریال but no bank structure', () {
      const body = 'کد تایید شما 12345 است. مبلغ 1000 ریال کسر شد.';
      final match = SmsBankPatternEngine.match(
        body: body,
        sender: '1000',
        patterns: seeds,
      );
      expect(match.matched, isFalse);
    });

    test('does not match pattern with empty sender hints', () {
      final loose = SmsBankPattern(
        id: 'legacy_short',
        name: 'legacy',
        enabled: true,
        isSeed: true,
        businessId: 1,
        senderHints: const [],
        template: '{amount_signed}\n{date}_{time}\nمانده: {balance} {account}',
        updatedAt: DateTime.now(),
      );
      final match = SmsBankPatternEngine.match(
        body: '''
1,000,000-
03/01/01_12:00
مانده: 2,000,000 1234
''',
        sender: 'Anyone',
        patterns: [loose],
      );
      expect(match.matched, isFalse);
    });

    test('generic seed requires bank-looking sender', () {
      const body = '''
برداشت مبلغ 2,000,000 ریال
مانده 5,000,000 ریال
''';
      final noBank = SmsBankPatternEngine.match(
        body: body,
        sender: 'RandomApp',
        patterns: seeds,
      );
      expect(noBank.matched, isFalse);

      final withBank = SmsBankPatternEngine.match(
        body: body,
        sender: 'BankMellat',
        patterns: seeds,
      );
      expect(withBank.matched, isTrue);
      expect(withBank.direction, SmsBankDirection.debit);
      expect(withBank.amount, 2000000);
    });

    test('heuristic requires strong structure and bank sender', () {
      // No template hit, but strong structure + bank sender.
      const body = '''
اطلاعیه تراکنش
برداشت از کارت
مبلغ: 750000 ریال
مانده: 1200000 ریال
با تشکر
''';
      final match = SmsBankPatternEngine.match(
        body: body,
        sender: 'Pasargad',
        patterns: seeds,
      );
      expect(match.matched, isTrue);
      expect(match.confidence, greaterThanOrEqualTo(SmsBankMatchPolicy.minAcceptConfidence));
    });
  });

  group('SmsBankSeedPatterns.migrate', () {
    test('disables legacy short_signed seed', () {
      final legacy = SmsBankPattern(
        id: 'seed_short_signed',
        name: 'پیامک کوتاه',
        enabled: true,
        isSeed: true,
        businessId: 1,
        senderHints: const [],
        template: '{amount_signed}',
        updatedAt: DateTime.now(),
      );
      final migrated = SmsBankSeedPatterns.migrate([legacy]);
      final shortSigned = migrated.firstWhere((e) => e.id == 'seed_short_signed');
      expect(shortSigned.enabled, isFalse);
    });

    test('refreshes generic seed hints', () {
      final old = SmsBankPattern(
        id: 'seed_generic_withdraw',
        name: 'عمومی — برداشت با مبلغ',
        enabled: true,
        isSeed: true,
        businessId: 1,
        senderHints: const ['بانک', 'بانك'],
        template: '{any}برداشت{any}{amount}{any}مانده{any}{balance}{any}',
        updatedAt: DateTime.now(),
      );
      final migrated = SmsBankSeedPatterns.migrate([old]);
      final updated = migrated.firstWhere((e) => e.id == 'seed_generic_withdraw');
      expect(updated.senderHints, isNot(equals(const ['بانک', 'بانك'])));
      expect(updated.senderHints, contains('tejarat'));
      expect(
        migrated.any((e) => e.id == 'seed_generic_withdraw_balance'),
        isTrue,
      );
    });
  });
}
