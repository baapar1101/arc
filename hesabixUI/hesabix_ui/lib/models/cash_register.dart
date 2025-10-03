class CashRegister {
  final int? id;
  final int businessId;
  final String name;
  final String? code;
  final int currencyId;
  final bool isActive;
  final bool isDefault;
  final String? description;
  final String? paymentSwitchNumber;
  final String? paymentTerminalNumber;
  final String? merchantId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CashRegister({
    this.id,
    required this.businessId,
    required this.name,
    this.code,
    required this.currencyId,
    this.isActive = true,
    this.isDefault = false,
    this.description,
    this.paymentSwitchNumber,
    this.paymentTerminalNumber,
    this.merchantId,
    this.createdAt,
    this.updatedAt,
  });

  factory CashRegister.fromJson(Map<String, dynamic> json) {
    return CashRegister(
      id: json['id'] as int?,
      businessId: (json['business_id'] ?? json['businessId']) as int,
      name: (json['name'] ?? '') as String,
      code: json['code'] as String?,
      currencyId: (json['currency_id'] ?? json['currencyId']) as int,
      isActive: (json['is_active'] ?? true) as bool,
      isDefault: (json['is_default'] ?? false) as bool,
      description: json['description'] as String?,
      paymentSwitchNumber: json['payment_switch_number'] as String?,
      paymentTerminalNumber: json['payment_terminal_number'] as String?,
      merchantId: json['merchant_id'] as String?,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'business_id': businessId,
      'name': name,
      'code': code,
      'currency_id': currencyId,
      'is_active': isActive,
      'is_default': isDefault,
      'description': description,
      'payment_switch_number': paymentSwitchNumber,
      'payment_terminal_number': paymentTerminalNumber,
      'merchant_id': merchantId,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}
