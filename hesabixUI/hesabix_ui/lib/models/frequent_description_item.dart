class FrequentDescriptionItem {
  final int id;
  final String text;
  final int sortOrder;
  final String? scope;

  const FrequentDescriptionItem({
    required this.id,
    required this.text,
    required this.sortOrder,
    this.scope,
  });

  factory FrequentDescriptionItem.fromJson(Map<String, dynamic> json) {
    return FrequentDescriptionItem(
      id: json['id'] as int,
      text: (json['text'] as String?) ?? '',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      scope: json['scope'] as String?,
    );
  }
}
