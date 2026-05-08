import 'package:shared_preferences/shared_preferences.dart';

/// تنظیمات محلی لانچر موبایل؛ هر کلید به ازای شناسهٔ کاربر جدا می‌شود (از اشتراک داده بین حساب‌ها جلوگیری می‌شود).
class MobileLauncherPrefs {
  static const defaultBackgroundArgb = 0xFF1565C0;
  static const int defaultGridColumns = 3;
  static const int defaultGridRows = 4;

  static const _legacyResume = 'mobile_launcher_resume_enabled';
  static const _legacyBiz = 'mobile_launcher_business_id';
  static const _legacyBg = 'mobile_launcher_bg_color_argb';
  static const _legacyGridColumns = 'mobile_launcher_grid_columns';
  static const _legacyGridRows = 'mobile_launcher_grid_rows';

  static String _resumeKey(int userId) => 'ml_resume_u$userId';

  static String _bizKey(int userId) => 'ml_biz_u$userId';

  static String _bgKey(int userId) => 'ml_bg_u$userId';
  static String _gridColumnsKey(int userId) => 'ml_grid_cols_u$userId';
  static String _gridRowsKey(int userId) => 'ml_grid_rows_u$userId';

  static Future<void> _clearLegacy(SharedPreferences prefs) async {
    await prefs.remove(_legacyResume);
    await prefs.remove(_legacyBiz);
    await prefs.remove(_legacyBg);
    await prefs.remove(_legacyGridColumns);
    await prefs.remove(_legacyGridRows);
  }

  /// یکبار مهاجرت از کلیدهای قدیمی بدون suffix به کلیدهای per-user (فرض: دستگاه تک‌کاربر POS).
  static Future<void> migrateLegacyIfNeeded(int? userId) async {
    if (userId == null || userId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final scopedResume = prefs.getBool(_resumeKey(userId));
    if (scopedResume == true) {
      await _clearLegacy(prefs);
      return;
    }
    if (prefs.getBool(_legacyResume) != true) return;
    final bid = prefs.getInt(_legacyBiz);
    if (bid == null || bid <= 0) return;
    await prefs.setBool(_resumeKey(userId), true);
    await prefs.setInt(_bizKey(userId), bid);
    final bg = prefs.getInt(_legacyBg);
    if (bg != null) {
      await prefs.setInt(_bgKey(userId), bg);
    }
    final cols = prefs.getInt(_legacyGridColumns);
    if (cols != null) {
      await prefs.setInt(_gridColumnsKey(userId), cols);
    }
    final rows = prefs.getInt(_legacyGridRows);
    if (rows != null) {
      await prefs.setInt(_gridRowsKey(userId), rows);
    }
    await _clearLegacy(prefs);
  }

  static Future<void> setResumeLauncher(int? userId, int businessId) async {
    final prefs = await SharedPreferences.getInstance();
    if (userId != null && userId > 0) {
      await prefs.setBool(_resumeKey(userId), true);
      await prefs.setInt(_bizKey(userId), businessId);
      await _clearLegacy(prefs);
      return;
    }
    await prefs.setBool(_legacyResume, true);
    await prefs.setInt(_legacyBiz, businessId);
  }

  static Future<void> clearResumeLauncher(int? userId) async {
    final prefs = await SharedPreferences.getInstance();
    if (userId != null && userId > 0) {
      await prefs.remove(_resumeKey(userId));
      await prefs.remove(_bizKey(userId));
    }
    await _clearLegacy(prefs);
  }

  static Future<String?> resumeHomeLocation(int? userId) async {
    await migrateLegacyIfNeeded(userId);
    final prefs = await SharedPreferences.getInstance();
    if (userId != null && userId > 0) {
      if (prefs.getBool(_resumeKey(userId)) != true) return null;
      final id = prefs.getInt(_bizKey(userId));
      if (id == null || id <= 0) return null;
      return '/mobile-launcher/$id';
    }
    if (prefs.getBool(_legacyResume) != true) return null;
    final id = prefs.getInt(_legacyBiz);
    if (id == null || id <= 0) return null;
    return '/mobile-launcher/$id';
  }

  static Future<String> postAuthHomeLocation(int? userId) async {
    final loc = await resumeHomeLocation(userId);
    return loc ?? '/user/profile/dashboard';
  }

  static Future<int?> resumeBusinessId(int? userId) async {
    await migrateLegacyIfNeeded(userId);
    final prefs = await SharedPreferences.getInstance();
    if (userId != null && userId > 0) {
      if (prefs.getBool(_resumeKey(userId)) != true) return null;
      final id = prefs.getInt(_bizKey(userId));
      if (id == null || id <= 0) return null;
      return id;
    }
    if (prefs.getBool(_legacyResume) != true) return null;
    return prefs.getInt(_legacyBiz);
  }

  static Future<int> backgroundColorArgb(int? userId) async {
    await migrateLegacyIfNeeded(userId);
    final prefs = await SharedPreferences.getInstance();
    if (userId != null && userId > 0) {
      return prefs.getInt(_bgKey(userId)) ?? defaultBackgroundArgb;
    }
    return prefs.getInt(_legacyBg) ?? defaultBackgroundArgb;
  }

  static Future<void> setBackgroundColorArgb(int? userId, int argb) async {
    final prefs = await SharedPreferences.getInstance();
    if (userId != null && userId > 0) {
      await prefs.setInt(_bgKey(userId), argb);
      await _clearLegacy(prefs);
      return;
    }
    await prefs.setInt(_legacyBg, argb);
  }

  static int _clampColumns(int v) => v.clamp(2, 6);
  static int _clampRows(int v) => v.clamp(2, 6);

  static Future<int> gridColumns(int? userId) async {
    await migrateLegacyIfNeeded(userId);
    final prefs = await SharedPreferences.getInstance();
    if (userId != null && userId > 0) {
      final v = prefs.getInt(_gridColumnsKey(userId)) ?? defaultGridColumns;
      return _clampColumns(v);
    }
    final v = prefs.getInt(_legacyGridColumns) ?? defaultGridColumns;
    return _clampColumns(v);
  }

  static Future<int> gridRows(int? userId) async {
    await migrateLegacyIfNeeded(userId);
    final prefs = await SharedPreferences.getInstance();
    if (userId != null && userId > 0) {
      final v = prefs.getInt(_gridRowsKey(userId)) ?? defaultGridRows;
      return _clampRows(v);
    }
    final v = prefs.getInt(_legacyGridRows) ?? defaultGridRows;
    return _clampRows(v);
  }

  static Future<void> setGridLayout(
    int? userId, {
    required int columns,
    required int rows,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final c = _clampColumns(columns);
    final r = _clampRows(rows);
    if (userId != null && userId > 0) {
      await prefs.setInt(_gridColumnsKey(userId), c);
      await prefs.setInt(_gridRowsKey(userId), r);
      await _clearLegacy(prefs);
      return;
    }
    await prefs.setInt(_legacyGridColumns, c);
    await prefs.setInt(_legacyGridRows, r);
  }

  /// پاک کردن لانچر و ظاهر ذخیره‌شده برای [userId]؛ کلیدهای legacy هم همیشه پاک می‌شوند.
  static Future<void> clearSession({required int? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    if (userId != null && userId > 0) {
      await prefs.remove(_resumeKey(userId));
      await prefs.remove(_bizKey(userId));
      await prefs.remove(_bgKey(userId));
      await prefs.remove(_gridColumnsKey(userId));
      await prefs.remove(_gridRowsKey(userId));
    }
    await _clearLegacy(prefs);
  }
}
