import 'dart:math' as math;

import 'package:flutter/services.dart';

/// نگاشت کاراکترهای عددی غیرانگلیسی به معادل انگلیسی
const Map<String, String> _digitMapping = {
  // فارسی
  '۰': '0',
  '۱': '1',
  '۲': '2',
  '۳': '3',
  '۴': '4',
  '۵': '5',
  '۶': '6',
  '۷': '7',
  '۸': '8',
  '۹': '9',
  // عربی
  '٠': '0',
  '١': '1',
  '٢': '2',
  '٣': '3',
  '٤': '4',
  '٥': '5',
  '٦': '6',
  '٧': '7',
  '٨': '8',
  '٩': '9',
  // کاراکترهای مرتبط در زبان‌های شبه‌هندی
  '০': '0',
  '১': '1',
  '২': '2',
  '৩': '3',
  '৪': '4',
  '৫': '5',
  '৬': '6',
  '৭': '7',
  '৮': '8',
  '৯': '9',
  '०': '0',
  '१': '1',
  '२': '2',
  '३': '3',
  '४': '4',
  '५': '5',
  '६': '6',
  '७': '7',
  '८': '8',
  '९': '9',
};

/// تبدیل هر رشته‌ای از ارقام فارسی/عربی/هندی به ارقام انگلیسی
String toEnglishDigits(String input) {
  if (input.isEmpty) {
    return input;
  }

  final buffer = StringBuffer();
  for (final char in input.runes) {
    final key = String.fromCharCode(char);
    buffer.write(_digitMapping[key] ?? key);
  }
  return buffer.toString();
}

/// تبدیل شماره موبایل ایرانی به فرمت بین‌المللی (E164)
/// فرمت‌های ورودی پشتیبانی شده:
/// - 09183282405 -> +989183282405
/// - 009183282405 -> +989183282405
/// - 989183282405 -> +989183282405
/// - +989183282405 -> +989183282405 (بدون تغییر)
String normalizeIranianMobileToE164(String input) {
  if (input.isEmpty) {
    return input;
  }

  // تبدیل ارقام فارسی به انگلیسی
  String cleaned = toEnglishDigits(input.trim());
  
  // حذف فاصله‌ها و کاراکترهای غیرعددی (به جز +)
  cleaned = cleaned.replaceAll(RegExp(r'[\s\-\(\)]'), '');
  
  // اگر از قبل فرمت E164 دارد، برگردان
  if (cleaned.startsWith('+989')) {
    return cleaned;
  }
  
  // حذف + اگر در ابتدا باشد (برای پردازش)
  if (cleaned.startsWith('+')) {
    cleaned = cleaned.substring(1);
  }
  
  // تبدیل فرمت‌های مختلف به +989...
  if (cleaned.startsWith('00989')) {
    // فرمت 00989...
    return '+989${cleaned.substring(5)}';
  } else if (cleaned.startsWith('989') && cleaned.length >= 12) {
    // فرمت 989... (بدون صفر)
    return '+$cleaned';
  } else if (cleaned.startsWith('09') && cleaned.length == 11) {
    // فرمت 091... (فرمت رایج ایرانی)
    return '+989${cleaned.substring(2)}';
  } else if (cleaned.startsWith('9') && cleaned.length == 10) {
    // فرمت 9... (بدون صفر و کد کشور)
    return '+989$cleaned';
  }
  
  // اگر فرمت شناخته شده نیست، همان را برگردان
  return input;
}

/// تبدیل بازگشتی ساختارهای Map/List برای ارسال به بک‌اند
dynamic normalizeDynamic(dynamic value) {
  if (value is String) {
    return toEnglishDigits(value);
  }
  if (value is List) {
    return value.map(normalizeDynamic).toList();
  }
  if (value is Map) {
    return value.map(
      (key, dynamic v) => MapEntry(key, normalizeDynamic(v)),
    );
  }
  return value;
}

/// تبدیل Map کوئری‌ها بدون تغییر مرجع اصلی
Map<String, dynamic> normalizeQueryParameters(Map<String, dynamic> params) {
  final result = <String, dynamic>{};
  params.forEach((key, value) {
    result[key] = normalizeDynamic(value);
  });
  return result;
}

/// TextInputFormatter برای تبدیل لحظه‌ای ارقام در فیلدهای متنی
class EnglishDigitsFormatter extends TextInputFormatter {
  const EnglishDigitsFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final converted = toEnglishDigits(newValue.text);
    if (converted == newValue.text) {
      return newValue;
    }

    int clampOffset(int offset) {
      if (offset < 0) return -1;
      return math.min(converted.length, offset);
    }

    final selection = TextSelection(
      baseOffset: clampOffset(newValue.selection.baseOffset),
      extentOffset: clampOffset(newValue.selection.extentOffset),
      affinity: newValue.selection.affinity,
      isDirectional: newValue.selection.isDirectional,
    );

    return TextEditingValue(
      text: converted,
      selection: selection,
      composing: newValue.composing,
    );
  }
}

String _stripTrailingZerosAndDot(String s) {
  if (!s.contains('.')) return s;
  var out = s;
  while (out.endsWith('0')) {
    out = out.substring(0, out.length - 1);
  }
  if (out.endsWith('.')) {
    out = out.substring(0, out.length - 1);
  }
  return out;
}

/// نمایش نرخ تسعیر و اعداد مشابه: جداکننده هزارگان و حذف صفرهای انتهایی اعشار.
String formatFxRateForDisplay(dynamic value) {
  if (value == null) return '—';
  final raw = value.toString().trim();
  if (raw.isEmpty || raw == '—') return '—';

  var canonical = toEnglishDigits(raw.replaceAll(RegExp(r'[\s,]'), ''));
  if (canonical.isEmpty) return '—';

  final n = num.tryParse(canonical);
  if (n == null) return raw;

  var s = n.toDouble().toStringAsFixed(12);
  s = _stripTrailingZerosAndDot(s);
  return _addThousandsSeparator(s);
}

/// فرمت کردن عدد برای نمایش در فیلد ورودی با جداکننده هزارگان
String formatNumberForInput(num? value, {int? decimalPlaces}) {
  if (value == null) return '';
  
  String text;
  if (decimalPlaces != null && decimalPlaces > 0) {
    text = value.toStringAsFixed(decimalPlaces);
  } else {
    // اگر عدد اعشاری است اما بخش اعشاری صفر است، بدون اعشار نمایش بده
    if (value % 1 == 0) {
      text = value.toInt().toString();
    } else {
      text = value.toString();
    }
  }
  
  return _addThousandsSeparator(text);
}

/// تبدیل رشته فرمت‌شده با جداکننده هزارگان به عدد
num? parseFormattedNumber(String? value) {
  if (value == null || value.isEmpty) return null;
  
  // حذف جداکننده‌های هزارگان و تبدیل به عدد
  final cleanValue = value.replaceAll(',', '').trim();
  if (cleanValue.isEmpty) return null;
  
  return num.tryParse(cleanValue);
}

/// تبدیل رشته فرمت‌شده به double
double? parseFormattedDouble(String? value) {
  final numValue = parseFormattedNumber(value);
  return numValue?.toDouble();
}

/// تبدیل رشته فرمت‌شده به int
int? parseFormattedInt(String? value) {
  final numValue = parseFormattedNumber(value);
  return numValue?.toInt();
}

/// افزودن جداکننده هزارگان به رشته عددی
String _addThousandsSeparator(String text) {
  if (text.isEmpty) return text;
  
  // جدا کردن بخش صحیح و اعشاری
  final parts = text.split('.');
  String integerPart = parts[0];
  String decimalPart = parts.length > 1 ? '.${parts[1]}' : '';
  
  // افزودن جداکننده هزارگان به بخش صحیح
  if (integerPart.isEmpty) return text;
  
  // اگر عدد منفی است، علامت منفی را جدا کن
  bool isNegative = integerPart.startsWith('-');
  if (isNegative) {
    integerPart = integerPart.substring(1);
  }
  
  String reversed = integerPart.split('').reversed.join('');
  String withCommas = reversed.replaceAllMapped(
    RegExp(r'(\d{3})(?=\d)'),
    (Match match) => '${match.group(1)},',
  );
  String formattedInteger = withCommas.split('').reversed.join('');
  
  if (isNegative) {
    formattedInteger = '-$formattedInteger';
  }
  
  return formattedInteger + decimalPart;
}

/// تبدیل مقادیر JSON (عدد، رشته) به [double] بدون پرتاب در web وقتی نوع غیرمنتظره
/// (مثلاً [bool]) از سمت API/ذخیرهٔ قدیمی برسد.
double parseJsonDouble(dynamic value, [double fallback = 0.0]) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  if (value is String) {
    final t = value.trim();
    if (t.isEmpty) return fallback;
    return double.tryParse(t.replaceAll(',', '')) ?? fallback;
  }
  return fallback;
}

/// نسخهٔ nullable برای فیلدهای اختیاری مثل کارمزد.
double? parseJsonDoubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) {
    final t = value.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t.replaceAll(',', ''));
  }
  return null;
}

/// TextInputFormatter برای افزودن جداکننده هزارگان به اعداد
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  final bool allowDecimal;
  
  const ThousandsSeparatorInputFormatter({this.allowDecimal = true});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // اگر متن خالی است
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // حذف کاراکترهای غیرمجاز (فقط اعداد، نقطه اعشار و علامت منفی)
    String cleanText = newValue.text.replaceAll(RegExp(r'[^\d.\-]'), '');
    
    // اگر اعشار مجاز نیست، نقطه را حذف کن
    if (!allowDecimal) {
      cleanText = cleanText.replaceAll('.', '');
    }
    
    // مدیریت نقطه اعشار (فقط یک نقطه)
    final dotIndex = cleanText.indexOf('.');
    if (dotIndex != -1) {
      final beforeDot = cleanText.substring(0, dotIndex);
      final afterDot = cleanText.substring(dotIndex + 1).replaceAll('.', '');
      cleanText = '$beforeDot.$afterDot';
    }
    
    // مدیریت علامت منفی (فقط در ابتدا)
    bool isNegative = cleanText.startsWith('-');
    if (isNegative) {
      cleanText = cleanText.substring(1);
    }
    cleanText = cleanText.replaceAll('-', '');
    if (isNegative) {
      cleanText = '-$cleanText';
    }

    // فرمت کردن با جداکننده هزارگان
    String formattedText = _addThousandsSeparator(cleanText);

    // محاسبه موقعیت جدید مکان‌نما
    int selectionOffset = _calculateCursorPosition(
      oldValue.text,
      newValue.text,
      formattedText,
      newValue.selection.baseOffset,
    );

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: selectionOffset),
      composing: newValue.composing,
    );
  }

  /// محاسبه موقعیت صحیح مکان‌نما بعد از فرمت کردن
  int _calculateCursorPosition(
    String oldText,
    String newText,
    String formattedText,
    int oldCursorPosition,
  ) {
    // شمارش کاراکترهای عددی قبل از موقعیت مکان‌نما در متن جدید
    int digitsBeforeCursor = 0;
    for (int i = 0; i < oldCursorPosition && i < newText.length; i++) {
      if (RegExp(r'[\d.\-]').hasMatch(newText[i])) {
        digitsBeforeCursor++;
      }
    }
    
    // پیدا کردن موقعیت در متن فرمت‌شده
    int digitsCounted = 0;
    for (int i = 0; i < formattedText.length; i++) {
      if (RegExp(r'[\d.\-]').hasMatch(formattedText[i])) {
        digitsCounted++;
        if (digitsCounted >= digitsBeforeCursor) {
          return i + 1;
        }
      }
    }
    
    return formattedText.length;
  }
}

/// TextInputFormatter ترکیبی برای تبدیل ارقام فارسی و افزودن جداکننده هزارگان با حفظ موقعیت کرسر
class NumberInputFormatter extends TextInputFormatter {
  final bool allowDecimal;
  
  const NumberInputFormatter({this.allowDecimal = true});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // اگر متن خالی است
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // تبدیل ارقام فارسی به انگلیسی
    String converted = toEnglishDigits(newValue.text);
    
    // حذف کاراکترهای غیرمجاز (فقط اعداد، نقطه اعشار و علامت منفی)
    String cleanText = converted.replaceAll(RegExp(r'[^\d.\-]'), '');
    
    // اگر اعشار مجاز نیست، نقطه را حذف کن
    if (!allowDecimal) {
      cleanText = cleanText.replaceAll('.', '');
    }
    
    // مدیریت نقطه اعشار (فقط یک نقطه)
    final dotIndex = cleanText.indexOf('.');
    if (dotIndex != -1) {
      final beforeDot = cleanText.substring(0, dotIndex);
      final afterDot = cleanText.substring(dotIndex + 1).replaceAll('.', '');
      cleanText = '$beforeDot.$afterDot';
    }
    
    // مدیریت علامت منفی (فقط در ابتدا)
    bool isNegative = cleanText.startsWith('-');
    if (isNegative) {
      cleanText = cleanText.substring(1);
    }
    cleanText = cleanText.replaceAll('-', '');
    if (isNegative) {
      cleanText = '-$cleanText';
    }

    // فرمت کردن با جداکننده هزارگان
    String formattedText = _addThousandsSeparator(cleanText);

    // محاسبه موقعیت کرسر در cleanText (بدون کاما)
    // باید موقعیت کرسر را در newValue.text به موقعیت در cleanText تبدیل کنیم
    int cleanTextCursorPosition = _convertCursorPositionToCleanText(
      newValue.text,
      newValue.selection.baseOffset,
    );

    // محاسبه موقعیت جدید مکان‌نما
    int selectionOffset = _calculateCursorPosition(
      oldValue.text.replaceAll(',', ''),
      cleanText,
      formattedText,
      cleanTextCursorPosition,
    );

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: selectionOffset),
      composing: newValue.composing,
    );
  }

  /// تبدیل موقعیت کرسر از متن با کاما به متن بدون کاما
  int _convertCursorPositionToCleanText(String textWithCommas, int cursorPosition) {
    if (cursorPosition >= textWithCommas.length) {
      // اگر کرسر در انتهاست، تعداد کاراکترهای عددی را بشمار
      int count = 0;
      for (int i = 0; i < textWithCommas.length; i++) {
        if (RegExp(r'[\d.\-]').hasMatch(textWithCommas[i])) {
          count++;
        }
      }
      return count;
    }
    
    // شمارش کاراکترهای عددی قبل از موقعیت کرسر
    int count = 0;
    for (int i = 0; i < cursorPosition && i < textWithCommas.length; i++) {
      if (RegExp(r'[\d.\-]').hasMatch(textWithCommas[i])) {
        count++;
      }
    }
    return count;
  }

  /// محاسبه موقعیت صحیح مکان‌نما بعد از فرمت کردن
  int _calculateCursorPosition(
    String oldText,
    String newText,
    String formattedText,
    int newCursorPosition,
  ) {
    // اگر متن خالی است
    if (formattedText.isEmpty) {
      return 0;
    }

    // newText در اینجا cleanText است (بدون کاما)
    // oldText هم بدون کاما است
    
    // اگر کرسر در انتهاست، آن را در انتها نگه دار
    if (newCursorPosition >= newText.length) {
      return formattedText.length;
    }
    
    // تعداد کاراکترهای عددی (ارقام، نقطه، منفی) قبل از کرسر در متن جدید
    // چون newText بدون کاما است، می‌توانیم مستقیماً از newCursorPosition استفاده کنیم
    int charsBeforeCursor = newCursorPosition;
    
    // اگر هیچ کاراکتری قبل از کرسر نیست
    if (charsBeforeCursor == 0) {
      if (formattedText.startsWith('-')) {
        return 1;
      }
      return 0;
    }
    
    // پیدا کردن موقعیت در متن فرمت‌شده
    // باید تعداد کاراکترهای عددی (بدون کاما) را بشماریم تا به تعداد مورد نظر برسیم
    int charsCounted = 0;
    for (int i = 0; i < formattedText.length; i++) {
      final char = formattedText[i];
      if (RegExp(r'[\d.\-]').hasMatch(char)) {
        charsCounted++;
        // وقتی به تعداد کاراکترهای قبل از کرسر رسیدیم
        if (charsCounted >= charsBeforeCursor) {
          // موقعیت کرسر را بعد از این کاراکتر قرار بده
          return i + 1;
        }
      }
    }
    
    // اگر به انتها رسیدیم، موقعیت را در انتها قرار بده
    return formattedText.length;
  }
}

