import '../../utils/number_normalizer.dart';
import 'sms_bank_models.dart';

/// Converts user-friendly templates into regex and extracts bank SMS fields.
class SmsBankPatternEngine {
  SmsBankPatternEngine._();

  static final Map<String, String> _placeholderRegex = {
    'amount': r'(?<amount>[+\-]?\d{1,3}(?:[,\u066C\u066B٫٬]\d{3})*(?:[.,]\d+)?|[+\-]?\d+(?:[.,]\d+)?)',
    'amount_signed':
        r'(?<amount_signed>[+\-]?\d{1,3}(?:[,\u066C\u066B٫٬]\d{3})*(?:[.,]\d+)?\s*-?|-?\s*[+\-]?\d{1,3}(?:[,\u066C\u066B٫٬]\d{3})*(?:[.,]\d+)?)',
    'balance': r'(?<balance>[+\-]?\d{1,3}(?:[,\u066C\u066B٫٬]\d{3})*(?:[.,]\d+)?|[+\-]?\d+(?:[.,]\d+)?)',
    'account': r'(?<account>[\d×xX*\-.\u00D7]+)',
    'direction':
        r'(?<direction>برداشت(?:\s*از)?|واریز|واريز|برداشت|واریزی|واريزي|debit|credit|withdraw|deposit)',
    'date': r'(?<date>\d{2,4}[/\-_.]\d{1,2}[/\-_.]\d{1,4}|\d{1,2}[/\-_.]\d{1,2})',
    'time': r'(?<time>\d{1,2}:\d{2}(?::\d{2})?)',
    'channel': r'(?<channel>[^\s\n]+)',
    'ref': r'(?<ref>[\w.\-×xX*]+)',
    'any': r'(?<any>[\s\S]*?)',
  };

  /// Match [body]/[sender] against [patterns]; returns best single result
  /// (no multi-business disambiguation). Prefer [matchResolved] for routing.
  static SmsBankMatchResult match({
    required String body,
    required String sender,
    required List<SmsBankPattern> patterns,
  }) {
    final all = matchAll(body: body, sender: sender, patterns: patterns);
    if (all.isEmpty) return SmsBankMatchResult.none;
    all.sort((a, b) => b.confidence.compareTo(a.confidence));
    return all.first;
  }

  /// Collect every viable match (template + heuristic), with scoring bonuses.
  static List<SmsBankMatchResult> matchAll({
    required String body,
    required String sender,
    required List<SmsBankPattern> patterns,
  }) {
    final normalizedBody = _normalizeBody(body);
    final normalizedSender = _normalizeBody(sender);
    final results = <SmsBankMatchResult>[];

    for (final pattern in patterns.where((p) => p.enabled)) {
      final hintsOk = _senderMatches(normalizedSender, normalizedBody, pattern.senderHints);
      if (!hintsOk && pattern.senderHints.isNotEmpty) continue;

      var result = _matchTemplate(normalizedBody, pattern);
      if (!result.matched) continue;
      result = _withScoreBonuses(result, pattern, hintsMatched: hintsOk || pattern.senderHints.isEmpty);
      results.add(result);
    }

    if (results.isEmpty) {
      final heuristic = _heuristicMatch(normalizedBody, normalizedSender, patterns);
      if (heuristic.matched) {
        results.add(heuristic);
      }
    }

    return results;
  }

  /// Resolve the best match across businesses. When several businesses score
  /// within [ambiguityDelta], returns [needsBusinessChoice] with candidates.
  static SmsBankMatchResult matchResolved({
    required String body,
    required String sender,
    required List<SmsBankPattern> patterns,
    int? preferredBusinessId,
    double ambiguityDelta = 0.12,
  }) {
    final all = matchAll(body: body, sender: sender, patterns: patterns);
    if (all.isEmpty) return SmsBankMatchResult.none;

    all.sort((a, b) {
      final byConf = b.confidence.compareTo(a.confidence);
      if (byConf != 0) return byConf;
      // Prefer mapped bank account, then preferred business.
      final aBank = a.bankAccountId != null ? 1 : 0;
      final bBank = b.bankAccountId != null ? 1 : 0;
      if (aBank != bBank) return bBank.compareTo(aBank);
      if (preferredBusinessId != null) {
        final aPref = a.businessId == preferredBusinessId ? 1 : 0;
        final bPref = b.businessId == preferredBusinessId ? 1 : 0;
        if (aPref != bPref) return bPref.compareTo(aPref);
      }
      return 0;
    });

    final top = all.first;
    final topScore = top.confidence;

    // Best candidate per business_id (null business ids share a bucket keyed 0 with care)
    final byBusiness = <int, SmsBankMatchResult>{};
    for (final r in all) {
      if (r.confidence < topScore - ambiguityDelta) continue;
      final bid = r.businessId;
      if (bid == null) continue;
      final existing = byBusiness[bid];
      if (existing == null || r.confidence > existing.confidence) {
        byBusiness[bid] = r;
      }
    }

    // Also consider unmatched-business results: if ONLY those exist, use preferred fallback later
    final withBusiness = byBusiness.values.toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    if (withBusiness.length >= 2) {
      final candidates = withBusiness
          .map(
            (r) => SmsBankBusinessCandidate(
              businessId: r.businessId!,
              businessName: r.businessName,
              patternId: r.patternId,
              patternName: r.patternName,
              bankAccountId: r.bankAccountId,
              bankAccountName: r.bankAccountName,
              confidence: r.confidence,
            ),
          )
          .toList();
      return top.copyWith(
        matched: true,
        needsBusinessChoice: true,
        businessId: null,
        candidates: candidates,
      );
    }

    if (withBusiness.length == 1) {
      return withBusiness.first.copyWith(needsBusinessChoice: false, candidates: const []);
    }

    // No businessId on matches — soft-prefer preferredBusinessId only as hint
    if (preferredBusinessId != null) {
      return top.copyWith(
        businessId: preferredBusinessId,
        needsBusinessChoice: false,
        candidates: const [],
      );
    }
    return top.copyWith(needsBusinessChoice: false, candidates: const []);
  }

  static SmsBankMatchResult _withScoreBonuses(
    SmsBankMatchResult result,
    SmsBankPattern pattern, {
    required bool hintsMatched,
  }) {
    var score = result.confidence;
    if (pattern.bankAccountId != null) score += 0.18;
    if (pattern.businessId != null) score += 0.10;
    if (hintsMatched && pattern.senderHints.isNotEmpty) score += 0.06;
    if (!pattern.isSeed) score += 0.04; // user-tuned patterns win ties
    return result.copyWith(
      confidence: score,
      businessName: pattern.businessName ?? result.businessName,
    );
  }

  /// Build a template suggestion from a sample by wrapping known values.
  /// [markers] maps placeholder name → exact substring in sample.
  static String buildTemplateFromMarkers(String sample, Map<String, String> markers) {
    var out = sample;
    // Replace longer values first to avoid partial collisions
    final entries = markers.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    for (final e in entries) {
      if (e.value.isEmpty) continue;
      final token = '{${e.key}}';
      out = out.replaceFirst(e.value, token);
    }
    return out;
  }

  static SmsBankMatchResult testTemplate({
    required String template,
    required String sampleBody,
    List<String> senderHints = const [],
    String sender = '',
  }) {
    final pattern = SmsBankPattern(
      id: 'test',
      name: 'test',
      template: template,
      senderHints: senderHints,
      updatedAt: DateTime.now(),
    );
    return match(body: sampleBody, sender: sender, patterns: [pattern]);
  }

  static String _normalizeBody(String input) {
    var s = toEnglishDigits(input);
    // Normalize Arabic Yeh/Kaf variants commonly used in bank SMS
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

  static bool _senderMatches(String sender, String body, List<String> hints) {
    if (hints.isEmpty) return true;
    final hay = '$sender\n$body'.toLowerCase();
    for (final h in hints) {
      final needle = _normalizeBody(h).toLowerCase();
      if (needle.isNotEmpty && hay.contains(needle)) return true;
    }
    return false;
  }

  static SmsBankMatchResult _matchTemplate(String body, SmsBankPattern pattern) {
    final template = pattern.template.trim();
    if (template.isEmpty) return SmsBankMatchResult.none;

    final regex = _templateToRegex(template);
    if (regex == null) return SmsBankMatchResult.none;

    final m = regex.firstMatch(body);
    if (m == null) {
      // Soft match: allow whitespace flexibility by collapsing spaces
      final softBody = body.replaceAll(RegExp(r'\s+'), ' ');
      final softTemplate = template.replaceAll(RegExp(r'\s+'), ' ');
      final softRegex = _templateToRegex(softTemplate);
      final m2 = softRegex?.firstMatch(softBody);
      if (m2 == null) return SmsBankMatchResult.none;
      return _resultFromMatch(m2, pattern, confidence: 0.85);
    }
    return _resultFromMatch(m, pattern, confidence: 1.0);
  }

  static RegExp? _templateToRegex(String template) {
    final buf = StringBuffer();
    buf.write('^');
    var i = 0;
    final usedNames = <String, int>{};
    while (i < template.length) {
      if (template[i] == '{') {
        final end = template.indexOf('}', i + 1);
        if (end > i) {
          final name = template.substring(i + 1, end).trim().toLowerCase();
          final piece = _placeholderRegex[name];
          if (piece != null) {
            final count = usedNames[name] ?? 0;
            usedNames[name] = count + 1;
            if (count == 0) {
              buf.write(piece);
            } else if (name == 'any') {
              buf.write(r'(?:[\s\S]*?)');
            } else {
              // Subsequent same-named placeholders: non-named copy of the pattern
              final stripped = piece.replaceFirst(RegExp('\\(\\?<$name>'), '(');
              buf.write(stripped);
            }
            i = end + 1;
            continue;
          }
        }
      }
      // Escape literal char; treat newlines loosely
      final ch = template[i];
      if (ch == '\n' || ch == '\r') {
        buf.write(r'\s*');
      } else if (RegExp(r'\s').hasMatch(ch)) {
        buf.write(r'\s*');
        // skip consecutive whitespace in template
        while (i + 1 < template.length && RegExp(r'\s').hasMatch(template[i + 1])) {
          i++;
        }
      } else {
        buf.write(RegExp.escape(ch));
      }
      i++;
    }
    buf.write(r'\s*$');
    try {
      return RegExp(buf.toString(), caseSensitive: false, dotAll: true);
    } catch (_) {
      return null;
    }
  }

  static SmsBankMatchResult _resultFromMatch(
    RegExpMatch m,
    SmsBankPattern pattern, {
    required double confidence,
  }) {
    final fields = <String, String>{};
    for (final name in m.groupNames) {
      final v = m.namedGroup(name);
      if (v != null && v.isNotEmpty) fields[name] = v;
    }

    final amountRaw = fields['amount'] ?? fields['amount_signed'] ?? '';
    final amount = parseAmount(amountRaw);
    final direction = _resolveDirection(
      fields['direction'],
      amountRaw,
      amount,
    );
    final balance = fields.containsKey('balance') ? parseAmount(fields['balance']!) : null;

    if (amount == null || amount <= 0) {
      return SmsBankMatchResult.none;
    }

    return SmsBankMatchResult(
      matched: true,
      amount: amount.abs(),
      direction: direction,
      balance: balance?.abs(),
      accountMask: fields['account'],
      channel: fields['channel'],
      patternId: pattern.id,
      patternName: pattern.name,
      bankAccountId: pattern.bankAccountId,
      bankAccountName: pattern.bankAccountName,
      businessId: pattern.businessId,
      businessName: pattern.businessName,
      confidence: confidence,
      fields: fields,
    );
  }

  static SmsBankMatchResult _heuristicMatch(
    String body,
    String sender,
    List<SmsBankPattern> patterns,
  ) {
    // Prefer patterns whose sender hints match, even without template hit
    SmsBankPattern? hinted;
    for (final p in patterns.where((e) => e.enabled)) {
      if (_senderMatches(sender, body, p.senderHints)) {
        hinted = p;
        break;
      }
    }

    // Generic Iranian bank SMS cues
    final looksBank = RegExp(
      r'مانده|موجودی|برداشت|واریز|واريز|ریال|ريال|بانک|بانك|شتاب',
      caseSensitive: false,
    ).hasMatch(body);
    if (!looksBank && hinted == null) return SmsBankMatchResult.none;

    SmsBankDirection direction = SmsBankDirection.unknown;
    if (RegExp(r'برداشت').hasMatch(body)) {
      direction = SmsBankDirection.debit;
    } else if (RegExp(r'واریز|واريز').hasMatch(body)) {
      direction = SmsBankDirection.credit;
    }

    double? amount;
    // Labeled amount
    final labeled = RegExp(
      r'(?:برداشت|واریز|واريز|مبلغ)\s*(?:از\s*[:：]?\s*)?[:：]?\s*([+\-]?\d[\d,٬٫]*)\s*(?:ریال|ريال)?',
      caseSensitive: false,
    ).firstMatch(body);
    if (labeled != null) {
      amount = parseAmount(labeled.group(1)!);
    }

    // Signed standalone line like 150,000,000- or +25,000,000
    if (amount == null) {
      final signed = RegExp(
        r'(?:^|\n)\s*([+\-]?\d{1,3}(?:,\d{3})+)\s*-?\s*(?:ریال|ريال)?\s*(?:$|\n)|(?:^|\n)\s*([+\-]\d[\d,]*)\s*(?:ریال|ريال)?',
      ).firstMatch(body);
      if (signed != null) {
        final raw = signed.group(1) ?? signed.group(2) ?? '';
        amount = parseAmount(raw);
        if (raw.contains('-') && !raw.trimLeft().startsWith('+')) {
          direction = direction == SmsBankDirection.unknown ? SmsBankDirection.debit : direction;
        } else if (raw.trimLeft().startsWith('+')) {
          direction = direction == SmsBankDirection.unknown ? SmsBankDirection.credit : direction;
        }
      }
    }

    // Trailing minus: 150,000,000-
    if (amount == null) {
      final trailing = RegExp(r'((?:\d{1,3},)*\d{3}|\d+)\s*-').firstMatch(body);
      if (trailing != null) {
        amount = parseAmount(trailing.group(1)!);
        direction = direction == SmsBankDirection.unknown ? SmsBankDirection.debit : direction;
      }
    }

    if (amount == null || amount <= 0) return SmsBankMatchResult.none;

    // Avoid picking balance as amount when labeled "مانده"
    final balanceMatch = RegExp(
      r'(?:مانده|موجودی)\s*[:：]?\s*([+\-]?\d[\d,٬٫]*)',
      caseSensitive: false,
    ).firstMatch(body);
    final balance = balanceMatch != null ? parseAmount(balanceMatch.group(1)!) : null;
    if (balance != null && amount == balance.abs() && labeled == null) {
      // Ambiguous — skip heuristic
      return SmsBankMatchResult.none;
    }

    final accountMatch = RegExp(
      r'(?:حساب|برداشت از|واریز|واريز)\s*[:：]?\s*([\d×xX*\-.\u00D7]+)',
      caseSensitive: false,
    ).firstMatch(body);

    return SmsBankMatchResult(
      matched: true,
      amount: amount.abs(),
      direction: direction,
      balance: balance?.abs(),
      accountMask: accountMatch?.group(1),
      patternId: hinted?.id,
      patternName: hinted?.name,
      bankAccountId: hinted?.bankAccountId,
      bankAccountName: hinted?.bankAccountName,
      businessId: hinted?.businessId,
      businessName: hinted?.businessName,
      confidence: hinted != null ? 0.7 : 0.55,
    );
  }

  static SmsBankDirection _resolveDirection(String? word, String amountRaw, double? amount) {
    final w = (word ?? '').toLowerCase();
    if (w.contains('برداشت') || w.contains('withdraw') || w.contains('debit')) {
      return SmsBankDirection.debit;
    }
    if (w.contains('واریز') ||
        w.contains('واريز') ||
        w.contains('deposit') ||
        w.contains('credit')) {
      return SmsBankDirection.credit;
    }
    final raw = amountRaw.trim();
    if (raw.startsWith('+')) return SmsBankDirection.credit;
    if (raw.startsWith('-') || raw.endsWith('-')) return SmsBankDirection.debit;
    if (amount != null && amount < 0) return SmsBankDirection.debit;
    return SmsBankDirection.unknown;
  }

  static double? parseAmount(String raw) {
    if (raw.trim().isEmpty) return null;
    var s = toEnglishDigits(raw)
        .replaceAll('٬', ',')
        .replaceAll('٫', '.')
        .replaceAll(' ', '')
        .replaceAll('ریال', '')
        .replaceAll('ريال', '')
        .trim();
    // Trailing minus
    var negative = false;
    if (s.endsWith('-')) {
      negative = true;
      s = s.substring(0, s.length - 1);
    }
    if (s.startsWith('-')) {
      negative = true;
      s = s.substring(1);
    }
    if (s.startsWith('+')) s = s.substring(1);
    s = s.replaceAll(',', '');
    final v = double.tryParse(s);
    if (v == null) return null;
    return negative ? -v.abs() : v;
  }

  /// Fingerprint to dedupe near-identical SMS.
  static String fingerprint(String sender, String body, DateTime receivedAt) {
    final norm = _normalizeBody(body).replaceAll(RegExp(r'\s+'), ' ');
    final bucket = receivedAt.millisecondsSinceEpoch ~/ 60000; // 1-minute bucket
    return '${sender.trim()}|$bucket|${norm.hashCode}';
  }
}
