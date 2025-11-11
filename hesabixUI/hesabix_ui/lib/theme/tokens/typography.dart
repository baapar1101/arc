import 'package:flutter/material.dart';

TextTheme faTextTheme({required bool isDark}) {
  // پایه را از M3 می‌گیریم؛ برای حالت تیره از white استفاده می‌کنیم تا کنتراست متن مناسب باشد
  final base = isDark
      ? Typography.material2021(platform: TargetPlatform.android).white
      : Typography.material2021(platform: TargetPlatform.android).black;
  return base.apply(fontFamily: 'YekanBakhFaNum');
}

TextTheme enTextTheme({required bool isDark}) {
  final base = isDark
      ? Typography.material2021(platform: TargetPlatform.android).white
      : Typography.material2021(platform: TargetPlatform.android).black;
  // از فونت پیش‌فرض سیستم استفاده می‌کنیم؛ در آینده می‌توانیم فونت انگلیسی سفارشی اضافه کنیم
  return base;
}


