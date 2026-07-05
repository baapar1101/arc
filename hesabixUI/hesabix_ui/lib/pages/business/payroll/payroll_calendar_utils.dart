import 'package:shamsi_date/shamsi_date.dart';

import '../../../core/date_utils.dart';

/// کمک‌کننده‌های تاریخ حقوق: دوره‌ها در API با سال/ماه شمسی ذخیره می‌شوند؛
/// نمایش و ورودی مطابق تقویم انتخاب‌شده کاربر است.
class PayrollCalendarUtils {
  PayrollCalendarUtils._();

  static String formatRunDate(
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

  static String formatRowDate(
    Map<String, dynamic> row,
    String key,
    bool isJalali, {
    String fallback = '-',
  }) {
    return HesabixDateUtils.formatApiDateForDisplay(
      row[key],
      isJalali,
      fallback: fallback,
      rawValue: row['${key}_raw'],
    );
  }

  /// نمایش سال/ماه دوره ذخیره‌شده (شمسی) در تقویم فعال کاربر.
  static String formatPeriodYearMonth(int jalaliYear, int jalaliMonth, bool isJalali) {
    if (isJalali) {
      return '$jalaliYear/${jalaliMonth.toString().padLeft(2, '0')}';
    }
    try {
      final dt = Jalali(jalaliYear, jalaliMonth, 1).toDateTime();
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}';
    } catch (_) {
      return '$jalaliYear/${jalaliMonth.toString().padLeft(2, '0')}';
    }
  }

  static String periodTitle(Map<String, dynamic> period, bool isJalali) {
    final title = '${period['title'] ?? ''}'.trim();
    if (title.isNotEmpty) return title;
    final y = (period['year'] as num?)?.toInt();
    final m = (period['month'] as num?)?.toInt();
    if (y == null || m == null) return '';
    return formatPeriodYearMonth(y, m, isJalali);
  }

  /// سال/ماه پیش‌فرض برای فرم دوره (نمایش در UI).
  static ({int year, int month}) defaultDisplayYearMonth(bool isJalali) {
    final now = DateTime.now();
    if (isJalali) {
      final j = Jalali.fromDateTime(now);
      return (year: j.year, month: j.month);
    }
    return (year: now.year, month: now.month);
  }

  /// تبدیل سال/ماه واردشده در UI به سال/ماه شمسی برای API.
  static ({int year, int month}) toApiYearMonth(int displayYear, int displayMonth, bool isJalali) {
    if (isJalali) {
      return (year: displayYear, month: displayMonth);
    }
    try {
      final j = Jalali.fromDateTime(DateTime(displayYear, displayMonth, 1));
      return (year: j.year, month: j.month);
    } catch (_) {
      final j = Jalali.fromDateTime(DateTime.now());
      return (year: j.year, month: j.month);
    }
  }

  /// سال نمایشی دوره (بر اساس تقویم فعال کاربر).
  static int displayYearFromPeriod(Map<String, dynamic> period, bool isJalali) {
    final jy = (period['year'] as num?)?.toInt();
    final jm = (period['month'] as num?)?.toInt() ?? 1;
    if (jy == null) return defaultDisplayYearMonth(isJalali).year;
    if (isJalali) return jy;
    try {
      return Jalali(jy, jm, 1).toDateTime().year;
    } catch (_) {
      return jy;
    }
  }

  /// سال‌های قابل انتخاب در گزارش (بر اساس تقویم نمایش).
  static List<int> displayYearsFromPeriods(List<Map<String, dynamic>> periods, bool isJalali) {
    final years = <int>{};
    for (final p in periods) {
      final jy = (p['year'] as num?)?.toInt();
      final jm = (p['month'] as num?)?.toInt() ?? 1;
      if (jy == null) continue;
      if (isJalali) {
        years.add(jy);
      } else {
        try {
          years.add(Jalali(jy, jm, 1).toDateTime().year);
        } catch (_) {
          years.add(jy);
        }
      }
    }
    final list = years.toList()..sort();
    if (list.isEmpty) {
      final d = defaultDisplayYearMonth(isJalali);
      return [d.year];
    }
    return list;
  }

  /// فیلتر دوره‌ها برای سال انتخاب‌شده در گزارش (سال نمایشی).
  static bool periodMatchesDisplayYear(
    Map<String, dynamic> period,
    int displayYear,
    bool isJalali,
  ) {
    final jy = (period['year'] as num?)?.toInt();
    final jm = (period['month'] as num?)?.toInt() ?? 1;
    if (jy == null) return false;
    if (isJalali) return jy == displayYear;
    try {
      return Jalali(jy, jm, 1).toDateTime().year == displayYear;
    } catch (_) {
      return false;
    }
  }
}
