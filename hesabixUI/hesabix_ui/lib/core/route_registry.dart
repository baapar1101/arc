import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Registry برای ذخیره صفحات Route ها
/// این کلاس صفحات را به صورت خودکار register و preload می‌کند
class RouteRegistry {
  static final RouteRegistry _instance = RouteRegistry._internal();
  factory RouteRegistry() => _instance;
  RouteRegistry._internal();

  /// لیست تمام صفحات که باید preload شوند
  final List<void Function()> _pagePreloaders = [];

  /// ثبت یک صفحه برای preload
  void registerPagePreloader(void Function() preloader) {
    _pagePreloaders.add(preloader);
  }

  /// Preload تمام صفحات ثبت شده
  void preloadAll() {
    for (final preloader in _pagePreloaders) {
      try {
        preloader();
      } catch (e) {
        debugPrint('Error preloading page: $e');
      }
    }
  }

  /// پاک کردن تمام صفحات ثبت شده (برای تست)
  void clear() {
    _pagePreloaders.clear();
  }
}

/// Helper function برای ثبت صفحات route
/// این تابع باید در زمان ساخت routes فراخوانی شود
/// برای ثبت صفحات جدید، کافی است این تابع را در builder function فراخوانی کنید
/// 
/// مثال استفاده:
/// ```dart
/// builder: (context, state) {
///   final page = MyPage(...);
///   registerRoutePage(() => MyPage(...)); // برای preload
///   return page;
/// }
/// ```
void registerRoutePage(void Function() pagePreloader) {
  RouteRegistry().registerPagePreloader(pagePreloader);
}

/// Helper function برای wrap کردن builder functions و auto-register کردن صفحات
/// این تابع builder را wrap می‌کند و صفحات را به صورت خودکار register می‌کند
/// 
/// استفاده:
/// ```dart
/// builder: wrapBuilder((context, state) => MyPage(...))
/// ```
/// 
/// توجه: استفاده از این تابع توصیه نمی‌شود چون نیاز به mock context دارد
/// بهتر است از registerRoutePage مستقیماً استفاده کنید
Widget Function(BuildContext, GoRouterState) wrapBuilder(
  Widget Function(BuildContext, GoRouterState) builder,
) {
  // این تابع به mock context نیاز دارد که پیچیده است
  // بهتر است از registerRoutePage مستقیماً استفاده کنید
  // به همین دلیل این تابع غیرفعال است
  return builder;
}

/// Helper function برای traverse کردن routes و استخراج صفحات
/// این تابع routes را traverse می‌کند و صفحات را از builders استخراج می‌کند
/// 
/// توجه: این تابع فقط برای صفحاتی که از registerRoutePage استفاده می‌کنند کار می‌کند
/// برای صفحاتی که مستقیماً ساخته می‌شوند، باید از registerRoutePage استفاده کنید
/// 
/// توجه: این تابع فعلاً غیرفعال است چون نیاز به mock context دارد
/// بهتر است از registerRoutePage مستقیماً در builder functions استفاده کنید
void extractPagesFromRoutes(List<RouteBase> routes) {
  // این تابع به mock context نیاز دارد که پیچیده است
  // بهتر است از registerRoutePage مستقیماً در builder functions استفاده کنید
  // به همین دلیل این تابع غیرفعال است
}

