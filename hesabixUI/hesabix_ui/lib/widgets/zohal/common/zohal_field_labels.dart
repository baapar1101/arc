/// برچسب‌ها و راهنماهای فارسی برای فیلدهای استعلام زحل
class ZohalFieldLabels {
  // ==================== Labels ====================
  
  static const String cardNumber = 'شماره کارت بانکی';
  static const String iban = 'شماره شبا';
  static const String bankAccount = 'شماره حساب بانکی';
  static const String bankCode = 'کد بانک';
  static const String name = 'نام';
  static const String nationalCode = 'کد ملی';
  static const String mobile = 'شماره موبایل';
  static const String phone = 'شماره تلفن';
  static const String postalCode = 'کد پستی';
  static const String website = 'آدرس وب‌سایت';
  static const String sayadId = 'شناسه صیادی';
  static const String nationalityType = 'نوع ملیت';
  static const String companyNationalId = 'شناسه ملی شرکت';
  static const String plateNumber = 'شماره پلاک خودرو';
  static const String regionCode = 'کد منطقه';
  static const String otp = 'کد تایید';
  static const String referenceId = 'شماره پیگیری';
  static const String persianText = 'متن فارسی';

  // ==================== Hints ====================
  
  static const String cardNumberHint = '6362141234567890';
  static const String ibanHint = 'IR120620000000001234567890';
  static const String bankAccountHint = '1234567890123';
  static const String nameHint = 'محمد صادقی';
  static const String nationalCodeHint = '0012345678';
  static const String mobileHint = '09123456789';
  static const String phoneHint = '02112345678';
  static const String postalCodeHint = '1234567890';
  static const String websiteHint = 'example.com یا www.example.com';
  static const String sayadIdHint = '1234567890123456';
  static const String companyNationalIdHint = '14001234567';
  static const String plateNumberHint = '12 ب 345';
  static const String regionCodeHint = '11';
  static const String otpHint = '123456';

  // ==================== Helper Texts ====================
  
  static const String cardNumberHelper = 'شماره 16 رقمی کارت بانکی';
  static const String ibanHelper = 'شماره شبا (IR + 24 رقم)';
  static const String bankAccountHelper = 'شماره حساب بانکی (5 تا 19 رقم)';
  static const String bankCodeHelper = 'کد 2 یا 3 رقمی بانک (مثال: 062)';
  static const String nameHelper = 'نام و نام خانوادگی به فارسی';
  static const String nationalCodeHelper = 'کد ملی 10 رقمی';
  static const String mobileHelper = 'شماره موبایل 11 رقمی (مثال: 09123456789)';
  static const String phoneHelper = 'شماره تلفن ثابت';
  static const String postalCodeHelper = 'کد پستی 10 رقمی';
  static const String websiteHelper = 'آدرس وب‌سایت (با یا بدون www)';
  static const String sayadIdHelper = 'شناسه صیادی چک (16 رقم)';
  static const String nationalityTypeHelper = '1 برای ایرانی، 2 برای غیرایرانی';
  static const String companyNationalIdHelper = 'شناسه ملی شرکت (11 رقم)';
  static const String plateNumberHelper = 'شماره پلاک خودرو';
  static const String regionCodeHelper = 'کد منطقه پلاک';
  static const String otpHelper = 'کد تایید ارسال شده به موبایل';
  static const String referenceIdHelper = 'شماره پیگیری دریافت شده';
  static const String persianTextHelper = 'متن فارسی برای تبدیل به فینگلیش';

  // ==================== Methods ====================
  
  /// دریافت برچسب بر اساس نام فیلد
  static String getLabel(String fieldName) {
    final lowerName = fieldName.toLowerCase();
    
    if (lowerName.contains('card') && lowerName.contains('number')) {
      return cardNumber;
    } else if (lowerName.contains('iban')) {
      return iban;
    } else if (lowerName.contains('account') && lowerName.contains('bank')) {
      return bankAccount;
    } else if (lowerName.contains('bank') && lowerName.contains('code')) {
      return bankCode;
    } else if (lowerName.contains('name')) {
      return name;
    } else if (lowerName.contains('national_code')) {
      return nationalCode;
    } else if (lowerName.contains('mobile')) {
      return mobile;
    } else if (lowerName.contains('phone')) {
      return phone;
    } else if (lowerName.contains('postal_code')) {
      return postalCode;
    } else if (lowerName.contains('website')) {
      return website;
    } else if (lowerName.contains('sayad_id')) {
      return sayadId;
    } else if (lowerName.contains('nationality_type')) {
      return nationalityType;
    } else if (lowerName.contains('national_id')) {
      return companyNationalId;
    } else if (lowerName.contains('plate_number') || lowerName.contains('plate')) {
      return plateNumber;
    } else if (lowerName.contains('region_code')) {
      return regionCode;
    } else if (lowerName.contains('otp')) {
      return otp;
    } else if (lowerName.contains('reference_id')) {
      return referenceId;
    }
    
    // اگر پیدا نشد، نام فیلد را با تبدیل _ به فاصله برمی‌گردانیم
    return fieldName.replaceAll('_', ' ');
  }

  /// دریافت راهنما بر اساس نام فیلد
  static String? getHelper(String fieldName) {
    final lowerName = fieldName.toLowerCase();
    
    if (lowerName.contains('card') && lowerName.contains('number')) {
      return cardNumberHelper;
    } else if (lowerName.contains('iban')) {
      return ibanHelper;
    } else if (lowerName.contains('account') && lowerName.contains('bank')) {
      return bankAccountHelper;
    } else if (lowerName.contains('bank') && lowerName.contains('code')) {
      return bankCodeHelper;
    } else if (lowerName.contains('name')) {
      return nameHelper;
    } else if (lowerName.contains('national_code')) {
      return nationalCodeHelper;
    } else if (lowerName.contains('mobile')) {
      return mobileHelper;
    } else if (lowerName.contains('phone')) {
      return phoneHelper;
    } else if (lowerName.contains('postal_code')) {
      return postalCodeHelper;
    } else if (lowerName.contains('website')) {
      return websiteHelper;
    } else if (lowerName.contains('sayad_id')) {
      return sayadIdHelper;
    } else if (lowerName.contains('nationality_type')) {
      return nationalityTypeHelper;
    } else if (lowerName.contains('national_id')) {
      return companyNationalIdHelper;
    } else if (lowerName.contains('plate_number') || lowerName.contains('plate')) {
      return plateNumberHelper;
    } else if (lowerName.contains('region_code')) {
      return regionCodeHelper;
    } else if (lowerName.contains('otp')) {
      return otpHelper;
    } else if (lowerName.contains('reference_id')) {
      return referenceIdHelper;
    }
    
    return null;
  }

  /// دریافت placeholder بر اساس نام فیلد
  static String? getHint(String fieldName) {
    final lowerName = fieldName.toLowerCase();
    
    if (lowerName.contains('card') && lowerName.contains('number')) {
      return cardNumberHint;
    } else if (lowerName.contains('iban')) {
      return ibanHint;
    } else if (lowerName.contains('account') && lowerName.contains('bank')) {
      return bankAccountHint;
    } else if (lowerName.contains('name')) {
      return nameHint;
    } else if (lowerName.contains('national_code')) {
      return nationalCodeHint;
    } else if (lowerName.contains('mobile')) {
      return mobileHint;
    } else if (lowerName.contains('phone')) {
      return phoneHint;
    } else if (lowerName.contains('postal_code')) {
      return postalCodeHint;
    } else if (lowerName.contains('website')) {
      return websiteHint;
    } else if (lowerName.contains('sayad_id')) {
      return sayadIdHint;
    } else if (lowerName.contains('national_id')) {
      return companyNationalIdHint;
    } else if (lowerName.contains('plate_number') || lowerName.contains('plate')) {
      return plateNumberHint;
    } else if (lowerName.contains('region_code')) {
      return regionCodeHint;
    } else if (lowerName.contains('otp')) {
      return otpHint;
    }
    
    return null;
  }
}
