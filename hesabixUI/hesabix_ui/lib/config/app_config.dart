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
}


