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

