import 'package:shared_preferences/shared_preferences.dart';

/// Per-user local preferences for Android biometric app-lock.
class BiometricLockPrefs {
  static String _enabledKey(int userId) => 'bio_lock_enabled_u$userId';

  static String _promptedKey(int userId) => 'bio_lock_prompted_u$userId';

  static const _migrationKey = 'bio_lock_migration_v2_fragment_activity';

  /// One-time: clear stale "already asked" flags from before FragmentActivity fix
  /// so users who never successfully enabled can see the opt-in again.
  static Future<void> runMigrationIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migrationKey) == true) return;
    final keys = prefs
        .getKeys()
        .where((k) => k.startsWith('bio_lock_prompted_u'))
        .toList();
    for (final key in keys) {
      final suffix = key.replaceFirst('bio_lock_prompted_u', '');
      final userId = int.tryParse(suffix);
      if (userId == null) continue;
      final enabled = prefs.getBool(_enabledKey(userId)) ?? false;
      if (!enabled) {
        await prefs.remove(key);
      }
    }
    await prefs.setBool(_migrationKey, true);
  }

  static Future<bool> isEnabled(int? userId) async {
    if (userId == null || userId <= 0) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey(userId)) ?? false;
  }

  static Future<void> setEnabled(int? userId, bool value) async {
    if (userId == null || userId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey(userId), value);
  }

  static Future<bool> hasBeenPrompted(int? userId) async {
    if (userId == null || userId <= 0) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_promptedKey(userId)) ?? false;
  }

  static Future<void> markPrompted(int? userId) async {
    if (userId == null || userId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_promptedKey(userId), true);
  }

  static Future<void> clearPrompted(int? userId) async {
    if (userId == null || userId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_promptedKey(userId));
  }

  static Future<void> clearForUser(int? userId) async {
    if (userId == null || userId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_enabledKey(userId));
    await prefs.remove(_promptedKey(userId));
  }
}
