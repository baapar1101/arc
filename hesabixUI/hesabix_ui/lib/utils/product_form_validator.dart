import '../../models/product_form_data.dart';

class ProductFormValidator {
  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'نام کالا الزامی است';
    }
    if (value.trim().length < 2) {
      return 'نام کالا باید حداقل ۲ کاراکتر باشد';
    }
    return null;
  }

  static String? validateCode(String? value) {
    if (value != null && value.trim().isNotEmpty) {
      if (value.trim().length < 2) {
        return 'کد کالا باید حداقل ۲ کاراکتر باشد';
      }
      // Add more code validation rules if needed
    }
    return null;
  }

  static String? validatePrice(String? value, {String fieldName = 'قیمت'}) {
    if (value != null && value.trim().isNotEmpty) {
      final price = num.tryParse(value.replaceAll(',', ''));
      if (price == null) {
        return '$fieldName باید عدد معتبر باشد';
      }
      if (price < 0) {
        return '$fieldName نمی‌تواند منفی باشد';
      }
    }
    return null;
  }

  static String? validateQuantity(String? value, {String fieldName = 'مقدار'}) {
    if (value != null && value.trim().isNotEmpty) {
      final quantity = int.tryParse(value);
      if (quantity == null) {
        return '$fieldName باید عدد صحیح باشد';
      }
      if (quantity < 0) {
        return '$fieldName نمی‌تواند منفی باشد';
      }
    }
    return null;
  }

  static String? validateConversionFactor(String? value) {
    if (value != null && value.trim().isNotEmpty) {
      final factor = num.tryParse(value);
      if (factor == null) {
        return 'ضریب تبدیل باید عدد معتبر باشد';
      }
      if (factor <= 0) {
        return 'ضریب تبدیل باید بزرگتر از صفر باشد';
      }
    }
    return null;
  }

  static String? validateTaxRate(String? value, {String fieldName = 'نرخ مالیات'}) {
    if (value != null && value.trim().isNotEmpty) {
      final rate = num.tryParse(value);
      if (rate == null) {
        return '$fieldName باید عدد معتبر باشد';
      }
      if (rate < 0) {
        return '$fieldName نمی‌تواند منفی باشد';
      }
      if (rate > 100) {
        return '$fieldName نمی‌تواند بیشتر از ۱۰۰٪ باشد';
      }
    }
    return null;
  }

  static String? validateLeadTime(String? value) {
    if (value != null && value.trim().isNotEmpty) {
      final days = int.tryParse(value);
      if (days == null) {
        return 'زمان تحویل باید عدد صحیح باشد';
      }
      if (days < 0) {
        return 'زمان تحویل نمی‌تواند منفی باشد';
      }
      if (days > 365) {
        return 'زمان تحویل نمی‌تواند بیشتر از ۳۶۵ روز باشد';
      }
    }
    return null;
  }

  static Map<String, String> validateFormData(ProductFormData formData) {
    final errors = <String, String>{};

    // Required fields
    if (formData.name.trim().isEmpty) {
      errors['name'] = 'نام کالا الزامی است';
    }

    // Optional field validations
    if (formData.baseSalesPrice != null && formData.baseSalesPrice! < 0) {
      errors['baseSalesPrice'] = 'قیمت فروش نمی‌تواند منفی باشد';
    }

    if (formData.basePurchasePrice != null && formData.basePurchasePrice! < 0) {
      errors['basePurchasePrice'] = 'قیمت خرید نمی‌تواند منفی باشد';
    }

    if (formData.unitConversionFactor != null && formData.unitConversionFactor! <= 0) {
      errors['unitConversionFactor'] = 'ضریب تبدیل باید بزرگتر از صفر باشد';
    }

    if (formData.salesTaxRate != null) {
      if (formData.salesTaxRate! < 0) {
        errors['salesTaxRate'] = 'نرخ مالیات فروش نمی‌تواند منفی باشد';
      } else if (formData.salesTaxRate! > 100) {
        errors['salesTaxRate'] = 'نرخ مالیات فروش نمی‌تواند بیشتر از ۱۰۰٪ باشد';
      }
    }

    if (formData.purchaseTaxRate != null) {
      if (formData.purchaseTaxRate! < 0) {
        errors['purchaseTaxRate'] = 'نرخ مالیات خرید نمی‌تواند منفی باشد';
      } else if (formData.purchaseTaxRate! > 100) {
        errors['purchaseTaxRate'] = 'نرخ مالیات خرید نمی‌تواند بیشتر از ۱۰۰٪ باشد';
      }
    }

    if (formData.reorderPoint != null && formData.reorderPoint! < 0) {
      errors['reorderPoint'] = 'نقطه سفارش مجدد نمی‌تواند منفی باشد';
    }

    if (formData.minOrderQty != null && formData.minOrderQty! < 0) {
      errors['minOrderQty'] = 'کمینه مقدار سفارش نمی‌تواند منفی باشد';
    }

    if (formData.leadTimeDays != null) {
      if (formData.leadTimeDays! < 0) {
        errors['leadTimeDays'] = 'زمان تحویل نمی‌تواند منفی باشد';
      } else if (formData.leadTimeDays! > 365) {
        errors['leadTimeDays'] = 'زمان تحویل نمی‌تواند بیشتر از ۳۶۵ روز باشد';
      }
    }

    return errors;
  }

  static bool isFormValid(ProductFormData formData) {
    return validateFormData(formData).isEmpty;
  }
}
