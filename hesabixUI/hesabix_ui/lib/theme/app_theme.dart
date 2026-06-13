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
    const spacing = AppSpacing();
    const radii = AppRadii();
    final shellColors = AppShellColors.fromScheme(scheme, isDark: isDark);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: isFa ? 'YekanBakhFaNum' : null,
      fontFamilyFallback: isFa
          ? const ['Noto Color Emoji', 'Noto Sans', 'NotoSansArabic', 'Vazirmatn']
          : const ['Noto Color Emoji', 'Noto Sans', 'Roboto'],
      textTheme: textTheme,
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: isDark ? scheme.surface : scheme.surfaceContainerLowest,
      inputDecorationTheme: appInputDecorationTheme(scheme, radii),
      elevatedButtonTheme: appElevatedButtonTheme(scheme, radii),
      filledButtonTheme: appFilledButtonTheme(scheme, radii),
      outlinedButtonTheme: appOutlinedButtonTheme(scheme, radii),
      textButtonTheme: appTextButtonTheme(scheme, radii),
      appBarTheme: appAppBarTheme(scheme),
      cardTheme: appCardTheme(scheme, radii),
      listTileTheme: appListTileTheme(scheme),
      navigationRailTheme: appNavigationRailTheme(scheme),
      dividerTheme: appDividerTheme(scheme),
      iconButtonTheme: appIconButtonTheme(scheme),
      dialogTheme: appDialogTheme(scheme, radii),
      tabBarTheme: appTabBarTheme(scheme),
      chipTheme: appChipTheme(scheme, radii),
      snackBarTheme: appSnackBarTheme(scheme, radii),
      dataTableTheme: appDataTableTheme(scheme),
      extensions: <ThemeExtension<dynamic>>[
        spacing,
        radii,
        shellColors,
      ],
    );
  }
}
