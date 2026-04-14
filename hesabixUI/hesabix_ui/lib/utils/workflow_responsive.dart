import 'package:flutter/material.dart';

/// Utility class برای مدیریت اندازه‌های responsive در workflow editor
class WorkflowResponsive {
  /// تشخیص نوع صفحه
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 600 && width < 1024;
  }

  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= 1024;
  }

  /// اندازه نود
  static Size getNodeSize(BuildContext context) {
    if (isMobile(context)) {
      return const Size(140, 80);
    } else if (isTablet(context)) {
      return const Size(160, 90);
    } else {
      return const Size(180, 100);
    }
  }

  /// اندازه connection point
  static double getConnectionPointSize(BuildContext context) {
    if (isMobile(context)) {
      return 20.0; // بزرگ‌تر برای لمس آسان‌تر
    } else {
      return 16.0;
    }
  }

  /// اندازه grid
  static double getGridSize(BuildContext context) {
    if (isMobile(context)) {
      return 15.0;
    } else {
      return 20.0;
    }
  }

  /// عرض drawer
  static double getDrawerWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (isMobile(context)) {
      return screenWidth * 0.85;
    } else if (isTablet(context)) {
      return 350.0;
    } else {
      return 300.0;
    }
  }
}

