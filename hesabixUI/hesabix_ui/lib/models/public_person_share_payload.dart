import 'package:intl/intl.dart';

import 'person_share_link.dart';

class PublicPersonSharePayload {
  final PersonShareLink? shareLink;
  final PublicPersonInfo person;
  final PublicBusinessInfo business;
  final PublicShareSummary summary;
  final List<PublicLedgerItem> ledger;
  final List<PublicInvoiceItem> invoices;
  final PersonShareLinkOptionsModel options;

  PublicPersonSharePayload({
    required this.shareLink,
    required this.person,
    required this.business,
    required this.summary,
    required this.ledger,
    required this.invoices,
    required this.options,
  });

  factory PublicPersonSharePayload.fromJson(Map<String, dynamic> json) {
    final linkJson = json['share_link'];
    return PublicPersonSharePayload(
      shareLink: linkJson is Map<String, dynamic>
          ? PersonShareLink.fromJson(Map<String, dynamic>.from(linkJson))
          : null,
      person: PublicPersonInfo.fromJson(json['person'] as Map<String, dynamic>? ?? const {}),
      business: PublicBusinessInfo.fromJson(json['business'] as Map<String, dynamic>? ?? const {}),
      summary: PublicShareSummary.fromJson(json['summary'] as Map<String, dynamic>? ?? const {}),
      ledger: ((json['ledger'] as List?) ?? const [])
          .map((e) => PublicLedgerItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      invoices: ((json['invoices'] as List?) ?? const [])
          .map((e) => PublicInvoiceItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      options: PersonShareLinkOptionsModel.fromJson(
        json['options'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

class PublicPersonInfo {
  final int? id;
  final String? code;
  final String? aliasName;
  final String? companyName;
  final String? mobile;
  final String? phone;
  final String? email;
  final String? city;

  const PublicPersonInfo({
    required this.id,
    required this.code,
    required this.aliasName,
    required this.companyName,
    required this.mobile,
    required this.phone,
    required this.email,
    required this.city,
  });

  factory PublicPersonInfo.fromJson(Map<String, dynamic> json) {
    return PublicPersonInfo(
      id: json['id'] as int?,
      code: json['code']?.toString(),
      aliasName: json['alias_name']?.toString(),
      companyName: json['company_name']?.toString(),
      mobile: json['mobile']?.toString(),
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      city: json['city']?.toString(),
    );
  }
}

class PublicBusinessInfo {
  final int? id;
  final String? name;
  final String? phone;
  final String? mobile;
  final String? address;
  final String? city;
  /// آیا کسب‌وکار لوگو دارد؛ تصویر از مسیر عمومی بدون احتمال افزودن به view بارگذاری می‌شود.
  final bool hasLogo;

  const PublicBusinessInfo({
    required this.id,
    required this.name,
    required this.phone,
    required this.mobile,
    required this.address,
    required this.city,
    this.hasLogo = false,
  });

  factory PublicBusinessInfo.fromJson(Map<String, dynamic> json) {
    return PublicBusinessInfo(
      id: json['id'] as int?,
      name: json['name']?.toString(),
      phone: json['phone']?.toString(),
      mobile: json['mobile']?.toString(),
      address: json['address']?.toString(),
      city: json['city']?.toString(),
      hasLogo: json['has_logo'] == true,
    );
  }
}

class PublicShareSummary {
  final double? balance;
  final String? status;
  final double? totalCredit;
  final double? totalDebit;

  const PublicShareSummary({
    required this.balance,
    required this.status,
    required this.totalCredit,
    required this.totalDebit,
  });

  factory PublicShareSummary.fromJson(Map<String, dynamic> json) {
    return PublicShareSummary(
      balance: _toDouble(json['balance']),
      status: json['status']?.toString(),
      totalCredit: _toDouble(json['total_credit']),
      totalDebit: _toDouble(json['total_debit']),
    );
  }
}

class PublicLedgerItem {
  final int? lineId;
  final int? documentId;
  final String? documentCode;
  final String? documentType;
  final String? documentTypeName;
  final DateTime? documentDate;
  final String? description;
  final double? debit;
  final double? credit;
  final String? currencyCode;

  const PublicLedgerItem({
    required this.lineId,
    required this.documentId,
    required this.documentCode,
    required this.documentType,
    required this.documentTypeName,
    required this.documentDate,
    required this.description,
    required this.debit,
    required this.credit,
    required this.currencyCode,
  });

  factory PublicLedgerItem.fromJson(Map<String, dynamic> json) {
    return PublicLedgerItem(
      lineId: json['line_id'] as int?,
      documentId: json['document_id'] as int?,
      documentCode: json['document_code']?.toString(),
      documentType: json['document_type']?.toString(),
      documentTypeName: json['document_type_name']?.toString(),
      documentDate: _parseDate(json['document_date']),
      description: json['description']?.toString(),
      debit: _toDouble(json['debit']),
      credit: _toDouble(json['credit']),
      currencyCode: json['currency_code']?.toString(),
    );
  }

  String formattedDate() {
    if (documentDate == null) return '';
    return DateFormat('yyyy/MM/dd').format(documentDate!);
  }
}

class PublicInvoiceItem {
  final int? documentId;
  final String? documentCode;
  final String? documentType;
  final String? documentTypeName;
  final DateTime? documentDate;
  final String? description;
  final double? amount;
  final String? currencyCode;
  final String? status;

  const PublicInvoiceItem({
    required this.documentId,
    required this.documentCode,
    required this.documentType,
    required this.documentTypeName,
    required this.documentDate,
    required this.description,
    required this.amount,
    required this.currencyCode,
    required this.status,
  });

  factory PublicInvoiceItem.fromJson(Map<String, dynamic> json) {
    return PublicInvoiceItem(
      documentId: json['document_id'] as int?,
      documentCode: json['document_code']?.toString(),
      documentType: json['document_type']?.toString(),
      documentTypeName: json['document_type_name']?.toString(),
      documentDate: _parseDate(json['document_date']),
      description: json['description']?.toString(),
      amount: _toDouble(json['amount']),
      currencyCode: json['currency_code']?.toString(),
      status: json['status']?.toString(),
    );
  }

  String formattedDate() {
    if (documentDate == null) return '';
    return DateFormat('yyyy/MM/dd').format(documentDate!);
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

