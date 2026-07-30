import 'package:uuid/uuid.dart';

import 'sms_bank_models.dart';

/// Built-in patterns covering common Iranian bank SMS formats.
class SmsBankSeedPatterns {
  SmsBankSeedPatterns._();

  static const _uuid = Uuid();

  static List<SmsBankPattern> build({int? businessId}) {
    final now = DateTime.now();
    return [
      SmsBankPattern(
        id: 'seed_tejarat_classic',
        name: 'بانک تجارت — کلاسیک',
        enabled: true,
        isSeed: true,
        businessId: businessId,
        senderHints: const ['تجارت', 'Tejarat', 'بانک تجارت'],
        template: '*بانک تجارت*\n'
            'حساب: {account}\n'
            '{direction}: {amount} ریال\n'
            'از طريق: {channel}\n'
            'مانده: {balance} ریال\n'
            '{date}\n'
            '{time} {ref}',
        updatedAt: now,
      ),
      SmsBankPattern(
        id: 'seed_short_signed',
        name: 'پیامک کوتاه با مبلغ علامت‌دار',
        enabled: true,
        isSeed: true,
        businessId: businessId,
        senderHints: const [],
        template: '{amount_signed}\n'
            '{date}_{time}\n'
            'مانده: {balance} {account}',
        updatedAt: now,
      ),
      SmsBankPattern(
        id: 'seed_tt_bank',
        name: 'بانک توسعه تعاون',
        enabled: true,
        isSeed: true,
        businessId: businessId,
        senderHints: const ['توسعه تعاون', 'تعاون'],
        template: 'بانك توسعه تعاون\n'
            '{any}\n'
            'برداشت از: {account}\n'
            'مبلغ: {amount} ريال\n'
            '{date}_{time}\n'
            'موجودي: {balance} ريال',
        updatedAt: now,
      ),
      SmsBankPattern(
        id: 'seed_en_bank',
        name: 'اقتصاد نوین',
        enabled: true,
        isSeed: true,
        businessId: businessId,
        senderHints: const ['اقتصاد نوین', 'اقتصاد نوين', 'نوین', 'آواي نوين', 'آوای نوین'],
        template: 'اقتصاد نوین\n'
            '{direction}: {account}\n'
            '{amount_signed}ريال\n'
            'مانده:{balance}ريال\n'
            '{date}-{time}',
        updatedAt: now,
      ),
      SmsBankPattern(
        id: 'seed_generic_withdraw',
        name: 'عمومی — برداشت با مبلغ',
        enabled: true,
        isSeed: true,
        businessId: businessId,
        senderHints: const ['بانک', 'بانك'],
        template: '{any}برداشت{any}{amount}{any}مانده{any}{balance}{any}',
        updatedAt: now,
      ),
      SmsBankPattern(
        id: 'seed_generic_deposit',
        name: 'عمومی — واریز با مبلغ',
        enabled: true,
        isSeed: true,
        businessId: businessId,
        senderHints: const ['بانک', 'بانك'],
        template: '{any}واریز{any}{amount}{any}مانده{any}{balance}{any}',
        updatedAt: now,
      ),
    ];
  }

  static String newId() => _uuid.v4();
}
