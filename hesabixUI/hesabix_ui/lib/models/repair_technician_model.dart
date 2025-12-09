/// مدل تعمیرکار
class RepairTechnician {
  final int id;
  final int businessId;
  final int personId;
  final String personName;
  final String code;
  final String commissionType; // fixed, percentage, case_by_case
  final double commissionValue;
  final bool isActive;
  final Map<String, dynamic> extraInfo;

  RepairTechnician({
    required this.id,
    required this.businessId,
    required this.personId,
    required this.personName,
    required this.code,
    required this.commissionType,
    required this.commissionValue,
    required this.isActive,
    required this.extraInfo,
  });

  factory RepairTechnician.fromJson(Map<String, dynamic> json) {
    return RepairTechnician(
      id: json['id'] as int,
      businessId: json['business_id'] as int,
      personId: json['person_id'] as int,
      personName: json['person_name'] as String,
      code: json['code'] as String,
      commissionType: json['commission_type'] as String,
      commissionValue: (json['commission_value'] as num).toDouble(),
      isActive: json['is_active'] as bool,
      extraInfo: (json['extra_info'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'business_id': businessId,
      'person_id': personId,
      'person_name': personName,
      'code': code,
      'commission_type': commissionType,
      'commission_value': commissionValue,
      'is_active': isActive,
      'extra_info': extraInfo,
    };
  }

  RepairTechnician copyWith({
    int? id,
    int? businessId,
    int? personId,
    String? personName,
    String? code,
    String? commissionType,
    double? commissionValue,
    bool? isActive,
    Map<String, dynamic>? extraInfo,
  }) {
    return RepairTechnician(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      personId: personId ?? this.personId,
      personName: personName ?? this.personName,
      code: code ?? this.code,
      commissionType: commissionType ?? this.commissionType,
      commissionValue: commissionValue ?? this.commissionValue,
      isActive: isActive ?? this.isActive,
      extraInfo: extraInfo ?? this.extraInfo,
    );
  }

  /// دریافت لیبل نوع حق‌الزحمه به فارسی
  String get commissionTypeLabel {
    switch (commissionType) {
      case 'fixed':
        return 'مبلغ ثابت';
      case 'percentage':
        return 'درصدی';
      case 'case_by_case':
        return 'موردی';
      default:
        return commissionType;
    }
  }

  /// فرمت حق‌الزحمه برای نمایش (با واحد ارز)
  String formattedCommission({String currencySymbol = 'تومان'}) {
    if (commissionType == 'percentage') {
      return '$commissionValue%';
    } else if (commissionType == 'fixed') {
      return '${commissionValue.toStringAsFixed(0)} $currencySymbol';
    } else {
      return 'موردی';
    }
  }
}

