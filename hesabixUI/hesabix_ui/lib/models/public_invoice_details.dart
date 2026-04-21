import '../core/date_utils.dart';

class PublicInvoiceDetails {
  final int id;
  final String? code;
  final int businessId;
  final String? documentType;
  final DateTime? documentDate;
  final DateTime? registeredAt;
  final int? currencyId;
  final String? currencyCode;
  final int? createdByUserId;
  final String? createdByName;
  final bool isProforma;
  final String? description;
  final Map<String, dynamic>? extraInfo;
  final List<PublicInvoiceProductLine> productLines;
  final List<PublicInvoiceAccountLine> accountLines;
  final double subtotal;
  final double discountAmount;
  final double taxAmount;
  final double total;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PublicInvoiceDetails({
    required this.id,
    required this.code,
    required this.businessId,
    required this.documentType,
    required this.documentDate,
    required this.registeredAt,
    required this.currencyId,
    required this.currencyCode,
    required this.createdByUserId,
    required this.createdByName,
    required this.isProforma,
    required this.description,
    required this.extraInfo,
    required this.productLines,
    required this.accountLines,
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.total,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PublicInvoiceDetails.fromJson(Map<String, dynamic> json) {
    return PublicInvoiceDetails(
      id: (json['id'] as num).toInt(),
      code: json['code']?.toString(),
      businessId: (json['business_id'] as num).toInt(),
      documentType: json['document_type']?.toString(),
      documentDate: _parseDate(json['document_date']),
      registeredAt: _parseDate(json['registered_at']),
      currencyId: json['currency_id'] as int?,
      currencyCode: json['currency_code']?.toString(),
      createdByUserId: json['created_by_user_id'] as int?,
      createdByName: json['created_by_name']?.toString(),
      isProforma: json['is_proforma'] == true,
      description: json['description']?.toString(),
      extraInfo: json['extra_info'] as Map<String, dynamic>?,
      productLines: ((json['product_lines'] as List?) ?? [])
          .map((e) => PublicInvoiceProductLine.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      accountLines: ((json['account_lines'] as List?) ?? [])
          .map((e) => PublicInvoiceAccountLine.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      subtotal: _toDouble(json['subtotal']) ?? 0.0,
      discountAmount: _toDouble(json['discount_amount']) ?? 0.0,
      taxAmount: _toDouble(json['tax_amount']) ?? 0.0,
      total: _toDouble(json['total']) ?? 0.0,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  String formattedDate({bool jalali = true}) {
    if (documentDate == null) return '';
    return HesabixDateUtils.formatForDisplay(documentDate, jalali);
  }
}

class PublicInvoiceProductLine {
  final int id;
  final int? productId;
  final String? productName;
  final double? quantity;
  final String? description;
  final Map<String, dynamic>? extraInfo;
  final double? unitPrice;
  final double? lineDiscount;
  final double? taxAmount;
  final double? lineTotal;

  const PublicInvoiceProductLine({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.description,
    required this.extraInfo,
    required this.unitPrice,
    required this.lineDiscount,
    required this.taxAmount,
    required this.lineTotal,
  });

  factory PublicInvoiceProductLine.fromJson(Map<String, dynamic> json) {
    final ex = json['extra_info'];
    final Map<String, dynamic>? extraMap = ex is Map<String, dynamic> ? ex : null;
    double? pick(String key) =>
        _toDouble(json[key]) ??
        (extraMap != null ? _toDouble(extraMap[key]) : null);

    return PublicInvoiceProductLine(
      id: (json['id'] as num).toInt(),
      productId: (json['product_id'] as num?)?.toInt(),
      productName: json['product_name']?.toString(),
      quantity: _toDouble(json['quantity']),
      description: json['description']?.toString(),
      extraInfo: extraMap,
      unitPrice: pick('unit_price'),
      lineDiscount: pick('line_discount'),
      taxAmount: pick('tax_amount'),
      lineTotal: pick('line_total'),
    );
  }
}

class PublicInvoiceAccountLine {
  final int id;
  final int? accountId;
  final String? accountName;
  final String? accountCode;
  final double debit;
  final double credit;
  final int? personId;
  final String? description;
  final Map<String, dynamic>? extraInfo;

  const PublicInvoiceAccountLine({
    required this.id,
    required this.accountId,
    required this.accountName,
    required this.accountCode,
    required this.debit,
    required this.credit,
    required this.personId,
    required this.description,
    required this.extraInfo,
  });

  factory PublicInvoiceAccountLine.fromJson(Map<String, dynamic> json) {
    return PublicInvoiceAccountLine(
      id: (json['id'] as num).toInt(),
      accountId: json['account_id'] as int?,
      accountName: json['account_name']?.toString(),
      accountCode: json['account_code']?.toString(),
      debit: _toDouble(json['debit']) ?? 0.0,
      credit: _toDouble(json['credit']) ?? 0.0,
      personId: json['person_id'] as int?,
      description: json['description']?.toString(),
      extraInfo: json['extra_info'] as Map<String, dynamic>?,
    );
  }
}

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  try {
    return DateTime.parse(value.toString()).toLocal();
  } catch (_) {
    return null;
  }
}

