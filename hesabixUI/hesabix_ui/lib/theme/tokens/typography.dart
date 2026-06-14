import 'package:flutter/material.dart';

/// فونت اصلی و fallback برای فارسی — بدون Noto Sans تا ارقام لاتین جایگزین نشوند.
abstract final class AppFonts {
  static const String faPrimary = 'YekanBakhFaNum';
  static const List<String> faFallback = [
    'Noto Color Emoji',
    'Vazirmatn',
    'NotoSansArabic',
  ];

  static const String enPrimary = 'Roboto';
  static const List<String> enFallback = [
    'Noto Color Emoji',
    'Noto Sans',
    'Roboto',
  ];
}

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
    return style.copyWith(
      fontSize: (size * scale).roundToDouble(),
      fontFamily: null,
      fontFamilyFallback: null,
    );
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

TextTheme _withFontFamily(
  TextTheme base, {
  required String fontFamily,
  required List<String> fontFamilyFallback,
}) {
  TextStyle? patch(TextStyle? style) {
    if (style == null) return null;
    return style.copyWith(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );
  }

  return base.copyWith(
    displayLarge: patch(base.displayLarge),
    displayMedium: patch(base.displayMedium),
    displaySmall: patch(base.displaySmall),
    headlineLarge: patch(base.headlineLarge),
    headlineMedium: patch(base.headlineMedium),
    headlineSmall: patch(base.headlineSmall),
    titleLarge: patch(base.titleLarge),
    titleMedium: patch(base.titleMedium),
    titleSmall: patch(base.titleSmall),
    bodyLarge: patch(base.bodyLarge),
    bodyMedium: patch(base.bodyMedium),
    bodySmall: patch(base.bodySmall),
    labelLarge: patch(base.labelLarge),
    labelMedium: patch(base.labelMedium),
    labelSmall: patch(base.labelSmall),
  );
}

TextTheme faTextTheme({required bool isDark}) {
  final scaled = _compactScale(_materialBase(isDark: isDark), scale: 0.90);
  return _withFontFamily(
    scaled,
    fontFamily: AppFonts.faPrimary,
    fontFamilyFallback: AppFonts.faFallback,
  );
}

TextTheme enTextTheme({required bool isDark}) {
  final scaled = _compactScale(_materialBase(isDark: isDark), scale: 0.93);
  return _withFontFamily(
    scaled,
    fontFamily: AppFonts.enPrimary,
    fontFamilyFallback: AppFonts.enFallback,
  );
}
