import 'package:shamsi_date/shamsi_date.dart';

/// Utility class for date management and conversion
class HesabixDateUtils {
  /// Convert DateTime to Jalali string for display
  static String formatForDisplay(DateTime? date, bool isJalali) {
    if (date == null) return '';

    final local = date.toLocal();
    if (isJalali) {
      final jalali = Jalali.fromDateTime(local);
      return '${jalali.year}/${jalali.month.toString().padLeft(2, '0')}/${jalali.day.toString().padLeft(2, '0')}';
    } else {
      return '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
    }
  }

  /// Format a date-like API value according to the active calendar.
  ///
  /// Accepts raw ISO Gregorian dates, DateTime values, backend formatted maps
  /// (`date_only`/`formatted`), and Persian slash dates when no raw value is
  /// available. Prefer passing [rawValue] when the response includes `*_raw`.
  static String formatApiDateForDisplay(dynamic value, bool isJalali, {dynamic rawValue, String fallback = '-'}) {
    final parsedRaw = _parseDateLike(rawValue);
    if (parsedRaw != null) {
      return formatForDisplay(parsedRaw, isJalali);
    }

    final parsed = _parseDateLike(value);
    if (parsed != null) {
      return formatForDisplay(parsed, isJalali);
    }

    if (value is Map) {
      final dateOnly = value['date_only'];
      if (dateOnly != null && dateOnly.toString().trim().isNotEmpty) {
        return dateOnly.toString().trim();
      }
      final formatted = value['formatted'];
      if (formatted != null && formatted.toString().trim().isNotEmpty) {
        return formatted.toString().trim().split(' ').first;
      }
    }

    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static DateTime? parseApiDate(dynamic value, {dynamic rawValue}) {
    return _parseDateLike(rawValue) ?? _parseDateLike(value);
  }

  static DateTime? _parseDateLike(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Map) {
      for (final key in const ['raw', 'gregorian', 'iso', 'date', 'date_only', 'formatted']) {
        final parsed = _parseDateLike(value[key]);
        if (parsed != null) return parsed;
      }
      return null;
    }

    var text = value.toString().trim();
    if (text.isEmpty) return null;
    text = text.split(' ').first;
    text = text.split('T').first;

    final isoMatch = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(text);
    if (isoMatch != null) {
      return _safeGregorianDate(
        int.parse(isoMatch.group(1)!),
        int.parse(isoMatch.group(2)!),
        int.parse(isoMatch.group(3)!),
      );
    }

    final slashMatch = RegExp(r'^(\d{4})/(\d{1,2})/(\d{1,2})$').firstMatch(text);
    if (slashMatch != null) {
      final year = int.parse(slashMatch.group(1)!);
      final month = int.parse(slashMatch.group(2)!);
      final day = int.parse(slashMatch.group(3)!);
      if (year >= 1700) return _safeGregorianDate(year, month, day);
      if (year >= 1200 && year <= 1600) {
        try {
          return Jalali(year, month, day).toDateTime();
        } catch (_) {
          return null;
        }
      }
    }

    return null;
  }

  static DateTime? _safeGregorianDate(int year, int month, int day) {
    try {
      final d = DateTime(year, month, day);
      if (d.year == year && d.month == month && d.day == day) return d;
    } catch (_) {}
    return null;
  }

  /// Format a DateTime for API date-only filters (YYYY-MM-DD).
  ///
  /// Why: Many backend filters treat dates as `date` (no time). Sending a UTC ISO string
  /// can shift the calendar day for users in non-UTC timezones, causing wrong results
  /// especially when from_date == to_date.
  static String formatForApiDate(DateTime date) {
    final local = date.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String formatDateTime(DateTime? date, bool isJalali) {
    if (date == null) return '-';
    final local = date.toLocal();
    final datePart = formatForDisplay(local, isJalali);
    final timePart = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (datePart.isEmpty) {
      return timePart;
    }
    return '$datePart $timePart';
  }

  /// نام روزهای هفته برای شمسی/میلادی (شنبه تا جمعه) به فارسی و انگلیسی
  static const List<String> _weekdayNamesFa = ['شنبه', 'یکشنبه', 'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنج‌شنبه', 'جمعه'];
  static const List<String> _weekdayNamesEn = [
    'Saturday',
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
  ];

  /// تاریخ و زمان به‌همراه نام روز هفته؛ چندزبانه بر اساس [localeLanguageCode] (مثلاً 'fa' یا 'en').
  static String formatDateTimeWithWeekday(DateTime? date, bool isJalali, String localeLanguageCode) {
    if (date == null) return '-';
    final local = date.toLocal();
    final datePart = formatForDisplay(local, isJalali);
    final timePart = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    // روز هفته برای هر تاریخ در شمسی و میلادی یکسان است؛ از DateTime استفاده می‌کنیم (۰=شنبه، ۶=جمعه)
    final int weekdayIndex = (local.weekday + 1) % 7;
    final String weekdayName = localeLanguageCode.startsWith('fa')
        ? _weekdayNamesFa[weekdayIndex]
        : _weekdayNamesEn[weekdayIndex];
    if (datePart.isEmpty) {
      return '$weekdayName $timePart';
    }
    return '$weekdayName $datePart $timePart';
  }

  /// Convert DateTime to Jalali string with month name for display
  static String formatForDisplayWithMonthName(DateTime? date, bool isJalali) {
    if (date == null) return '';

    if (isJalali) {
      final jalali = Jalali.fromDateTime(date);
      final monthName = _getJalaliMonthName(jalali.month);
      return '${jalali.day} $monthName ${jalali.year}';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  /// Convert display string back to DateTime
  static DateTime? parseFromDisplay(String? displayString, bool isJalali) {
    if (displayString == null || displayString.isEmpty) return null;

    try {
      if (isJalali) {
        // Parse format: YYYY/MM/DD
        final parts = displayString.split('/');
        if (parts.length == 3) {
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final day = int.parse(parts[2]);
          final jalali = Jalali(year, month, day);
          final dt = jalali.toDateTime();
          final l = dt.toLocal();
          if (l.year < 1800 || l.year > 2200) {
            return null;
          }
          return dt;
        }
      } else {
        // Parse format: YYYY/MM/DD
        final parts = displayString.split('/');
        if (parts.length == 3) {
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final day = int.parse(parts[2]);

          // اعتبارسنجی محدوده‌های معتبر
          if (year < 1900 || year > 2100) {
            return null;
          }
          if (month < 1 || month > 12 || day < 1 || day > 31) {
            return null;
          }

          try {
            return DateTime(year, month, day);
          } catch (e) {
            // اگر تاریخ نامعتبر بود (مثلاً 31 فوریه)
            return null;
          }
        }
      }
    } catch (e) {
      // Return null if parsing fails
    }
    return null;
  }

  /// نرمال‌سازی به «فقط روز» در زمان محلی (بدون ساعت) برای مقایسه و بازه.
  static DateTime toDateOnlyLocal(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  /// پایان سال مالی به‌صورت **شامل**: یک سال بعد از تاریخ شروع در همان تقویم (شمسی یا میلادی)، منهای یک روز.
  ///
  /// مثال شمسی: شروع ۱۴۰۴/۰۱/۰۴ → سالگرد ۱۴۰۵/۰۱/۰۴ منهای یک روز → ۱۴۰۵/۰۱/۰۳.
  /// میلادی: در سال کبیسه و روزهای ماه‌ها به‌درستی در نظر گرفته می‌شود (۲۹ فوریه، غیرهم‌طول ماه‌ها).
  static DateTime fiscalYearInclusiveEndFromStart(DateTime start, bool isJalali) {
    final startDay = toDateOnlyLocal(start);
    if (isJalali) {
      final j = Jalali.fromDateTime(startDay);
      final ty = j.year + 1;
      final tm = j.month;
      var td = j.day;
      final maxDay = Jalali(ty, tm, 1).monthLength;
      if (td > maxDay) td = maxDay;
      final jAnniversary = Jalali(ty, tm, td);
      return toDateOnlyLocal(jAnniversary.toDateTime().subtract(const Duration(days: 1)));
    }
    final anniv = _gregorianSameCalendarDayNextYear(startDay);
    return toDateOnlyLocal(anniv.subtract(const Duration(days: 1)));
  }

  /// همان روز تقویمی در سال میلادی بعد؛ اگر ۲۹ فوریه در سال مقصد وجود نداشته باشد، آخر فوریه همان سال.
  static DateTime _gregorianSameCalendarDayNextYear(DateTime d) {
    final y = d.year + 1;
    final m = d.month;
    var day = d.day;
    if (m == 2 && day == 29) {
      final lastFeb = DateTime(y, 3, 0).day;
      if (day > lastFeb) day = lastFeb;
    }
    return DateTime(y, m, day);
  }

  /// آیا [date] (فقط روز) بین [firstDate] و [lastDate] (شامل) است؟
  static bool isDateOnlyInRange(DateTime date, DateTime? firstDate, DateTime? lastDate) {
    final d = toDateOnlyLocal(date);
    if (firstDate != null) {
      final f = toDateOnlyLocal(firstDate);
      if (d.isBefore(f)) {
        return false;
      }
    }
    if (lastDate != null) {
      final l = toDateOnlyLocal(lastDate);
      if (d.isAfter(l)) {
        return false;
      }
    }
    return true;
  }

  /// Get Jalali month name
  static String _getJalaliMonthName(int month) {
    const monthNames = [
      'فروردین',
      'اردیبهشت',
      'خرداد',
      'تیر',
      'مرداد',
      'شهریور',
      'مهر',
      'آبان',
      'آذر',
      'دی',
      'بهمن',
      'اسفند',
    ];
    return monthNames[month - 1];
  }

  /// Format date with both Jalali and Gregorian for display
  static String formatDualCalendar(DateTime? date) {
    if (date == null) return '';

    final jalali = Jalali.fromDateTime(date);
    final jalaliStr =
        '${jalali.year}/${jalali.month.toString().padLeft(2, '0')}/${jalali.day.toString().padLeft(2, '0')}';
    final gregorianStr = '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

    return '$jalaliStr (میلادی: $gregorianStr)';
  }

  /// Parse date from API (always Gregorian)
  /// جایگزینی تاریخ‌های `YYYY-MM-DD` در یک متن با قالب نمایش شمسی/میلادی (برای پیام‌های خطای سرور).
  static String formatIsoDatesInPlainText(String text, bool isJalali) {
    return text.replaceAllMapped(RegExp(r'\b\d{4}-\d{2}-\d{2}\b'), (Match m) {
      final parsed = parseFromAPI(m.group(0));
      if (parsed == null) return m.group(0)!;
      return formatForDisplay(parsed, isJalali);
    });
  }

  static DateTime? parseFromAPI(String? apiString) {
    if (apiString == null || apiString.isEmpty) return null;

    try {
      // Parse format: YYYY-MM-DD
      final parts = apiString.split('-');
      if (parts.length == 3) {
        final year = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final day = int.parse(parts[2]);

        // اعتبارسنجی محدوده‌های معتبر
        if (year < 1900 || year > 2100) {
          return null;
        }
        if (month < 1 || month > 12 || day < 1 || day > 31) {
          return null;
        }

        try {
          return DateTime(year, month, day);
        } catch (e) {
          // اگر تاریخ نامعتبر بود (مثلاً 31 فوریه)
          return null;
        }
      }
    } catch (e) {
      // Return null if parsing fails
    }
    return null;
  }
}
