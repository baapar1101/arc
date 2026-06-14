import 'package:shared_preferences/shared_preferences.dart';

/// ذخیرهٔ محلی شناسه گفت‌وگوهای پین‌شده.
abstract final class AISessionPinsStore {
  static String _key(int? businessId) =>
      'ai_chat_pinned_sessions_${businessId ?? 0}';

  static Future<Set<int>> load(int? businessId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key(businessId)) ?? const [];
    return raw.map(int.tryParse).whereType<int>().toSet();
  }

  static Future<void> save(int? businessId, Set<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key(businessId),
      ids.map((e) => e.toString()).toList(),
    );
  }
}
