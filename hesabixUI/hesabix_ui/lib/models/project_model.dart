/// مدل پروژه
class ProjectModel {
  final int id;
  final int businessId;
  final String code;
  final String name;
  final String? description;
  final String status; // active, completed, on_hold, cancelled
  final String statusName;
  final DateTime? startDate;
  final DateTime? endDate;
  final double? budget;
  final int? currencyId;
  final String? currencyCode;
  final String? currencySymbol;
  final int? managerUserId;
  final String? managerName;
  final int? personId;
  final String? personName;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int createdById;
  final String? createdByName;
  final Map<String, dynamic>? extraInfo;

  ProjectModel({
    required this.id,
    required this.businessId,
    required this.code,
    required this.name,
    this.description,
    required this.status,
    required this.statusName,
    this.startDate,
    this.endDate,
    this.budget,
    this.currencyId,
    this.currencyCode,
    this.currencySymbol,
    this.managerUserId,
    this.managerName,
    this.personId,
    this.personName,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    required this.createdById,
    this.createdByName,
    this.extraInfo,
  });

  factory ProjectModel.fromJson(Map<String, dynamic> json) {
    return ProjectModel(
      id: json['id'] as int,
      businessId: json['business_id'] as int,
      code: json['code'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      status: json['status'] as String,
      statusName: json['status_name'] as String,
      startDate: json['start_date'] != null
          ? DateTime.parse(json['start_date'] as String)
          : null,
      endDate: json['end_date'] != null
          ? DateTime.parse(json['end_date'] as String)
          : null,
      budget: json['budget'] != null ? (json['budget'] as num).toDouble() : null,
      currencyId: json['currency_id'] as int?,
      currencyCode: json['currency_code'] as String?,
      currencySymbol: json['currency_symbol'] as String?,
      managerUserId: json['manager_user_id'] as int?,
      managerName: json['manager_name'] as String?,
      personId: json['person_id'] as int?,
      personName: json['person_name'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      createdById: json['created_by_id'] as int,
      createdByName: json['created_by_name'] as String?,
      extraInfo: json['extra_info'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'business_id': businessId,
      'code': code,
      'name': name,
      'description': description,
      'status': status,
      'start_date': startDate?.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'budget': budget,
      'currency_id': currencyId,
      'manager_user_id': managerUserId,
      'person_id': personId,
      'is_active': isActive,
      'extra_info': extraInfo,
    };
  }

  /// نسخه کپی با تغییرات
  ProjectModel copyWith({
    int? id,
    int? businessId,
    String? code,
    String? name,
    String? description,
    String? status,
    String? statusName,
    DateTime? startDate,
    DateTime? endDate,
    double? budget,
    int? currencyId,
    String? currencyCode,
    String? currencySymbol,
    int? managerUserId,
    String? managerName,
    int? personId,
    String? personName,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? createdById,
    String? createdByName,
    Map<String, dynamic>? extraInfo,
  }) {
    return ProjectModel(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      code: code ?? this.code,
      name: name ?? this.name,
      description: description ?? this.description,
      status: status ?? this.status,
      statusName: statusName ?? this.statusName,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      budget: budget ?? this.budget,
      currencyId: currencyId ?? this.currencyId,
      currencyCode: currencyCode ?? this.currencyCode,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      managerUserId: managerUserId ?? this.managerUserId,
      managerName: managerName ?? this.managerName,
      personId: personId ?? this.personId,
      personName: personName ?? this.personName,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdById: createdById ?? this.createdById,
      createdByName: createdByName ?? this.createdByName,
      extraInfo: extraInfo ?? this.extraInfo,
    );
  }
}

