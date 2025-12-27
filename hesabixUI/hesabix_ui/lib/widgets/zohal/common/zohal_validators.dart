import '../../../utils/number_normalizer.dart';

/// اعتبارسنج‌های مشترک برای فرم‌های استعلام زحل
class ZohalValidators {
  /// اعتبارسنجی شماره کارت بانکی (16 رقم)
  static String? validateCardNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'شماره کارت الزامی است';
    }
    
    final cleaned = toEnglishDigits(value.trim()).replaceAll(RegExp(r'[^\d]'), '');
    
    if (cleaned.length != 16) {
      return 'شماره کارت باید 16 رقم باشد';
    }
    
    if (!RegExp(r'^\d{16}$').hasMatch(cleaned)) {
      return 'شماره کارت نامعتبر است';
    }
    
    // اعتبارسنجی الگوریتم Luhn (اختیاری - برای بررسی دقیق‌تر)
    if (!_isValidLuhn(cleaned)) {
      return 'شماره کارت نامعتبر است';
    }
    
    return null;
  }

  /// اعتبارسنجی شماره شبا (IR + 24 رقم)
  static String? validateIban(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'شماره شبا الزامی است';
    }
    
    final cleaned = toEnglishDigits(value.trim().replaceAll(RegExp(r'[\s\-]'), ''));
    
    // فرمت IRXXXXXXXXXXXX (24 رقم بعد از IR)
    if (!RegExp(r'^IR\d{24}$', caseSensitive: false).hasMatch(cleaned)) {
      return 'شماره شبا باید با IR شروع شده و 24 رقم داشته باشد';
    }
    
    return null;
  }

  /// اعتبارسنجی کد ملی ایرانی (10 رقم)
  static String? validateNationalCode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'کد ملی الزامی است';
    }
    
    final cleaned = toEnglishDigits(value.trim()).replaceAll(RegExp(r'[^\d]'), '');
    
    if (cleaned.length != 10) {
      return 'کد ملی باید 10 رقم باشد';
    }
    
    if (!RegExp(r'^\d{10}$').hasMatch(cleaned)) {
      return 'کد ملی نامعتبر است';
    }
    
    // اعتبارسنجی الگوریتم کد ملی ایرانی
    if (!_isValidNationalCode(cleaned)) {
      return 'کد ملی نامعتبر است';
    }
    
    return null;
  }

  /// اعتبارسنجی شماره موبایل ایرانی
  static String? validateMobile(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'شماره موبایل الزامی است';
    }
    
    final cleaned = toEnglishDigits(value.trim()).replaceAll(RegExp(r'[^\d]'), '');
    
    // فرمت: 09123456789 یا 9123456789
    if (!RegExp(r'^(09|9)\d{9}$').hasMatch(cleaned)) {
      return 'شماره موبایل معتبر نیست (مثال: 09123456789)';
    }
    
    return null;
  }

  /// اعتبارسنجی کد پستی (10 رقم)
  static String? validatePostalCode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'کد پستی الزامی است';
    }
    
    final cleaned = toEnglishDigits(value.trim()).replaceAll(RegExp(r'[^\d]'), '');
    
    if (cleaned.length != 10) {
      return 'کد پستی باید 10 رقم باشد';
    }
    
    if (!RegExp(r'^\d{10}$').hasMatch(cleaned)) {
      return 'کد پستی نامعتبر است';
    }
    
    return null;
  }

  /// اعتبارسنجی شماره حساب بانکی
  static String? validateBankAccount(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'شماره حساب الزامی است';
    }
    
    final cleaned = toEnglishDigits(value.trim()).replaceAll(RegExp(r'[^\d]'), '');
    
    if (cleaned.length < 5 || cleaned.length > 19) {
      return 'شماره حساب باید بین 5 تا 19 رقم باشد';
    }
    
    return null;
  }

  /// اعتبارسنجی کد بانک (2 تا 3 رقم)
  static String? validateBankCode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'کد بانک الزامی است';
    }
    
    final cleaned = toEnglishDigits(value.trim()).replaceAll(RegExp(r'[^\d]'), '');
    
    if (cleaned.length < 2 || cleaned.length > 3) {
      return 'کد بانک باید 2 یا 3 رقم باشد';
    }
    
    return null;
  }

  /// اعتبارسنجی نام فارسی
  static String? validatePersianName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'نام الزامی است';
    }
    
    final trimmed = value.trim();
    
    if (trimmed.length < 2) {
      return 'نام باید حداقل 2 کاراکتر باشد';
    }
    
    // بررسی اینکه فقط حروف فارسی و فاصله داشته باشد
    if (!RegExp(r'^[\u0600-\u06FF\s]+$').hasMatch(trimmed)) {
      return 'لطفاً نام را به فارسی وارد کنید';
    }
    
    return null;
  }

  /// اعتبارسنجی URL
  static String? validateUrl(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'آدرس وب‌سایت الزامی است';
    }
    
    final trimmed = value.trim();
    
    // بررسی فرمت URL
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      // اگر scheme ندارد، http:// اضافه می‌کنیم و دوباره بررسی می‌کنیم
      final uriWithScheme = Uri.tryParse('http://$trimmed');
      if (uriWithScheme == null || !uriWithScheme.hasAuthority) {
        return 'آدرس وب‌سایت معتبر نیست (مثال: example.com یا www.example.com)';
      }
    }
    
    return null;
  }

  /// اعتبارسنجی شناسه صیادی (16 رقم)
  static String? validateSayadId(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'شناسه صیادی الزامی است';
    }
    
    final cleaned = toEnglishDigits(value.trim()).replaceAll(RegExp(r'[^\d]'), '');
    
    if (cleaned.length != 16) {
      return 'شناسه صیادی باید 16 رقم باشد';
    }
    
    return null;
  }

  /// اعتبارسنجی شماره پلاک خودرو
  static String? validatePlateNumber(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'شماره پلاک الزامی است';
    }
    
    final trimmed = value.trim();
    
    if (trimmed.length < 5) {
      return 'شماره پلاک معتبر نیست';
    }
    
    return null;
  }

  /// اعتبارسنجی کد منطقه
  static String? validateRegionCode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'کد منطقه الزامی است';
    }
    
    final cleaned = toEnglishDigits(value.trim()).replaceAll(RegExp(r'[^\d]'), '');
    
    if (cleaned.isEmpty || cleaned.length > 3) {
      return 'کد منطقه معتبر نیست';
    }
    
    return null;
  }

  /// اعتبارسنجی شناسه ملی شرکت
  static String? validateCompanyNationalId(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'شناسه ملی شرکت الزامی است';
    }
    
    final cleaned = toEnglishDigits(value.trim()).replaceAll(RegExp(r'[^\d]'), '');
    
    if (cleaned.length != 11) {
      return 'شناسه ملی شرکت باید 11 رقم باشد';
    }
    
    return null;
  }

  /// اعتبارسنجی OTP (4 تا 6 رقم)
  static String? validateOtp(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'کد تایید الزامی است';
    }
    
    final cleaned = toEnglishDigits(value.trim()).replaceAll(RegExp(r'[^\d]'), '');
    
    if (cleaned.length < 4 || cleaned.length > 6) {
      return 'کد تایید باید 4 تا 6 رقم باشد';
    }
    
    return null;
  }

  /// اعتبارسنجی نوع ملیت
  static String? validateNationalityType(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'نوع ملیت الزامی است';
    }
    
    final cleaned = toEnglishDigits(value.trim());
    final type = int.tryParse(cleaned);
    
    if (type == null || (type != 1 && type != 2)) {
      return 'نوع ملیت باید 1 (ایرانی) یا 2 (غیرایرانی) باشد';
    }
    
    return null;
  }

  // ==================== Helper Methods ====================

  /// بررسی الگوریتم Luhn برای شماره کارت
  static bool _isValidLuhn(String cardNumber) {
    int sum = 0;
    bool alternate = false;
    
    for (int i = cardNumber.length - 1; i >= 0; i--) {
      int n = int.parse(cardNumber[i]);
      
      if (alternate) {
        n *= 2;
        if (n > 9) {
          n = (n % 10) + 1;
        }
      }
      
      sum += n;
      alternate = !alternate;
    }
    
    return (sum % 10) == 0;
  }

  /// بررسی الگوریتم کد ملی ایرانی
  static bool _isValidNationalCode(String code) {
    // کدهای یکسان معتبر نیستند
    if (RegExp(r'^(\d)\1{9}$').hasMatch(code)) {
      return false;
    }
    
    if (code.isEmpty) {
      return false;
    }
    
    int sum = 0;
    for (int i = 0; i < 9; i++) {
      sum += int.parse(code[i]) * (10 - i);
    }
    
    int remainder = sum % 11;
    int checkDigit = int.parse(code[9]);
    
    if (remainder < 2) {
      return checkDigit == remainder;
    } else {
      return checkDigit == (11 - remainder);
    }
  }
}
