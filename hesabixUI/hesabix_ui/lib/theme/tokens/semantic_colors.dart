import 'package:flutter/material.dart';

import 'theme_catalog.dart';

/// رنگ‌های معنایی سراسری (موفقیت / هشدار / خطا / اطلاعات).
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  final Color positive;
  final Color onPositive;
  final Color warning;
  final Color onWarning;
  final Color negative;
  final Color onNegative;
  final Color info;
  final Color onInfo;

  const AppSemanticColors({
    required this.positive,
    required this.onPositive,
    required this.warning,
    required this.onWarning,
    required this.negative,
    required this.onNegative,
    required this.info,
    required this.onInfo,
  });

  factory AppSemanticColors.fromDefinition(
    AppThemeDefinition def, {
    required bool isDark,
    required ColorScheme scheme,
  }) {
    Color adapt(Color c) {
      if (!isDark) return c;
      return Color.lerp(c, Colors.white, 0.12) ?? c;
    }

    Color onFor(Color bg) =>
        ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
            ? Colors.white
            : const Color(0xFF1A1A1A);

    final positive = adapt(def.positive);
    final warning = adapt(def.warning);
    final negative = adapt(def.negative);
    final info = adapt(scheme.primary);

    return AppSemanticColors(
      positive: positive,
      onPositive: onFor(positive),
      warning: warning,
      onWarning: onFor(warning),
      negative: negative,
      onNegative: onFor(negative),
      info: info,
      onInfo: onFor(info),
    );
  }

  @override
  AppSemanticColors copyWith({
    Color? positive,
    Color? onPositive,
    Color? warning,
    Color? onWarning,
    Color? negative,
    Color? onNegative,
    Color? info,
    Color? onInfo,
  }) {
    return AppSemanticColors(
      positive: positive ?? this.positive,
      onPositive: onPositive ?? this.onPositive,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      negative: negative ?? this.negative,
      onNegative: onNegative ?? this.onNegative,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      positive: Color.lerp(positive, other.positive, t)!,
      onPositive: Color.lerp(onPositive, other.onPositive, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      negative: Color.lerp(negative, other.negative, t)!,
      onNegative: Color.lerp(onNegative, other.onNegative, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
    );
  }
}
