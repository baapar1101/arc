import 'package:flutter/material.dart';

@immutable
class AppSpacing extends ThemeExtension<AppSpacing> {
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;

  const AppSpacing({this.xs = 4, this.sm = 8, this.md = 12, this.lg = 16, this.xl = 24});

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
  const AppRadii({this.sm = 6, this.md = 10, this.lg = 16});

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


