class Account {
  final int? id;
  final int? businessId; // nullable - برای حساب‌های عمومی
  final String name;
  final String code;
  final String accountType;
  final int? parentId;
  final String? description;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Account({
    this.id,
    this.businessId, // nullable شد
    required this.name,
    required this.code,
    required this.accountType,
    this.parentId,
    this.description,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'] as int?,
      businessId: json['business_id'] as int?, // nullable
      name: json['name'] as String,
      code: json['code'] as String,
      accountType: json['account_type'] as String,
      parentId: json['parent_id'] as int?,
      description: json['description'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'business_id': businessId,
      'name': name,
      'code': code,
      'account_type': accountType,
      'parent_id': parentId,
      'description': description,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Account copyWith({
    int? id,
    int? businessId,
    String? name,
    String? code,
    String? accountType,
    int? parentId,
    String? description,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Account(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      name: name ?? this.name,
      code: code ?? this.code,
      accountType: accountType ?? this.accountType,
      parentId: parentId ?? this.parentId,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// آیا این حساب یک حساب عمومی است؟
  bool get isGeneralAccount => businessId == null;

  /// نمایش نام کامل با کد
  String get displayName => '$code - $name';
}
