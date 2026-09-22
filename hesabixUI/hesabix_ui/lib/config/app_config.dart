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
    return resolveApiBaseUrl(
      configuredValue: _envApiBaseUrl,
      isWebBuild: kIsWeb,
      currentUri: Uri.base,
    );
  }

  static String resolveApiBaseUrl({
    required String configuredValue,
    required bool isWebBuild,
    required Uri currentUri,
  }) {
    final value = configuredValue.trim();
    if (value.isNotEmpty) return value;

    if (isWebBuild) {
      final host = currentUri.host.toLowerCase();
      final isLocalPreview =
          host == 'localhost' || host == '127.0.0.1' || currentUri.port == 8080;
      if (isLocalPreview) {
        // Flutter web-server روی 8080 فقط فایل استاتیک سرو می‌کند. فرستادن
        // درخواست‌های API به همان origin خطا می‌دهد. این تشخیص شامل IP شبکه
        // نیز هست تا پیش‌نمایش روی دستگاه دیگری API همان میزبان را ببیند.
        return Uri(
          scheme: currentUri.scheme,
          host: currentUri.host,
          port: 8000,
        ).origin;
      }
      // مثال: http://localhost:8080 یا https://arc.hesabix.ir
      // در این حالت انتظار داریم reverse proxy مسیرهای api/ws را route کند.
      return currentUri.origin;
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
