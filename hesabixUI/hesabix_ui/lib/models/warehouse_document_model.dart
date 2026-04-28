class WarehouseDocument {
  final int? id;
  final int businessId;
  final String code;
  final String docType;
  final String status;
  final DateTime? documentDate;
  final int? warehouseIdFrom;
  final int? warehouseIdTo;
  final String? warehouseNameFrom;
  final String? warehouseNameTo;
  final String? sourceType;
  final String? sourceTypeLabelFa;
  final int? sourceDocumentId;
  final String? sourceDocumentCode;
  final String? sourceInvoiceDocumentType;
  final String? sourceInvoiceTypeLabelFa;
  final String? sourceInvoicePartyName;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final double? totalQuantity;
  // فیلدهای ارسال
  final String? description;
  final String? deliveryMethod;
  final String? carrierName;
  final String? recipientName;
  final String? recipientPhone;
  final String? trackingNumber;

  const WarehouseDocument({
    this.id,
    required this.businessId,
    required this.code,
    required this.docType,
    required this.status,
    this.documentDate,
    this.warehouseIdFrom,
    this.warehouseIdTo,
    this.warehouseNameFrom,
    this.warehouseNameTo,
    this.sourceType,
    this.sourceTypeLabelFa,
    this.sourceDocumentId,
    this.sourceDocumentCode,
    this.sourceInvoiceDocumentType,
    this.sourceInvoiceTypeLabelFa,
    this.sourceInvoicePartyName,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.totalQuantity,
    this.description,
    this.deliveryMethod,
    this.carrierName,
    this.recipientName,
    this.recipientPhone,
    this.trackingNumber,
  });

  factory WarehouseDocument.fromJson(Map<String, dynamic> json) {
    // استخراج فیلدهای ارسال از extra_info در صورت عدم وجود مستقیم
    final extraInfo = json['extra_info'] as Map<String, dynamic>?;
    String? getField(String key) {
      return json[key] as String? ?? 
             (extraInfo != null ? extraInfo[key] as String? : null);
    }
    
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
      warehouseNameFrom: json['warehouse_name_from'] as String?,
      warehouseNameTo: json['warehouse_name_to'] as String?,
      sourceType: json['source_type'] as String?,
      sourceTypeLabelFa: json['source_type_label_fa'] as String?,
      sourceDocumentId: json['source_document_id'] as int?,
      sourceDocumentCode: json['source_document_code'] as String?,
      sourceInvoiceDocumentType: json['source_invoice_document_type'] as String?,
      sourceInvoiceTypeLabelFa: json['source_invoice_type_label_fa'] as String?,
      sourceInvoicePartyName: json['source_invoice_party_name'] as String?,
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
      description: getField('description'),
      deliveryMethod: getField('delivery_method'),
      carrierName: getField('carrier_name'),
      recipientName: getField('recipient_name'),
      recipientPhone: getField('recipient_phone'),
      trackingNumber: getField('tracking_number'),
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
      'warehouse_name_from': warehouseNameFrom,
      'warehouse_name_to': warehouseNameTo,
      'source_type': sourceType,
      'source_type_label_fa': sourceTypeLabelFa,
      'source_document_id': sourceDocumentId,
      'source_document_code': sourceDocumentCode,
      'source_invoice_document_type': sourceInvoiceDocumentType,
      'source_invoice_type_label_fa': sourceInvoiceTypeLabelFa,
      'source_invoice_party_name': sourceInvoicePartyName,
      'notes': notes,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'total_quantity': totalQuantity,
      'description': description,
      'delivery_method': deliveryMethod,
      'carrier_name': carrierName,
      'recipient_name': recipientName,
      'recipient_phone': recipientPhone,
      'tracking_number': trackingNumber,
    };
  }
}

