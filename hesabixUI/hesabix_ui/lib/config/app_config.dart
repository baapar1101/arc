import 'package:flutter/foundation.dart' show kIsWeb;

class AppConfig {
  AppConfig._();

  static const String _envApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  /// بک‌اند پیش‌فرض. مسیرها خودشان `/api/v1/...` را دارند، پس اینجا فقط
  /// origin نوشته می‌شود — نه `/api/v1`، وگرنه دو بار تکرار می‌شود.
  static const String defaultApiBaseUrl = 'https://tamastore.ir';

  /// هاست‌هایی که یعنی «در حال توسعهٔ محلی هستیم».
  static const Set<String> _devHosts = {'localhost', '127.0.0.1', '::1'};

  /// API Base URL
  ///
  /// - اگر با `--dart-define=API_BASE_URL=...` مقداردهی شود همان استفاده می‌شود.
  /// - در وب وقتی از یک هاست محلی سرو می‌شویم، بک‌اند محلی وجود ندارد؛ پس به
  ///   [defaultApiBaseUrl] وصل می‌شویم تا بشود صفحات را با دادهٔ واقعی دید.
  /// - در وبِ منتشرشده از همان origin استفاده می‌شود (reverse proxy مسیرهای
  ///   `/api/*` و `/ws/*` را به بک‌اند پاس می‌دهد).
  static String get apiBaseUrl {
    final v = _envApiBaseUrl.trim();
    if (v.isNotEmpty) return v;

    if (kIsWeb) {
      final u = Uri.base;
      // توسعهٔ محلی: origin ما یک سرور استاتیک است و API ندارد.
      if (_devHosts.contains(u.host)) return defaultApiBaseUrl;
      // مثال: https://arc.hesabix.ir — پشت reverse proxy.
      return u.origin;
    }

    return defaultApiBaseUrl;
  }

  static const String _envAppPublicUrl = String.fromEnvironment(
    'APP_PUBLIC_URL',
    defaultValue: '',
  );

  /// آدرس پایهٔ وب‌اپ (بدون /login) — برای ساخت لینک بازیابی وقتی API لینک ندهد
  static String get appPublicBaseUrl {
    final v = _envAppPublicUrl.trim();
    if (v.isNotEmpty) {
      return v.replaceAll(RegExp(r'/+$'), '');
    }
    if (kIsWeb) {
      return Uri.base.origin;
    }
    return apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
  }

  /// لینک کامل: باز کردن /login?reset_token=... (هم‌راستا با بک‌اند)
  static String? buildPasswordResetUrl(String token) {
    if (token.isEmpty) return null;
    final b = appPublicBaseUrl;
    if (b.isEmpty) return null;
    return '$b/login?reset_token=${Uri.encodeComponent(token)}';
  }
}


