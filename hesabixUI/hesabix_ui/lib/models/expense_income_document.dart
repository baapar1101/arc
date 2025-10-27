import 'package:hesabix_ui/models/account_model.dart';

/// مدل سند هزینه/درآمد
class ExpenseIncomeDocument {
  final int id;
  final String code;
  final String documentType; // "expense" یا "income"
  final String documentTypeName; // "هزینه" یا "درآمد"
  final DateTime documentDate;
  final int currencyId;
  final String? currencyCode;
  final double totalAmount;
  final String? description;
  final List<ItemLine> itemLines;
  final List<CounterpartyLine> counterpartyLines;
  final int itemLinesCount;
  final int counterpartyLinesCount;
  final String? createdByName;
  final DateTime registeredAt;
  final Map<String, dynamic>? extraInfo;

  const ExpenseIncomeDocument({
    required this.id,
    required this.code,
    required this.documentType,
    required this.documentTypeName,
    required this.documentDate,
    required this.currencyId,
    this.currencyCode,
    required this.totalAmount,
    this.description,
    required this.itemLines,
    required this.counterpartyLines,
    required this.itemLinesCount,
    required this.counterpartyLinesCount,
    this.createdByName,
    required this.registeredAt,
    this.extraInfo,
  });

  /// آیا این سند درآمد است؟
  bool get isIncome => documentType == 'income';

  /// آیا این سند هزینه است؟
  bool get isExpense => documentType == 'expense';

  /// نام حساب‌های آیتم‌ها
  String? get itemAccountNames {
    if (itemLines.isEmpty) return null;
    return itemLines.map((line) => line.accountName).join(', ');
  }

  /// اطلاعات طرف‌حساب‌ها
  String? get counterpartyInfo {
    if (counterpartyLines.isEmpty) return null;
    return counterpartyLines.map((line) => line.displayName).join(', ');
  }

  factory ExpenseIncomeDocument.fromJson(Map<String, dynamic> json) {
    return ExpenseIncomeDocument(
      id: json['id'] as int,
      code: json['code'] as String,
      documentType: json['document_type'] as String,
      documentTypeName: json['document_type_name'] as String? ?? 
          (json['document_type'] == 'income' ? 'درآمد' : 'هزینه'),
      documentDate: DateTime.parse(json['document_date'] as String),
      currencyId: json['currency_id'] as int,
      currencyCode: json['currency_code'] as String?,
      totalAmount: (json['total_amount'] as num).toDouble(),
      description: json['description'] as String?,
      itemLines: (json['item_lines'] as List<dynamic>?)
          ?.map((line) => ItemLine.fromJson(line as Map<String, dynamic>))
          .toList() ?? [],
      counterpartyLines: (json['counterparty_lines'] as List<dynamic>?)
          ?.map((line) => CounterpartyLine.fromJson(line as Map<String, dynamic>))
          .toList() ?? [],
      itemLinesCount: json['item_lines_count'] as int? ?? 0,
      counterpartyLinesCount: json['counterparty_lines_count'] as int? ?? 0,
      createdByName: json['created_by_name'] as String?,
      registeredAt: DateTime.parse(json['registered_at'] as String),
      extraInfo: json['extra_info'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'document_type': documentType,
      'document_type_name': documentTypeName,
      'document_date': documentDate.toIso8601String(),
      'currency_id': currencyId,
      'currency_code': currencyCode,
      'total_amount': totalAmount,
      'description': description,
      'item_lines': itemLines.map((line) => line.toJson()).toList(),
      'counterparty_lines': counterpartyLines.map((line) => line.toJson()).toList(),
      'item_lines_count': itemLinesCount,
      'counterparty_lines_count': counterpartyLinesCount,
      'created_by_name': createdByName,
      'registered_at': registeredAt.toIso8601String(),
      'extra_info': extraInfo,
    };
  }
}

/// خط آیتم (حساب هزینه/درآمد)
class ItemLine {
  final int id;
  final int accountId;
  final String accountCode;
  final String accountName;
  final double amount;
  final String? description;

  const ItemLine({
    required this.id,
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.amount,
    this.description,
  });

  factory ItemLine.fromJson(Map<String, dynamic> json) {
    return ItemLine(
      id: json['id'] as int,
      accountId: json['account_id'] as int,
      accountCode: json['account_code'] as String,
      accountName: json['account_name'] as String,
      amount: (json['amount'] as num).toDouble(),
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'account_id': accountId,
      'account_code': accountCode,
      'account_name': accountName,
      'amount': amount,
      'description': description,
    };
  }
}

/// خط طرف‌حساب
class CounterpartyLine {
  final int id;
  final String transactionType;
  final String transactionTypeName;
  final double amount;
  final DateTime transactionDate;
  final String? description;
  final double? commission;
  
  // فیلدهای اختیاری بر اساس نوع تراکنش
  final int? bankAccountId;
  final String? bankAccountName;
  final int? cashRegisterId;
  final String? cashRegisterName;
  final int? pettyCashId;
  final String? pettyCashName;
  final int? checkId;
  final String? checkNumber;
  final int? personId;
  final String? personName;

  const CounterpartyLine({
    required this.id,
    required this.transactionType,
    required this.transactionTypeName,
    required this.amount,
    required this.transactionDate,
    this.description,
    this.commission,
    this.bankAccountId,
    this.bankAccountName,
    this.cashRegisterId,
    this.cashRegisterName,
    this.pettyCashId,
    this.pettyCashName,
    this.checkId,
    this.checkNumber,
    this.personId,
    this.personName,
  });

  /// نام نمایشی طرف‌حساب
  String get displayName {
    switch (transactionType) {
      case 'bank':
        return bankAccountName ?? 'حساب بانکی';
      case 'cash_register':
        return cashRegisterName ?? 'صندوق';
      case 'petty_cash':
        return pettyCashName ?? 'تنخواهگردان';
      case 'check':
        return checkNumber != null ? 'چک $checkNumber' : 'چک';
      case 'person':
        return personName ?? 'شخص';
      default:
        return transactionTypeName;
    }
  }

  factory CounterpartyLine.fromJson(Map<String, dynamic> json) {
    return CounterpartyLine(
      id: json['id'] as int,
      transactionType: json['transaction_type'] as String,
      transactionTypeName: json['transaction_type_name'] as String? ?? 
          _getTransactionTypeName(json['transaction_type'] as String),
      amount: (json['amount'] as num).toDouble(),
      transactionDate: DateTime.parse(json['transaction_date'] as String),
      description: json['description'] as String?,
      commission: json['commission'] != null ? (json['commission'] as num).toDouble() : null,
      bankAccountId: json['bank_account_id'] as int?,
      bankAccountName: json['bank_account_name'] as String?,
      cashRegisterId: json['cash_register_id'] as int?,
      cashRegisterName: json['cash_register_name'] as String?,
      pettyCashId: json['petty_cash_id'] as int?,
      pettyCashName: json['petty_cash_name'] as String?,
      checkId: json['check_id'] as int?,
      checkNumber: json['check_number'] as String?,
      personId: json['person_id'] as int?,
      personName: json['person_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'transaction_type': transactionType,
      'transaction_type_name': transactionTypeName,
      'amount': amount,
      'transaction_date': transactionDate.toIso8601String(),
      'description': description,
      'commission': commission,
      'bank_account_id': bankAccountId,
      'bank_account_name': bankAccountName,
      'cash_register_id': cashRegisterId,
      'cash_register_name': cashRegisterName,
      'petty_cash_id': pettyCashId,
      'petty_cash_name': pettyCashName,
      'check_id': checkId,
      'check_number': checkNumber,
      'person_id': personId,
      'person_name': personName,
    };
  }

  static String _getTransactionTypeName(String type) {
    switch (type) {
      case 'bank':
        return 'بانک';
      case 'cash_register':
        return 'صندوق';
      case 'petty_cash':
        return 'تنخواهگردان';
      case 'check':
        return 'چک';
      case 'person':
        return 'شخص';
      default:
        return type;
    }
  }
}

/// نوع تراکنش برای فرم
enum TransactionType {
  bank('bank', 'بانک'),
  cashRegister('cash_register', 'صندوق'),
  pettyCash('petty_cash', 'تنخواهگردان'),
  check('check', 'چک'),
  person('person', 'شخص');

  const TransactionType(this.value, this.displayName);
  
  final String value;
  final String displayName;

  static TransactionType? fromValue(String value) {
    for (final type in TransactionType.values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// داده‌های خط آیتم برای فرم
class ItemLineData {
  final int? accountId;
  final String? accountName;
  final double amount;
  final String? description;

  const ItemLineData({
    this.accountId,
    this.accountName,
    required this.amount,
    this.description,
  });

  ItemLineData copyWith({
    int? accountId,
    String? accountName,
    double? amount,
    String? description,
  }) {
    return ItemLineData(
      accountId: accountId ?? this.accountId,
      accountName: accountName ?? this.accountName,
      amount: amount ?? this.amount,
      description: description ?? this.description,
    );
  }
}

/// داده‌های خط طرف‌حساب برای فرم
class CounterpartyLineData {
  final TransactionType transactionType;
  final double amount;
  final DateTime transactionDate;
  final String? description;
  final double? commission;
  
  // فیلدهای اختیاری بر اساس نوع تراکنش
  final int? bankAccountId;
  final String? bankAccountName;
  final int? cashRegisterId;
  final String? cashRegisterName;
  final int? pettyCashId;
  final String? pettyCashName;
  final int? checkId;
  final String? checkNumber;
  final int? personId;
  final String? personName;

  const CounterpartyLineData({
    required this.transactionType,
    required this.amount,
    required this.transactionDate,
    this.description,
    this.commission,
    this.bankAccountId,
    this.bankAccountName,
    this.cashRegisterId,
    this.cashRegisterName,
    this.pettyCashId,
    this.pettyCashName,
    this.checkId,
    this.checkNumber,
    this.personId,
    this.personName,
  });

  CounterpartyLineData copyWith({
    TransactionType? transactionType,
    double? amount,
    DateTime? transactionDate,
    String? description,
    double? commission,
    int? bankAccountId,
    String? bankAccountName,
    int? cashRegisterId,
    String? cashRegisterName,
    int? pettyCashId,
    String? pettyCashName,
    int? checkId,
    String? checkNumber,
    int? personId,
    String? personName,
  }) {
    return CounterpartyLineData(
      transactionType: transactionType ?? this.transactionType,
      amount: amount ?? this.amount,
      transactionDate: transactionDate ?? this.transactionDate,
      description: description ?? this.description,
      commission: commission ?? this.commission,
      bankAccountId: bankAccountId ?? this.bankAccountId,
      bankAccountName: bankAccountName ?? this.bankAccountName,
      cashRegisterId: cashRegisterId ?? this.cashRegisterId,
      cashRegisterName: cashRegisterName ?? this.cashRegisterName,
      pettyCashId: pettyCashId ?? this.pettyCashId,
      pettyCashName: pettyCashName ?? this.pettyCashName,
      checkId: checkId ?? this.checkId,
      checkNumber: checkNumber ?? this.checkNumber,
      personId: personId ?? this.personId,
      personName: personName ?? this.personName,
    );
  }
}
