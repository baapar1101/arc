import 'package:shared_preferences/shared_preferences.dart';

/// Persisted preferences for Android sideload updates.
class AndroidUpdatePrefs {
  static const _kAutoCheck = 'android_update_auto_check';
  static const _kAutoDownload = 'android_update_auto_download';
  static const _kSkippedVersion = 'android_update_skipped_version';
  static const _kLastCheckMs = 'android_update_last_check_ms';
  static const _kPendingTaskId = 'android_update_pending_task_id';
  static const _kPendingReleaseTag = 'android_update_pending_release_tag';

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

  static Future<String?> getPendingTaskId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kPendingTaskId);
  }

  static Future<String?> getPendingReleaseTag() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kPendingReleaseTag);
  }

  static Future<void> setPendingDownload({
    required String taskId,
    required String releaseTag,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPendingTaskId, taskId);
    await p.setString(_kPendingReleaseTag, releaseTag);
  }

  static Future<void> clearPendingDownload() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kPendingTaskId);
    await p.remove(_kPendingReleaseTag);
  }
}
