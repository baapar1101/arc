import 'package:flutter/material.dart';

TextTheme faTextTheme({required bool isDark}) {
  // پوشش ایموجی/نماد در چت وب و متن مختلط؛ کاهش وابستگی به دانلود Noto توسط موتور وب
  const fallback = ['Noto Color Emoji', 'Noto Sans', 'NotoSansArabic', 'Vazirmatn'];
  final base = isDark
      ? Typography.material2021(platform: TargetPlatform.android).white
      : Typography.material2021(platform: TargetPlatform.android).black;
  return base.apply(
    fontFamily: 'YekanBakhFaNum',
    fontFamilyFallback: fallback,
  );
}

TextTheme enTextTheme({required bool isDark}) {
  const fallback = ['Noto Color Emoji', 'Noto Sans', 'Roboto'];
  final base = isDark
      ? Typography.material2021(platform: TargetPlatform.android).white
      : Typography.material2021(platform: TargetPlatform.android).black;
  return base.apply(
    fontFamily: 'Roboto',
    fontFamilyFallback: fallback,
  );
}


