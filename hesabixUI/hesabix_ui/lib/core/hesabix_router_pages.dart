import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// [NoTransitionPage] با کلید پایدار از مسیر کامل؛ برای ناوبری تب‌دار در شِل کسب‌وکار
/// به موتور مسیر کمک می‌کند همان مسیر را با هویت پایدارتر بازشناسی کند.
NoTransitionPage<void> hesabixNoTransitionPage(GoRouterState state, Widget child) {
  return NoTransitionPage<void>(
    // pageKey شامل query است؛ فقط path باعث می‌شد صفحاتی مثل کاردکس با تغییر فیلتر دوباره ساخته نشوند.
    key: state.pageKey,
    name: state.name,
    child: child,
  );
}
