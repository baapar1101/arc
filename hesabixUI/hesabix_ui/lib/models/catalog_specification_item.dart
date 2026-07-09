class CatalogSpecificationItem {
  final int? fieldId;
  final String label;
  final String value;
  final int sortOrder;

  const CatalogSpecificationItem({
    this.fieldId,
    required this.label,
    this.value = '',
    this.sortOrder = 0,
  });

  CatalogSpecificationItem copyWith({
    int? fieldId,
    String? label,
    String? value,
    int? sortOrder,
  }) {
    return CatalogSpecificationItem(
      fieldId: fieldId ?? this.fieldId,
      label: label ?? this.label,
      value: value ?? this.value,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() => {
        if (fieldId != null) 'field_id': fieldId,
        'label': label,
        'value': value,
        'sort_order': sortOrder,
      };

  factory CatalogSpecificationItem.fromJson(Map<String, dynamic> json) {
    return CatalogSpecificationItem(
      fieldId: _parseInt(json['field_id']),
      label: (json['label'] ?? '').toString(),
      value: (json['value'] ?? '').toString(),
      sortOrder: _parseInt(json['sort_order']) ?? 0,
    );
  }

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
