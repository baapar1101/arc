/// گروه اشخاص (قالب پیش‌فرض + دسته‌بندی)
class PersonGroup {
  final int id;
  final int businessId;
  final int? parentId;
  final String name;
  final int? code;
  final String? description;
  final Map<String, dynamic> profileDefaults;
  final int sortOrder;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  PersonGroup({
    required this.id,
    required this.businessId,
    this.parentId,
    required this.name,
    this.code,
    this.description,
    required this.profileDefaults,
    this.sortOrder = 0,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PersonGroup.fromJson(Map<String, dynamic> json) {
    final pd = json['profile_defaults'];
    return PersonGroup(
      id: json['id'] as int,
      businessId: json['business_id'] as int,
      parentId: json['parent_id'] as int?,
      name: json['name'] as String,
      code: json['code'] as int?,
      description: json['description'] as String?,
      profileDefaults: pd is Map<String, dynamic>
          ? Map<String, dynamic>.from(pd)
          : (pd is Map ? Map<String, dynamic>.from(pd.map((k, v) => MapEntry(k.toString(), v))) : <String, dynamic>{}),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] == true || json['is_active'] == 1,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class PersonGroupCreateRequest {
  final String name;
  final int? code;
  final String? description;
  final Map<String, dynamic> profileDefaults;
  final int sortOrder;
  final bool isActive;

  PersonGroupCreateRequest({
    required this.name,
    this.code,
    this.description,
    this.profileDefaults = const {},
    this.sortOrder = 0,
    this.isActive = true,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        if (code != null) 'code': code,
        if (description != null && description!.trim().isNotEmpty) 'description': description!.trim(),
        'profile_defaults': profileDefaults,
        'sort_order': sortOrder,
        'is_active': isActive,
      };
}

class PersonGroupUpdateRequest {
  final String? name;
  final int? code;
  final String? description;
  final Map<String, dynamic>? profileDefaults;
  final int? sortOrder;
  final bool? isActive;

  PersonGroupUpdateRequest({
    this.name,
    this.code,
    this.description,
    this.profileDefaults,
    this.sortOrder,
    this.isActive,
  });

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    if (name != null) m['name'] = name;
    if (code != null) m['code'] = code;
    if (description != null) m['description'] = description;
    if (profileDefaults != null) m['profile_defaults'] = profileDefaults;
    if (sortOrder != null) m['sort_order'] = sortOrder;
    if (isActive != null) m['is_active'] = isActive;
    return m;
  }
}
