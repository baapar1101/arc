import 'package:shared_preferences/shared_preferences.dart';

/// Persisted preferences for Windows installer updates (keys isolated from Android).
class WindowsUpdatePrefs {
  static const _kAutoCheck = 'windows_update_auto_check';
  static const _kAutoDownload = 'windows_update_auto_download';
  static const _kSkippedVersion = 'windows_update_skipped_version';
  static const _kLastCheckMs = 'windows_update_last_check_ms';

  static Future<bool> isAutoCheckEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kAutoCheck) ?? true;
  }

  static Future<void> setAutoCheckEnabled(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAutoCheck, value);
  }

  static Future<bool> isAutoDownloadEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kAutoDownload) ?? true;
  }

  static Future<void> setAutoDownloadEnabled(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAutoDownload, value);
  }

  /// Tag the user dismissed with "Later" — suppress prompts until a newer tag.
  static Future<String?> getSkippedVersion() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kSkippedVersion);
  }

  static Future<void> setSkippedVersion(String tag) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSkippedVersion, tag);
  }

  static Future<void> clearSkippedVersion() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kSkippedVersion);
  }

  static Future<DateTime?> getLastCheckAt() async {
    final p = await SharedPreferences.getInstance();
    final ms = p.getInt(_kLastCheckMs);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> setLastCheckNow() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kLastCheckMs, DateTime.now().millisecondsSinceEpoch);
  }
}
