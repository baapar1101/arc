import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/android_notification_prefs.dart';
import '../core/api_client.dart';
import '../services/user_ui_preferences_service.dart';
import '../utils/web/loader_prefs_sync.dart';
import 'tokens/theme_catalog.dart';
import 'dart:async';

class ThemeController extends ChangeNotifier {
  static const String _modeKey = 'theme_mode';
  static const String _themeIdKey = 'theme_id';
  static const String _seedKey = 'theme_seed'; // legacy

  ThemeMode _mode = ThemeMode.system;
  String _themeId = kDefaultThemeId;
  bool _modeFromUser = false;
  bool _themeIdFromUser = false;

  ThemeMode get mode => _mode;
  String get themeId => _themeId;
  AppThemeDefinition get themeDefinition => themeDefinitionById(_themeId);
  Color get seedColor => themeDefinition.primary;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();

    final modeIndex = p.getInt(_modeKey);
    if (modeIndex != null && modeIndex >= 0 && modeIndex < ThemeMode.values.length) {
      _mode = ThemeMode.values[modeIndex];
      _modeFromUser = true;
    }

    final localThemeId = p.getString(_themeIdKey);
    if (localThemeId != null && isAllowedThemeId(localThemeId)) {
      _themeId = localThemeId.trim().toLowerCase();
      _themeIdFromUser = true;
    } else {
      // مهاجرت از seed قدیمی SharedPreferences
      final legacySeed = p.getInt(_seedKey);
      if (legacySeed != null) {
        final legacyColor = Color(legacySeed);
        AppThemeDefinition? matched;
        for (final t in kAppThemeCatalog) {
          if (t.primary.toARGB32() == legacyColor.toARGB32()) {
            matched = t;
            break;
          }
        }
        if (matched != null) {
          _themeId = matched.id;
          _themeIdFromUser = true;
          await p.setString(_themeIdKey, _themeId);
        }
      }
    }

    // پیش‌فرض ادمین از public-config (بدون نیاز به دسترسی ادمین)
    if (!_modeFromUser || !_themeIdFromUser) {
      await _applyDefaultsFromPublicConfig();
    }

    // ترجیحات سرور کاربر (اولویت بالاتر از پیش‌فرض ادمین، نه بالاتر از انتخاب محلی صریح)
    await _hydrateFromUserPreferences(preferLocalOverrides: true);

    _syncLoader();
    notifyListeners();
  }

  Future<void> _applyDefaultsFromPublicConfig() async {
    try {
      final api = ApiClient();
      final res = await api.get<Map<String, dynamic>>('/api/v1/auth/public-config');
      final data = Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});

      if (!_modeFromUser) {
        final defaultTheme = data['default_theme']?.toString() ?? 'system';
        switch (defaultTheme.toLowerCase()) {
          case 'light':
            _mode = ThemeMode.light;
            break;
          case 'dark':
            _mode = ThemeMode.dark;
            break;
          case 'system':
          default:
            _mode = ThemeMode.system;
            break;
        }
      }

      if (!_themeIdFromUser) {
        final defaultThemeId = data['default_theme_id']?.toString();
        if (isAllowedThemeId(defaultThemeId)) {
          _themeId = defaultThemeId!.trim().toLowerCase();
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ThemeController public-config defaults failed: $e');
      }
    }
  }

  Future<void> _hydrateFromUserPreferences({required bool preferLocalOverrides}) async {
    try {
      final authStore = ApiClient.getAuthStore();
      if (authStore == null || authStore.apiKey == null || authStore.apiKey!.isEmpty) {
        return;
      }
      final svc = UserUiPreferencesService(ApiClient());
      final data = await svc.getPreferences();

      final serverThemeId = data['theme_id']?.toString();
      if (isAllowedThemeId(serverThemeId)) {
        if (!preferLocalOverrides || !_themeIdFromUser) {
          _themeId = serverThemeId!.trim().toLowerCase();
          _themeIdFromUser = true;
          final p = await SharedPreferences.getInstance();
          await p.setString(_themeIdKey, _themeId);
        }
      }

      final serverMode = data['theme_mode']?.toString();
      if (serverMode != null) {
        final parsed = _themeModeFromString(serverMode);
        if (parsed != null && (!preferLocalOverrides || !_modeFromUser)) {
          _mode = parsed;
          _modeFromUser = true;
          final p = await SharedPreferences.getInstance();
          await p.setInt(_modeKey, _mode.index);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ThemeController user prefs hydrate failed: $e');
      }
    }
  }

  /// بعد از لاگین فراخوانی شود تا تم ذخیره‌شده کاربر اعمال گردد.
  Future<void> syncFromServerAfterLogin() async {
    await _hydrateFromUserPreferences(preferLocalOverrides: false);
    _syncLoader();
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    if (_mode == m) return;
    _mode = m;
    _modeFromUser = true;
    _syncLoader();
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt(_modeKey, m.index);
    await _persistToServer();
  }

  Future<void> setThemeId(String id) async {
    final normalized = id.trim().toLowerCase();
    if (!isAllowedThemeId(normalized)) return;
    if (_themeId == normalized) return;
    _themeId = normalized;
    _themeIdFromUser = true;
    _syncLoader();
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_themeIdKey, _themeId);
    // پاک کردن seed قدیمی تا تداخل ایجاد نشود
    await p.remove(_seedKey);
    await _persistToServer();
  }

  @Deprecated('Use setThemeId instead')
  Future<void> setSeedColor(Color c) async {
    AppThemeDefinition? matched;
    for (final t in kAppThemeCatalog) {
      if (t.primary.toARGB32() == c.toARGB32()) {
        matched = t;
        break;
      }
    }
    if (matched != null) {
      await setThemeId(matched.id);
    }
  }

  Future<void> _persistToServer() async {
    try {
      final authStore = ApiClient.getAuthStore();
      if (authStore == null || authStore.apiKey == null || authStore.apiKey!.isEmpty) {
        return;
      }
      final svc = UserUiPreferencesService(ApiClient());
      await svc.putPreferences({
        'theme_id': _themeId,
        'theme_mode': _themeModeToString(_mode),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ThemeController persist failed: $e');
      }
    }
  }

  void _syncLoader() {
    syncLoaderThemeMode(_mode.index);
    syncLoaderBrandColor(themeDefinition.primary);
    unawaited(AndroidNotificationPrefs.syncThemePrimaryFallback(
      themeDefinition.primary.toARGB32(),
    ));
  }

  static String _themeModeToString(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  static ThemeMode? _themeModeFromString(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return null;
    }
  }
}
