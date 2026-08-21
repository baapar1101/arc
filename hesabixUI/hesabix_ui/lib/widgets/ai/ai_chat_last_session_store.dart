import 'package:shared_preferences/shared_preferences.dart';

/// آخرین جلسهٔ بازشده برای بازگردانی بعد از رفرش.
abstract final class AIChatLastSessionStore {
  static String _key(int? businessId) => 'ai_chat_last_session_${businessId ?? 0}';

  static Future<int?> load(int? businessId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key(businessId));
  }

  static Future<void> save(int? businessId, int sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(businessId), sessionId);
  }

  static Future<void> clear(int? businessId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(businessId));
  }
}
