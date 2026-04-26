/// آیتم برچسب فاکتور (از API)
class InvoiceTagRef {
  final int id;
  final String name;
  final String? color;
  final bool isSystem;
  final bool isActive;
  final int sortOrder;

  const InvoiceTagRef({
    required this.id,
    required this.name,
    this.color,
    this.isSystem = false,
    this.isActive = true,
    this.sortOrder = 0,
  });

  factory InvoiceTagRef.fromJson(Map<String, dynamic> json) {
    return InvoiceTagRef(
      id: (json['id'] as num).toInt(),
      name: json['name']?.toString() ?? '',
      color: json['color']?.toString(),
      isSystem: json['is_system'] == true,
      isActive: json['is_active'] != false,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}
