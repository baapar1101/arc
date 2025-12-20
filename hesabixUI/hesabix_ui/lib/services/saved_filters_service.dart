import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hesabix_ui/models/saved_filter.dart';

class SavedFiltersService {
  static const String _keyPrefix = 'operator_tickets_saved_filters_';

  /// Get all saved filters for operator tickets
  static Future<List<SavedFilter>> getSavedFilters() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${_keyPrefix}list';
      final jsonString = prefs.getString(key);

      if (jsonString == null) return [];

      final List<dynamic> jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList.map((json) => SavedFilter.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Save a filter
  static Future<void> saveFilter(SavedFilter filter) async {
    try {
      final filters = await getSavedFilters();
      
      // Check if filter with same name exists, replace it
      final index = filters.indexWhere((f) => f.name == filter.name);
      if (index >= 0) {
        filters[index] = filter;
      } else {
        filters.add(filter);
      }

      final prefs = await SharedPreferences.getInstance();
      final key = '${_keyPrefix}list';
      final jsonString = jsonEncode(filters.map((f) => f.toJson()).toList());
      await prefs.setString(key, jsonString);
    } catch (e) {
      // Handle error silently
    }
  }

  /// Delete a saved filter
  static Future<void> deleteFilter(String filterName) async {
    try {
      final filters = await getSavedFilters();
      filters.removeWhere((f) => f.name == filterName);

      final prefs = await SharedPreferences.getInstance();
      final key = '${_keyPrefix}list';
      if (filters.isEmpty) {
        await prefs.remove(key);
      } else {
        final jsonString = jsonEncode(filters.map((f) => f.toJson()).toList());
        await prefs.setString(key, jsonString);
      }
    } catch (e) {
      // Handle error silently
    }
  }

  /// Get default filters
  static List<SavedFilter> getDefaultFilters(int? currentUserId) {
    return [
      SavedFilter(
        name: 'تیکت‌های من',
        filters: currentUserId != null
            ? {'assigned_operator_id': currentUserId}
            : {},
      ),
      SavedFilter(
        name: 'تیکت‌های بدون اپراتور',
        filters: {'assigned_operator_id': null},
      ),
      SavedFilter(
        name: 'اولویت بالا',
        filters: {'priority.name': ['بالا', 'فوری']},
      ),
      SavedFilter(
        name: 'تیکت‌های باز',
        filters: {'status.name': ['باز']},
      ),
    ];
  }
}




