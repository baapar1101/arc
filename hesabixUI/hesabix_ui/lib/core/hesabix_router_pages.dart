import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// [NoTransitionPage] با کلید پایدار از مسیر کامل؛ برای ناوبری تب‌دار در شِل کسب‌وکار
/// به موتور مسیر کمک می‌کند همان مسیر را با هویت پایدارتر بازشناسی کند.
NoTransitionPage<void> hesabixNoTransitionPage(GoRouterState state, Widget child) {
  return NoTransitionPage<void>(
    key: ValueKey<String>('hesabix_${state.uri.path}'),
    name: state.name,
    child: child,
  );
}
