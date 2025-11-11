import 'package:flutter/material.dart';

import 'components.dart';
import 'tokens/color_schemes.dart';
import 'tokens/extensions.dart';
import 'tokens/typography.dart';

class AppTheme {
  static ThemeData build({
    required bool isDark,
    required Locale locale,
    required Color seed,
  }) {
    final scheme = AppColorTokens.schemeFromSeed(seed, dark: isDark);
    final isFa = locale.languageCode.toLowerCase() == 'fa';

    final textTheme = isFa ? faTextTheme(isDark: isDark) : enTextTheme(isDark: isDark);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: isFa ? 'YekanBakhFaNum' : null,
      textTheme: textTheme,
      // در حالت تیره، کنتراست متن‌ها را کمی تقویت می‌کنیم
      scaffoldBackgroundColor: isDark ? scheme.surface : null,
      inputDecorationTheme: appInputDecorationTheme(scheme),
      elevatedButtonTheme: appElevatedButtonTheme(scheme),
      appBarTheme: appAppBarTheme(scheme),
      cardTheme: appCardTheme,
      extensions: const <ThemeExtension<dynamic>>[
        AppSpacing(),
        AppRadii(),
      ],
    );
  }
}


