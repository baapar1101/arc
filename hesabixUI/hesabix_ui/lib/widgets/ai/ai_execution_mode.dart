import 'package:flutter/material.dart';

/// حالت‌های اجرای دستیار AI در چت کسب‌وکار.
abstract final class AIExecutionMode {
  static const analyzer = 'analyzer';
  static const supervised = 'supervised';
  static const autonomous = 'autonomous';

  static const defaultMode = analyzer;

  static const all = [analyzer, supervised, autonomous];

  static bool isValid(String? value) =>
      value != null && all.contains(value.trim().toLowerCase());

  static String normalize(String? value) {
    final v = (value ?? defaultMode).trim().toLowerCase();
    return isValid(v) ? v : defaultMode;
  }

  static String label(String mode) {
    switch (normalize(mode)) {
      case supervised:
        return 'با تأیید من';
      case autonomous:
        return 'خودکار';
      case analyzer:
      default:
        return 'تحلیلگر';
    }
  }

  static String description(String mode) {
    switch (normalize(mode)) {
      case supervised:
        return 'هر تغییر قبل از اجرا نیاز به تأیید شما دارد';
      case autonomous:
        return 'اجرای مستقیم تغییرات؛ عملیات پرریسک همچنان تأیید می‌خواهند';
      case analyzer:
      default:
        return 'فقط خواندن و تحلیل — بدون تغییر در داده‌ها';
    }
  }

  static IconData icon(String mode) {
    switch (normalize(mode)) {
      case supervised:
        return Icons.verified_user_outlined;
      case autonomous:
        return Icons.bolt_outlined;
      case analyzer:
      default:
        return Icons.analytics_outlined;
    }
  }

  static Color accentColor(BuildContext context, String mode) {
    final scheme = Theme.of(context).colorScheme;
    switch (normalize(mode)) {
      case supervised:
        return scheme.primary;
      case autonomous:
        return Colors.amber.shade700;
      case analyzer:
      default:
        return scheme.tertiary;
    }
  }

  static bool requiresAutonomousConfirmation(String from, String to) {
    return normalize(from) != autonomous && normalize(to) == autonomous;
  }
}
