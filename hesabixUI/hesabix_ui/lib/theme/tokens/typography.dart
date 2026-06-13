import 'package:flutter/material.dart';

TextTheme _materialBase({required bool isDark}) {
  return isDark
      ? Typography.material2021(platform: TargetPlatform.android).white
      : Typography.material2021(platform: TargetPlatform.android).black;
}

/// مقیاس فشردهٔ ERP — کوچک‌تر از Material پیش‌فرض برای نمایش بیشتر داده.
TextTheme _compactScale(TextTheme base, {required double scale}) {
  TextStyle? scaled(TextStyle? style) {
    if (style == null) return null;
    final size = style.fontSize;
    if (size == null) return style;
    return style.copyWith(fontSize: (size * scale).roundToDouble());
  }

  return base.copyWith(
    displayLarge: scaled(base.displayLarge),
    displayMedium: scaled(base.displayMedium),
    displaySmall: scaled(base.displaySmall),
    headlineLarge: scaled(base.headlineLarge),
    headlineMedium: scaled(base.headlineMedium),
    headlineSmall: scaled(base.headlineSmall),
    titleLarge: scaled(base.titleLarge),
    titleMedium: scaled(base.titleMedium),
    titleSmall: scaled(base.titleSmall),
    bodyLarge: scaled(base.bodyLarge),
    bodyMedium: scaled(base.bodyMedium),
    bodySmall: scaled(base.bodySmall),
    labelLarge: scaled(base.labelLarge),
    labelMedium: scaled(base.labelMedium),
    labelSmall: scaled(base.labelSmall),
  );
}

TextTheme faTextTheme({required bool isDark}) {
  const fallback = ['Noto Color Emoji', 'Noto Sans', 'NotoSansArabic', 'Vazirmatn'];
  final base = _compactScale(_materialBase(isDark: isDark), scale: 0.90);
  return base.apply(
    fontFamily: 'YekanBakhFaNum',
    fontFamilyFallback: fallback,
  );
}

TextTheme enTextTheme({required bool isDark}) {
  const fallback = ['Noto Color Emoji', 'Noto Sans', 'Roboto'];
  final base = _compactScale(_materialBase(isDark: isDark), scale: 0.93);
  return base.apply(
    fontFamily: 'Roboto',
    fontFamilyFallback: fallback,
  );
}
