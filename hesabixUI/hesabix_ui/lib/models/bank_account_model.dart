class BankAccount {
  final int? id;
  final int businessId;
  final String? code;
  final String name;
  final String? branch;
  final String? accountNumber;
  final String? shebaNumber;
  final String? cardNumber;
  final String? ownerName;
  final String? posNumber;
  final int currencyId;
  final String? paymentId;
  final String? description;
  final bool isActive;
  final bool isDefault;
  final double? balance;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BankAccount({
    this.id,
    required this.businessId,
    this.code,
    required this.name,
    this.branch,
    this.accountNumber,
    this.shebaNumber,
    this.cardNumber,
    this.ownerName,
    this.posNumber,
    required this.currencyId,
    this.paymentId,
    this.description,
    this.isActive = true,
    this.isDefault = false,
    this.balance,
    this.createdAt,
    this.updatedAt,
  });

  factory BankAccount.fromJson(Map<String, dynamic> json) {
    return BankAccount(
      id: json['id'] as int?,
      businessId: (json['business_id'] ?? json['businessId']) as int,
      code: json['code'] as String?,
      name: (json['name'] ?? '') as String,
      branch: json['branch'] as String?,
      accountNumber: json['account_number'] as String?,
      shebaNumber: json['sheba_number'] as String?,
      cardNumber: json['card_number'] as String?,
      ownerName: json['owner_name'] as String?,
      posNumber: json['pos_number'] as String?,
      currencyId: (json['currency_id'] ?? json['currencyId']) as int,
      paymentId: json['payment_id'] as String?,
      description: json['description'] as String?,
      isActive: (json['is_active'] ?? true) as bool,
      isDefault: (json['is_default'] ?? false) as bool,
      balance: json['balance'] != null ? (json['balance'] is num ? (json['balance'] as num).toDouble() : double.tryParse(json['balance'].toString())) : null,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'business_id': businessId,
      'code': code,
      'name': name,
      'branch': branch,
      'account_number': accountNumber,
      'sheba_number': shebaNumber,
      'card_number': cardNumber,
      'owner_name': ownerName,
      'pos_number': posNumber,
      'currency_id': currencyId,
      'payment_id': paymentId,
      'description': description,
      'is_active': isActive,
      'is_default': isDefault,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}


