/// مدل سند انتقال
class TransferDocument {
  final int id;
  final String code;
  final DateTime documentDate;
  final DateTime registeredAt;
  final double totalAmount;
  final String? createdByName;
  final String? description;
  final String? sourceType;
  final String? sourceName;
  final String? destinationType;
  final String? destinationName;

  TransferDocument({
    required this.id,
    required this.code,
    required this.documentDate,
    required this.registeredAt,
    required this.totalAmount,
    this.createdByName,
    this.description,
    this.sourceType,
    this.sourceName,
    this.destinationType,
    this.destinationName,
  });

  factory TransferDocument.fromJson(Map<String, dynamic> json) {
    return TransferDocument(
      id: json['id'] as int,
      code: (json['code'] ?? '').toString(),
      documentDate: DateTime.tryParse((json['document_date'] ?? '').toString()) ?? DateTime.now(),
      registeredAt: DateTime.tryParse((json['registered_at'] ?? '').toString()) ?? DateTime.now(),
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      createdByName: (json['created_by_name'] ?? '') as String?,
      description: (json['description'] ?? '') as String?,
      sourceType: (json['source_type'] ?? '') as String?,
      sourceName: (json['source_name'] ?? '') as String?,
      destinationType: (json['destination_type'] ?? '') as String?,
      destinationName: (json['destination_name'] ?? '') as String?,
    );
  }

  String get documentTypeName => 'انتقال';
}


