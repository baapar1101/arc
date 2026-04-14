import 'dart:convert';

/// حداکثر طول رمز عبور بر اساس بایت UTF-8 (محدودیت bcrypt).
const int kMaxPasswordBytes = 72;

/// بررسی می‌کند که رمز از نظر بایت UTF-8 از حد مجاز بیشتر نباشد.
bool passwordExceedsMaxBytes(String? value) {
  if (value == null || value.isEmpty) return false;
  return utf8.encode(value).length > kMaxPasswordBytes;
}

/// اعتبارسنجی رمز برای فرم‌ها.
/// [minLength] حداقل طول کاراکتری (اختیاری).
/// [maxBytes] حداکثر بایت UTF-8 (پیش‌فرض ۷۲ برای bcrypt).
/// برمی‌گرداند: پیام خطا یا null اگر معتبر باشد.
String? validatePassword({
  required String? value,
  required String? Function() getRequiredError,
  required String? Function() getMinLengthError,
  required String? Function() getMaxLengthError,
  int? minLength,
  int maxBytes = kMaxPasswordBytes,
}) {
  if (value == null || value.isEmpty) {
    return getRequiredError();
  }
  if (minLength != null && value.length < minLength) {
    return getMinLengthError();
  }
  if (utf8.encode(value).length > maxBytes) {
    return getMaxLengthError();
  }
  return null;
}
