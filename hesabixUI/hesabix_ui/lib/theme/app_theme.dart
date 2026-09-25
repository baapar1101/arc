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
    final primaryFont = isFa ? AppFonts.faPrimary : AppFonts.enPrimary;
    final fontFallback = isFa ? AppFonts.faFallback : AppFonts.enFallback;
    const spacing = AppSpacing();
    const radii = AppRadii();
    final shellColors = AppShellColors.fromScheme(scheme, isDark: isDark);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: primaryFont,
      fontFamilyFallback: fontFallback,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      splashColor: scheme.primary.withValues(alpha: 0.10),
      highlightColor: scheme.primary.withValues(alpha: 0.06),
      hoverColor: scheme.primary.withValues(alpha: 0.07),
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
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.onSurface.withValues(alpha: 0.10),
        circularTrackColor: scheme.onSurface.withValues(alpha: 0.10),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? const Color(0xF2111827) : const Color(0xF7FFFFFF),
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.10)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xE6111827) : const Color(0xE6FFFFFF),
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        surfaceTintColor: Colors.transparent,
      ),
      extensions: <ThemeExtension<dynamic>>[
        spacing,
        radii,
        shellColors,
      ],
    );
  }
}
