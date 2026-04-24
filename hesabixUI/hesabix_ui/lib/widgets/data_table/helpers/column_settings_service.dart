import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api_client.dart';

/// Column settings for a specific table
class ColumnSettings {
  final List<String> visibleColumns;
  final List<String> columnOrder;
  final Map<String, double> columnWidths;
  final List<String> pinnedLeft;
  final List<String> pinnedRight;

  const ColumnSettings({
    required this.visibleColumns,
    required this.columnOrder,
    this.columnWidths = const {},
    this.pinnedLeft = const [],
    this.pinnedRight = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'visibleColumns': visibleColumns,
      'columnOrder': columnOrder,
      'columnWidths': columnWidths,
      'pinnedLeft': pinnedLeft,
      'pinnedRight': pinnedRight,
    };
  }

  factory ColumnSettings.fromJson(Map<String, dynamic> json) {
    final rawWidths = json['columnWidths'];
    final Map<String, double> widths = {};
    if (rawWidths is Map) {
      rawWidths.forEach((k, v) {
        if (v is num) {
          widths[k.toString()] = v.toDouble();
        }
      });
    }
    return ColumnSettings(
      visibleColumns: List<String>.from(json['visibleColumns'] ?? []),
      columnOrder: List<String>.from(json['columnOrder'] ?? []),
      columnWidths: widths,
      pinnedLeft: List<String>.from(json['pinnedLeft'] ?? []),
      pinnedRight: List<String>.from(json['pinnedRight'] ?? []),
    );
  }

  ColumnSettings copyWith({
    List<String>? visibleColumns,
    List<String>? columnOrder,
    Map<String, double>? columnWidths,
    List<String>? pinnedLeft,
    List<String>? pinnedRight,
  }) {
    return ColumnSettings(
      visibleColumns: visibleColumns ?? this.visibleColumns,
      columnOrder: columnOrder ?? this.columnOrder,
      columnWidths: columnWidths ?? this.columnWidths,
      pinnedLeft: pinnedLeft ?? this.pinnedLeft,
      pinnedRight: pinnedRight ?? this.pinnedRight,
    );
  }
}

/// Service for managing column settings persistence
/// (SharedPreferences + در صورت [businessId]، ذخیرهٔ سمت سرور)
class ColumnSettingsService {
  static const String _keyPrefix = 'data_table_column_settings_';
  static final ApiClient _api = ApiClient();

  /// دریافت تنظیمات: اگر [businessId] داده شود، ابتدا سرور؛ سپس حافظهٔ محلی.
  static Future<ColumnSettings?> getColumnSettings(String tableId, {int? businessId}) async {
    if (businessId != null) {
      try {
        final remote = await _fetchFromServer(businessId, tableId);
        if (remote != null) {
          return remote;
        }
      } catch (e) {
        debugPrint('ColumnSettingsService: server load failed, using local: $e');
      }
    }
    return _getFromLocalPrefs(tableId);
  }

  static Future<ColumnSettings?> _fetchFromServer(int businessId, String tableId) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/business/$businessId/data-tables/column-settings',
      query: {'table_id': tableId},
    );
    final root = res.data;
    if (root == null || root['success'] != true) {
      return null;
    }
    final data = root['data'] as Map<String, dynamic>?;
    if (data == null) {
      return null;
    }
    final raw = data['settings'];
    if (raw is! Map) {
      return null;
    }
    return ColumnSettings.fromJson(
      Map<String, dynamic>.from(Map<dynamic, dynamic>.from(raw)),
    );
  }

  static Future<ColumnSettings?> _getFromLocalPrefs(String tableId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$tableId';
      final jsonString = prefs.getString(key);
      if (jsonString == null) return null;
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return ColumnSettings.fromJson(json);
    } catch (e) {
      debugPrint('Error loading column settings from prefs: $e');
      return null;
    }
  }

  /// ذخیره: همیشه محلی؛ با [businessId] هم تلاش برای PUT سمت سرور
  static Future<void> saveColumnSettings(
    String tableId,
    ColumnSettings settings, {
    int? businessId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$tableId';
      await prefs.setString(key, jsonEncode(settings.toJson()));
    } catch (e) {
      debugPrint('Error saving column settings to prefs: $e');
    }
    if (businessId == null) {
      return;
    }
    try {
      await _api.put<Map<String, dynamic>>(
        '/api/v1/business/$businessId/data-tables/column-settings',
        data: {
          'table_id': tableId,
          'settings': settings.toJson(),
        },
      );
    } catch (e) {
      debugPrint('Error saving column settings to server: $e');
    }
  }

  /// حذف از محلی و در صورت [businessId] حذف ردیف سمت سرور
  static Future<void> clearColumnSettings(String tableId, {int? businessId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$tableId';
      await prefs.remove(key);
    } catch (e) {
      debugPrint('Error clearing column settings from prefs: $e');
    }
    if (businessId == null) {
      return;
    }
    try {
      await _api.delete<Map<String, dynamic>>(
        '/api/v1/business/$businessId/data-tables/column-settings',
        query: {'table_id': tableId},
      );
    } catch (e) {
      debugPrint('Error clearing column settings on server: $e');
    }
  }

  /// Get default column settings from column definitions
  static ColumnSettings getDefaultSettings(List<String> columnKeys) {
    return ColumnSettings(
      visibleColumns: List.from(columnKeys),
      columnOrder: List.from(columnKeys),
      pinnedLeft: const [],
      pinnedRight: const [],
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
    // If new columns are added (not in user settings), include them by default
    final visibleColumns = <String>[];
    final userVisible = Set<String>.from(userSettings.visibleColumns);
    for (final key in defaultColumnKeys) {
      if (userVisible.contains(key)) {
        visibleColumns.add(key);
      } else {
        // New column introduced → show by default
        visibleColumns.add(key);
      }
    }

    // Ensure at least one column is visible
    if (visibleColumns.isEmpty && defaultColumnKeys.isNotEmpty) {
      visibleColumns.add(defaultColumnKeys.first);
    }

    // Build columnOrder: keep user's order for known columns, append new ones at the end
    final columnOrder = <String>[];
    for (final key in userSettings.columnOrder) {
      if (visibleColumns.contains(key)) {
        columnOrder.add(key);
      }
    }
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
    // Sanitize pins to only include visible columns
    final leftPins = <String>[];
    for (final key in userSettings.pinnedLeft) {
      if (visibleColumns.contains(key)) leftPins.add(key);
    }
    final rightPins = <String>[];
    for (final key in userSettings.pinnedRight) {
      if (visibleColumns.contains(key)) rightPins.add(key);
    }

    return userSettings.copyWith(
      visibleColumns: visibleColumns,
      columnOrder: columnOrder,
      columnWidths: validColumnWidths,
      pinnedLeft: leftPins,
      pinnedRight: rightPins,
    );
  }
}
