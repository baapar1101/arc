import 'package:shared_preferences/shared_preferences.dart';

/// حالت مرتب‌سازی لیست سوییچر کسب‌وکارها.
enum BusinessSwitcherSort {
  /// آخرین ورودهای کاربر (محلی) + کسب‌وکار فعال در بالا
  recent,

  /// نام الفبایی
  name,

  /// تاریخ ایجاد (جدیدتر اول)
  created,
}

/// ترجیحات محلی سوییچر فضای کاری (به‌ازای کاربر).
class BusinessSwitcherPrefs {
  static const _legacySort = 'business_switcher_sort';
  static const _legacyLastUsed = 'business_switcher_last_used';

  static String _sortKey(int userId) => 'bs_sort_u$userId';
  static String _lastUsedKey(int userId) => 'bs_last_used_u$userId';

  static BusinessSwitcherSort _parseSort(String? raw) {
    switch (raw) {
      case 'name':
        return BusinessSwitcherSort.name;
      case 'created':
        return BusinessSwitcherSort.created;
      case 'recent':
      default:
        return BusinessSwitcherSort.recent;
    }
  }

  static String _encodeSort(BusinessSwitcherSort sort) => switch (sort) {
        BusinessSwitcherSort.recent => 'recent',
        BusinessSwitcherSort.name => 'name',
        BusinessSwitcherSort.created => 'created',
      };

  static Future<BusinessSwitcherSort> sortMode(int? userId) async {
    final prefs = await SharedPreferences.getInstance();
    if (userId != null && userId > 0) {
      final scoped = prefs.getString(_sortKey(userId));
      if (scoped != null) return _parseSort(scoped);
    }
    return _parseSort(prefs.getString(_legacySort));
  }

  static Future<void> setSortMode(int? userId, BusinessSwitcherSort sort) async {
    final prefs = await SharedPreferences.getInstance();
    final value = _encodeSort(sort);
    if (userId != null && userId > 0) {
      await prefs.setString(_sortKey(userId), value);
      await prefs.remove(_legacySort);
      return;
    }
    await prefs.setString(_legacySort, value);
  }

  static Future<List<int>> lastUsedIds(int? userId) async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? raw;
    if (userId != null && userId > 0) {
      raw = prefs.getStringList(_lastUsedKey(userId));
    }
    raw ??= prefs.getStringList(_legacyLastUsed);
    if (raw == null || raw.isEmpty) return const [];
    return raw.map(int.tryParse).whereType<int>().where((id) => id > 0).toList();
  }

  /// ثبت ورود به کسب‌وکار؛ حداکثر ۲۰ مورد نگه داشته می‌شود.
  static Future<void> recordLastUsed(int? userId, int businessId) async {
    if (businessId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final current = await lastUsedIds(userId);
    current.remove(businessId);
    current.insert(0, businessId);
    final trimmed = current.take(20).map((e) => e.toString()).toList();
    if (userId != null && userId > 0) {
      await prefs.setStringList(_lastUsedKey(userId), trimmed);
      await prefs.remove(_legacyLastUsed);
      return;
    }
    await prefs.setStringList(_legacyLastUsed, trimmed);
  }

  static Future<void> clearSession({required int? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    if (userId != null && userId > 0) {
      await prefs.remove(_sortKey(userId));
      await prefs.remove(_lastUsedKey(userId));
    }
    await prefs.remove(_legacySort);
    await prefs.remove(_legacyLastUsed);
  }
}
