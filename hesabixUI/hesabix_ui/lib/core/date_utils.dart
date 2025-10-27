import 'package:shamsi_date/shamsi_date.dart';

/// Utility class for date management and conversion
class HesabixDateUtils {
  /// Convert DateTime to Jalali string for display
  static String formatForDisplay(DateTime? date, bool isJalali) {
    if (date == null) return '';
    
    if (isJalali) {
      final jalali = Jalali.fromDateTime(date);
      return '${jalali.year}/${jalali.month.toString().padLeft(2, '0')}/${jalali.day.toString().padLeft(2, '0')}';
    } else {
      return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
    }
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
          return jalali.toDateTime();
        }
      } else {
        // Parse format: YYYY/MM/DD
        final parts = displayString.split('/');
        if (parts.length == 3) {
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final day = int.parse(parts[2]);
          return DateTime(year, month, day);
        }
      }
    } catch (e) {
      // Return null if parsing fails
    }
    return null;
  }

  /// Get Jalali month name
  static String _getJalaliMonthName(int month) {
    const monthNames = [
      'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
      'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'
    ];
    return monthNames[month - 1];
  }

  /// Format date with both Jalali and Gregorian for display
  static String formatDualCalendar(DateTime? date) {
    if (date == null) return '';
    
    final jalali = Jalali.fromDateTime(date);
    final jalaliStr = '${jalali.year}/${jalali.month.toString().padLeft(2, '0')}/${jalali.day.toString().padLeft(2, '0')}';
    final gregorianStr = '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
    
    return '$jalaliStr (میلادی: $gregorianStr)';
  }

  /// Parse date from API (always Gregorian)
  static DateTime? parseFromAPI(String? apiString) {
    if (apiString == null || apiString.isEmpty) return null;
    
    try {
      // Parse format: YYYY-MM-DD
      final parts = apiString.split('-');
      if (parts.length == 3) {
        final year = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final day = int.parse(parts[2]);
        return DateTime(year, month, day);
      }
    } catch (e) {
      // Return null if parsing fails
    }
    return null;
  }
}
