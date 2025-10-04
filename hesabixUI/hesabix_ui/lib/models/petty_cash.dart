class PettyCash {
  final int? id;
  final int businessId;
  final String name;
  final String? code;
  final int currencyId;
  final bool isActive;
  final bool isDefault;
  final String? description;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PettyCash({
    this.id,
    required this.businessId,
    required this.name,
    this.code,
    required this.currencyId,
    this.isActive = true,
    this.isDefault = false,
    this.description,
    this.createdAt,
    this.updatedAt,
  });

  factory PettyCash.fromJson(Map<String, dynamic> json) {
    return PettyCash(
      id: json['id'] as int?,
      businessId: (json['business_id'] ?? json['businessId']) as int,
      name: (json['name'] ?? '') as String,
      code: json['code'] as String?,
      currencyId: (json['currency_id'] ?? json['currencyId']) as int,
      isActive: (json['is_active'] ?? true) as bool,
      isDefault: (json['is_default'] ?? false) as bool,
      description: json['description'] as String?,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'code': code,
      'currency_id': currencyId,
      'is_active': isActive,
      'is_default': isDefault,
      'description': description,
    };
  }

  PettyCash copyWith({
    int? id,
    int? businessId,
    String? name,
    String? code,
    int? currencyId,
    bool? isActive,
    bool? isDefault,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PettyCash(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      name: name ?? this.name,
      code: code ?? this.code,
      currencyId: currencyId ?? this.currencyId,
      isActive: isActive ?? this.isActive,
      isDefault: isDefault ?? this.isDefault,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PettyCash &&
        other.id == id &&
        other.businessId == businessId &&
        other.name == name &&
        other.code == code &&
        other.currencyId == currencyId &&
        other.isActive == isActive &&
        other.isDefault == isDefault &&
        other.description == description;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      businessId, 
      name,
      code,
      currencyId,
      isActive,
      isDefault,
      description,
    );
  }

  @override
  String toString() {
    return 'PettyCash(id: $id, businessId: $businessId, name: $name, code: $code, currencyId: $currencyId, isActive: $isActive, isDefault: $isDefault, description: $description)';
  }
}
