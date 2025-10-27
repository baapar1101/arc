class Warehouse {
  final int? id;
  final int businessId;
  final String code;
  final String name;
  final String? description;
  final bool isDefault;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Warehouse({
    this.id,
    required this.businessId,
    required this.code,
    required this.name,
    this.description,
    this.isDefault = false,
    this.createdAt,
    this.updatedAt,
  });

  factory Warehouse.fromJson(Map<String, dynamic> json) {
    return Warehouse(
      id: json['id'] as int?,
      businessId: (json['business_id'] ?? json['businessId']) as int,
      code: (json['code'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      description: json['description'] as String?,
      isDefault: (json['is_default'] ?? json['isDefault'] ?? false) as bool,
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
      'description': description,
      'is_default': isDefault,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}


