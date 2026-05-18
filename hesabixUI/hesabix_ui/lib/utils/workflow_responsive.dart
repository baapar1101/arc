import 'package:flutter/material.dart';

import 'responsive_helper.dart';

/// اندازه‌های workflow editor؛ آستانه‌ها از [ResponsiveHelper] خوانده می‌شوند.
class WorkflowResponsive {
  static bool isMobile(BuildContext context) => ResponsiveHelper.isMobile(context);

  static bool isTablet(BuildContext context) => ResponsiveHelper.isTablet(context);

  static bool isDesktop(BuildContext context) => ResponsiveHelper.isDesktop(context);

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

