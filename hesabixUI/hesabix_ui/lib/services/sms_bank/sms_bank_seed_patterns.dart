import 'package:uuid/uuid.dart';

import 'sms_bank_match_policy.dart';
import 'sms_bank_models.dart';

/// Built-in patterns covering common Iranian bank SMS formats.
class SmsBankSeedPatterns {
  SmsBankSeedPatterns._();

  static const _uuid = Uuid();

  static const _legacyDisabledSeedIds = {'seed_short_signed'};

  static const _additiveSeedIds = {
    'seed_generic_withdraw_balance',
    'seed_generic_deposit_balance',
  };

  static List<SmsBankPattern> build({int? businessId}) {
    final now = DateTime.now();
    return [
      SmsBankPattern(
        id: 'seed_tejarat_classic',
        name: 'بانک تجارت — کلاسیک',
        enabled: true,
        isSeed: true,
        businessId: businessId,
        senderHints: const ['بانک تجارت', 'Tejarat', 'TEJARAT', 'تجارت'],
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
        id: 'seed_tt_bank',
        name: 'بانک توسعه تعاون',
        enabled: true,
        isSeed: true,
        businessId: businessId,
        senderHints: const [
          'توسعه تعاون',
          'بانك توسعه تعاون',
          'بانک توسعه تعاون',
          'TTBank',
          'ttbank',
        ],
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
        senderHints: const [
          'اقتصاد نوین',
          'اقتصاد نوين',
          'آوای نوین',
          'آواي نوين',
          'ENBank',
          'enbank',
        ],
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
        senderHints: SmsBankMatchPolicy.commonBankSenderHints,
        template:
            '{any}برداشت{any}مبلغ{any}{amount}{any}مانده{any}{balance}{any}',
        updatedAt: now,
      ),
      SmsBankPattern(
        id: 'seed_generic_deposit',
        name: 'عمومی — واریز با مبلغ',
        enabled: true,
        isSeed: true,
        businessId: businessId,
        senderHints: SmsBankMatchPolicy.commonBankSenderHints,
        template:
            '{any}واریز{any}مبلغ{any}{amount}{any}مانده{any}{balance}{any}',
        updatedAt: now,
      ),
      SmsBankPattern(
        id: 'seed_generic_withdraw_balance',
        name: 'عمومی — برداشت و مانده',
        enabled: true,
        isSeed: true,
        businessId: businessId,
        senderHints: SmsBankMatchPolicy.commonBankSenderHints,
        template: '{any}برداشت{any}{amount}{any}مانده{any}{balance}{any}',
        updatedAt: now,
      ),
      SmsBankPattern(
        id: 'seed_generic_deposit_balance',
        name: 'عمومی — واریز و مانده',
        enabled: true,
        isSeed: true,
        businessId: businessId,
        senderHints: SmsBankMatchPolicy.commonBankSenderHints,
        template: '{any}واریز{any}{amount}{any}مانده{any}{balance}{any}',
        updatedAt: now,
      ),
    ];
  }

  /// Upgrade legacy weak seeds in-place (disable short_signed, refresh hints).
  static List<SmsBankPattern> migrate(List<SmsBankPattern> patterns) {
    if (patterns.isEmpty) return patterns;

    final catalog = {for (final p in build()) p.id: p};
    final out = <SmsBankPattern>[];
    var changed = false;

    for (final p in patterns) {
      if (_legacyDisabledSeedIds.contains(p.id)) {
        if (p.enabled) {
          changed = true;
          out.add(p.copyWith(enabled: false, updatedAt: DateTime.now()));
        } else {
          out.add(p);
        }
        continue;
      }

      final fresh = catalog[p.id];
      if (p.isSeed && fresh != null) {
        final needsRefresh = !_sameHints(p.senderHints, fresh.senderHints) ||
            p.template != fresh.template ||
            p.name != fresh.name;
        if (needsRefresh) {
          changed = true;
          out.add(
            p.copyWith(
              senderHints: fresh.senderHints,
              template: fresh.template,
              name: fresh.name,
              updatedAt: DateTime.now(),
            ),
          );
        } else {
          out.add(p);
        }
        continue;
      }

      out.add(p);
    }

    // Add newer seed variants for businesses that already have seed patterns.
    final byBusiness = <int, List<SmsBankPattern>>{};
    for (final p in out) {
      final bid = p.businessId;
      if (bid == null) continue;
      byBusiness.putIfAbsent(bid, () => []).add(p);
    }

    for (final entry in byBusiness.entries) {
      final bid = entry.key;
      final existingIds = entry.value.map((e) => e.id).toSet();
      String? bizName;
      for (final p in entry.value) {
        final n = p.businessName;
        if (n != null && n.isNotEmpty) {
          bizName = n;
          break;
        }
      }

      // Only inject additive seeds when this business already had seeds.
      final hadSeeds = entry.value.any((e) => e.isSeed);
      if (!hadSeeds) continue;

      for (final seedId in _additiveSeedIds) {
        if (existingIds.contains(seedId)) continue;
        final fresh = catalog[seedId];
        if (fresh == null) continue;
        changed = true;
        out.add(
          fresh.copyWith(
            businessId: bid,
            businessName: bizName,
            updatedAt: DateTime.now(),
          ),
        );
      }
    }

    return changed ? out : patterns;
  }

  static bool _sameHints(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String newId() => _uuid.v4();
}
