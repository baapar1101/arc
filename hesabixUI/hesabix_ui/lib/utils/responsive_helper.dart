import 'package:flutter/material.dart';

/// آستانه‌های واکنش‌گرا و اسکلهٔ ناوبری اپ — همه از این کلاس استفاده کنند تا تغییرات بعدی یکجا اعمال شود.
class ResponsiveHelper {
  /// موبایل (کلاس compact در Material)
  static const double mobileBreakpoint = 600;

  /// مرز تبلت کوچک / بزرگ (Material window size classes)
  static const double tabletSmallBreakpoint = 904;

  /// بالاتر از این عرض دیگر «تبلت» برای چیدمان عمومی نیست (دسکتاپ از اینجا).
  /// مقدار ۱۰۲۴ برای جلوگیری از افتادن لپتاپ/مانیتور با مقیاس نمایش در بازهٔ تبلت انتخاب شده است.
  static const double tabletLargeBreakpoint = 1024;

  static const double desktopSmallBreakpoint = 1600;

  /// زیر این عرض در shellها منوی کشویی؛ از این عرض به بالا rail کناری.
  static const double shellPersistentNavMinWidth = 700;

  /// از این عرض به بالا rail کناری با برچسب کامل (حالت extended).
  static const double shellNavigationRailExtendedMinWidth = 1024;

  /// حداکثر عرض رایج برای دیالوگ/فرم چندستونه روی دسکتاپ
  static const double wideFormDialogMaxWidth = 1100;

  static double widthOf(BuildContext context) => MediaQuery.sizeOf(context).width;

  /// `xs` موبایل، `sm`/`md` تبلت، `lg`/`xl` دسکتاپ
  static String breakpointFromWidth(double width) {
    if (width < mobileBreakpoint) return 'xs';
    if (width < tabletSmallBreakpoint) return 'sm';
    if (width < tabletLargeBreakpoint) return 'md';
    if (width < desktopSmallBreakpoint) return 'lg';
    return 'xl';
  }

  static String breakpoint(BuildContext context) => breakpointFromWidth(widthOf(context));

  static bool isMobile(BuildContext context) => breakpoint(context) == 'xs';

  static bool isTablet(BuildContext context) {
    final bp = breakpoint(context);
    return bp == 'sm' || bp == 'md';
  }

  static bool isDesktop(BuildContext context) {
    final bp = breakpoint(context);
    return bp == 'lg' || bp == 'xl';
  }

  static bool useShellPersistentNavigation(BuildContext context) =>
      widthOf(context) >= shellPersistentNavMinWidth;

  static bool shellNavigationRailExtended(BuildContext context) =>
      widthOf(context) >= shellNavigationRailExtendedMinWidth;

  /// همان منطق قبلی عرض کمتر از ۷۰۰ برای AppBar فشرده و برخی comboboxها.
  static bool isShellCompactWidth(BuildContext context) =>
      widthOf(context) < shellPersistentNavMinWidth;

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

  static double getPadding(BuildContext context) {
    final bp = breakpoint(context);
    switch (bp) {
      case 'xs':
        return 8.0;
      case 'sm':
        return 10.0;
      case 'md':
        return 12.0;
      case 'lg':
        return 16.0;
      case 'xl':
        return 20.0;
      default:
        return 12.0;
    }
  }

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

  static EdgeInsets getDialogPadding(BuildContext context) {
    if (isMobile(context)) {
      return EdgeInsets.zero;
    }
    return const EdgeInsets.all(20.0);
  }

  static BoxConstraints getDialogConstraints(BuildContext context) {
    if (isMobile(context)) {
      return BoxConstraints(
        maxWidth: double.infinity,
        maxHeight: MediaQuery.of(context).size.height,
      );
    }
    final screenSize = MediaQuery.of(context).size;
    final targetWidth = screenSize.width * 0.92;
    return BoxConstraints(
      minWidth: 480,
      maxWidth: targetWidth.clamp(560, 1200),
      maxHeight: screenSize.height * 0.9,
    );
  }

  static double getCardMaxWidth(BuildContext context) {
    if (isMobile(context)) {
      return double.infinity;
    }
    final bp = breakpoint(context);
    switch (bp) {
      case 'sm':
        return 440;
      case 'md':
        return 480;
      case 'lg':
        return 520;
      case 'xl':
        return 560;
      default:
        return 440;
    }
  }

  static int getGridCrossAxisCount(
    BuildContext context, {
    int mobile = 1,
    int tablet = 2,
    int desktop = 3,
  }) {
    if (isMobile(context)) return mobile;
    if (isTablet(context)) return tablet;
    return desktop;
  }

  static double getGridMaxCrossAxisExtent(
    BuildContext context, {
    double mobile = double.infinity,
    double? tablet,
    double? desktop,
  }) {
    if (isMobile(context)) return mobile;
    if (isTablet(context)) return tablet ?? 260;
    return desktop ?? 300;
  }
}
