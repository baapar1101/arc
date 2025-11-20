/// مدل سند حسابداری (Document)
class DocumentModel {
  final int id;
  final String code;
  final int businessId;
  final int fiscalYearId;
  final int currencyId;
  final int createdByUserId;
  final DateTime registeredAt;
  final DateTime documentDate;
  final String documentType;
  final bool isProforma;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;

  // اطلاعات مرتبط
  final String? businessTitle;
  final String? fiscalYearTitle;
  final String? currencyCode;
  final String? currencySymbol;
  final String? createdByName;
  final String? documentTypeName;

  // محاسبات
  final double totalDebit;
  final double totalCredit;
  final int linesCount;

  // سطرهای سند (فقط برای جزئیات)
  final List<DocumentLineModel>? lines;

  // اطلاعات اضافی
  final Map<String, dynamic>? extraInfo;
  final Map<String, dynamic>? developerSettings;

  // فیلدهای formatted از سرور (برای نمایش)
  final String? documentDateRaw;
  final String? registeredAtRaw;
  final String? createdAtRaw;
  final String? updatedAtRaw;

  DocumentModel({
    required this.id,
    required this.code,
    required this.businessId,
    required this.fiscalYearId,
    required this.currencyId,
    required this.createdByUserId,
    required this.registeredAt,
    required this.documentDate,
    required this.documentType,
    required this.isProforma,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    this.businessTitle,
    this.fiscalYearTitle,
    this.currencyCode,
    this.currencySymbol,
    this.createdByName,
    this.documentTypeName,
    required this.totalDebit,
    required this.totalCredit,
    required this.linesCount,
    this.lines,
    this.extraInfo,
    this.developerSettings,
    this.documentDateRaw,
    this.registeredAtRaw,
    this.createdAtRaw,
    this.updatedAtRaw,
  });

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    return DocumentModel(
      id: json['id'] as int,
      code: json['code'] as String,
      businessId: json['business_id'] as int,
      fiscalYearId: json['fiscal_year_id'] as int,
      currencyId: json['currency_id'] as int,
      createdByUserId: json['created_by_user_id'] as int,
      registeredAt: _parseDateTime(json['registered_at']),
      documentDate: _parseDateTime(json['document_date']),
      documentType: json['document_type'] as String,
      isProforma: json['is_proforma'] as bool? ?? false,
      description: json['description'] as String?,
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
      businessTitle: json['business_title'] as String?,
      fiscalYearTitle: json['fiscal_year_title'] as String?,
      currencyCode: json['currency_code'] as String?,
      currencySymbol: json['currency_symbol'] as String?,
      createdByName: json['created_by_name'] as String?,
      documentTypeName: json['document_type_name'] as String?,
      totalDebit: (json['total_debit'] as num?)?.toDouble() ?? 0.0,
      totalCredit: (json['total_credit'] as num?)?.toDouble() ?? 0.0,
      linesCount: json['lines_count'] as int? ?? 0,
      lines: json['lines'] != null
          ? (json['lines'] as List)
              .map((line) => DocumentLineModel.fromJson(line as Map<String, dynamic>))
              .toList()
          : null,
      extraInfo: json['extra_info'] as Map<String, dynamic>?,
      developerSettings: json['developer_settings'] as Map<String, dynamic>?,
      documentDateRaw: json['document_date_raw'] as String? ?? json['document_date'] as String?,
      registeredAtRaw: json['registered_at_raw'] as String? ?? json['registered_at'] as String?,
      createdAtRaw: json['created_at_raw'] as String? ?? json['created_at'] as String?,
      updatedAtRaw: json['updated_at_raw'] as String? ?? json['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'business_id': businessId,
      'fiscal_year_id': fiscalYearId,
      'currency_id': currencyId,
      'created_by_user_id': createdByUserId,
      'registered_at': registeredAt.toIso8601String(),
      'document_date': documentDate.toIso8601String(),
      'document_type': documentType,
      'is_proforma': isProforma,
      'description': description,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'business_title': businessTitle,
      'fiscal_year_title': fiscalYearTitle,
      'currency_code': currencyCode,
      'currency_symbol': currencySymbol,
      'created_by_name': createdByName,
      'total_debit': totalDebit,
      'total_credit': totalCredit,
      'lines_count': linesCount,
      'lines': lines?.map((line) => line.toJson()).toList(),
      'extra_info': extraInfo,
      'developer_settings': developerSettings,
    };
  }

  /// دریافت نام فارسی نوع سند
  String getDocumentTypeName() {
    // اگر document_type_name از سرور آمده باشد، از آن استفاده کن
    if (documentTypeName != null && documentTypeName!.isNotEmpty) {
      return documentTypeName!;
    }
    
    // در غیر این صورت از switch case استفاده کن
    switch (documentType) {
      case 'expense':
        return 'هزینه';
      case 'income':
        return 'درآمد';
      case 'receipt':
        return 'دریافت';
      case 'payment':
        return 'پرداخت';
      case 'transfer':
        return 'انتقال';
      case 'manual':
        return 'سند دستی';
      case 'invoice':
        return 'فاکتور';
      case 'invoice_sales':
        return 'فروش';
      case 'invoice_sales_return':
        return 'برگشت از فروش';
      case 'invoice_purchase':
        return 'خرید';
      case 'invoice_purchase_return':
        return 'برگشت از خرید';
      case 'invoice_direct_consumption':
        return 'مصرف مستقیم';
      case 'invoice_production':
        return 'تولید';
      case 'invoice_waste':
        return 'ضایعات';
      case 'production':
        return 'تولید';
      case 'opening_balance':
        return 'موجودی اولیه';
      default:
        return documentType;
    }
  }

  /// آیا سند قابل ویرایش است؟
  bool get isEditable => documentType == 'manual';

  /// آیا سند قابل حذف است؟
  bool get isDeletable => documentType == 'manual';

  /// دریافت وضعیت سند
  String get statusText => isProforma ? 'پیش‌فاکتور' : 'قطعی';

  /// Parse DateTime from various formats
  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    
    String dateStr = value.toString();
    
    // Try ISO format first
    try {
      return DateTime.parse(dateStr);
    } catch (e) {
      // If ISO parse fails, try other formats
      // Format: "1404/07/23 14:02:20" or "1404/07/23"
      try {
        // Remove time if exists and just use current datetime
        // Since we can't easily parse Jalali dates without conversion
        // we'll just return a valid DateTime
        return DateTime.now();
      } catch (e) {
        return DateTime.now();
      }
    }
  }
}

/// مدل سطر سند حسابداری (Document Line)
class DocumentLineModel {
  final int id;
  final int documentId;
  final int? accountId;
  final int? personId;
  final int? productId;
  final int? bankAccountId;
  final int? cashRegisterId;
  final int? pettyCashId;
  final int? checkId;
  final double? quantity;
  final double debit;
  final double credit;
  final String? description;
  final Map<String, dynamic>? extraInfo;
  final DateTime createdAt;
  final DateTime updatedAt;

  // اطلاعات مرتبط
  final String? accountCode;
  final String? accountName;
  final String? personName;
  final String? productName;
  final String? bankAccountName;
  final String? cashRegisterName;
  final String? pettyCashName;
  final String? checkNumber;

  DocumentLineModel({
    required this.id,
    required this.documentId,
    this.accountId,
    this.personId,
    this.productId,
    this.bankAccountId,
    this.cashRegisterId,
    this.pettyCashId,
    this.checkId,
    this.quantity,
    required this.debit,
    required this.credit,
    this.description,
    this.extraInfo,
    required this.createdAt,
    required this.updatedAt,
    this.accountCode,
    this.accountName,
    this.personName,
    this.productName,
    this.bankAccountName,
    this.cashRegisterName,
    this.pettyCashName,
    this.checkNumber,
  });

  factory DocumentLineModel.fromJson(Map<String, dynamic> json) {
    return DocumentLineModel(
      id: json['id'] as int,
      documentId: json['document_id'] as int,
      accountId: json['account_id'] as int?,
      personId: json['person_id'] as int?,
      productId: json['product_id'] as int?,
      bankAccountId: json['bank_account_id'] as int?,
      cashRegisterId: json['cash_register_id'] as int?,
      pettyCashId: json['petty_cash_id'] as int?,
      checkId: json['check_id'] as int?,
      quantity: (json['quantity'] as num?)?.toDouble(),
      debit: (json['debit'] as num?)?.toDouble() ?? 0.0,
      credit: (json['credit'] as num?)?.toDouble() ?? 0.0,
      description: json['description'] as String?,
      extraInfo: json['extra_info'] as Map<String, dynamic>?,
      createdAt: DocumentModel._parseDateTime(json['created_at']),
      updatedAt: DocumentModel._parseDateTime(json['updated_at']),
      accountCode: json['account_code'] as String?,
      accountName: json['account_name'] as String?,
      personName: json['person_name'] as String?,
      productName: json['product_name'] as String?,
      bankAccountName: json['bank_account_name'] as String?,
      cashRegisterName: json['cash_register_name'] as String?,
      pettyCashName: json['petty_cash_name'] as String?,
      checkNumber: json['check_number'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'document_id': documentId,
      'account_id': accountId,
      'person_id': personId,
      'product_id': productId,
      'bank_account_id': bankAccountId,
      'cash_register_id': cashRegisterId,
      'petty_cash_id': pettyCashId,
      'check_id': checkId,
      'quantity': quantity,
      'debit': debit,
      'credit': credit,
      'description': description,
      'extra_info': extraInfo,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'account_code': accountCode,
      'account_name': accountName,
      'person_name': personName,
      'product_name': productName,
      'bank_account_name': bankAccountName,
      'cash_register_name': cashRegisterName,
      'petty_cash_name': pettyCashName,
      'check_number': checkNumber,
    };
  }

  /// دریافت نام کامل حساب
  String get fullAccountName {
    if (accountCode != null && accountName != null) {
      return '$accountCode - $accountName';
    }
    return accountName ?? accountCode ?? '-';
  }

  /// دریافت نام طرف‌حساب
  String? get counterpartyName {
    return personName ??
        bankAccountName ??
        cashRegisterName ??
        pettyCashName ??
        checkNumber;
  }
}


/// مدل درخواست ایجاد سطر سند
class DocumentLineCreateRequest {
  final int accountId;
  final int? personId;
  final int? productId;
  final int? bankAccountId;
  final int? cashRegisterId;
  final int? pettyCashId;
  final int? checkId;
  final double? quantity;
  final double debit;
  final double credit;
  final String? description;
  final Map<String, dynamic>? extraInfo;

  DocumentLineCreateRequest({
    required this.accountId,
    this.personId,
    this.productId,
    this.bankAccountId,
    this.cashRegisterId,
    this.pettyCashId,
    this.checkId,
    this.quantity,
    this.debit = 0,
    this.credit = 0,
    this.description,
    this.extraInfo,
  });

  Map<String, dynamic> toJson() {
    return {
      'account_id': accountId,
      if (personId != null) 'person_id': personId,
      if (productId != null) 'product_id': productId,
      if (bankAccountId != null) 'bank_account_id': bankAccountId,
      if (cashRegisterId != null) 'cash_register_id': cashRegisterId,
      if (pettyCashId != null) 'petty_cash_id': pettyCashId,
      if (checkId != null) 'check_id': checkId,
      if (quantity != null) 'quantity': quantity,
      'debit': debit,
      'credit': credit,
      if (description != null) 'description': description,
      if (extraInfo != null) 'extra_info': extraInfo,
    };
  }
}


/// مدل درخواست ایجاد سند دستی
class CreateManualDocumentRequest {
  final String? code;
  final DateTime documentDate;
  final int? fiscalYearId;
  final int currencyId;
  final bool isProforma;
  final String? description;
  final List<DocumentLineCreateRequest> lines;
  final Map<String, dynamic>? extraInfo;

  CreateManualDocumentRequest({
    this.code,
    required this.documentDate,
    this.fiscalYearId,
    required this.currencyId,
    this.isProforma = false,
    this.description,
    required this.lines,
    this.extraInfo,
  });

  Map<String, dynamic> toJson() {
    return {
      if (code != null) 'code': code,
      'document_date': documentDate.toIso8601String().split('T')[0], // فقط تاریخ
      if (fiscalYearId != null) 'fiscal_year_id': fiscalYearId,
      'currency_id': currencyId,
      'is_proforma': isProforma,
      if (description != null) 'description': description,
      'lines': lines.map((line) => line.toJson()).toList(),
      if (extraInfo != null) 'extra_info': extraInfo,
    };
  }

  /// اعتبارسنجی درخواست
  String? validate() {
    if (lines.length < 2) {
      return 'سند باید حداقل 2 سطر داشته باشد';
    }

    double totalDebit = 0;
    double totalCredit = 0;
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      
      // بررسی که هر سطر یا بدهکار یا بستانکار داشته باشد
      if (line.debit == 0 && line.credit == 0) {
        return 'سطر ${i + 1} باید مقدار بدهکار یا بستانکار داشته باشد';
      }
      
      // نمی‌تواند هم بدهکار هم بستانکار داشته باشد
      if (line.debit > 0 && line.credit > 0) {
        return 'سطر ${i + 1} نمی‌تواند همزمان بدهکار و بستانکار داشته باشد';
      }
      
      totalDebit += line.debit;
      totalCredit += line.credit;
    }

    // بررسی متوازن بودن سند
    if ((totalDebit - totalCredit).abs() > 0.01) {
      final diff = totalDebit - totalCredit;
      return 'سند متوازن نیست. تفاوت: ${diff.toStringAsFixed(2)}';
    }

    return null; // اعتبارسنجی موفق
  }
}


/// مدل درخواست ویرایش سند دستی
class UpdateManualDocumentRequest {
  final String? code;
  final DateTime? documentDate;
  final int? currencyId;
  final bool? isProforma;
  final String? description;
  final List<DocumentLineCreateRequest>? lines;
  final Map<String, dynamic>? extraInfo;

  UpdateManualDocumentRequest({
    this.code,
    this.documentDate,
    this.currencyId,
    this.isProforma,
    this.description,
    this.lines,
    this.extraInfo,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    
    if (code != null) map['code'] = code;
    if (documentDate != null) {
      map['document_date'] = documentDate!.toIso8601String().split('T')[0];
    }
    if (currencyId != null) map['currency_id'] = currencyId;
    if (isProforma != null) map['is_proforma'] = isProforma;
    if (description != null) map['description'] = description;
    if (lines != null) {
      map['lines'] = lines!.map((line) => line.toJson()).toList();
    }
    if (extraInfo != null) map['extra_info'] = extraInfo;
    
    return map;
  }

  /// اعتبارسنجی درخواست
  String? validate() {
    if (lines != null) {
      if (lines!.length < 2) {
        return 'سند باید حداقل 2 سطر داشته باشد';
      }

      double totalDebit = 0;
      double totalCredit = 0;
      
      for (int i = 0; i < lines!.length; i++) {
        final line = lines![i];
        
        if (line.debit == 0 && line.credit == 0) {
          return 'سطر ${i + 1} باید مقدار بدهکار یا بستانکار داشته باشد';
        }
        
        if (line.debit > 0 && line.credit > 0) {
          return 'سطر ${i + 1} نمی‌تواند همزمان بدهکار و بستانکار داشته باشد';
        }
        
        totalDebit += line.debit;
        totalCredit += line.credit;
      }

      if ((totalDebit - totalCredit).abs() > 0.01) {
        final diff = totalDebit - totalCredit;
        return 'سند متوازن نیست. تفاوت: ${diff.toStringAsFixed(2)}';
      }
    }

    return null;
  }
}

