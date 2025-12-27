import 'package:flutter/services.dart';
import '../../../utils/number_normalizer.dart';

/// فرمترهای ورودی برای فیلدهای استعلام زحل
class ZohalInputFormatters {
  /// فرمتر شماره کارت (16 رقم با فاصله: XXXX-XXXX-XXXX-XXXX)
  static List<TextInputFormatter> cardNumber() => [
    EnglishDigitsFormatter(),
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(16),
    CardNumberFormatter(),
  ];

  /// فرمتر کد ملی (10 رقم)
  static List<TextInputFormatter> nationalCode() => [
    EnglishDigitsFormatter(),
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(10),
  ];

  /// فرمتر شماره موبایل (11 رقم: 09XXXXXXXXX)
  static List<TextInputFormatter> mobile() => [
    EnglishDigitsFormatter(),
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(11),
  ];

  /// فرمتر شماره شبا (IR + 24 رقم)
  static List<TextInputFormatter> iban() => [
    EnglishDigitsFormatter(),
    FilteringTextInputFormatter.allow(RegExp(r'[IRir0-9\s\-]')),
    LengthLimitingTextInputFormatter(28), // IR + 24 رقم + فاصله
    IbanFormatter(),
  ];

  /// فرمتر کد پستی (10 رقم)
  static List<TextInputFormatter> postalCode() => [
    EnglishDigitsFormatter(),
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(10),
  ];

  /// فرمتر شماره حساب (حداکثر 19 رقم)
  static List<TextInputFormatter> bankAccount() => [
    EnglishDigitsFormatter(),
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(19),
  ];

  /// فرمتر کد بانک (2-3 رقم)
  static List<TextInputFormatter> bankCode() => [
    EnglishDigitsFormatter(),
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(3),
  ];

  /// فرمتر شناسه صیادی (16 رقم)
  static List<TextInputFormatter> sayadId() => [
    EnglishDigitsFormatter(),
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(16),
  ];

  /// فرمتر شناسه ملی شرکت (11 رقم)
  static List<TextInputFormatter> companyNationalId() => [
    EnglishDigitsFormatter(),
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(11),
  ];

  /// فرمتر OTP (4-6 رقم)
  static List<TextInputFormatter> otp() => [
    EnglishDigitsFormatter(),
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(6),
  ];

  /// فرمتر کد منطقه (1-3 رقم)
  static List<TextInputFormatter> regionCode() => [
    EnglishDigitsFormatter(),
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(3),
  ];
}

/// فرمتر شماره کارت با جداکننده خط تیره
class CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    
    if (text.isEmpty) {
      return newValue.copyWith(text: '');
    }
    
    // تقسیم به گروه‌های 4 تایی
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      if (i > 0 && i % 4 == 0) {
        buffer.write('-');
      }
      buffer.write(text[i]);
    }
    
    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
  }
}

/// فرمتر شماره شبا با فرمت IR XX XXXX XXXX XXXX XXXX XXXX XX
class IbanFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text.toUpperCase().replaceAll(RegExp(r'[^IR0-9]'), '');
    
    // اطمینان از شروع با IR
    if (text.isNotEmpty && !text.startsWith('IR')) {
      if (text.startsWith('I')) {
        if (text.length == 1 || (text.length > 1 && text[1] != 'R')) {
          text = 'IR${text.substring(1)}';
        }
      } else {
        text = 'IR$text';
      }
    }
    
    if (text.isEmpty) {
      return newValue.copyWith(text: '');
    }
    
    // فقط IR را نمایش می‌دهیم، بعد از آن اعداد را با فاصله گروه‌بندی می‌کنیم
    if (text.length <= 2) {
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    
    final digits = text.substring(2);
    final buffer = StringBuffer('IR');
    
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) {
        buffer.write(' ');
      }
      buffer.write(digits[i]);
    }
    
    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
  }
}
