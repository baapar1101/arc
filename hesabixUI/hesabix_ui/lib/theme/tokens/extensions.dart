import 'package:flutter/material.dart';

@immutable
class AppSpacing extends ThemeExtension<AppSpacing> {
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;

  const AppSpacing({this.xs = 4, this.sm = 8, this.md = 12, this.lg = 16, this.xl = 24});

  EdgeInsets get pagePadding => EdgeInsets.all(lg);
  EdgeInsets get cardPadding => EdgeInsets.all(md);
  EdgeInsets get sectionGap => EdgeInsets.symmetric(vertical: md);

  @override
  AppSpacing copyWith({double? xs, double? sm, double? md, double? lg, double? xl}) => AppSpacing(
        xs: xs ?? this.xs,
        sm: sm ?? this.sm,
        md: md ?? this.md,
        lg: lg ?? this.lg,
        xl: xl ?? this.xl,
      );

  @override
  AppSpacing lerp(ThemeExtension<AppSpacing>? other, double t) {
    if (other is! AppSpacing) return this;
    double l(double a, double b) => a + (b - a) * t;
    return AppSpacing(
      xs: l(xs, other.xs),
      sm: l(sm, other.sm),
      md: l(md, other.md),
      lg: l(lg, other.lg),
      xl: l(xl, other.xl),
    );
  }
}

@immutable
class AppRadii extends ThemeExtension<AppRadii> {
  final double sm;
  final double md;
  final double lg;

  const AppRadii({this.sm = 6, this.md = 10, this.lg = 14});

  BorderRadius get smBorder => BorderRadius.circular(sm);
  BorderRadius get mdBorder => BorderRadius.circular(md);
  BorderRadius get lgBorder => BorderRadius.circular(lg);

  @override
  AppRadii copyWith({double? sm, double? md, double? lg}) => AppRadii(
        sm: sm ?? this.sm,
        md: md ?? this.md,
        lg: lg ?? this.lg,
      );

  @override
  AppRadii lerp(ThemeExtension<AppRadii>? other, double t) {
    if (other is! AppRadii) return this;
    double l(double a, double b) => a + (b - a) * t;
    return AppRadii(
      sm: l(sm, other.sm),
      md: l(md, other.md),
      lg: l(lg, other.lg),
    );
  }
}

/// رنگ‌های ثابت shell و پس‌زمینهٔ صفحات — از seed تم مشتق می‌شوند.
@immutable
class AppShellColors extends ThemeExtension<AppShellColors> {
  final Color topBarBackground;
  final Color topBarForeground;
  final Color dashboardBackground;

  const AppShellColors({
    required this.topBarBackground,
    required this.topBarForeground,
    required this.dashboardBackground,
  });

  static AppShellColors fromScheme(ColorScheme scheme, {required bool isDark}) {
    final topBarBg = isDark
        ? Color.lerp(scheme.primary, scheme.surface, 0.25)!
        : scheme.primary;
    final topBarFg = ThemeData.estimateBrightnessForColor(topBarBg) == Brightness.dark
        ? Colors.white
        : scheme.onPrimary;
    return AppShellColors(
      topBarBackground: topBarBg,
      topBarForeground: topBarFg,
      dashboardBackground: isDark
          ? scheme.surface
          : Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.035),
              scheme.surfaceContainerLowest,
            ),
    );
  }

  @override
  AppShellColors copyWith({
    Color? topBarBackground,
    Color? topBarForeground,
    Color? dashboardBackground,
  }) =>
      AppShellColors(
        topBarBackground: topBarBackground ?? this.topBarBackground,
        topBarForeground: topBarForeground ?? this.topBarForeground,
        dashboardBackground: dashboardBackground ?? this.dashboardBackground,
      );

  @override
  AppShellColors lerp(ThemeExtension<AppShellColors>? other, double t) {
    if (other is! AppShellColors) return this;
    return AppShellColors(
      topBarBackground: Color.lerp(topBarBackground, other.topBarBackground, t)!,
      topBarForeground: Color.lerp(topBarForeground, other.topBarForeground, t)!,
      dashboardBackground: Color.lerp(dashboardBackground, other.dashboardBackground, t)!,
    );
  }
}

extension AppThemeExtensions on BuildContext {
  AppSpacing get appSpacing => Theme.of(this).extension<AppSpacing>() ?? const AppSpacing();
  AppRadii get appRadii => Theme.of(this).extension<AppRadii>() ?? const AppRadii();
  AppShellColors get shellColors =>
      Theme.of(this).extension<AppShellColors>() ??
      AppShellColors.fromScheme(Theme.of(this).colorScheme, isDark: Theme.of(this).brightness == Brightness.dark);
}
