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

  /// شناسه و نوع تفصیل حساب انتخاب‌شده (مثل person_id یا product_id).
  final String? detailType;
  final String? detailId;
  final String? detailName;
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

  /// تأیید صریح اختلاف تسعیر بزرگ (>۲۵٪) برای عبور از گارد بک‌اند.
  final bool allowLargeFxDiff;

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
    this.detailType,
    this.detailId,
    this.detailName,
    required this.transactionDate,
    required this.amount,
    this.commission,
    this.description,
    this.settlesAmount,
    this.fxRate,
    this.paymentCurrencyId,
    this.allowLargeFxDiff = false,
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
    String? detailType,
    String? detailId,
    String? detailName,
    DateTime? transactionDate,
    num? amount,
    num? commission,
    String? description,
    Object? settlesAmount = _unset,
    Object? fxRate = _unset,
    Object? paymentCurrencyId = _unset,
    bool? allowLargeFxDiff,
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
      detailType: detailType ?? this.detailType,
      detailId: detailId ?? this.detailId,
      detailName: detailName ?? this.detailName,
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
      allowLargeFxDiff: allowLargeFxDiff ?? this.allowLargeFxDiff,
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
    final detailKey = _detailKeyForType(detailType);
    if (detailKey != null && detailId != null) {
      map[detailKey] = int.tryParse(detailId!) ?? detailId;
    }
    if (detailName != null) map['detail_name'] = detailName;
    if (settlesAmount != null) {
      map['settles_amount'] = settlesAmount;
    }
    if (fxRate != null) {
      map['fx_rate'] = fxRate;
    }
    if (paymentCurrencyId != null) {
      map['payment_currency_id'] = paymentCurrencyId;
    }
    if (allowLargeFxDiff) {
      map['allow_large_fx_diff'] = true;
    }
    return map;
  }

  /// برای فاکتور ارزی، اگر کلاینت settles را جا انداخته باشد، از amount پر می‌کند
  /// تا بک‌اند SETTLES_AMOUNT_REQUIRED ندهد (تبدیل نرخ در بک‌اند انجام می‌شود).
  Map<String, dynamic> toPaymentPayload({
    int? invoiceCurrencyId,
    int? baseCurrencyId,
    num? invoiceFxRate,
  }) {
    final map = toJson();
    final foreignInvoice =
        invoiceCurrencyId != null &&
        baseCurrencyId != null &&
        invoiceCurrencyId != baseCurrencyId;
    if (foreignInvoice) {
      map.putIfAbsent('settles_amount', () => settlesAmount ?? amount);
      if (map['fx_rate'] == null &&
          invoiceFxRate != null &&
          invoiceFxRate > 0) {
        map['fx_rate'] = invoiceFxRate;
      }
    }
    return map;
  }

  factory InvoiceTransaction.fromJson(Map<String, dynamic> json) {
    return InvoiceTransaction(
      id: json['id'] as String,
      type:
          TransactionType.fromValue(json['type'] as String) ??
          TransactionType.person,
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
      detailType: json['detail_type'] as String? ?? _detailTypeFromJson(json),
      detailId: _detailIdFromJson(json)?.toString(),
      detailName:
          json['detail_name'] as String? ??
          json['person_name'] as String? ??
          json['product_name'] as String? ??
          json['bank_account_name'] as String? ??
          json['cash_register_name'] as String? ??
          json['petty_cash_name'] as String? ??
          json['check_number'] as String?,
      transactionDate: DateTime.parse(json['transaction_date'] as String),
      amount: json['amount'] as num,
      commission: json['commission'] as num?,
      description: json['description'] as String?,
      settlesAmount: json['settles_amount'] as num?,
      fxRate: json['fx_rate'] as num? ?? json['exchange_rate'] as num?,
      paymentCurrencyId: (json['payment_currency_id'] as num?)?.toInt(),
      allowLargeFxDiff: json['allow_large_fx_diff'] == true,
    );
  }
}

const Object _unset = Object();

String? _detailKeyForType(String? type) => switch (type) {
  'person' => 'person_id',
  'product' => 'product_id',
  'bank_account' => 'bank_account_id',
  'cash_register' => 'cash_register_id',
  'petty_cash' => 'petty_cash_id',
  'check' => 'check_id',
  _ => null,
};

String? _detailTypeFromJson(Map<String, dynamic> json) {
  if (json['type'] != 'account') return null;
  for (final type in [
    'person',
    'product',
    'bank_account',
    'cash_register',
    'petty_cash',
    'check',
  ]) {
    if (json['${type}_id'] != null) return type;
  }
  return null;
}

dynamic _detailIdFromJson(Map<String, dynamic> json) {
  final key = _detailKeyForType(
    json['detail_type'] as String? ?? _detailTypeFromJson(json),
  );
  return key == null ? null : json[key];
}
