/// Utility functions for formatting dates from server responses
class DateFormatters {
  /// Format date from server response
  /// Handles both string dates and formatted date objects
  static String formatServerDate(dynamic dateData) {
    if (dateData == null) return '-';
    
    // If it's already a string, return it
    if (dateData is String) return dateData;
    
    // If it's a Map (formatted object), extract the formatted field
    if (dateData is Map<String, dynamic>) {
      final formatted = dateData['formatted'];
      if (formatted != null) return formatted.toString();
      
      // Fallback to date_only if formatted is not available
      final dateOnly = dateData['date_only'];
      if (dateOnly != null) return dateOnly.toString();
    }
    
    return dateData.toString();
  }

  /// Format date with time from server response
  /// Returns formatted string with time if available, otherwise just date
  static String formatServerDateTime(dynamic dateData) {
    if (dateData == null) return '-';
    
    // If it's already a string, return it
    if (dateData is String) return dateData;
    
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
    
    return dateData.toString();
  }

  /// Format date only (without time) from server response
  static String formatServerDateOnly(dynamic dateData) {
    if (dateData == null) return '-';
    
    // If it's already a string, return it
    if (dateData is String) return dateData;
    
    // If it's a Map (formatted object), extract the date_only field
    if (dateData is Map<String, dynamic>) {
      final dateOnly = dateData['date_only'];
      if (dateOnly != null) return dateOnly.toString();
      
      // Fallback to formatted if date_only is not available
      final formatted = dateData['formatted'];
      if (formatted != null) return formatted.toString();
    }
    
    return dateData.toString();
  }
}
