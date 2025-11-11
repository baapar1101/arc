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

