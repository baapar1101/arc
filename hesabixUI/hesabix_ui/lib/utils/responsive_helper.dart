import 'package:flutter/material.dart';

/// Helper class for responsive design
/// Provides utilities for breakpoint detection and responsive values
class ResponsiveHelper {
  /// Breakpoint values based on Material Design 3
  static const double mobileBreakpoint = 600;
  static const double tabletSmallBreakpoint = 904;
  static const double tabletLargeBreakpoint = 1240;
  static const double desktopSmallBreakpoint = 1600;

  /// Get current breakpoint based on screen width
  /// Returns: 'xs' (mobile), 'sm' (small tablet), 'md' (large tablet), 'lg' (small desktop), 'xl' (large desktop)
  static String breakpoint(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < mobileBreakpoint) return 'xs';
    if (width < tabletSmallBreakpoint) return 'sm';
    if (width < tabletLargeBreakpoint) return 'md';
    if (width < desktopSmallBreakpoint) return 'lg';
    return 'xl';
  }

  /// Check if current screen is mobile
  static bool isMobile(BuildContext context) {
    return breakpoint(context) == 'xs';
  }

  /// Check if current screen is tablet (small or large)
  static bool isTablet(BuildContext context) {
    final bp = breakpoint(context);
    return bp == 'sm' || bp == 'md';
  }

  /// Check if current screen is desktop (small or large)
  static bool isDesktop(BuildContext context) {
    final bp = breakpoint(context);
    return bp == 'lg' || bp == 'xl';
  }

  /// Get responsive value based on breakpoint
  /// mobile: value for mobile screens
  /// tablet: value for tablet screens (defaults to mobile * 1.5 if not provided)
  /// desktop: value for desktop screens (defaults to mobile * 2 if not provided)
  static double responsiveValue(
    BuildContext context, {
    required double mobile,
    double? tablet,
    double? desktop,
  }) {
    if (isMobile(context)) return mobile;
    if (isTablet(context)) return tablet ?? mobile * 1.5;
    return desktop ?? mobile * 2;
  }

  /// Get responsive padding based on breakpoint
  static double getPadding(BuildContext context) {
    final bp = breakpoint(context);
    switch (bp) {
      case 'xs':
        return 8.0; // موبایل
      case 'sm':
        return 12.0; // تبلت کوچک
      case 'md':
        return 16.0; // تبلت بزرگ
      case 'lg':
        return 20.0; // دسکتاپ کوچک
      case 'xl':
        return 24.0; // دسکتاپ بزرگ
      default:
        return 16.0;
    }
  }

  /// Get responsive spacing for grids
  static double getGridSpacing(BuildContext context) {
    final bp = breakpoint(context);
    switch (bp) {
      case 'xs':
        return 8.0;
      case 'sm':
        return 10.0;
      case 'md':
        return 12.0;
      case 'lg':
        return 14.0;
      case 'xl':
        return 16.0;
      default:
        return 12.0;
    }
  }

  /// Get responsive dialog padding
  static EdgeInsets getDialogPadding(BuildContext context) {
    if (isMobile(context)) {
      return EdgeInsets.zero; // Fullscreen on mobile
    }
    return const EdgeInsets.all(24.0);
  }

  /// Get responsive dialog constraints
  static BoxConstraints getDialogConstraints(BuildContext context) {
    if (isMobile(context)) {
      return BoxConstraints(
        maxWidth: double.infinity,
        maxHeight: MediaQuery.of(context).size.height,
      );
    }
    final screenSize = MediaQuery.of(context).size;
    final targetWidth = screenSize.width * 0.95;
    return BoxConstraints(
      minWidth: 1000,
      maxWidth: targetWidth.clamp(1000, 1400),
      maxHeight: screenSize.height * 0.92,
    );
  }

  /// Get responsive card max width
  static double getCardMaxWidth(BuildContext context) {
    if (isMobile(context)) {
      return double.infinity;
    }
    final bp = breakpoint(context);
    switch (bp) {
      case 'sm':
        return 520;
      case 'md':
        return 600;
      case 'lg':
        return 700;
      case 'xl':
        return 800;
      default:
        return 520;
    }
  }

  /// Get responsive grid cross axis count
  static int getGridCrossAxisCount(BuildContext context, {
    int mobile = 1,
    int tablet = 2,
    int desktop = 3,
  }) {
    if (isMobile(context)) return mobile;
    if (isTablet(context)) return tablet;
    return desktop;
  }

  /// Get responsive grid max cross axis extent
  static double getGridMaxCrossAxisExtent(BuildContext context, {
    double mobile = double.infinity,
    double? tablet,
    double? desktop,
  }) {
    if (isMobile(context)) return mobile;
    if (isTablet(context)) return tablet ?? 260;
    return desktop ?? 300;
  }
}

