import 'package:shared_preferences/shared_preferences.dart';

import 'ai_execution_mode.dart';

/// ذخیرهٔ محلی حالت اجرای پیش‌فرض AI per business.
abstract final class AIChatExecutionModeStore {
  static String _key(int? businessId) =>
      'ai_chat_execution_mode_${businessId ?? 0}';

  static Future<String> load(int? businessId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(businessId));
    return AIExecutionMode.normalize(raw);
  }

  static Future<void> save(int? businessId, String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(businessId), AIExecutionMode.normalize(mode));
  }
}
