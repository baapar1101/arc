import '../core/api_client.dart';

/// سرویس ترجمه ورک‌فلو
/// این سرویس ترجمه‌های نودهای ورک‌فلو را از backend دریافت می‌کند
class WorkflowTranslationService {
  final ApiClient _api;
  
  // Cache برای ترجمه‌ها
  static Map<String, Map<String, dynamic>>? _cachedTranslations;
  static String? _cachedLanguage;
  
  WorkflowTranslationService({ApiClient? apiClient}) 
      : _api = apiClient ?? ApiClient();
  
  /// دریافت تمام ترجمه‌های ورک‌فلو
  Future<Map<String, dynamic>> getTranslations({String lang = 'fa'}) async {
    // بررسی cache
    if (_cachedTranslations != null && _cachedLanguage == lang) {
      return _cachedTranslations![lang] ?? {};
    }
    
    try {
      final response = await _api.get(
        '/api/v1/workflows/translations',
        query: {'lang': lang},
      );
      
      final translations = response.data['data']['translations'] as Map<String, dynamic>?;
      
      if (translations != null) {
        _cachedTranslations = {lang: translations};
        _cachedLanguage = lang;
        return translations;
      }
      
      return {};
    } catch (e) {
      // در حالت debug لاگ می‌کنیم
      if (const bool.fromEnvironment('dart.vm.product') == false) {
        // ignore: avoid_print
        print('خطا در دریافت ترجمه‌های ورک‌فلو: $e');
      }
      return {};
    }
  }
  
  /// دریافت metadata actionها با ترجمه
  Future<List<Map<String, dynamic>>> getActionsMetadata({String lang = 'fa'}) async {
    try {
      final response = await _api.get(
        '/api/v1/workflows/metadata/actions',
        query: {'lang': lang},
      );
      
      final actions = response.data['data'] as List<dynamic>?;
      return actions?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      // در حالت debug لاگ می‌کنیم
      if (const bool.fromEnvironment('dart.vm.product') == false) {
        // ignore: avoid_print
        print('خطا در دریافت metadata actionها: $e');
      }
      return [];
    }
  }
  
  /// دریافت metadata triggerها با ترجمه
  Future<List<Map<String, dynamic>>> getTriggersMetadata({String lang = 'fa'}) async {
    try {
      final response = await _api.get(
        '/api/v1/workflows/metadata/triggers',
        query: {'lang': lang},
      );
      
      final triggers = response.data['data'] as List<dynamic>?;
      return triggers?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      // در حالت debug لاگ می‌کنیم
      if (const bool.fromEnvironment('dart.vm.product') == false) {
        // ignore: avoid_print
        print('خطا در دریافت metadata triggerها: $e');
      }
      return [];
    }
  }
  
  /// دریافت ترجمه یک کلید خاص
  String getTranslation(
    String key, {
    String? action,
    String lang = 'fa',
    String? fallback,
  }) {
    if (_cachedTranslations == null || _cachedLanguage != lang) {
      return fallback ?? key;
    }
    
    final translations = _cachedTranslations![lang];
    if (translations == null) {
      return fallback ?? key;
    }
    
    // جستجو در ترجمه‌های مشترک
    if (translations.containsKey(key)) {
      return translations[key] as String;
    }
    
    // جستجو در ترجمه‌های خاص action
    if (action != null && translations.containsKey(action)) {
      final actionTranslations = translations[action] as Map<String, dynamic>?;
      if (actionTranslations != null && actionTranslations.containsKey(key)) {
        return actionTranslations[key] as String;
      }
    }
    
    return fallback ?? key;
  }
  
  /// پاک کردن cache
  void clearCache() {
    _cachedTranslations = null;
    _cachedLanguage = null;
  }
  
  /// بارگذاری مجدد ترجمه‌ها
  Future<void> reloadTranslations({String lang = 'fa'}) async {
    clearCache();
    await getTranslations(lang: lang);
  }
}

