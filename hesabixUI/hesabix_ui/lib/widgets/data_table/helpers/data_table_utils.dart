import 'package:intl/intl.dart';
import 'package:data_table_2/data_table_2.dart';
import '../data_table_config.dart';

/// Utility functions for data table
class DataTableUtils {
  /// Format text with ellipsis if needed
  static String formatText(String text, {int? maxLength}) {
    if (maxLength != null && text.length > maxLength) {
      return '${text.substring(0, maxLength)}...';
    }
    return text;
  }

  /// Format number with thousand separators
  static String formatNumber(dynamic value, {int? decimalPlaces, String? prefix, String? suffix}) {
    if (value == null) return '';
    
    final number = value is num ? value : double.tryParse(value.toString()) ?? 0;
    final formatter = NumberFormat.currency(
      symbol: '',
      decimalDigits: decimalPlaces ?? 0,
    );
    
    final formatted = formatter.format(number);
    return '${prefix ?? ''}$formatted${suffix ?? ''}';
  }

  /// Format date based on locale and format
  static String formatDate(
    dynamic value, {
    String? format,
    bool isJalali = false,
    bool showTime = false,
  }) {
    if (value == null) return '';
    
    DateTime? date;
    if (value is DateTime) {
      date = value;
    } else if (value is String) {
      try {
        date = DateTime.parse(value);
      } catch (e) {
        return value; // Return original string if parsing fails
      }
    } else if (value is Map<String, dynamic>) {
      // Handle formatted date objects from backend
      if (value.containsKey('date_only')) {
        return value['date_only'].toString();
      } else if (value.containsKey('formatted')) {
        return value['formatted'].toString();
      }
      return value.toString();
    }
    
    if (date == null) return value.toString();
    
    if (isJalali) {
      // TODO: Implement Jalali date formatting
      return DateFormat(format ?? 'yyyy/MM/dd').format(date);
    } else {
      final pattern = format ?? (showTime ? 'yyyy/MM/dd HH:mm' : 'yyyy/MM/dd');
      return DateFormat(pattern).format(date);
    }
  }

  /// Get column width as double
  static double getColumnWidth(ColumnWidth width) {
    switch (width) {
      case ColumnWidth.small:
        return 100.0;
      case ColumnWidth.medium:
        return 150.0;
      case ColumnWidth.large:
        return 200.0;
      case ColumnWidth.extraLarge:
        return 300.0;
    }
  }

  /// Get column size for DataTable2
  static ColumnSize getColumnSize(ColumnWidth width) {
    switch (width) {
      case ColumnWidth.small:
        return ColumnSize.S;
      case ColumnWidth.medium:
        return ColumnSize.M;
      case ColumnWidth.large:
        return ColumnSize.L;
      case ColumnWidth.extraLarge:
        return ColumnSize.L;
    }
  }

  /// Get search operator label
  static String getSearchOperatorLabel(String operator) {
    switch (operator) {
      case '*':
        return 'شامل';
      case '*?':
        return 'شروع با';
      case '?*':
        return 'خاتمه با';
      case '=':
        return 'مطابقت دقیق';
      default:
        return operator;
    }
  }

  /// Get search operator label in English
  static String getSearchOperatorLabelEn(String operator) {
    switch (operator) {
      case '*':
        return 'Contains';
      case '*?':
        return 'Starts With';
      case '?*':
        return 'Ends With';
      case '=':
        return 'Exact Match';
      default:
        return operator;
    }
  }

  /// Validate search value
  static bool isValidSearchValue(String value) {
    return value.trim().isNotEmpty;
  }

  /// Get default empty state message
  static String getDefaultEmptyMessage() {
    return 'هیچ داده‌ای یافت نشد';
  }

  /// Get default loading message
  static String getDefaultLoadingMessage() {
    return 'در حال بارگذاری...';
  }

  /// Get default error message
  static String getDefaultErrorMessage() {
    return 'خطا در بارگذاری داده‌ها';
  }

  /// Create filter item for date range
  static List<FilterItem> createDateRangeFilters(
    String field,
    DateTime startDate,
    DateTime endDate,
  ) {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final endExclusive = DateTime(endDate.year, endDate.month, endDate.day)
        .add(const Duration(days: 1));
    
    return [
      FilterItem(
        property: field,
        operator: '>=',
        value: start.toIso8601String(),
      ),
      FilterItem(
        property: field,
        operator: '<',
        value: endExclusive.toIso8601String(),
      ),
    ];
  }

  /// Create filter item for column search
  static FilterItem createColumnFilter(
    String field,
    String value,
    String operator,
  ) {
    return FilterItem(
      property: field,
      operator: operator,
      value: value,
    );
  }

  /// Get column label by key
  static String getColumnLabel(String key, List<DataTableColumn> columns) {
    final column = columns.firstWhere(
      (col) => col.key == key,
      orElse: () => TextColumn(key, key),
    );
    return column.label;
  }

  /// Check if column is searchable
  static bool isColumnSearchable(String key, List<DataTableColumn> columns) {
    final column = columns.firstWhere(
      (col) => col.key == key,
      orElse: () => TextColumn(key, key, searchable: false),
    );
    return column.searchable;
  }

  /// Check if column is sortable
  static bool isColumnSortable(String key, List<DataTableColumn> columns) {
    final column = columns.firstWhere(
      (col) => col.key == key,
      orElse: () => TextColumn(key, key, sortable: false),
    );
    return column.sortable;
  }

  /// Get cell value from item
  static dynamic getCellValue(dynamic item, String key) {
    if (item is Map<String, dynamic>) {
      return item[key];
    }
    // For custom objects, try to access property using reflection
    // This is a simplified version - in real implementation you might need
    // to use reflection or have a more sophisticated approach
    return null;
  }

  /// Format cell value based on column type
  static String formatCellValue(
    dynamic value,
    DataTableColumn column,
  ) {
    if (value == null) return '';
    
    if (column is TextColumn) {
      if (column.formatter != null) {
        return column.formatter!(value) ?? '';
      }
      return value.toString();
    } else if (column is NumberColumn) {
      if (column.formatter != null) {
        return column.formatter!(value) ?? '';
      }
      return formatNumber(
        value,
        decimalPlaces: column.decimalPlaces,
        prefix: column.prefix,
        suffix: column.suffix,
      );
    } else if (column is DateColumn) {
      if (column.formatter != null) {
        return column.formatter!(value) ?? '';
      }
      return formatDate(
        value,
        format: column.dateFormat,
        showTime: column.showTime,
      );
    }
    
    return value.toString();
  }
}
