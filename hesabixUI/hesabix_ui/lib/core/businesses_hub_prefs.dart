import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// تنظیمات محلی هاب کسب‌وکارها: اخیراً استفاده‌شده و سنجاق‌شده.
class BusinessesHubPrefs {
  static const _maxRecent = 8;

  static String _recentKey(int userId) => 'biz_hub_recent_u$userId';
  static String _pinnedKey(int userId) => 'biz_hub_pinned_u$userId';

  static Future<void> recordAccess(int? userId, int businessId) async {
    if (userId == null || userId <= 0 || businessId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final ids = _readIdList(prefs, _recentKey(userId));
    ids.remove(businessId);
    ids.insert(0, businessId);
    if (ids.length > _maxRecent) {
      ids.removeRange(_maxRecent, ids.length);
    }
    await prefs.setString(_recentKey(userId), jsonEncode(ids));
  }

  static Future<List<int>> getRecentIds(int? userId) async {
    if (userId == null || userId <= 0) return const [];
    final prefs = await SharedPreferences.getInstance();
    return _readIdList(prefs, _recentKey(userId));
  }

  static Future<Set<int>> getPinnedIds(int? userId) async {
    if (userId == null || userId <= 0) return {};
    final prefs = await SharedPreferences.getInstance();
    return _readIdList(prefs, _pinnedKey(userId)).toSet();
  }

  static Future<bool> togglePin(int? userId, int businessId) async {
    if (userId == null || userId <= 0 || businessId <= 0) return false;
    final prefs = await SharedPreferences.getInstance();
    final key = _pinnedKey(userId);
    final ids = _readIdList(prefs, key);
    final pinned = ids.contains(businessId);
    if (pinned) {
      ids.remove(businessId);
    } else {
      ids.add(businessId);
    }
    await prefs.setString(key, jsonEncode(ids));
    return !pinned;
  }

  static List<int> _readIdList(SharedPreferences prefs, String key) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map((e) => e is int ? e : int.tryParse('$e'))
          .whereType<int>()
          .where((id) => id > 0)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
