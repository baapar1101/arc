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
      isActive: json['is_active'] ?? true,
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
  seller('فروشنده', 'Seller');

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
  final PersonType personType;
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

  Person({
    this.id,
    required this.businessId,
    this.code,
    required this.aliasName,
    this.firstName,
    this.lastName,
    required this.personType,
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
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.bankAccounts = const [],
  });

  factory Person.fromJson(Map<String, dynamic> json) {
    final List<PersonType> types = (json['person_types'] as List?)
            ?.map((e) => PersonType.fromString(e.toString()))
            .toList() ??
        [];
    final PersonType primaryType = types.isNotEmpty
        ? types.first
        : PersonType.fromString(json['person_type']);
    return Person(
      id: json['id'],
      businessId: json['business_id'],
      code: json['code'],
      aliasName: json['alias_name'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      personType: primaryType,
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
      isActive: json['is_active'] ?? true,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      bankAccounts: (json['bank_accounts'] as List<dynamic>?)
          ?.map((ba) => PersonBankAccount.fromJson(ba))
          .toList() ?? [],
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
      'person_type': personType.persianName,
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
    };
  }

  Person copyWith({
    int? id,
    int? businessId,
    String? aliasName,
    String? firstName,
    String? lastName,
    PersonType? personType,
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
      personType: personType ?? this.personType,
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
    };
  }
}

class PersonUpdateRequest {
  final int? code;
  final String? aliasName;
  final String? firstName;
  final String? lastName;
  final PersonType? personType;
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

  PersonUpdateRequest({
    this.code,
    this.aliasName,
    this.firstName,
    this.lastName,
    this.personType,
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
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {};
    
    if (code != null) json['code'] = code;
    if (aliasName != null) json['alias_name'] = aliasName;
    if (firstName != null) json['first_name'] = firstName;
    if (lastName != null) json['last_name'] = lastName;
    if (personType != null) json['person_type'] = personType!.persianName;
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
    
    return json;
  }
}
