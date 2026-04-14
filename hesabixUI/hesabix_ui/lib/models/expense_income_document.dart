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
  final int? projectId;
  final String? projectName;
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
    this.projectId,
    this.projectName,
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
    // نوع سند
    final String docType = (json['document_type'] as String?) ?? 'expense';
    // تاریخ سند
    final DateTime docDate = _safeParseDate(json['document_date']) ?? DateTime.now();
    // registered_at ممکن است در پاسخ لیست نباشد؛ در این صورت از document_date استفاده می‌کنیم
    final DateTime regAt = _safeParseDate(json['registered_at']) ?? docDate;

    // خطوط آیتم: پشتیبانی از دو شکل different: item_lines (جدید) یا items (قدیمی/دیگر لیست‌ها)
    final List<ItemLine> parsedItemLines = (() {
      final dynamic il = json['item_lines'];
      if (il is List) {
        return il
            .whereType<Map<String, dynamic>>()
            .map((m) => ItemLine.fromJson(m))
            .toList();
      }
      final dynamic legacyItems = json['items'];
      if (legacyItems is List) {
        return legacyItems.whereType<Map<String, dynamic>>().map((m) {
          // بعضی پاسخ‌ها debit/credit دارند؛ amount را بیشینه این دو می‌گیریم
          final num debit = (m['debit'] as num?) ?? 0;
          final num credit = (m['credit'] as num?) ?? 0;
          final double amount = (debit.abs() > credit.abs() ? debit : credit).toDouble();
          return ItemLine(
            id: (m['id'] as int?) ?? 0,
            accountId: (m['account_id'] as int?) ?? 0,
            accountCode: (m['account_code'] as String?) ?? '',
            accountName: (m['account_name'] as String?) ?? 'حساب',
            amount: amount,
            description: m['description'] as String?,
          );
        }).toList();
      }
      return <ItemLine>[];
    })();

    // خطوط طرف‌حساب: پشتیبانی از counterparty_lines یا counterparties + extra_info
    final List<CounterpartyLine> parsedCounterpartyLines = (() {
      final dynamic cl = json['counterparty_lines'];
      if (cl is List) {
        return cl
            .whereType<Map<String, dynamic>>()
            .map((m) => CounterpartyLine.fromJson(m))
            .toList();
      }
      final dynamic legacy = json['counterparties'];
      if (legacy is List) {
        return legacy.whereType<Map<String, dynamic>>().map((m) {
          final num debit = (m['debit'] as num?) ?? 0;
          final num credit = (m['credit'] as num?) ?? 0;
          final double amount = (debit.abs() > credit.abs() ? debit : credit).toDouble();
          final Map<String, dynamic> extra = (m['extra_info'] as Map<String, dynamic>?) ?? const {};
          final String txType = (extra['transaction_type'] as String?) ?? 'account';
          final DateTime txDate = _safeParseDate(extra['transaction_date']) ?? docDate;
          return CounterpartyLine(
            id: (m['id'] as int?) ?? 0,
            transactionType: txType,
            transactionTypeName: CounterpartyLine._getTransactionTypeName(txType),
            amount: amount,
            transactionDate: txDate,
            description: m['description'] as String?,
            commission: null,
            bankAccountId: m['bank_account_id'] as int? ?? extra['bank_account_id'] as int?,
            bankAccountName: extra['bank_account_name'] as String?,
            cashRegisterId: m['cash_register_id'] as int? ?? extra['cash_register_id'] as int?,
            cashRegisterName: extra['cash_register_name'] as String?,
            pettyCashId: m['petty_cash_id'] as int? ?? extra['petty_cash_id'] as int?,
            pettyCashName: extra['petty_cash_name'] as String?,
            checkId: m['check_id'] as int?,
            checkNumber: extra['check_number'] as String?,
            personId: m['person_id'] as int? ?? extra['person_id'] as int?,
            personName: extra['person_name'] as String?,
            accountId: m['account_id'] as int?,
            accountName: m['account_name'] as String?,
          );
        }).toList();
      }
      return <CounterpartyLine>[];
    })();

    // مبلغ کل: اگر total_amount نبود، از جمع مبالغ خطوط می‌سازیم
    final double totalAmount = (() {
      final num? ta = json['total_amount'] as num?;
      if (ta != null) return ta.toDouble();
      if (parsedItemLines.isNotEmpty) {
        return parsedItemLines.fold<double>(0, (sum, l) => sum + l.amount);
      }
      if (parsedCounterpartyLines.isNotEmpty) {
        return parsedCounterpartyLines.fold<double>(0, (sum, l) => sum + l.amount);
      }
      return 0.0;
    })();

    return ExpenseIncomeDocument(
      id: json['id'] as int,
      code: (json['code'] as String?) ?? '',
      documentType: docType,
      documentTypeName: (json['document_type_name'] as String?) ??
          (docType == 'income' ? 'درآمد' : 'هزینه'),
      documentDate: docDate,
      currencyId: (json['currency_id'] as int?) ?? 0,
      currencyCode: json['currency_code'] as String?,
      totalAmount: totalAmount,
      description: json['description'] as String?,
      projectId: json['project_id'] as int?,
      projectName: json['project_name'] as String?,
      itemLines: parsedItemLines,
      counterpartyLines: parsedCounterpartyLines,
      itemLinesCount: (json['item_lines_count'] as int?) ?? parsedItemLines.length,
      counterpartyLinesCount:
          (json['counterparty_lines_count'] as int?) ?? parsedCounterpartyLines.length,
      createdByName: json['created_by_name'] as String?,
      registeredAt: regAt,
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
      if (projectId != null) 'project_id': projectId,
      if (projectName != null) 'project_name': projectName,
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

DateTime? _safeParseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) {
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }
  return null;
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
  final int? accountId;
  final String? accountName;

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
    this.accountId,
    this.accountName,
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
      case 'check_expense':
        return checkNumber != null ? 'خرج چک $checkNumber' : 'خرج چک';
      case 'person':
        return personName ?? 'شخص';
      case 'account':
        return accountName ?? 'حساب';
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
      accountId: json['account_id'] as int?,
      accountName: json['account_name'] as String?,
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
      'account_id': accountId,
      'account_name': accountName,
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
      case 'check_expense':
        return 'خرج چک';
      case 'person':
        return 'شخص';
      case 'account':
        return 'حساب';
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
  checkExpense('check_expense', 'خرج چک'),
  person('person', 'شخص'),
  account('account', 'حساب');

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
  final int? accountId;
  final String? accountName;

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
    this.accountId,
    this.accountName,
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
    int? accountId,
    String? accountName,
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
      accountId: accountId ?? this.accountId,
      accountName: accountName ?? this.accountName,
    );
  }
}
