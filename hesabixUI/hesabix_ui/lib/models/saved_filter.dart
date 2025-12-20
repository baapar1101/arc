class SavedFilter {
  final String name;
  final Map<String, dynamic> filters;
  final String? sortBy;
  final bool? sortDesc;
  final DateTime createdAt;

  SavedFilter({
    required this.name,
    required this.filters,
    this.sortBy,
    this.sortDesc,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'filters': filters,
      'sort_by': sortBy,
      'sort_desc': sortDesc,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory SavedFilter.fromJson(Map<String, dynamic> json) {
    return SavedFilter(
      name: json['name'] as String,
      filters: Map<String, dynamic>.from(json['filters'] as Map),
      sortBy: json['sort_by'] as String?,
      sortDesc: json['sort_desc'] as bool?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  SavedFilter copyWith({
    String? name,
    Map<String, dynamic>? filters,
    String? sortBy,
    bool? sortDesc,
    DateTime? createdAt,
  }) {
    return SavedFilter(
      name: name ?? this.name,
      filters: filters ?? this.filters,
      sortBy: sortBy ?? this.sortBy,
      sortDesc: sortDesc ?? this.sortDesc,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}




