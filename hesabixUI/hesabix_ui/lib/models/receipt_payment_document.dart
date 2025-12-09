
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

  factory PersonLine.fromJson(Map<String, dynamic> json) {
    return PersonLine(
      id: json['id'] ?? 0,
      personId: json['person_id'],
      personName: json['person_name'],
      amount: (json['amount'] ?? 0).toDouble(),
      description: json['description'],
      extraInfo: json['extra_info'],
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

  factory AccountLine.fromJson(Map<String, dynamic> json) {
    return AccountLine(
      id: json['id'] ?? 0,
      accountId: json['account_id'] ?? 0,
      accountName: json['account_name'] ?? '',
      accountCode: json['account_code'] ?? '',
      accountType: json['account_type'],
      amount: (json['amount'] ?? 0).toDouble(),
      description: json['description'],
      transactionType: json['transaction_type'],
      transactionDate: json['transaction_date'] != null 
          ? DateTime.tryParse(json['transaction_date']) 
          : null,
      commission: json['commission']?.toDouble(),
      extraInfo: json['extra_info'],
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
          ?.map((item) => PersonLine.fromJson(item))
          .toList() ?? [],
      accountLines: (json['account_lines'] as List<dynamic>?)
          ?.map((item) => AccountLine.fromJson(item))
          .toList() ?? [],
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
