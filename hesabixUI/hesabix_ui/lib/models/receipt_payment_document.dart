double _jsonAmountToDouble(dynamic v, [double fallback = 0.0]) {
  if (v == null) return fallback;
  if (v is bool) return fallback;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  if (v is String) {
    final t = v.trim().replaceAll(',', '');
    if (t.isEmpty) return fallback;
    return double.tryParse(t) ?? fallback;
  }
  return fallback;
}

double? _jsonAmountToDoubleNullable(dynamic v) {
  if (v == null) return null;
  if (v is bool) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  if (v is String) {
    final t = v.trim().replaceAll(',', '');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }
  return null;
}

/// مدل خط شخص در سند دریافت/پرداخت
class PersonLine {
  final int id;
  final int? personId;
  final String? personName;
  final double amount;
  final String? description;
  final Map<String, dynamic>? extraInfo;

  const PersonLine({
    required this.id,
    this.personId,
    this.personName,
    required this.amount,
    this.description,
    this.extraInfo,
  });

  factory PersonLine.fromJson(dynamic json) {
    final m = json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
    return PersonLine(
      id: (m['id'] as num?)?.toInt() ?? 0,
      personId: (m['person_id'] as num?)?.toInt(),
      personName: m['person_name'] as String?,
      amount: _jsonAmountToDouble(m['amount']),
      description: m['description'] as String?,
      extraInfo: m['extra_info'] is Map ? Map<String, dynamic>.from(m['extra_info'] as Map) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'person_id': personId,
      'person_name': personName,
      'amount': amount,
      'description': description,
      'extra_info': extraInfo,
    };
  }
}

/// مدل خط حساب در سند دریافت/پرداخت
class AccountLine {
  final int id;
  final int accountId;
  final String accountName;
  final String accountCode;
  final String? accountType;
  final double amount;
  final String? description;
  final String? transactionType;
  final DateTime? transactionDate;
  final double? commission;
  final Map<String, dynamic>? extraInfo;

  const AccountLine({
    required this.id,
    required this.accountId,
    required this.accountName,
    required this.accountCode,
    this.accountType,
    required this.amount,
    this.description,
    this.transactionType,
    this.transactionDate,
    this.commission,
    this.extraInfo,
  });

  factory AccountLine.fromJson(dynamic json) {
    final m = json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
    // API فیلدهای توصیفی را گاهی در ریشهٔ خط و نه فقط داخل extra_info برمی‌گرداند.
    final baseExtra = m['extra_info'] is Map
        ? Map<String, dynamic>.from(m['extra_info'] as Map)
        : <String, dynamic>{};
    final mergedExtra = Map<String, dynamic>.from(baseExtra);
    void mergeRoot(String key) {
      if (!m.containsKey(key)) return;
      final v = m[key];
      if (v == null) return;
      if (v is String && v.trim().isEmpty) return;
      mergedExtra.putIfAbsent(key, () => v);
    }
    mergeRoot('bank_name');
    mergeRoot('bank_id');
    mergeRoot('cash_register_name');
    mergeRoot('cash_register_id');
    mergeRoot('petty_cash_name');
    mergeRoot('petty_cash_id');
    mergeRoot('check_number');
    mergeRoot('check_id');
    mergeRoot('person_name');
    mergeRoot('person_id');
    mergeRoot('transaction_type');
    mergeRoot('transaction_date');
    mergeRoot('commission');
    mergeRoot('invoice_id');
    mergeRoot('invoice_code');
    mergeRoot('link_to_invoice');

    final transactionType = m['transaction_type'] as String? ?? mergedExtra['transaction_type'] as String?;
    DateTime? transactionDate;
    if (m['transaction_date'] != null) {
      transactionDate = DateTime.tryParse(m['transaction_date'].toString());
    }
    transactionDate ??= mergedExtra['transaction_date'] != null
        ? DateTime.tryParse(mergedExtra['transaction_date'].toString())
        : null;

    return AccountLine(
      id: (m['id'] as num?)?.toInt() ?? 0,
      accountId: (m['account_id'] as num?)?.toInt() ?? 0,
      accountName: m['account_name'] as String? ?? '',
      accountCode: m['account_code'] as String? ?? '',
      accountType: m['account_type'] as String?,
      amount: _jsonAmountToDouble(m['amount']),
      description: m['description'] as String?,
      transactionType: transactionType,
      transactionDate: transactionDate,
      commission: _jsonAmountToDoubleNullable(m['commission'] ?? mergedExtra['commission']),
      extraInfo: mergedExtra.isEmpty && m['extra_info'] == null ? null : mergedExtra,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'account_id': accountId,
      'account_name': accountName,
      'account_code': accountCode,
      'account_type': accountType,
      'amount': amount,
      'description': description,
      'transaction_type': transactionType,
      'transaction_date': transactionDate?.toIso8601String(),
      'commission': commission,
      'extra_info': extraInfo,
    };
  }
}

/// مدل سند دریافت/پرداخت
class ReceiptPaymentDocument {
  final int id;
  final String code;
  final int businessId;
  final String documentType; // 'receipt' or 'payment'
  final DateTime documentDate;
  final DateTime registeredAt;
  final int currencyId;
  final String? currencyCode;
  final int createdByUserId;
  final String? createdByName;
  final bool isProforma;
  final String? description;
  final int? projectId;
  final String? projectName;
  final Map<String, dynamic>? extraInfo;
  final List<PersonLine> personLines;
  final List<AccountLine> accountLines;
  final String? personNames;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ReceiptPaymentDocument({
    required this.id,
    required this.code,
    required this.businessId,
    required this.documentType,
    required this.documentDate,
    required this.registeredAt,
    required this.currencyId,
    this.currencyCode,
    required this.createdByUserId,
    this.createdByName,
    required this.isProforma,
    this.description,
    this.projectId,
    this.projectName,
    this.extraInfo,
    required this.personLines,
    required this.accountLines,
    this.personNames,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ReceiptPaymentDocument.fromJson(Map<String, dynamic> json) {
    return ReceiptPaymentDocument(
      id: json['id'] ?? 0,
      code: json['code'] ?? '',
      businessId: json['business_id'] ?? 0,
      documentType: json['document_type'] ?? '',
      documentDate: DateTime.tryParse(json['document_date'] ?? '') ?? DateTime.now(),
      registeredAt: DateTime.tryParse(json['registered_at'] ?? '') ?? DateTime.now(),
      currencyId: json['currency_id'] ?? 0,
      currencyCode: json['currency_code'],
      createdByUserId: json['created_by_user_id'] ?? 0,
      createdByName: json['created_by_name'],
      isProforma: json['is_proforma'] ?? false,
      description: json['description'],
      projectId: json['project_id'],
      projectName: json['project_name'],
      extraInfo: json['extra_info'],
      personLines: (json['person_lines'] as List<dynamic>?)
              ?.map((dynamic item) => PersonLine.fromJson(item))
              .toList() ??
          [],
      accountLines: (json['account_lines'] as List<dynamic>?)
              ?.map((dynamic item) => AccountLine.fromJson(item))
              .toList() ??
          [],
      personNames: json['person_names'],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'business_id': businessId,
      'document_type': documentType,
      'document_date': documentDate.toIso8601String(),
      'registered_at': registeredAt.toIso8601String(),
      'currency_id': currencyId,
      'currency_code': currencyCode,
      'created_by_user_id': createdByUserId,
      'created_by_name': createdByName,
      'is_proforma': isProforma,
      'description': description,
      if (projectId != null) 'project_id': projectId,
      if (projectName != null) 'project_name': projectName,
      'extra_info': extraInfo,
      'person_lines': personLines.map((item) => item.toJson()).toList(),
      'account_lines': accountLines.map((item) => item.toJson()).toList(),
      'person_names': personNames,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// محاسبه مجموع مبلغ کل
  double get totalAmount {
    return personLines.fold(0.0, (sum, line) => sum + line.amount);
  }

  /// تعداد خطوط اشخاص
  int get personLinesCount => personLines.length;

  /// تعداد خطوط حساب‌ها
  int get accountLinesCount => accountLines.length;

  /// آیا سند دریافت است؟
  bool get isReceipt => documentType == 'receipt';

  /// آیا سند پرداخت است؟
  bool get isPayment => documentType == 'payment';

  /// دریافت نام نوع سند
  String get documentTypeName {
    switch (documentType) {
      case 'receipt':
        return 'دریافت';
      case 'payment':
        return 'پرداخت';
      default:
        return documentType;
    }
  }
}
