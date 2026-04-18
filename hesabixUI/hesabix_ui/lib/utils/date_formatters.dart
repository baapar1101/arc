import '../core/api_client.dart';
import '../core/date_utils.dart';

/// Utility functions for formatting dates from server responses
class DateFormatters {
  /// Format date from server response
  /// Handles both string dates and formatted date objects
  /// Supports user's calendar preference (Jalali/Gregorian)
  static String formatServerDate(dynamic dateData) {
    if (dateData == null) return '-';
    
    // Get calendar controller to check user's calendar preference
    final calendarController = ApiClient.getCalendarController();
    final isJalali = calendarController?.isJalali ?? true; // Default to Jalali
    
    // If it's a Map (formatted object), extract the formatted field
    if (dateData is Map<String, dynamic>) {
      final formatted = dateData['formatted'];
      if (formatted != null) return formatted.toString();
      
      // Fallback to date_only if formatted is not available
      final dateOnly = dateData['date_only'];
      if (dateOnly != null) return dateOnly.toString();
    }
    
    // If it's a string, try to parse it as ISO date and format based on calendar
    if (dateData is String) {
      try {
        // Try to parse ISO format date
        DateTime? parsedDate;
        if (dateData.contains('T') || dateData.contains(' ')) {
          // ISO format with time: 2024-01-15T10:30:00 or 2024-01-15 10:30:00
          final normalized = dateData.replaceAll(' ', 'T');
          if (normalized.endsWith('Z')) {
            parsedDate = DateTime.parse(normalized.substring(0, normalized.length - 1) + '+00:00').toLocal();
          } else if (!normalized.contains('+') && !normalized.contains('-', 10)) {
            // No timezone info, assume UTC
            parsedDate = DateTime.parse(normalized + 'Z').toLocal();
          } else {
            parsedDate = DateTime.parse(normalized).toLocal();
          }
        } else {
          // Date only: 2024-01-15
          parsedDate = DateTime.parse(dateData).toLocal();
        }
        
        if (parsedDate != null) {
          return HesabixDateUtils.formatForDisplay(parsedDate, isJalali);
        }
      } catch (e) {
        // If parsing fails, return the original string
        return dateData;
      }
    }
    
    return dateData.toString();
  }

  /// Format date with time from server response
  /// Returns formatted string with time if available, otherwise just date
  /// Supports user's calendar preference (Jalali/Gregorian)
  static String formatServerDateTime(dynamic dateData) {
    if (dateData == null) return '-';
    
    // Get calendar controller to check user's calendar preference
    final calendarController = ApiClient.getCalendarController();
    final isJalali = calendarController?.isJalali ?? true; // Default to Jalali
    
    // If it's a Map (formatted object), extract the formatted field
    if (dateData is Map<String, dynamic>) {
      final formatted = dateData['formatted'];
      if (formatted != null) return formatted.toString();
      
      // Try to construct date with time
      final dateOnly = dateData['date_only'];
      final timeOnly = dateData['time_only'];
      if (dateOnly != null && timeOnly != null) {
        return '$dateOnly $timeOnly';
      } else if (dateOnly != null) {
        return dateOnly.toString();
      }
    }
    
    // If it's a string, try to parse it as ISO datetime and format based on calendar
    if (dateData is String) {
      try {
        // Try to parse ISO format datetime
        DateTime? parsedDate;
        if (dateData.contains('T') || dateData.contains(' ')) {
          // ISO format with time: 2024-01-15T10:30:00 or 2024-01-15 10:30:00
          final normalized = dateData.replaceAll(' ', 'T');
          if (normalized.endsWith('Z')) {
            parsedDate = DateTime.parse(normalized.substring(0, normalized.length - 1) + '+00:00').toLocal();
          } else if (!normalized.contains('+') && !normalized.contains('-', 10)) {
            // No timezone info, assume UTC
            parsedDate = DateTime.parse(normalized + 'Z').toLocal();
          } else {
            parsedDate = DateTime.parse(normalized).toLocal();
          }
        } else {
          // Date only: 2024-01-15
          parsedDate = DateTime.parse(dateData).toLocal();
        }
        
        if (parsedDate != null) {
          return HesabixDateUtils.formatDateTime(parsedDate, isJalali);
        }
      } catch (e) {
        // If parsing fails, return the original string
        return dateData;
      }
    }
    
    return dateData.toString();
  }

  /// زمان نسبی برای چند روز اخیر؛ برای قدیمی‌تر از [relativeDaysThreshold] روز، تاریخ و زمان با تقویم انتخاب‌شده کاربر (شمسی/میلادی).
  static String formatRelativeOrAbsoluteDateTime(String? dateString, {int relativeDaysThreshold = 7}) {
    if (dateString == null || dateString.isEmpty) return '-';

    late final DateTime date;
    try {
      if (dateString.contains('T') || dateString.contains(' ')) {
        final normalized = dateString.replaceAll(' ', 'T');
        if (normalized.endsWith('Z')) {
          date = DateTime.parse(normalized.substring(0, normalized.length - 1) + '+00:00').toLocal();
        } else if (!normalized.contains('+') && !normalized.contains('-', 10)) {
          date = DateTime.parse(normalized + 'Z').toLocal();
        } else {
          date = DateTime.parse(normalized).toLocal();
        }
      } else {
        date = DateTime.parse(dateString).toLocal();
      }
    } catch (_) {
      return dateString;
    }

    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'همین الان';
        }
        return '${difference.inMinutes} دقیقه پیش';
      }
      return '${difference.inHours} ساعت پیش';
    }
    if (difference.inDays == 1) {
      return 'دیروز';
    }
    if (difference.inDays < relativeDaysThreshold) {
      return '${difference.inDays} روز پیش';
    }

    final isJalali = ApiClient.getCalendarController()?.isJalali ?? true;
    return HesabixDateUtils.formatDateTime(date, isJalali);
  }

  /// Format date only (without time) from server response
  /// Supports user's calendar preference (Jalali/Gregorian)
  static String formatServerDateOnly(dynamic dateData) {
    if (dateData == null) return '-';
    
    // Get calendar controller to check user's calendar preference
    final calendarController = ApiClient.getCalendarController();
    final isJalali = calendarController?.isJalali ?? true; // Default to Jalali
    
    // If it's a Map (formatted object), extract the date_only field
    if (dateData is Map<String, dynamic>) {
      final dateOnly = dateData['date_only'];
      if (dateOnly != null) return dateOnly.toString();
      
      // Fallback to formatted if date_only is not available
      final formatted = dateData['formatted'];
      if (formatted != null) return formatted.toString();
    }
    
    // If it's a string, try to parse it as ISO date and format based on calendar
    if (dateData is String) {
      try {
        // Try to parse ISO format date
        DateTime? parsedDate;
        if (dateData.contains('T') || dateData.contains(' ')) {
          // ISO format with time: 2024-01-15T10:30:00 or 2024-01-15 10:30:00
          final normalized = dateData.replaceAll(' ', 'T');
          if (normalized.endsWith('Z')) {
            parsedDate = DateTime.parse(normalized.substring(0, normalized.length - 1) + '+00:00').toLocal();
          } else if (!normalized.contains('+') && !normalized.contains('-', 10)) {
            // No timezone info, assume UTC
            parsedDate = DateTime.parse(normalized + 'Z').toLocal();
          } else {
            parsedDate = DateTime.parse(normalized).toLocal();
          }
        } else {
          // Date only: 2024-01-15
          parsedDate = DateTime.parse(dateData).toLocal();
        }
        
        if (parsedDate != null) {
          return HesabixDateUtils.formatForDisplay(parsedDate, isJalali);
        }
      } catch (e) {
        // If parsing fails, return the original string
        return dateData;
      }
    }
    
    return dateData.toString();
  }
}
