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

  /// فاصله ثابت hue بین سطوح مجاور (درجه).
  /// با این فاصله، حتی اگر primary/secondary/tertiary تم نزدیک باشند،
  /// هر سطح رنگ متمایزی می‌گیرد.
  static const double _hueStepPerLevel = 47.0;

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

    // پس‌زمینه بسیار ملایم و کمرنگ
    final bgSaturation = isDark ? 0.07 : 0.09;
    final lightnessBand = safeLevel % 3;
    final bgLightness = isDark
        ? (0.17 + lightnessBand * 0.008).clamp(0.0, 1.0)
        : (0.985 - lightnessBand * 0.005).clamp(0.0, 1.0);

    final tintedBackground = HSLColor.fromAHSL(1.0, hue, bgSaturation, bgLightness).toColor();
    final baseSurface = isDark ? scheme.surface : scheme.surfaceContainerLowest;
    final backgroundColor = Color.alphaBlend(
      tintedBackground.withValues(alpha: isDark ? 0.38 : 0.32),
      baseSurface,
    );

    // نوار accent کمی پررنگ‌تر از پس‌زمینه، ولی همچنان ملایم
    final accentSaturation = isDark ? 0.32 : 0.38;
    final accentLightness = isDark ? 0.68 : 0.52;
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
    final baseHue = HSLColor.fromColor(scheme.primary).hue;
    return (baseHue + level * _hueStepPerLevel) % 360.0;
  }
}
