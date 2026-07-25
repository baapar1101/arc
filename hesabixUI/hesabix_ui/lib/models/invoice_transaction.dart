enum TransactionType {
  bank('bank', 'بانک'),
  cashRegister('cash_register', 'صندوق'),
  pettyCash('petty_cash', 'تنخواهگردان'),
  check('check', 'چک'),
  checkExpense('check_expense', 'خرج چک'),
  person('person', 'شخص'),
  account('account', 'حساب');

  const TransactionType(this.value, this.label);

  final String value;
  final String label;

  static TransactionType? fromValue(String value) {
    for (final type in TransactionType.values) {
      if (type.value == value) {
        return type;
      }
    }
    return null;
  }

  static List<TransactionType> get allTypes => TransactionType.values;
}

class InvoiceTransaction {
  final String id;
  final TransactionType type;
  final String? bankId;
  final String? bankName;
  final String? cashRegisterId;
  final String? cashRegisterName;
  final String? pettyCashId;
  final String? pettyCashName;
  final String? checkId;
  final String? checkNumber;
  final String? personId;
  final String? personName;
  final String? accountId;
  final String? accountName;
  final DateTime transactionDate;
  /// مبلغ واقعی پرداخت به ارز حساب پرداخت.
  final num amount;
  final num? commission;
  final String? description;
  /// مبلغ تسویه به ارز فاکتور (پرداخت بین‌ارزی).
  final num? settlesAmount;
  /// نرخ تبدیل تراکنش (۱ واحد ارز غیرپایه = rate × پایه / یا طبق قرارداد API).
  final num? fxRate;
  /// ارز حساب پرداخت (برای نمایش و تشخیص بین‌ارزی در UI).
  final int? paymentCurrencyId;

  const InvoiceTransaction({
    required this.id,
    required this.type,
    this.bankId,
    this.bankName,
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
    required this.transactionDate,
    required this.amount,
    this.commission,
    this.description,
    this.settlesAmount,
    this.fxRate,
    this.paymentCurrencyId,
  });

  /// مبلغ مؤثر برای مانده فاکتور (به ارز فاکتور).
  num get settlesAgainstInvoice => settlesAmount ?? amount;

  bool get isCrossCurrency =>
      settlesAmount != null && paymentCurrencyId != null;

  InvoiceTransaction copyWith({
    String? id,
    TransactionType? type,
    String? bankId,
    String? bankName,
    String? cashRegisterId,
    String? cashRegisterName,
    String? pettyCashId,
    String? pettyCashName,
    String? checkId,
    String? checkNumber,
    String? personId,
    String? personName,
    String? accountId,
    String? accountName,
    DateTime? transactionDate,
    num? amount,
    num? commission,
    String? description,
    Object? settlesAmount = _unset,
    Object? fxRate = _unset,
    Object? paymentCurrencyId = _unset,
  }) {
    return InvoiceTransaction(
      id: id ?? this.id,
      type: type ?? this.type,
      bankId: bankId ?? this.bankId,
      bankName: bankName ?? this.bankName,
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
      transactionDate: transactionDate ?? this.transactionDate,
      amount: amount ?? this.amount,
      commission: commission ?? this.commission,
      description: description ?? this.description,
      settlesAmount: identical(settlesAmount, _unset)
          ? this.settlesAmount
          : settlesAmount as num?,
      fxRate: identical(fxRate, _unset) ? this.fxRate : fxRate as num?,
      paymentCurrencyId: identical(paymentCurrencyId, _unset)
          ? this.paymentCurrencyId
          : paymentCurrencyId as int?,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'type': type.value,
      'bank_id': bankId,
      'bank_name': bankName,
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
      'transaction_date': transactionDate.toIso8601String(),
      'amount': amount,
      'commission': commission,
      'description': description,
    };
    if (settlesAmount != null) {
      map['settles_amount'] = settlesAmount;
    }
    if (fxRate != null) {
      map['fx_rate'] = fxRate;
    }
    if (paymentCurrencyId != null) {
      map['payment_currency_id'] = paymentCurrencyId;
    }
    return map;
  }

  factory InvoiceTransaction.fromJson(Map<String, dynamic> json) {
    return InvoiceTransaction(
      id: json['id'] as String,
      type: TransactionType.fromValue(json['type'] as String) ?? TransactionType.person,
      bankId: json['bank_id'] as String?,
      bankName: json['bank_name'] as String?,
      cashRegisterId: json['cash_register_id'] as String?,
      cashRegisterName: json['cash_register_name'] as String?,
      pettyCashId: json['petty_cash_id'] as String?,
      pettyCashName: json['petty_cash_name'] as String?,
      checkId: json['check_id'] as String?,
      checkNumber: json['check_number'] as String?,
      personId: json['person_id'] as String?,
      personName: json['person_name'] as String?,
      accountId: json['account_id'] as String?,
      accountName: json['account_name'] as String?,
      transactionDate: DateTime.parse(json['transaction_date'] as String),
      amount: json['amount'] as num,
      commission: json['commission'] as num?,
      description: json['description'] as String?,
      settlesAmount: json['settles_amount'] as num?,
      fxRate: json['fx_rate'] as num? ?? json['exchange_rate'] as num?,
      paymentCurrencyId: (json['payment_currency_id'] as num?)?.toInt(),
    );
  }
}

const Object _unset = Object();
