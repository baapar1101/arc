/// Converts JSON value to bool safely (handles int 0/1 and string 'true'/'false' from API).
bool _fromJsonBool(dynamic v, [bool defaultValue = false]) {
  if (v == null) return defaultValue;
  if (v is bool) return v;
  if (v is int) return v != 0;
  if (v is String) return v.toLowerCase() == 'true' || v == '1';
  return defaultValue;
}

class PersonBankAccount {
  final int? id;
  final int personId;
  final String bankName;
  final String? accountNumber;
  final String? cardNumber;
  final String? shebaNumber;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  PersonBankAccount({
    this.id,
    required this.personId,
    required this.bankName,
    this.accountNumber,
    this.cardNumber,
    this.shebaNumber,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PersonBankAccount.fromJson(Map<String, dynamic> json) {
    return PersonBankAccount(
      id: json['id'],
      personId: json['person_id'],
      bankName: json['bank_name'],
      accountNumber: json['account_number'],
      cardNumber: json['card_number'],
      shebaNumber: json['sheba_number'],
      isActive: _fromJsonBool(json['is_active'], true),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'person_id': personId,
      'bank_name': bankName,
      'account_number': accountNumber,
      'card_number': cardNumber,
      'sheba_number': shebaNumber,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  PersonBankAccount copyWith({
    int? id,
    int? personId,
    String? bankName,
    String? accountNumber,
    String? cardNumber,
    String? shebaNumber,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PersonBankAccount(
      id: id ?? this.id,
      personId: personId ?? this.personId,
      bankName: bankName ?? this.bankName,
      accountNumber: accountNumber ?? this.accountNumber,
      cardNumber: cardNumber ?? this.cardNumber,
      shebaNumber: shebaNumber ?? this.shebaNumber,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

enum PersonType {
  customer('مشتری', 'Customer'),
  marketer('بازاریاب', 'Marketer'),
  employee('کارمند', 'Employee'),
  supplier('تامین‌کننده', 'Supplier'),
  partner('همکار', 'Partner'),
  seller('فروشنده', 'Seller'),
  shareholder('سهامدار', 'Shareholder');

  const PersonType(this.persianName, this.englishName);
  final String persianName;
  final String englishName;

  static PersonType fromString(String value) {
    return PersonType.values.firstWhere(
      (type) => type.persianName == value || type.englishName == value,
      orElse: () => PersonType.customer,
    );
  }
}

class Person {
  final int? id;
  final int businessId;
  final int? code;
  final String aliasName;
  final String? firstName;
  final String? lastName;
  final List<PersonType> personTypes;
  final String? companyName;
  final String? paymentId;
  final String? nationalId;
  final String? registrationNumber;
  final String? economicId;
  final String? country;
  final String? province;
  final String? city;
  final String? address;
  final String? postalCode;
  final String? phone;
  final String? mobile;
  final String? fax;
  final String? email;
  final String? website;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<PersonBankAccount> bankAccounts;
  final int? shareCount;
  // پورسانت
  final double? commissionSalePercent;
  final double? commissionSalesReturnPercent;
  final double? commissionSalesAmount;
  final double? commissionSalesReturnAmount;
  final bool commissionExcludeDiscounts;
  final bool commissionExcludeAdditionsDeductions;
  final bool commissionPostInInvoiceDocument;
  
  // تراز و وضعیت مالی
  final double? balance;
  final String? status;

  Person({
    this.id,
    required this.businessId,
    this.code,
    required this.aliasName,
    this.firstName,
    this.lastName,
    required this.personTypes,
    this.companyName,
    this.paymentId,
    this.nationalId,
    this.registrationNumber,
    this.economicId,
    this.country,
    this.province,
    this.city,
    this.address,
    this.postalCode,
    this.phone,
    this.mobile,
    this.fax,
    this.email,
    this.website,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.bankAccounts = const [],
    this.shareCount,
    this.commissionSalePercent,
    this.commissionSalesReturnPercent,
    this.commissionSalesAmount,
    this.commissionSalesReturnAmount,
    this.commissionExcludeDiscounts = false,
    this.commissionExcludeAdditionsDeductions = false,
    this.commissionPostInInvoiceDocument = false,
    this.balance,
    this.status,
  });

  factory Person.fromJson(Map<String, dynamic> json) {
    final List<PersonType> types = (json['person_types'] as List?)
            ?.map((e) => PersonType.fromString(e.toString()))
            .toList() ??
        [];
    return Person(
      id: json['id'],
      businessId: json['business_id'],
      code: json['code'],
      aliasName: json['alias_name'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      personTypes: types,
      companyName: json['company_name'],
      paymentId: json['payment_id'],
      nationalId: json['national_id'],
      registrationNumber: json['registration_number'],
      economicId: json['economic_id'],
      country: json['country'],
      province: json['province'],
      city: json['city'],
      address: json['address'],
      postalCode: json['postal_code'],
      phone: json['phone'],
      mobile: json['mobile'],
      fax: json['fax'],
      email: json['email'],
      website: json['website'],
      isActive: _fromJsonBool(json['is_active'], true),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      bankAccounts: (json['bank_accounts'] as List<dynamic>?)
          ?.map((ba) => PersonBankAccount.fromJson(ba))
          .toList() ?? [],
      shareCount: json['share_count'],
      commissionSalePercent: (json['commission_sale_percent'] as num?)?.toDouble(),
      commissionSalesReturnPercent: (json['commission_sales_return_percent'] as num?)?.toDouble(),
      commissionSalesAmount: (json['commission_sales_amount'] as num?)?.toDouble(),
      commissionSalesReturnAmount: (json['commission_sales_return_amount'] as num?)?.toDouble(),
      commissionExcludeDiscounts: _fromJsonBool(json['commission_exclude_discounts'], false),
      commissionExcludeAdditionsDeductions: _fromJsonBool(json['commission_exclude_additions_deductions'], false),
      commissionPostInInvoiceDocument: _fromJsonBool(json['commission_post_in_invoice_document'], false),
      balance: (json['balance'] as num?)?.toDouble(),
      status: json['status'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'business_id': businessId,
      'code': code,
      'alias_name': aliasName,
      'first_name': firstName,
      'last_name': lastName,
      'person_types': personTypes.map((t) => t.persianName).toList(),
      'company_name': companyName,
      'payment_id': paymentId,
      'national_id': nationalId,
      'registration_number': registrationNumber,
      'economic_id': economicId,
      'country': country,
      'province': province,
      'city': city,
      'address': address,
      'postal_code': postalCode,
      'phone': phone,
      'mobile': mobile,
      'fax': fax,
      'email': email,
      'website': website,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'bank_accounts': bankAccounts.map((ba) => ba.toJson()).toList(),
      'share_count': shareCount,
      'commission_sale_percent': commissionSalePercent,
      'commission_sales_return_percent': commissionSalesReturnPercent,
      'commission_sales_amount': commissionSalesAmount,
      'commission_sales_return_amount': commissionSalesReturnAmount,
      'commission_exclude_discounts': commissionExcludeDiscounts,
      'commission_exclude_additions_deductions': commissionExcludeAdditionsDeductions,
      'commission_post_in_invoice_document': commissionPostInInvoiceDocument,
      'balance': balance,
      'status': status,
    };
  }

  Person copyWith({
    int? id,
    int? businessId,
    String? aliasName,
    String? firstName,
    String? lastName,
    List<PersonType>? personTypes,
    String? companyName,
    String? paymentId,
    String? nationalId,
    String? registrationNumber,
    String? economicId,
    String? country,
    String? province,
    String? city,
    String? address,
    String? postalCode,
    String? phone,
    String? mobile,
    String? fax,
    String? email,
    String? website,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<PersonBankAccount>? bankAccounts,
  }) {
    return Person(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      aliasName: aliasName ?? this.aliasName,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      personTypes: personTypes ?? this.personTypes,
      companyName: companyName ?? this.companyName,
      paymentId: paymentId ?? this.paymentId,
      nationalId: nationalId ?? this.nationalId,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      economicId: economicId ?? this.economicId,
      country: country ?? this.country,
      province: province ?? this.province,
      city: city ?? this.city,
      address: address ?? this.address,
      postalCode: postalCode ?? this.postalCode,
      phone: phone ?? this.phone,
      mobile: mobile ?? this.mobile,
      fax: fax ?? this.fax,
      email: email ?? this.email,
      website: website ?? this.website,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      bankAccounts: bankAccounts ?? this.bankAccounts,
    );
  }

  String get fullName {
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    } else if (firstName != null) {
      return firstName!;
    } else if (lastName != null) {
      return lastName!;
    }
    return aliasName;
  }

  String get displayName {
    return fullName.isNotEmpty ? fullName : aliasName;
  }
}

class PersonCreateRequest {
  final String aliasName;
  final int? code;
  final String? firstName;
  final String? lastName;
  final List<PersonType> personTypes;
  final String? companyName;
  final String? paymentId;
  final String? nationalId;
  final String? registrationNumber;
  final String? economicId;
  final String? country;
  final String? province;
  final String? city;
  final String? address;
  final String? postalCode;
  final String? phone;
  final String? mobile;
  final String? fax;
  final String? email;
  final String? website;
  final List<PersonBankAccount> bankAccounts;
  final int? shareCount;
  final double? commissionSalePercent;
  final double? commissionSalesReturnPercent;
  final double? commissionSalesAmount;
  final double? commissionSalesReturnAmount;
  final bool? commissionExcludeDiscounts;
  final bool? commissionExcludeAdditionsDeductions;
  final bool? commissionPostInInvoiceDocument;

  PersonCreateRequest({
    required this.aliasName,
    this.code,
    this.firstName,
    this.lastName,
    this.personTypes = const [],
    this.companyName,
    this.paymentId,
    this.nationalId,
    this.registrationNumber,
    this.economicId,
    this.country,
    this.province,
    this.city,
    this.address,
    this.postalCode,
    this.phone,
    this.mobile,
    this.fax,
    this.email,
    this.website,
    this.bankAccounts = const [],
    this.shareCount,
    this.commissionSalePercent,
    this.commissionSalesReturnPercent,
    this.commissionSalesAmount,
    this.commissionSalesReturnAmount,
    this.commissionExcludeDiscounts,
    this.commissionExcludeAdditionsDeductions,
    this.commissionPostInInvoiceDocument,
  });

  Map<String, dynamic> toJson() {
    return {
      'alias_name': aliasName,
      if (code != null) 'code': code,
      'first_name': firstName,
      'last_name': lastName,
      if (personTypes.isNotEmpty) 'person_types': personTypes.map((t) => t.persianName).toList(),
      'company_name': companyName,
      'payment_id': paymentId,
      'national_id': nationalId,
      'registration_number': registrationNumber,
      'economic_id': economicId,
      'country': country,
      'province': province,
      'city': city,
      'address': address,
      'postal_code': postalCode,
      'phone': phone,
      'mobile': mobile,
      'fax': fax,
      'email': email,
      'website': website,
      // Only send fields expected by backend for create
      'bank_accounts': bankAccounts
          .where((ba) => (ba.bankName).trim().isNotEmpty)
          .map((ba) => {
                'bank_name': ba.bankName,
                'account_number': ba.accountNumber,
                'card_number': ba.cardNumber,
                'sheba_number': ba.shebaNumber,
              })
          .toList(),
      if (shareCount != null) 'share_count': shareCount,
      if (commissionSalePercent != null) 'commission_sale_percent': commissionSalePercent,
      if (commissionSalesReturnPercent != null) 'commission_sales_return_percent': commissionSalesReturnPercent,
      if (commissionSalesAmount != null) 'commission_sales_amount': commissionSalesAmount,
      if (commissionSalesReturnAmount != null) 'commission_sales_return_amount': commissionSalesReturnAmount,
      if (commissionExcludeDiscounts != null) 'commission_exclude_discounts': commissionExcludeDiscounts,
      if (commissionExcludeAdditionsDeductions != null) 'commission_exclude_additions_deductions': commissionExcludeAdditionsDeductions,
      if (commissionPostInInvoiceDocument != null) 'commission_post_in_invoice_document': commissionPostInInvoiceDocument,
    };
  }
}

class PersonUpdateRequest {
  final int? code;
  final String? aliasName;
  final String? firstName;
  final String? lastName;
  final List<PersonType>? personTypes;
  final String? companyName;
  final String? paymentId;
  final String? nationalId;
  final String? registrationNumber;
  final String? economicId;
  final String? country;
  final String? province;
  final String? city;
  final String? address;
  final String? postalCode;
  final String? phone;
  final String? mobile;
  final String? fax;
  final String? email;
  final String? website;
  final bool? isActive;
  final int? shareCount;
  final double? commissionSalePercent;
  final double? commissionSalesReturnPercent;
  final double? commissionSalesAmount;
  final double? commissionSalesReturnAmount;
  final bool? commissionExcludeDiscounts;
  final bool? commissionExcludeAdditionsDeductions;
  final bool? commissionPostInInvoiceDocument;

  PersonUpdateRequest({
    this.code,
    this.aliasName,
    this.firstName,
    this.lastName,
    this.personTypes,
    this.companyName,
    this.paymentId,
    this.nationalId,
    this.registrationNumber,
    this.economicId,
    this.country,
    this.province,
    this.city,
    this.address,
    this.postalCode,
    this.phone,
    this.mobile,
    this.fax,
    this.email,
    this.website,
    this.isActive,
    this.shareCount,
    this.commissionSalePercent,
    this.commissionSalesReturnPercent,
    this.commissionSalesAmount,
    this.commissionSalesReturnAmount,
    this.commissionExcludeDiscounts,
    this.commissionExcludeAdditionsDeductions,
    this.commissionPostInInvoiceDocument,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {};
    
    if (code != null) json['code'] = code;
    if (aliasName != null) json['alias_name'] = aliasName;
    if (firstName != null) json['first_name'] = firstName;
    if (lastName != null) json['last_name'] = lastName;
    if (personTypes != null) json['person_types'] = personTypes!.map((t) => t.persianName).toList();
    if (companyName != null) json['company_name'] = companyName;
    if (paymentId != null) json['payment_id'] = paymentId;
    if (nationalId != null) json['national_id'] = nationalId;
    if (registrationNumber != null) json['registration_number'] = registrationNumber;
    if (economicId != null) json['economic_id'] = economicId;
    if (country != null) json['country'] = country;
    if (province != null) json['province'] = province;
    if (city != null) json['city'] = city;
    if (address != null) json['address'] = address;
    if (postalCode != null) json['postal_code'] = postalCode;
    if (phone != null) json['phone'] = phone;
    if (mobile != null) json['mobile'] = mobile;
    if (fax != null) json['fax'] = fax;
    if (email != null) json['email'] = email;
    if (website != null) json['website'] = website;
    if (isActive != null) json['is_active'] = isActive;
    if (shareCount != null) json['share_count'] = shareCount;
    if (commissionSalePercent != null) json['commission_sale_percent'] = commissionSalePercent;
    if (commissionSalesReturnPercent != null) json['commission_sales_return_percent'] = commissionSalesReturnPercent;
    if (commissionSalesAmount != null) json['commission_sales_amount'] = commissionSalesAmount;
    if (commissionSalesReturnAmount != null) json['commission_sales_return_amount'] = commissionSalesReturnAmount;
    if (commissionExcludeDiscounts != null) json['commission_exclude_discounts'] = commissionExcludeDiscounts;
    if (commissionExcludeAdditionsDeductions != null) json['commission_exclude_additions_deductions'] = commissionExcludeAdditionsDeductions;
    if (commissionPostInInvoiceDocument != null) json['commission_post_in_invoice_document'] = commissionPostInInvoiceDocument;
    
    return json;
  }
}
