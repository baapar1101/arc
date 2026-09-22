import 'package:flutter/cupertino.dart';
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

    final textTheme = isFa
        ? faTextTheme(color: scheme.onSurface)
        : enTextTheme(color: scheme.onSurface);
    final primaryFont = isFa ? AppFonts.faPrimary : AppFonts.enPrimary;
    final fontFallback = isFa ? AppFonts.faFallback : AppFonts.enFallback;

    const spacing = AppSpacing();
    const shape = AppShape();
    const radii = AppRadii(); // سازگاری با کد قدیمی
    const motion = AppMotion();
    final semantic = AppSemanticColors.fromScheme(scheme);
    final shellColors = AppShellColors.fromScheme(scheme, isDark: isDark);
    final surfaces = AppSurfaces.fromScheme(scheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: primaryFont,
      fontFamilyFallback: fontFallback,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      visualDensity: VisualDensity.compact,

      // در M3 پس‌زمینهٔ صفحه پایین‌ترین لایهٔ سطح است.
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,

      iconTheme: IconThemeData(
        color: scheme.onSurfaceVariant,
        size: AppIconSize.small,
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),

      inputDecorationTheme: appInputDecorationTheme(scheme, shape, textTheme),
      elevatedButtonTheme: appElevatedButtonTheme(scheme, shape, textTheme),
      filledButtonTheme: appFilledButtonTheme(scheme, shape, textTheme),
      outlinedButtonTheme: appOutlinedButtonTheme(scheme, shape, textTheme),
      textButtonTheme: appTextButtonTheme(scheme, shape, textTheme),
      segmentedButtonTheme: appSegmentedButtonTheme(scheme, shape, textTheme),
      floatingActionButtonTheme: appFabTheme(scheme, shape),
      appBarTheme: appAppBarTheme(scheme, textTheme),
      cardTheme: appCardTheme(scheme, shape),
      listTileTheme: appListTileTheme(scheme, shape, textTheme),
      navigationRailTheme: appNavigationRailTheme(scheme, textTheme),
      navigationBarTheme: appNavigationBarTheme(scheme, textTheme),
      navigationDrawerTheme: appNavigationDrawerTheme(scheme, textTheme),
      drawerTheme: appDrawerTheme(scheme, shape),
      dividerTheme: appDividerTheme(scheme),
      iconButtonTheme: appIconButtonTheme(scheme),
      dialogTheme: appDialogTheme(scheme, shape, textTheme),
      bottomSheetTheme: appBottomSheetTheme(scheme, shape),
      tabBarTheme: appTabBarTheme(scheme, textTheme),
      chipTheme: appChipTheme(scheme, shape, textTheme),
      snackBarTheme: appSnackBarTheme(scheme, shape, textTheme),
      dataTableTheme: appDataTableTheme(scheme, textTheme),
      tooltipTheme: appTooltipTheme(scheme, shape, textTheme),
      menuTheme: appMenuTheme(scheme, shape),
      popupMenuTheme: appPopupMenuTheme(scheme, shape, textTheme),
      searchBarTheme: appSearchBarTheme(scheme, shape, textTheme),
      searchViewTheme: appSearchViewTheme(scheme, shape, textTheme),
      switchTheme: appSwitchTheme(scheme),
      checkboxTheme: appCheckboxTheme(scheme, shape),
      radioTheme: appRadioTheme(scheme),
      sliderTheme: appSliderTheme(scheme),
      progressIndicatorTheme: appProgressTheme(scheme),
      badgeTheme: appBadgeTheme(scheme, textTheme),
      expansionTileTheme: appExpansionTileTheme(scheme, shape),

      extensions: <ThemeExtension<dynamic>>[
        spacing,
        shape,
        radii,
        motion,
        semantic,
        shellColors,
        surfaces,
      ],
    );
  }
}
