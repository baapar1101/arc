class WarehouseInvoiceSourceDoc {
  final int id;
  final String code;
  final String status;
  final String docType;

  const WarehouseInvoiceSourceDoc({
    required this.id,
    required this.code,
    required this.status,
    required this.docType,
  });

  factory WarehouseInvoiceSourceDoc.fromJson(Map<String, dynamic> json) {
    return WarehouseInvoiceSourceDoc(
      id: json['id'] as int,
      code: (json['code'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      docType: (json['doc_type'] ?? '').toString(),
    );
  }
}

class WarehouseInvoiceSource {
  final int invoiceId;
  final String code;
  final String invoiceType;
  final DateTime? documentDate;
  final String? personName;
  final double? netAmount;
  final String warehouseState;
  final String? warehouseDocTypeHint;
  final List<WarehouseInvoiceSourceDoc> warehouseDocuments;

  const WarehouseInvoiceSource({
    required this.invoiceId,
    required this.code,
    required this.invoiceType,
    required this.documentDate,
    required this.personName,
    required this.netAmount,
    required this.warehouseState,
    required this.warehouseDocTypeHint,
    required this.warehouseDocuments,
  });

  bool get hasPosted => warehouseDocuments.any((doc) => doc.status == 'posted');

  bool get hasDraft => warehouseDocuments.any((doc) => doc.status == 'draft');

  factory WarehouseInvoiceSource.fromJson(Map<String, dynamic> json) {
    final docs = (json['warehouse_documents'] as List<dynamic>? ?? const [])
        .map((e) => WarehouseInvoiceSourceDoc.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    DateTime? parsedDate;
    final dateStr = json['document_date']?.toString();
    if (dateStr != null && dateStr.isNotEmpty) {
      parsedDate = DateTime.tryParse(dateStr);
    }
    return WarehouseInvoiceSource(
      invoiceId: json['invoice_id'] as int,
      code: (json['code'] ?? '').toString(),
      invoiceType: (json['invoice_type'] ?? '').toString(),
      documentDate: parsedDate,
      personName: json['person_name']?.toString(),
      netAmount: json['net_amount'] == null ? null : double.tryParse(json['net_amount'].toString()),
      warehouseState: (json['warehouse_state'] ?? 'missing').toString(),
      warehouseDocTypeHint: json['warehouse_doc_type_hint']?.toString(),
      warehouseDocuments: docs,
    );
  }
}


