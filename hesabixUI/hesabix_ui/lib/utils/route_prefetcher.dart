import 'package:flutter/foundation.dart';

/// Utility class برای بهینه‌سازی loading صفحات در Flutter Web
/// 
/// توجه: در Flutter Web، تمام صفحات به صورت eager load می‌شوند
/// (همه import شده‌اند) بنابراین کد تمام صفحات در bundle اولیه موجود است.
/// 
/// این کلاس برای مستندات و احتمالات آینده نگهداری می‌شود.
/// 
/// برای بهینه‌سازی بیشتر:
/// 1. از build flags مناسب استفاده کنید (--release --web-renderer canvaskit)
/// 2. از CDN و caching استفاده کنید
/// 3. فایل‌های static را cache کنید
class RoutePrefetcher {
  /// یادآوری: در Flutter Web با eager loading، تمام صفحات از قبل لود شده‌اند
  /// این متد برای مستندات نگه داشته شده است
  static void initialize() {
    if (kDebugMode) {
      print('RoutePrefetcher: تمام صفحات به صورت eager load می‌شوند');
      print('RoutePrefetcher: برای بهینه‌سازی، از build flags مناسب استفاده کنید');
    }
  }
  
  /// راهنمایی برای بهینه‌سازی
  /// 
  /// در Flutter Web، بهترین راه برای حذف تأخیر:
  /// 1. استفاده از --release برای production build
  /// 2. استفاده از --web-renderer canvaskit
  /// 3. Cache کردن فایل‌های static
  /// 4. استفاده از CDN
  static String getOptimizationTips() {
    return '''
راهنمای بهینه‌سازی Flutter Web:

1. Build برای Production:
   flutter build web --release --web-renderer canvaskit

2. تمام صفحات به صورت eager load می‌شوند (همه import شده‌اند)
   بنابراین کد تمام صفحات در bundle اولیه موجود است

3. برای کاهش حجم bundle، می‌توانید از deferred imports استفاده کنید
   اما این باعث ایجاد تأخیر در جابجایی بین صفحات می‌شود

4. توصیه: eager loading بهتر از lazy loading برای تجربه کاربری است
''';
  }
}

