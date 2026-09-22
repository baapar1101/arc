
DateTime _safeParse(dynamic value) {
  if (value == null) return DateTime.now();
  try {
    final text = value.toString().trim();
    // Try ISO first
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(text)) {
      return DateTime.parse(text);
    }
    // Try Persian/Gregorian slash pattern: YYYY/MM/DD
    final match = RegExp(r'^(\d{4})/(\d{1,2})/(\d{1,2})').firstMatch(text);
    if (match != null) {
      final year = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final day = int.parse(match.group(3)!);
      if (year >= 1700 && year <= 2200 && month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return DateTime(year, month, day);
      }
    }
  } catch (_) {}
  return DateTime.now();
}

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
          ? _safeParse(json['created_at'] as String)
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




