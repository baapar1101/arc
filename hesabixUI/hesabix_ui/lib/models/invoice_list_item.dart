
/// مدل سطر لیست فاکتورها برای استفاده در DataTableWidget
class InvoiceListItem {
  final int id;
  final String code;
  final String documentType;
  final String documentTypeName;
  final DateTime documentDate;
  final DateTime? registeredAt;
  final double? totalAmount;
  final String? currencyCode;
  final String? createdByName;
  final bool isProforma;
  final String? description;
  final String? taxStatus;
  final bool isInstallmentSale;
  final String? counterparty;
  final int? projectId;
  final String? projectName;

  const InvoiceListItem({
    required this.id,
    required this.code,
    required this.documentType,
    required this.documentTypeName,
    required this.documentDate,
    this.registeredAt,
    this.totalAmount,
    this.currencyCode,
    this.createdByName,
    required this.isProforma,
    this.description,
    this.taxStatus,
    required this.isInstallmentSale,
    this.counterparty,
    this.projectId,
    this.projectName,
  });

  factory InvoiceListItem.fromJson(Map<String, dynamic> json) {
    DateTime _parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      final s = v.toString();
      return DateTime.tryParse(s) ?? DateTime.now();
    }

    double? _toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return InvoiceListItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      code: json['code']?.toString() ?? '',
      documentType: json['document_type']?.toString() ?? '',
      documentTypeName: json['document_type_name']?.toString() ?? json['document_type']?.toString() ?? '',
      documentDate: _parseDate(json['document_date']),
      registeredAt: json['registered_at'] != null ? DateTime.tryParse(json['registered_at'].toString()) : null,
      totalAmount: _toDouble(json['total_amount']),
      currencyCode: json['currency_code']?.toString(),
      createdByName: json['created_by_name']?.toString(),
      isProforma: json['is_proforma'] == true,
      description: json['description']?.toString(),
      taxStatus: json['tax_status']?.toString(),
      isInstallmentSale: json['is_installment_sale'] == true,
      counterparty: json['counterparty']?.toString(),
      projectId: json['project_id'] as int?,
      projectName: json['project_name']?.toString(),
    );
  }
}


