class WarehouseDocument {
  final int? id;
  final int businessId;
  final String code;
  final String docType;
  final String status;
  final DateTime? documentDate;
  final int? warehouseIdFrom;
  final int? warehouseIdTo;
  final String? sourceType;
  final int? sourceDocumentId;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final double? totalQuantity;

  const WarehouseDocument({
    this.id,
    required this.businessId,
    required this.code,
    required this.docType,
    required this.status,
    this.documentDate,
    this.warehouseIdFrom,
    this.warehouseIdTo,
    this.sourceType,
    this.sourceDocumentId,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.totalQuantity,
  });

  factory WarehouseDocument.fromJson(Map<String, dynamic> json) {
    return WarehouseDocument(
      id: json['id'] as int?,
      businessId: (json['business_id'] ?? json['businessId']) as int,
      code: (json['code'] ?? '') as String,
      docType: (json['doc_type'] ?? json['docType'] ?? '') as String,
      status: (json['status'] ?? '') as String,
      documentDate: json['document_date'] != null
          ? DateTime.tryParse(json['document_date'].toString())
          : null,
      warehouseIdFrom: json['warehouse_id_from'] as int?,
      warehouseIdTo: json['warehouse_id_to'] as int?,
      sourceType: json['source_type'] as String?,
      sourceDocumentId: json['source_document_id'] as int?,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      totalQuantity: json['total_quantity'] != null
          ? (json['total_quantity'] as num).toDouble()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'business_id': businessId,
      'code': code,
      'doc_type': docType,
      'status': status,
      'document_date': documentDate?.toIso8601String(),
      'warehouse_id_from': warehouseIdFrom,
      'warehouse_id_to': warehouseIdTo,
      'source_type': sourceType,
      'source_document_id': sourceDocumentId,
      'notes': notes,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'total_quantity': totalQuantity,
    };
  }
}

