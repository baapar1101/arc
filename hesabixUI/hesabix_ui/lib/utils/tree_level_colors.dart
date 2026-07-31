import 'package:flutter/material.dart';

/// استایل بصری یک سطح در نمای درختی سلسله‌مراتبی.
@immutable
class TreeLevelStyle {
  final Color backgroundColor;
  final Color accentColor;
  final double indent;

  const TreeLevelStyle({
    required this.backgroundColor,
    required this.accentColor,
    required this.indent,
  });
}

/// رنگ‌های سطح‌محور برای درخت‌ها — از [ColorScheme] تم مشتق می‌شوند
/// تا در حالت روشن/تاریک و با seedهای مختلف سازگار بمانند.
abstract final class TreeLevelColors {
  TreeLevelColors._();

  /// فاصله افقی به ازای هر سطح (پیکسل).
  static const double indentPerLevel = 16.0;

  /// ضخامت نوار راهنمای عمودی کنار ردیف.
  static const double accentBarWidth = 3.0;

  static const int _anchorCount = 3;

  /// جابجایی hue در هر دور کامل پالت (درجه).
  static const double _hueCycleShift = 24.0;

  /// فاصله hue بین anchorها برای کاهش شباهت سطوح مجاور.
  static const double _hueAnchorSpread = 12.0;

  static TreeLevelStyle styleFor(BuildContext context, int level) {
    return styleForScheme(
      Theme.of(context).colorScheme,
      Theme.of(context).brightness,
      level,
    );
  }

  static TreeLevelStyle styleForScheme(
    ColorScheme scheme,
    Brightness brightness,
    int level,
  ) {
    final safeLevel = level < 0 ? 0 : level;
    final isDark = brightness == Brightness.dark;
    final hue = _hueForLevel(safeLevel, scheme);

    final bgSaturation = isDark ? 0.14 : 0.18;
    final bgLightnessBand = safeLevel % 4;
    final bgLightness = isDark
        ? (0.14 + bgLightnessBand * 0.012).clamp(0.0, 1.0)
        : (0.965 - bgLightnessBand * 0.012).clamp(0.0, 1.0);

    final tintedBackground = HSLColor.fromAHSL(1.0, hue, bgSaturation, bgLightness).toColor();
    final baseSurface = isDark ? scheme.surface : scheme.surfaceContainerLowest;
    final backgroundColor = Color.alphaBlend(
      tintedBackground.withValues(alpha: isDark ? 0.55 : 0.65),
      baseSurface,
    );

    final accentSaturation = isDark ? 0.42 : 0.55;
    final accentLightness = isDark ? 0.62 : 0.42;
    final accentColor = HSLColor.fromAHSL(
      1.0,
      hue,
      accentSaturation,
      accentLightness,
    ).toColor();

    return TreeLevelStyle(
      backgroundColor: backgroundColor,
      accentColor: accentColor,
      indent: safeLevel * indentPerLevel,
    );
  }

  static double _hueForLevel(int level, ColorScheme scheme) {
    final anchorHues = <double>[
      HSLColor.fromColor(scheme.primary).hue,
      HSLColor.fromColor(scheme.secondary).hue,
      HSLColor.fromColor(scheme.tertiary).hue,
    ];
    final cycle = level ~/ _anchorCount;
    final index = level % _anchorCount;
    return (anchorHues[index] + cycle * _hueCycleShift + index * _hueAnchorSpread) % 360.0;
  }
}
