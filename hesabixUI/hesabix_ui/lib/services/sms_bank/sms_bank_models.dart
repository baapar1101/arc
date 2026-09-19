import 'dart:convert';

/// Direction inferred from bank SMS wording / signed amount.
enum SmsBankDirection {
  debit, // برداشت / پرداخت
  credit, // واریز / دریافت
  unknown,
}

extension SmsBankDirectionX on SmsBankDirection {
  String get wireName {
    switch (this) {
      case SmsBankDirection.debit:
        return 'debit';
      case SmsBankDirection.credit:
        return 'credit';
      case SmsBankDirection.unknown:
        return 'unknown';
    }
  }

  static SmsBankDirection fromWire(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'debit':
      case 'withdraw':
      case 'برداشت':
        return SmsBankDirection.debit;
      case 'credit':
      case 'deposit':
      case 'واریز':
      case 'واريز':
        return SmsBankDirection.credit;
      default:
        return SmsBankDirection.unknown;
    }
  }

  /// true → دریافت، false → پرداخت
  bool get isReceiptPreferred => this == SmsBankDirection.credit;

  /// true → درآمد، false → هزینه
  bool get isIncomePreferred => this == SmsBankDirection.credit;
}

/// How aggressively to interrupt the user when a match is found.
enum SmsBankInterruptMode {
  /// Heads-up notification with actions (recommended default).
  notification,

  /// Same as notification, but Flutter opens quick-capture as soon as possible.
  autoOpen,
}

extension SmsBankInterruptModeX on SmsBankInterruptMode {
  String get wireName => this == SmsBankInterruptMode.autoOpen ? 'auto_open' : 'notification';

  static SmsBankInterruptMode fromWire(String? raw) {
    if ((raw ?? '') == 'auto_open') return SmsBankInterruptMode.autoOpen;
    return SmsBankInterruptMode.notification;
  }
}

/// User / seed pattern mapped to a business bank account.
class SmsBankPattern {
  final String id;
  final String name;
  final bool enabled;
  final List<String> senderHints;
  /// Template with placeholders like `{amount}`, `{direction}`, `{account}`.
  final String template;
  final int? bankAccountId;
  final String? bankAccountName;
  final int? businessId;
  final String? businessName;
  final bool isSeed;
  final DateTime updatedAt;

  const SmsBankPattern({
    required this.id,
    required this.name,
    this.enabled = true,
    this.senderHints = const [],
    required this.template,
    this.bankAccountId,
    this.bankAccountName,
    this.businessId,
    this.businessName,
    this.isSeed = false,
    required this.updatedAt,
  });

  SmsBankPattern copyWith({
    String? id,
    String? name,
    bool? enabled,
    List<String>? senderHints,
    String? template,
    int? bankAccountId,
    String? bankAccountName,
    int? businessId,
    String? businessName,
    bool? isSeed,
    DateTime? updatedAt,
    bool clearBank = false,
  }) {
    return SmsBankPattern(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      senderHints: senderHints ?? this.senderHints,
      template: template ?? this.template,
      bankAccountId: clearBank ? null : (bankAccountId ?? this.bankAccountId),
      bankAccountName: clearBank ? null : (bankAccountName ?? this.bankAccountName),
      businessId: businessId ?? this.businessId,
      businessName: businessName ?? this.businessName,
      isSeed: isSeed ?? this.isSeed,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'enabled': enabled,
        'sender_hints': senderHints,
        'template': template,
        'bank_account_id': bankAccountId,
        'bank_account_name': bankAccountName,
        'business_id': businessId,
        'business_name': businessName,
        'is_seed': isSeed,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory SmsBankPattern.fromJson(Map<String, dynamic> json) {
    final hints = json['sender_hints'] ?? json['senderHints'];
    return SmsBankPattern(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      enabled: json['enabled'] != false,
      senderHints: hints is List
          ? hints.map((e) => '$e').where((e) => e.trim().isNotEmpty).toList()
          : const [],
      template: '${json['template'] ?? ''}',
      bankAccountId: _asInt(json['bank_account_id'] ?? json['bankAccountId']),
      bankAccountName: json['bank_account_name']?.toString() ?? json['bankAccountName']?.toString(),
      businessId: _asInt(json['business_id'] ?? json['businessId']),
      businessName: json['business_name']?.toString() ?? json['businessName']?.toString(),
      isSeed: json['is_seed'] == true || json['isSeed'] == true,
      updatedAt: DateTime.tryParse('${json['updated_at'] ?? json['updatedAt'] ?? ''}') ??
          DateTime.now(),
    );
  }
}

class SmsBankSettings {
  final bool enabled;
  final SmsBankInterruptMode interruptMode;
  final double minAmount;
  final int? quietStartHour; // 0-23 inclusive, null = off
  final int? quietEndHour;
  /// Soft hint: last opened business (never the sole source of truth for routing).
  final int? activeBusinessId;
  /// Businesses that participate in SMS capture when [enabled] is true.
  final List<int> enabledBusinessIds;
  final bool vibrate;
  final bool onboarded;

  const SmsBankSettings({
    this.enabled = false,
    this.interruptMode = SmsBankInterruptMode.notification,
    this.minAmount = 0,
    this.quietStartHour,
    this.quietEndHour,
    this.activeBusinessId,
    this.enabledBusinessIds = const [],
    this.vibrate = true,
    this.onboarded = false,
  });

  SmsBankSettings copyWith({
    bool? enabled,
    SmsBankInterruptMode? interruptMode,
    double? minAmount,
    int? quietStartHour,
    int? quietEndHour,
    int? activeBusinessId,
    List<int>? enabledBusinessIds,
    bool? vibrate,
    bool? onboarded,
    bool clearQuiet = false,
    bool clearBusiness = false,
  }) {
    return SmsBankSettings(
      enabled: enabled ?? this.enabled,
      interruptMode: interruptMode ?? this.interruptMode,
      minAmount: minAmount ?? this.minAmount,
      quietStartHour: clearQuiet ? null : (quietStartHour ?? this.quietStartHour),
      quietEndHour: clearQuiet ? null : (quietEndHour ?? this.quietEndHour),
      activeBusinessId: clearBusiness ? null : (activeBusinessId ?? this.activeBusinessId),
      enabledBusinessIds: enabledBusinessIds ?? this.enabledBusinessIds,
      vibrate: vibrate ?? this.vibrate,
      onboarded: onboarded ?? this.onboarded,
    );
  }

  bool get quietHoursEnabled => quietStartHour != null && quietEndHour != null;

  bool isBusinessEnabled(int businessId) {
    if (!enabled) return false;
    if (enabledBusinessIds.isEmpty) {
      // Legacy / first-run: only last-opened business participates.
      return activeBusinessId == null || activeBusinessId == businessId;
    }
    return enabledBusinessIds.contains(businessId);
  }

  SmsBankSettings withBusinessEnabled(int businessId, bool value) {
    final set = enabledBusinessIds.toSet();
    if (value) {
      set.add(businessId);
    } else {
      set.remove(businessId);
    }
    return copyWith(
      enabledBusinessIds: set.toList()..sort(),
      enabled: value ? true : (enabled && set.isNotEmpty),
      activeBusinessId: value ? businessId : activeBusinessId,
      onboarded: value ? true : onboarded,
    );
  }

  bool isInQuietHours([DateTime? now]) {
    if (!quietHoursEnabled) return false;
    final h = (now ?? DateTime.now()).hour;
    final start = quietStartHour!;
    final end = quietEndHour!;
    if (start == end) return true;
    if (start < end) return h >= start && h < end;
    return h >= start || h < end;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'enabled': enabled,
        'interrupt_mode': interruptMode.wireName,
        'min_amount': minAmount,
        'quiet_start_hour': quietStartHour,
        'quiet_end_hour': quietEndHour,
        'active_business_id': activeBusinessId,
        'enabled_business_ids': enabledBusinessIds,
        'vibrate': vibrate,
        'onboarded': onboarded,
      };

  factory SmsBankSettings.fromJson(Map<String, dynamic> json) {
    final rawIds = json['enabled_business_ids'] ?? json['enabledBusinessIds'];
    final ids = <int>[];
    if (rawIds is List) {
      for (final e in rawIds) {
        final id = _asInt(e);
        if (id != null) ids.add(id);
      }
    }
    return SmsBankSettings(
      enabled: json['enabled'] == true,
      interruptMode: SmsBankInterruptModeX.fromWire('${json['interrupt_mode'] ?? ''}'),
      minAmount: _asDouble(json['min_amount']) ?? 0,
      quietStartHour: _asInt(json['quiet_start_hour']),
      quietEndHour: _asInt(json['quiet_end_hour']),
      activeBusinessId: _asInt(json['active_business_id']),
      enabledBusinessIds: ids,
      vibrate: json['vibrate'] != false,
      onboarded: json['onboarded'] == true,
    );
  }
}

/// One business that could own a matched SMS (for disambiguation UI).
class SmsBankBusinessCandidate {
  final int businessId;
  final String? businessName;
  final String? patternId;
  final String? patternName;
  final int? bankAccountId;
  final String? bankAccountName;
  final double confidence;

  const SmsBankBusinessCandidate({
    required this.businessId,
    this.businessName,
    this.patternId,
    this.patternName,
    this.bankAccountId,
    this.bankAccountName,
    this.confidence = 0,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'business_id': businessId,
        'business_name': businessName,
        'pattern_id': patternId,
        'pattern_name': patternName,
        'bank_account_id': bankAccountId,
        'bank_account_name': bankAccountName,
        'confidence': confidence,
      };

  factory SmsBankBusinessCandidate.fromJson(Map<String, dynamic> json) {
    return SmsBankBusinessCandidate(
      businessId: _asInt(json['business_id'] ?? json['businessId']) ?? 0,
      businessName: json['business_name']?.toString() ?? json['businessName']?.toString(),
      patternId: json['pattern_id']?.toString() ?? json['patternId']?.toString(),
      patternName: json['pattern_name']?.toString() ?? json['patternName']?.toString(),
      bankAccountId: _asInt(json['bank_account_id'] ?? json['bankAccountId']),
      bankAccountName: json['bank_account_name']?.toString() ?? json['bankAccountName']?.toString(),
      confidence: _asDouble(json['confidence']) ?? 0,
    );
  }
}

enum SmsBankEventStatus { pending, captured, dismissed, registered }

extension SmsBankEventStatusX on SmsBankEventStatus {
  String get wireName {
    switch (this) {
      case SmsBankEventStatus.pending:
        return 'pending';
      case SmsBankEventStatus.captured:
        return 'captured';
      case SmsBankEventStatus.dismissed:
        return 'dismissed';
      case SmsBankEventStatus.registered:
        return 'registered';
    }
  }

  static SmsBankEventStatus fromWire(String? raw) {
    switch (raw) {
      case 'captured':
        return SmsBankEventStatus.captured;
      case 'dismissed':
        return SmsBankEventStatus.dismissed;
      case 'registered':
        return SmsBankEventStatus.registered;
      default:
        return SmsBankEventStatus.pending;
    }
  }
}

/// A matched (or heuristically parsed) bank SMS waiting for user action.
class SmsBankEvent {
  final String id;
  final String fingerprint;
  final String sender;
  final String body;
  final double amount;
  final SmsBankDirection direction;
  final double? balance;
  final String? accountMask;
  final String? channel;
  final String? patternId;
  final String? patternName;
  final int? bankAccountId;
  final String? bankAccountName;
  final int? businessId;
  final String? businessName;
  final DateTime receivedAt;
  final SmsBankEventStatus status;
  final double confidence;
  /// True when more than one business could own this SMS.
  final bool needsBusinessChoice;
  final List<SmsBankBusinessCandidate> candidates;

  const SmsBankEvent({
    required this.id,
    required this.fingerprint,
    required this.sender,
    required this.body,
    required this.amount,
    required this.direction,
    this.balance,
    this.accountMask,
    this.channel,
    this.patternId,
    this.patternName,
    this.bankAccountId,
    this.bankAccountName,
    this.businessId,
    this.businessName,
    required this.receivedAt,
    this.status = SmsBankEventStatus.pending,
    this.confidence = 1,
    this.needsBusinessChoice = false,
    this.candidates = const [],
  });

  bool get hasResolvedBusiness => businessId != null && !needsBusinessChoice;

  SmsBankEvent copyWith({
    SmsBankEventStatus? status,
    int? bankAccountId,
    String? bankAccountName,
    SmsBankDirection? direction,
    int? businessId,
    String? businessName,
    String? patternId,
    String? patternName,
    bool? needsBusinessChoice,
    List<SmsBankBusinessCandidate>? candidates,
    double? confidence,
    bool clearBank = false,
    bool clearBusinessChoice = false,
  }) {
    return SmsBankEvent(
      id: id,
      fingerprint: fingerprint,
      sender: sender,
      body: body,
      amount: amount,
      direction: direction ?? this.direction,
      balance: balance,
      accountMask: accountMask,
      channel: channel,
      patternId: patternId ?? this.patternId,
      patternName: patternName ?? this.patternName,
      bankAccountId: clearBank ? null : (bankAccountId ?? this.bankAccountId),
      bankAccountName: clearBank ? null : (bankAccountName ?? this.bankAccountName),
      businessId: businessId ?? this.businessId,
      businessName: businessName ?? this.businessName,
      receivedAt: receivedAt,
      status: status ?? this.status,
      confidence: confidence ?? this.confidence,
      needsBusinessChoice:
          clearBusinessChoice ? false : (needsBusinessChoice ?? this.needsBusinessChoice),
      candidates: candidates ?? this.candidates,
    );
  }

  /// Apply a chosen business (from disambiguation) onto this event.
  SmsBankEvent withChosenBusiness(SmsBankBusinessCandidate chosen) {
    return copyWith(
      businessId: chosen.businessId,
      businessName: chosen.businessName,
      patternId: chosen.patternId ?? patternId,
      patternName: chosen.patternName ?? patternName,
      bankAccountId: chosen.bankAccountId,
      bankAccountName: chosen.bankAccountName,
      confidence: chosen.confidence,
      needsBusinessChoice: false,
      clearBusinessChoice: true,
      candidates: const [],
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'fingerprint': fingerprint,
        'sender': sender,
        'body': body,
        'amount': amount,
        'direction': direction.wireName,
        'balance': balance,
        'account_mask': accountMask,
        'channel': channel,
        'pattern_id': patternId,
        'pattern_name': patternName,
        'bank_account_id': bankAccountId,
        'bank_account_name': bankAccountName,
        'business_id': businessId,
        'business_name': businessName,
        'received_at': receivedAt.toIso8601String(),
        'status': status.wireName,
        'confidence': confidence,
        'needs_business_choice': needsBusinessChoice,
        'candidates': candidates.map((e) => e.toJson()).toList(),
      };

  factory SmsBankEvent.fromJson(Map<String, dynamic> json) {
    final rawCandidates = json['candidates'];
    final candidates = <SmsBankBusinessCandidate>[];
    if (rawCandidates is List) {
      for (final e in rawCandidates) {
        if (e is Map) {
          candidates.add(SmsBankBusinessCandidate.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return SmsBankEvent(
      id: '${json['id'] ?? ''}',
      fingerprint: '${json['fingerprint'] ?? ''}',
      sender: '${json['sender'] ?? ''}',
      body: '${json['body'] ?? ''}',
      amount: _asDouble(json['amount']) ?? 0,
      direction: SmsBankDirectionX.fromWire('${json['direction'] ?? ''}'),
      balance: _asDouble(json['balance']),
      accountMask: json['account_mask']?.toString() ?? json['accountMask']?.toString(),
      channel: json['channel']?.toString(),
      patternId: json['pattern_id']?.toString() ?? json['patternId']?.toString(),
      patternName: json['pattern_name']?.toString() ?? json['patternName']?.toString(),
      bankAccountId: _asInt(json['bank_account_id'] ?? json['bankAccountId']),
      bankAccountName: json['bank_account_name']?.toString() ?? json['bankAccountName']?.toString(),
      businessId: _asInt(json['business_id'] ?? json['businessId']),
      businessName: json['business_name']?.toString() ?? json['businessName']?.toString(),
      receivedAt: DateTime.tryParse('${json['received_at'] ?? json['receivedAt'] ?? ''}') ??
          DateTime.now(),
      status: SmsBankEventStatusX.fromWire('${json['status'] ?? ''}'),
      confidence: _asDouble(json['confidence']) ?? 1,
      needsBusinessChoice: json['needs_business_choice'] == true ||
          json['needsBusinessChoice'] == true,
      candidates: candidates,
    );
  }

  String toJsonString() => jsonEncode(toJson());
}

class SmsBankMatchResult {
  final bool matched;
  final double amount;
  final SmsBankDirection direction;
  final double? balance;
  final String? accountMask;
  final String? channel;
  final String? patternId;
  final String? patternName;
  final int? bankAccountId;
  final String? bankAccountName;
  final int? businessId;
  final String? businessName;
  final double confidence;
  final Map<String, String> fields;
  final bool needsBusinessChoice;
  final List<SmsBankBusinessCandidate> candidates;

  const SmsBankMatchResult({
    required this.matched,
    this.amount = 0,
    this.direction = SmsBankDirection.unknown,
    this.balance,
    this.accountMask,
    this.channel,
    this.patternId,
    this.patternName,
    this.bankAccountId,
    this.bankAccountName,
    this.businessId,
    this.businessName,
    this.confidence = 0,
    this.fields = const {},
    this.needsBusinessChoice = false,
    this.candidates = const [],
  });

  static const SmsBankMatchResult none = SmsBankMatchResult(matched: false);

  SmsBankMatchResult copyWith({
    bool? matched,
    double? amount,
    SmsBankDirection? direction,
    double? balance,
    String? accountMask,
    String? channel,
    String? patternId,
    String? patternName,
    int? bankAccountId,
    String? bankAccountName,
    int? businessId,
    String? businessName,
    double? confidence,
    Map<String, String>? fields,
    bool? needsBusinessChoice,
    List<SmsBankBusinessCandidate>? candidates,
  }) {
    return SmsBankMatchResult(
      matched: matched ?? this.matched,
      amount: amount ?? this.amount,
      direction: direction ?? this.direction,
      balance: balance ?? this.balance,
      accountMask: accountMask ?? this.accountMask,
      channel: channel ?? this.channel,
      patternId: patternId ?? this.patternId,
      patternName: patternName ?? this.patternName,
      bankAccountId: bankAccountId ?? this.bankAccountId,
      bankAccountName: bankAccountName ?? this.bankAccountName,
      businessId: businessId ?? this.businessId,
      businessName: businessName ?? this.businessName,
      confidence: confidence ?? this.confidence,
      fields: fields ?? this.fields,
      needsBusinessChoice: needsBusinessChoice ?? this.needsBusinessChoice,
      candidates: candidates ?? this.candidates,
    );
  }
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse('$v'.replaceAll(',', ''));
}
