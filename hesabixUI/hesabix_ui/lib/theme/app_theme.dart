import 'package:flutter/material.dart';

import 'components.dart';
import 'tokens/color_schemes.dart';
import 'tokens/extensions.dart';
import 'tokens/typography.dart';

class AppTheme {
  static ThemeData build({
    required bool isDark,
    required Locale locale,
    required AppThemeDefinition themeDef,
  }) {
    final scheme = AppColorTokens.schemeForTheme(themeDef, dark: isDark);
    final isFa = locale.languageCode.toLowerCase() == 'fa';

    final textTheme = isFa ? faTextTheme(isDark: isDark) : enTextTheme(isDark: isDark);
    final primaryFont = isFa ? AppFonts.faPrimary : AppFonts.enPrimary;
    final fontFallback = isFa ? AppFonts.faFallback : AppFonts.enFallback;
    const spacing = AppSpacing();
    const radii = AppRadii();
    final shellColors = AppShellColors.fromScheme(scheme, isDark: isDark);
    final semantics = AppSemanticColors.fromDefinition(
      themeDef,
      isDark: isDark,
      scheme: scheme,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: primaryFont,
      fontFamilyFallback: fontFallback,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: isDark ? scheme.surface : scheme.surfaceContainerLowest,
      inputDecorationTheme: appInputDecorationTheme(scheme, radii, textTheme),
      elevatedButtonTheme: appElevatedButtonTheme(scheme, radii, textTheme),
      filledButtonTheme: appFilledButtonTheme(scheme, radii, textTheme),
      outlinedButtonTheme: appOutlinedButtonTheme(scheme, radii, textTheme),
      textButtonTheme: appTextButtonTheme(scheme, radii, textTheme),
      appBarTheme: appAppBarTheme(scheme, textTheme),
      cardTheme: appCardTheme(scheme, radii),
      listTileTheme: appListTileTheme(scheme, textTheme),
      navigationRailTheme: appNavigationRailTheme(scheme, textTheme),
      dividerTheme: appDividerTheme(scheme),
      iconButtonTheme: appIconButtonTheme(scheme),
      dialogTheme: appDialogTheme(scheme, radii, textTheme),
      tabBarTheme: appTabBarTheme(scheme, textTheme),
      chipTheme: appChipTheme(scheme, radii, textTheme),
      snackBarTheme: appSnackBarTheme(scheme, radii, textTheme),
      dataTableTheme: appDataTableTheme(scheme, textTheme),
      extensions: <ThemeExtension<dynamic>>[
        spacing,
        radii,
        shellColors,
        semantics,
      ],
    );
  }

  /// سازگاری با فراخوانی‌های قدیمی مبتنی بر seed.
  static ThemeData buildFromSeed({
    required bool isDark,
    required Locale locale,
    required Color seed,
  }) {
    return build(
      isDark: isDark,
      locale: locale,
      themeDef: AppThemeDefinition(
        id: 'custom_seed',
        labelFa: 'سفارشی',
        labelEn: 'Custom',
        primary: seed,
        secondary: const Color(0xFF5A6A7A),
        positive: const Color(0xFF2E7D32),
        negative: const Color(0xFFB3261E),
        warning: const Color(0xFFF0B92A),
        seedOnly: true,
      ),
    );
  }
}
