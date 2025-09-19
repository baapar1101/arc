import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Column settings for a specific table
class ColumnSettings {
  final List<String> visibleColumns;
  final List<String> columnOrder;
  final Map<String, double> columnWidths;

  const ColumnSettings({
    required this.visibleColumns,
    required this.columnOrder,
    this.columnWidths = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'visibleColumns': visibleColumns,
      'columnOrder': columnOrder,
      'columnWidths': columnWidths,
    };
  }

  factory ColumnSettings.fromJson(Map<String, dynamic> json) {
    return ColumnSettings(
      visibleColumns: List<String>.from(json['visibleColumns'] ?? []),
      columnOrder: List<String>.from(json['columnOrder'] ?? []),
      columnWidths: Map<String, double>.from(json['columnWidths'] ?? {}),
    );
  }

  ColumnSettings copyWith({
    List<String>? visibleColumns,
    List<String>? columnOrder,
    Map<String, double>? columnWidths,
  }) {
    return ColumnSettings(
      visibleColumns: visibleColumns ?? this.visibleColumns,
      columnOrder: columnOrder ?? this.columnOrder,
      columnWidths: columnWidths ?? this.columnWidths,
    );
  }
}

/// Service for managing column settings persistence
class ColumnSettingsService {
  static const String _keyPrefix = 'data_table_column_settings_';
  
  /// Get column settings for a specific table
  static Future<ColumnSettings?> getColumnSettings(String tableId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$tableId';
      final jsonString = prefs.getString(key);
      
      if (jsonString == null) return null;
      
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return ColumnSettings.fromJson(json);
    } catch (e) {
      print('Error loading column settings: $e');
      return null;
    }
  }
  
  /// Save column settings for a specific table
  static Future<void> saveColumnSettings(String tableId, ColumnSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$tableId';
      final jsonString = jsonEncode(settings.toJson());
      await prefs.setString(key, jsonString);
    } catch (e) {
      print('Error saving column settings: $e');
    }
  }
  
  /// Clear column settings for a specific table
  static Future<void> clearColumnSettings(String tableId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$tableId';
      await prefs.remove(key);
    } catch (e) {
      print('Error clearing column settings: $e');
    }
  }
  
  /// Get default column settings from column definitions
  static ColumnSettings getDefaultSettings(List<String> columnKeys) {
    return ColumnSettings(
      visibleColumns: List.from(columnKeys),
      columnOrder: List.from(columnKeys),
    );
  }
  
  /// Merge user settings with default settings
  static ColumnSettings mergeWithDefaults(
    ColumnSettings? userSettings,
    List<String> defaultColumnKeys,
  ) {
    if (userSettings == null) {
      return getDefaultSettings(defaultColumnKeys);
    }
    
    // Ensure all default columns are present in visible columns
    final visibleColumns = <String>[];
    for (final key in defaultColumnKeys) {
      if (userSettings.visibleColumns.contains(key)) {
        visibleColumns.add(key);
      }
    }
    
    // Ensure at least one column is visible
    if (visibleColumns.isEmpty && defaultColumnKeys.isNotEmpty) {
      visibleColumns.add(defaultColumnKeys.first);
    }
    
    // Ensure all visible columns are in the correct order
    final columnOrder = <String>[];
    for (final key in userSettings.columnOrder) {
      if (visibleColumns.contains(key)) {
        columnOrder.add(key);
      }
    }
    
    // Add any missing visible columns to the end
    for (final key in visibleColumns) {
      if (!columnOrder.contains(key)) {
        columnOrder.add(key);
      }
    }
    
    // Filter column widths to only include valid columns
    final validColumnWidths = <String, double>{};
    for (final entry in userSettings.columnWidths.entries) {
      if (visibleColumns.contains(entry.key)) {
        validColumnWidths[entry.key] = entry.value;
      }
    }
    
    return userSettings.copyWith(
      visibleColumns: visibleColumns,
      columnOrder: columnOrder,
      columnWidths: validColumnWidths,
    );
  }
}
