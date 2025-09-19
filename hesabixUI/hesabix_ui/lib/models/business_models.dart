enum BusinessType {
  company('شرکت'),
  shop('مغازه'),
  store('فروشگاه'),
  union('اتحادیه'),
  club('باشگاه'),
  institute('موسسه'),
  individual('شخصی');

  const BusinessType(this.displayName);
  final String displayName;
}

enum BusinessField {
  manufacturing('تولیدی'),
  commercial('بازرگانی'),
  service('خدماتی'),
  other('سایر');

  const BusinessField(this.displayName);
  final String displayName;
}

class BusinessData {
  // مرحله 1: اطلاعات پایه
  String name;
  BusinessType? businessType;
  BusinessField? businessField;

  // مرحله 2: اطلاعات تماس
  String? address;
  String? phone;
  String? mobile;
  String? postalCode;

  // مرحله 3: اطلاعات قانونی
  String? nationalId;
  String? registrationNumber;
  String? economicId;

  // مرحله 4: اطلاعات جغرافیایی
  String? country;
  String? province;
  String? city;

  BusinessData({
    this.name = '',
    this.businessType,
    this.businessField,
    this.address,
    this.phone,
    this.mobile,
    this.postalCode,
    this.nationalId,
    this.registrationNumber,
    this.economicId,
    this.country,
    this.province,
    this.city,
  });

  // تبدیل به Map برای ارسال به API
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'business_type': businessType?.name,
      'business_field': businessField?.name,
      'address': address,
      'phone': phone,
      'mobile': mobile,
      'postal_code': postalCode,
      'national_id': nationalId,
      'registration_number': registrationNumber,
      'economic_id': economicId,
      'country': country,
      'province': province,
      'city': city,
    };
  }

  // کپی کردن با تغییرات
  BusinessData copyWith({
    String? name,
    BusinessType? businessType,
    BusinessField? businessField,
    String? address,
    String? phone,
    String? mobile,
    String? postalCode,
    String? nationalId,
    String? registrationNumber,
    String? economicId,
    String? country,
    String? province,
    String? city,
  }) {
    return BusinessData(
      name: name ?? this.name,
      businessType: businessType ?? this.businessType,
      businessField: businessField ?? this.businessField,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      mobile: mobile ?? this.mobile,
      postalCode: postalCode ?? this.postalCode,
      nationalId: nationalId ?? this.nationalId,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      economicId: economicId ?? this.economicId,
      country: country ?? this.country,
      province: province ?? this.province,
      city: city ?? this.city,
    );
  }

  // بررسی اعتبار مرحله 1
  bool isStep1Valid() {
    return name.isNotEmpty && businessType != null && businessField != null;
  }

  // بررسی اعتبار مرحله 2 (اختیاری)
  bool isStep2Valid() {
    // اعتبارسنجی موبایل اگر وارد شده باشد
    if (mobile != null && mobile!.isNotEmpty) {
      if (!_isValidMobile(mobile!)) {
        return false;
      }
    }
    
    // اعتبارسنجی تلفن ثابت اگر وارد شده باشد
    if (phone != null && phone!.isNotEmpty) {
      if (!_isValidPhone(phone!)) {
        return false;
      }
    }
    
    return true;
  }

  // بررسی اعتبار مرحله 3 (اختیاری)
  bool isStep3Valid() {
    // اعتبارسنجی کد ملی اگر وارد شده باشد
    if (nationalId != null && nationalId!.isNotEmpty) {
      if (!_isValidNationalId(nationalId!)) {
        return false;
      }
    }
    
    return true;
  }

  // بررسی اعتبار مرحله 4 (اختیاری)
  bool isStep4Valid() {
    return true; // همه فیلدها اختیاری هستند
  }

  // بررسی اعتبار کل فرم
  bool isFormValid() {
    return isStep1Valid() && isStep2Valid() && isStep3Valid() && isStep4Valid();
  }

  // اعتبارسنجی شماره موبایل ایرانی
  bool _isValidMobile(String mobile) {
    // حذف فاصله‌ها و کاراکترهای اضافی
    String cleanMobile = mobile.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    
    // بررسی فرمت‌های مختلف موبایل ایرانی
    RegExp mobileRegex = RegExp(r'^(\+98|0)?9\d{9}$');
    
    if (!mobileRegex.hasMatch(cleanMobile)) {
      return false;
    }
    
    // بررسی طول نهایی (باید 11 رقم باشد)
    String finalMobile = cleanMobile.startsWith('+98') 
        ? cleanMobile.substring(3)
        : cleanMobile.startsWith('0') 
            ? cleanMobile 
            : '0$cleanMobile';
    
    return finalMobile.length == 11 && finalMobile.startsWith('09');
  }

  // اعتبارسنجی شماره تلفن ثابت ایرانی
  bool _isValidPhone(String phone) {
    // حذف فاصله‌ها و کاراکترهای اضافی
    String cleanPhone = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    
    // بررسی فرمت‌های مختلف تلفن ثابت ایرانی
    RegExp phoneRegex = RegExp(r'^(\+98|0)?[1-9]\d{7,8}$');
    
    if (!phoneRegex.hasMatch(cleanPhone)) {
      return false;
    }
    
    // بررسی طول نهایی (باید 8-11 رقم باشد)
    String finalPhone = cleanPhone.startsWith('+98') 
        ? cleanPhone.substring(3)
        : cleanPhone.startsWith('0') 
            ? cleanPhone 
            : '0$cleanPhone';
    
    return finalPhone.length >= 8 && finalPhone.length <= 11;
  }

  // اعتبارسنجی کد ملی ایرانی
  bool _isValidNationalId(String nationalId) {
    // حذف فاصله‌ها و کاراکترهای اضافی
    String cleanId = nationalId.replaceAll(RegExp(r'[\s\-]'), '');
    
    // بررسی طول (باید 10 رقم باشد)
    if (cleanId.length != 10) {
      return false;
    }
    
    // بررسی اینکه همه کاراکترها عدد باشند
    if (!RegExp(r'^\d{10}$').hasMatch(cleanId)) {
      return false;
    }
    
    // بررسی الگوریتم کد ملی
    int sum = 0;
    for (int i = 0; i < 9; i++) {
      sum += int.parse(cleanId[i]) * (10 - i);
    }
    
    int remainder = sum % 11;
    int checkDigit = remainder < 2 ? remainder : 11 - remainder;
    
    return checkDigit == int.parse(cleanId[9]);
  }

  // دریافت پیام خطای اعتبارسنجی
  String? getValidationError(String field) {
    switch (field) {
      case 'mobile':
        if (mobile != null && mobile!.isNotEmpty && !_isValidMobile(mobile!)) {
          return 'شماره موبایل نامعتبر است. مثال: 09123456789';
        }
        break;
      case 'phone':
        if (phone != null && phone!.isNotEmpty && !_isValidPhone(phone!)) {
          return 'شماره تلفن ثابت نامعتبر است. مثال: 02112345678';
        }
        break;
      case 'nationalId':
        if (nationalId != null && nationalId!.isNotEmpty && !_isValidNationalId(nationalId!)) {
          return 'کد ملی نامعتبر است. مثال: 1234567890';
        }
        break;
    }
    return null;
  }
}

class BusinessResponse {
  final int id;
  final String name;
  final String businessType;
  final String businessField;
  final int ownerId;
  final String? address;
  final String? phone;
  final String? mobile;
  final String? nationalId;
  final String? registrationNumber;
  final String? economicId;
  final String? country;
  final String? province;
  final String? city;
  final String? postalCode;
  final DateTime createdAt;
  final DateTime updatedAt;

  BusinessResponse({
    required this.id,
    required this.name,
    required this.businessType,
    required this.businessField,
    required this.ownerId,
    this.address,
    this.phone,
    this.mobile,
    this.nationalId,
    this.registrationNumber,
    this.economicId,
    this.country,
    this.province,
    this.city,
    this.postalCode,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BusinessResponse.fromJson(Map<String, dynamic> json) {
    return BusinessResponse(
      id: json['id'],
      name: json['name'],
      businessType: json['business_type'],
      businessField: json['business_field'],
      ownerId: json['owner_id'],
      address: json['address'],
      phone: json['phone'],
      mobile: json['mobile'],
      nationalId: json['national_id'],
      registrationNumber: json['registration_number'],
      economicId: json['economic_id'],
      country: json['country'],
      province: json['province'],
      city: json['city'],
      postalCode: json['postal_code'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}
