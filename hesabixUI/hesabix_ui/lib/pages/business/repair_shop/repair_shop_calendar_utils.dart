import '../../../core/date_utils.dart';

/// کمک‌کننده‌های تاریخ افزونه تعمیرگاه — نمایش مطابق تقویم انتخاب‌شده کاربر.
class RepairShopCalendarUtils {
  RepairShopCalendarUtils._();

  /// تاریخ + ساعت (برای received_at، completed_at و ...)
  static String formatDateTime(
    dynamic value,
    bool isJalali, {
    String fallback = '-',
    dynamic rawValue,
  }) {
    final parsed = HesabixDateUtils.parseApiDate(value, rawValue: rawValue);
    if (parsed != null) {
      return HesabixDateUtils.formatDateTime(parsed, isJalali);
    }
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String formatDateTimeFromRow(
    Map<String, dynamic> row,
    String key,
    bool isJalali, {
    String fallback = '-',
  }) {
    return formatDateTime(
      row[key],
      isJalali,
      fallback: fallback,
      rawValue: row['${key}_raw'],
    );
  }

  /// فقط تاریخ (برای estimated_delivery_at و فیلترها)
  static String formatDate(
    dynamic value,
    bool isJalali, {
    String fallback = '-',
    dynamic rawValue,
  }) {
    return HesabixDateUtils.formatApiDateForDisplay(
      value,
      isJalali,
      fallback: fallback,
      rawValue: rawValue,
    );
  }

  static DateTime? parseApiDateTime(Map<String, dynamic> json, String key) {
    return HesabixDateUtils.parseApiDate(
      json[key],
      rawValue: json['${key}_raw'],
    );
  }
}
