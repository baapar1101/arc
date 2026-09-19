import '../../utils/number_normalizer.dart';

/// Shared matching policy for Dart + mirrored by native [SmsBankMatcher].
class SmsBankMatchPolicy {
  SmsBankMatchPolicy._();

  /// Minimum confidence to accept a match for notify / capture.
  static const double minAcceptConfidence = 0.72;

  /// Heuristic-only matches must clear this floor (and usually a sender hint).
  static const double heuristicConfidenceWithSenderHint = 0.78;
  static const double heuristicConfidenceBankSenderOnly = 0.72;

  /// Body may satisfy a hint only when the hint is at least this long
  /// (avoids short tokens like «بانک» / «نوین» matching promo SMS).
  static const int minBodyHintLength = 5;

  /// Common Iranian bank sender tokens (normalized / lowercase).
  static const List<String> commonBankSenderHints = [
    'بانک تجارت',
    'tejarat',
    'تجارت',
    'بانک ملت',
    'bmellat',
    'mellat',
    'ملت',
    'بانک ملی',
    'bmi',
    'melli',
    'ملی',
    'بانک صادرات',
    'bsi',
    'saderat',
    'صادرات',
    'پاسارگاد',
    'pasargad',
    'پارسیان',
    'parsian',
    'سامان',
    'saman',
    'اقتصاد نوین',
    'enbank',
    'آوای نوین',
    'توسعه تعاون',
    'ttbank',
    'کشاورزی',
    'bki',
    'مسکن',
    'maskan',
    'رفاه',
    'refah',
    'سینا',
    'sina',
    'آینده',
    'ayandeh',
    'شهر',
    'shahr',
    'بانک دی',
    'day',
    'رسالت',
    'resalat',
    'گردشگری',
    'tourism',
    'ایران زمین',
    'izbank',
    'کارآفرین',
    'karafarin',
    'مهر',
    'mebank',
    'سپه',
    'banksepah',
    'postbank',
    'پست بانک',
    'blu',
    'blubank',
    'bank',
  ];

  static String normalize(String input) {
    var s = toEnglishDigits(input);
    s = s
        .replaceAll('ي', 'ی')
        .replaceAll('ك', 'ک')
        .replaceAll('\u200f', '')
        .replaceAll('\u200e', '')
        .replaceAll('\u202a', '')
        .replaceAll('\u202c', '')
        .replaceAll('\u202b', '')
        .replaceAll('\u00a0', ' ');
    return s.trim();
  }

  /// True when [sender] looks like a bank origin (name / known token).
  static bool senderLooksLikeBank(String sender) {
    final s = normalize(sender).toLowerCase();
    if (s.isEmpty) return false;
    for (final token in commonBankSenderHints) {
      final t = normalize(token).toLowerCase();
      if (t.isNotEmpty && s.contains(t)) return true;
    }
    return false;
  }

  static bool hintMatchesSender(String sender, List<String> hints) {
    if (hints.isEmpty) return false;
    final hay = normalize(sender).toLowerCase();
    for (final h in hints) {
      final needle = normalize(h).toLowerCase();
      if (needle.isNotEmpty && hay.contains(needle)) return true;
    }
    return false;
  }

  static bool hintMatchesBody(
    String body,
    List<String> hints, {
    int minHintLength = minBodyHintLength,
  }) {
    if (hints.isEmpty) return false;
    final hay = normalize(body).toLowerCase();
    for (final h in hints) {
      final needle = normalize(h).toLowerCase();
      if (needle.length >= minHintLength && hay.contains(needle)) return true;
    }
    return false;
  }

  /// Pattern gate: empty hints never match. Prefer sender; long hints may hit body.
  static bool senderHintsAllowMatch({
    required String sender,
    required String body,
    required List<String> hints,
    bool requireSenderForGeneric = false,
  }) {
    if (hints.isEmpty) return false;
    if (hintMatchesSender(sender, hints)) return true;
    if (requireSenderForGeneric) return false;
    return hintMatchesBody(body, hints);
  }

  static bool isGenericSeedId(String? patternId) {
    final id = patternId ?? '';
    return id.startsWith('seed_generic');
  }

  /// Strong bank-SMS structure for heuristic fallback.
  static bool bodyHasStrongBankStructure(String body) {
    final b = normalize(body);
    final hasDirection = RegExp(r'برداشت|واریز|واريز').hasMatch(b);
    final hasBalance = RegExp(r'مانده|موجودی|موجودي').hasMatch(b);
    final hasAmountCue = RegExp(r'مبلغ|ریال|ريال').hasMatch(b);
    return hasDirection && hasBalance && hasAmountCue;
  }
}
