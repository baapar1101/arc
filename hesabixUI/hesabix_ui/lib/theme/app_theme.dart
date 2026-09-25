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
        color: isDark ? const Color(0x8F111827) : const Color(0xA6FFFFFF),
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.10)),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            isDark ? const Color(0x8F111827) : const Color(0xA6FFFFFF),
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(12),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: scheme.onSurface.withValues(alpha: 0.10),
              ),
            ),
          ),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: appInputDecorationTheme(scheme, radii, textTheme),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(
            isDark ? const Color(0x8F111827) : const Color(0xA6FFFFFF),
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(12),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: scheme.onSurface.withValues(alpha: 0.10),
              ),
            ),
          ),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor:
            isDark ? const Color(0x8A111827) : const Color(0xA6FFFFFF),
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: scheme.onSurface.withValues(alpha: 0.10),
          ),
        ),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor:
            isDark ? const Color(0x80111827) : const Color(0x99FFFFFF),
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        indicatorColor: scheme.primary.withValues(alpha: 0.16),
      ),
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(
          isDark ? const Color(0x66111827) : const Color(0x80FFFFFF),
        ),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        side: WidgetStatePropertyAll(
          BorderSide(
            color: scheme.onSurface.withValues(alpha: 0.12),
          ),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor:
            isDark ? const Color(0x8F111827) : const Color(0xA6FFFFFF),
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        headerBackgroundColor: scheme.primary.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: scheme.onSurface.withValues(alpha: 0.10),
          ),
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor:
            isDark ? const Color(0xA6111827) : const Color(0xB8FFFFFF),
        elevation: 12,
        dialBackgroundColor: scheme.onSurface.withValues(alpha: 0.07),
        hourMinuteColor: scheme.onSurface.withValues(alpha: 0.07),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: scheme.onSurface.withValues(alpha: 0.10),
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark
            ? const Color(0xA6111827)
            : const Color(0xB8FFFFFF),
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: isDark
            ? const Color(0xA6111827)
            : const Color(0xB8FFFFFF),
        modalBarrierColor: isDark
            ? const Color(0x99000000)
            : const Color(0x520F172A),
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0x73111827) : const Color(0x80FFFFFF),
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        surfaceTintColor: Colors.transparent,
      ),
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
