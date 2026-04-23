import 'package:flutter/foundation.dart' show kIsWeb;

class AppConfig {
  AppConfig._();

  static const String _envApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  /// API Base URL
  ///
  /// - اگر با `--dart-define=API_BASE_URL=...` مقداردهی شود همان استفاده می‌شود.
  /// - در وب اگر مقداردهی نشده باشد، از همان origin فعلی استفاده می‌کنیم (به شرط اینکه
  ///   روی reverse proxy مسیرهای `/api/*` و `/ws/*` به بک‌اند پاس داده شوند).
  /// - در غیر وب، پیش‌فرض `http://localhost:8000` است.
  static String get apiBaseUrl {
    final v = _envApiBaseUrl.trim();
    if (v.isNotEmpty) return v;

    if (kIsWeb) {
      final u = Uri.base;
      // مثال: http://localhost:8080 یا https://arc.hesabix.ir
      // در این حالت انتظار داریم reverse proxy مسیرهای api/ws را route کند.
      return u.origin;
    }

    return 'http://localhost:8000';
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


