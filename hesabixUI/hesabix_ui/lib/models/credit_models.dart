class CreditSettings {
  final int businessId;
  bool isEnabled;
  double? defaultLimit;
  int? graceDays;
  double? lateFeeRate;
  int? autoBlockAfterDays;
  String strategy;

  CreditSettings({
    required this.businessId,
    required this.isEnabled,
    this.defaultLimit,
    this.graceDays,
    this.lateFeeRate,
    this.autoBlockAfterDays,
    this.strategy = 'single-default',
  });

  factory CreditSettings.fromJson(Map<String, dynamic> json) {
    return CreditSettings(
      businessId: json['business_id'] is String ? int.parse(json['business_id']) : (json['business_id'] ?? 0),
      isEnabled: json['is_enabled'] == true,
      defaultLimit: json['default_limit'] == null ? null : (json['default_limit'] as num).toDouble(),
      graceDays: json['grace_days'],
      lateFeeRate: json['late_fee_rate'] == null ? null : (json['late_fee_rate'] as num).toDouble(),
      autoBlockAfterDays: json['auto_block_after_days'],
      strategy: (json['strategy'] ?? 'single-default').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'is_enabled': isEnabled,
      'default_limit': defaultLimit,
      'grace_days': graceDays,
      'late_fee_rate': lateFeeRate,
      'auto_block_after_days': autoBlockAfterDays,
      'strategy': strategy,
    };
  }
}

class InstallmentPlan {
  final int id;
  final int businessId;
  String name;
  String method;
  int numInstallments;
  int periodDays;
  double? downPaymentPercent;
  double? interestRate;
  double? lateFeeRate;
  double? issueFee;
  String? description;
  bool isActive;

  InstallmentPlan({
    required this.id,
    required this.businessId,
    required this.name,
    required this.method,
    required this.numInstallments,
    required this.periodDays,
    this.downPaymentPercent,
    this.interestRate,
    this.lateFeeRate,
    this.issueFee,
    this.description,
    required this.isActive,
  });

  factory InstallmentPlan.fromJson(Map<String, dynamic> json) {
    return InstallmentPlan(
      id: json['id'] is String ? int.parse(json['id']) : (json['id'] ?? 0),
      businessId: json['business_id'] is String ? int.parse(json['business_id']) : (json['business_id'] ?? 0),
      name: (json['name'] ?? '').toString(),
      method: (json['method'] ?? 'flat').toString(),
      numInstallments: json['num_installments'] is String ? int.parse(json['num_installments']) : (json['num_installments'] ?? 0),
      periodDays: json['period_days'] is String ? int.parse(json['period_days']) : (json['period_days'] ?? 30),
      downPaymentPercent: json['down_payment_percent'] == null ? null : (json['down_payment_percent'] as num).toDouble(),
      interestRate: json['interest_rate'] == null ? null : (json['interest_rate'] as num).toDouble(),
      lateFeeRate: json['late_fee_rate'] == null ? null : (json['late_fee_rate'] as num).toDouble(),
      issueFee: json['issue_fee'] == null ? null : (json['issue_fee'] as num).toDouble(),
      description: json['description'],
      isActive: json['is_active'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'method': method,
      'num_installments': numInstallments,
      'period_days': periodDays,
      'down_payment_percent': downPaymentPercent,
      'interest_rate': interestRate,
      'late_fee_rate': lateFeeRate,
      'issue_fee': issueFee,
      'description': description,
      'is_active': isActive,
    };
  }
}


