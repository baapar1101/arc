import 'package:flutter/material.dart';

import 'tokens/extensions.dart';

// ---------------------------------------------------------------------------
// ورودی
// ---------------------------------------------------------------------------

/// ورودی در دیزاین مرجع: زمینهٔ `ink-800/60`، لبهٔ `white/[0.06]` و
/// در فوکوس لبهٔ زمردی — بدون ضخیم شدن قاب.
InputDecorationTheme appInputDecorationTheme(
  ColorScheme scheme,
  AppShape shape,
  TextTheme textTheme,
) {
  final radius = shape.smallBorder;
  final idle = scheme.outlineVariant;
  OutlineInputBorder outline(BorderSide side) =>
      OutlineInputBorder(borderRadius: radius, borderSide: side);

  return InputDecorationTheme(
    isDense: true,
    contentPadding: const EdgeInsetsDirectional.symmetric(
      horizontal: 14,
      vertical: 12,
    ),
    border: outline(BorderSide(color: idle)),
    enabledBorder: outline(BorderSide(color: idle)),
    focusedBorder: outline(
      BorderSide(color: scheme.primary.withValues(alpha: 0.6), width: 1.5),
    ),
    disabledBorder: outline(
      BorderSide(color: scheme.onSurface.withValues(alpha: 0.08)),
    ),
    errorBorder: outline(BorderSide(color: scheme.error)),
    focusedErrorBorder: outline(BorderSide(color: scheme.error, width: 1.5)),
    filled: true,
    fillColor: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
    hintStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
    labelStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
    floatingLabelStyle: textTheme.bodySmall?.copyWith(color: scheme.primary),
    errorStyle: textTheme.bodySmall?.copyWith(color: scheme.error),
    helperStyle: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
    prefixIconColor: scheme.onSurfaceVariant,
    suffixIconColor: scheme.onSurfaceVariant,
  );
}

// ---------------------------------------------------------------------------
// دکمه‌ها — سلسله‌مراتب M3:
//   Filled  → کنش اصلی صفحه (یکی در هر صفحه)
//   Tonal   → کنش مهم ولی نه اصلی
//   Outlined→ کنش ثانویه
//   Text    → کم‌اهمیت‌ترین، داخل دیالوگ و کارت
//   Elevated→ فقط روی سطح شلوغ (نقشه، تصویر)
// ---------------------------------------------------------------------------

ButtonStyle _base(ColorScheme scheme, AppShape shape, TextTheme textTheme) =>
    ButtonStyle(
      padding: const WidgetStatePropertyAll(
        EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 10),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
      // هدف لمسی ۴۸dp حتی وقتی ظاهر دکمه کوچک‌تر است.
      tapTargetSize: MaterialTapTargetSize.padded,
      // در M3 دکمه‌ها به‌طور پیش‌فرض کاملاً گرد (stadium) هستند.
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
      animationDuration: const Duration(milliseconds: 150),
    );

/// کنش اصلی: زمردی تخت با متن تیره و هالهٔ ملایم در hover —
/// معادل دکمهٔ `bg-gradient-to-l from-brand-500 to-brand-600 shadow-glow`.
FilledButtonThemeData appFilledButtonTheme(
  ColorScheme scheme,
  AppShape shape,
  TextTheme textTheme,
) =>
    FilledButtonThemeData(
      style: _base(scheme, shape, textTheme).copyWith(
        elevation: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return AppElevation.level0;
          if (states.contains(WidgetState.hovered)) return AppElevation.level2;
          return AppElevation.level0;
        }),
        shadowColor: WidgetStatePropertyAll(scheme.primary),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return scheme.onPrimary.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.hovered)) {
            return scheme.onPrimary.withValues(alpha: 0.06);
          }
          return null;
        }),
      ),
    );

OutlinedButtonThemeData appOutlinedButtonTheme(
  ColorScheme scheme,
  AppShape shape,
  TextTheme textTheme,
) =>
    OutlinedButtonThemeData(
      style: _base(scheme, shape, textTheme).copyWith(
        foregroundColor: WidgetStatePropertyAll(scheme.primary),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return BorderSide(color: scheme.onSurface.withValues(alpha: 0.12));
          }
          if (states.contains(WidgetState.focused)) {
            return BorderSide(color: scheme.primary);
          }
          return BorderSide(color: scheme.outlineVariant);
        }),
      ),
    );

TextButtonThemeData appTextButtonTheme(
  ColorScheme scheme,
  AppShape shape,
  TextTheme textTheme,
) =>
    TextButtonThemeData(
      style: _base(scheme, shape, textTheme).copyWith(
        foregroundColor: WidgetStatePropertyAll(scheme.primary),
        padding: const WidgetStatePropertyAll(
          EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );

/// عمداً ارتفاع واقعی دارد. اگر جایی سایه لازم نیست، آن مورد باید
/// FilledButton.tonal شود نه ElevatedButtonِ صاف.
ElevatedButtonThemeData appElevatedButtonTheme(
  ColorScheme scheme,
  AppShape shape,
  TextTheme textTheme,
) =>
    ElevatedButtonThemeData(
      style: _base(scheme, shape, textTheme).copyWith(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerLow),
        foregroundColor: WidgetStatePropertyAll(scheme.primary),
        elevation: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return AppElevation.level0;
          if (states.contains(WidgetState.pressed)) return AppElevation.level1;
          if (states.contains(WidgetState.hovered)) return AppElevation.level2;
          return AppElevation.level1;
        }),
      ),
    );

SegmentedButtonThemeData appSegmentedButtonTheme(
  ColorScheme scheme,
  AppShape shape,
  TextTheme textTheme,
) =>
    SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
        padding: const WidgetStatePropertyAll(
          EdgeInsetsDirectional.symmetric(horizontal: 12),
        ),
      ),
    );

FloatingActionButtonThemeData appFabTheme(ColorScheme scheme, AppShape shape) =>
    FloatingActionButtonThemeData(
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      elevation: AppElevation.level3,
      focusElevation: AppElevation.level3,
      hoverElevation: AppElevation.level4,
      shape: RoundedRectangleBorder(borderRadius: shape.largeBorder),
    );

// ---------------------------------------------------------------------------
// سطوح و ظروف
// ---------------------------------------------------------------------------

AppBarTheme appAppBarTheme(ColorScheme scheme, TextTheme textTheme) =>
    AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      // در M3 وقتی محتوا زیر نوار می‌لغزد، نوار به لایهٔ بالاتر می‌رود.
      surfaceTintColor: scheme.surfaceTint,
      elevation: AppElevation.level0,
      scrolledUnderElevation: AppElevation.level2,
      centerTitle: false, // M3 عنوان را در ابتدای خط می‌گذارد
      toolbarHeight: 56,
      titleSpacing: 16,
      titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      iconTheme: IconThemeData(
        color: scheme.onSurface,
        size: AppIconSize.standard,
      ),
      actionsIconTheme: IconThemeData(
        color: scheme.onSurfaceVariant,
        size: AppIconSize.standard,
      ),
    );

/// کارت = معادل `.glass-card` دیزاین مرجع: شعاع ۱۶، لبهٔ بسیار کم‌رنگ،
/// بدون سایهٔ متریال (سایه از `context.surfaces.cardShadow` می‌آید وقتی لازم شود).
CardThemeData appCardTheme(ColorScheme scheme, AppShape shape) => CardThemeData(
      clipBehavior: Clip.antiAlias,
      elevation: AppElevation.level0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shadowColor: scheme.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: shape.largeBorder,
        side: BorderSide(
          color: scheme.onSurface.withValues(
            alpha: scheme.brightness == Brightness.dark ? 0.06 : 0.08,
          ),
        ),
      ),
    );

ListTileThemeData appListTileTheme(
  ColorScheme scheme,
  AppShape shape,
  TextTheme textTheme,
) =>
    ListTileThemeData(
      dense: true,
      visualDensity: VisualDensity.compact,
      minVerticalPadding: 4,
      contentPadding: const EdgeInsetsDirectional.symmetric(
        horizontal: 16,
        vertical: 4,
      ),
      shape: RoundedRectangleBorder(borderRadius: shape.mediumBorder),
      iconColor: scheme.onSurfaceVariant,
      selectedColor: scheme.onPrimaryContainer,
      selectedTileColor: scheme.primary.withValues(alpha: 0.12),
      titleTextStyle: textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
      subtitleTextStyle:
          textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
    );

DrawerThemeData appDrawerTheme(ColorScheme scheme, AppShape shape) =>
    DrawerThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: AppElevation.level0,
      width: 360,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadiusDirectional.horizontal(
          end: Radius.circular(16),
        ),
      ),
    );

BottomSheetThemeData appBottomSheetTheme(ColorScheme scheme, AppShape shape) =>
    BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: AppElevation.level1,
      modalElevation: AppElevation.level1,
      showDragHandle: true,
      dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: shape.topLarge),
      clipBehavior: Clip.antiAlias,
    );

DialogThemeData appDialogTheme(
  ColorScheme scheme,
  AppShape shape,
  TextTheme textTheme,
) =>
    DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: AppElevation.level3,
      // دیالوگ در M3 بزرگ‌ترین شعاع را دارد: ۲۸.
      shape: RoundedRectangleBorder(borderRadius: shape.extraLargeBorder),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      titleTextStyle: textTheme.headlineSmall?.copyWith(color: scheme.onSurface),
      contentTextStyle:
          textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      actionsPadding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 24),
    );

// ---------------------------------------------------------------------------
// ناوبری
// ---------------------------------------------------------------------------

/// معادل `.nav-item`: زمینهٔ محوِ زمردی و متن `brand-300` در حالت فعال،
/// با گوشهٔ ۱۲ به‌جای قرص کامل.
NavigationRailThemeData appNavigationRailTheme(
  ColorScheme scheme,
  TextTheme textTheme,
) =>
    NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      elevation: AppElevation.level0,
      indicatorColor: scheme.primary.withValues(alpha: 0.15),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      useIndicator: true,
      selectedIconTheme: IconThemeData(
        color: scheme.onPrimaryContainer,
        size: AppIconSize.standard,
      ),
      unselectedIconTheme: IconThemeData(
        color: scheme.onSurfaceVariant,
        size: AppIconSize.standard,
      ),
      selectedLabelTextStyle:
          textTheme.labelMedium?.copyWith(color: scheme.onPrimaryContainer),
      unselectedLabelTextStyle:
          textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
    );

NavigationBarThemeData appNavigationBarTheme(
  ColorScheme scheme,
  TextTheme textTheme,
) =>
    NavigationBarThemeData(
      height: 80,
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: AppElevation.level0,
      indicatorColor: scheme.primary.withValues(alpha: 0.15),
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: AppIconSize.standard,
          color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return textTheme.labelMedium?.copyWith(
          color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        );
      }),
    );

NavigationDrawerThemeData appNavigationDrawerTheme(
  ColorScheme scheme,
  TextTheme textTheme,
) =>
    NavigationDrawerThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: AppElevation.level0,
      indicatorColor: scheme.primary.withValues(alpha: 0.15),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      indicatorSize: const Size(336, 48),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: AppIconSize.small,
          color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return textTheme.titleSmall?.copyWith(
          color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        );
      }),
    );

TabBarThemeData appTabBarTheme(ColorScheme scheme, TextTheme textTheme) =>
    TabBarThemeData(
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      labelStyle: textTheme.titleSmall,
      unselectedLabelStyle: textTheme.titleSmall,
      indicatorColor: scheme.primary,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: scheme.surfaceContainerHighest,
      dividerHeight: 1,
      overlayColor: WidgetStatePropertyAll(
        scheme.primary.withValues(alpha: 0.08),
      ),
    );

// ---------------------------------------------------------------------------
// جست‌وجو
// ---------------------------------------------------------------------------

SearchBarThemeData appSearchBarTheme(
  ColorScheme scheme,
  AppShape shape,
  TextTheme textTheme,
) =>
    SearchBarThemeData(
      elevation: const WidgetStatePropertyAll(AppElevation.level0),
      backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      padding: const WidgetStatePropertyAll(
        EdgeInsetsDirectional.symmetric(horizontal: 16),
      ),
      constraints: const BoxConstraints(minHeight: 48),
      textStyle: WidgetStatePropertyAll(
        textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
      ),
      hintStyle: WidgetStatePropertyAll(
        textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );

SearchViewThemeData appSearchViewTheme(
  ColorScheme scheme,
  AppShape shape,
  TextTheme textTheme,
) =>
    SearchViewThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: AppElevation.level0,
      dividerColor: scheme.outlineVariant,
      shape: RoundedRectangleBorder(borderRadius: shape.extraLargeBorder),
      headerHintStyle:
          textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
      headerTextStyle: textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
    );

// ---------------------------------------------------------------------------
// اجزای کوچک
// ---------------------------------------------------------------------------

/// معادل `.chip`: قرص کامل، ۱۱px با وزن ۶۰۰، زمینهٔ کم‌رنگِ نقش.
ChipThemeData appChipTheme(
  ColorScheme scheme,
  AppShape shape,
  TextTheme textTheme,
) =>
    ChipThemeData(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      labelStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
      secondaryLabelStyle:
          textTheme.labelMedium?.copyWith(color: scheme.onPrimaryContainer),
      backgroundColor: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
      selectedColor: scheme.primaryContainer,
      disabledColor: scheme.onSurface.withValues(alpha: 0.12),
      side: BorderSide(color: scheme.outlineVariant),
      shape: const StadiumBorder(),
      showCheckmark: true,
      checkmarkColor: scheme.onPrimaryContainer,
      elevation: AppElevation.level0,
      pressElevation: AppElevation.level0,
    );

DividerThemeData appDividerTheme(ColorScheme scheme) => DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    );

/// معادل `.icon-btn`: مربع ۴۰ با گوشهٔ ۱۲، لبهٔ کم‌رنگ، و در hover
/// لبه و آیکون زمردی می‌شوند.
IconButtonThemeData appIconButtonTheme(ColorScheme scheme) =>
    IconButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
        tapTargetSize: MaterialTapTargetSize.padded,
        iconSize: const WidgetStatePropertyAll(AppIconSize.small),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return BorderSide(color: scheme.primary.withValues(alpha: 0.3));
          }
          return null;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return scheme.onSurface.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return scheme.onPrimaryContainer;
          }
          return scheme.onSurfaceVariant;
        }),
        overlayColor: WidgetStatePropertyAll(
          scheme.primary.withValues(alpha: 0.08),
        ),
      ),
    );

SnackBarThemeData appSnackBarTheme(
  ColorScheme scheme,
  AppShape shape,
  TextTheme textTheme,
) =>
    SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: AppElevation.level3,
      shape: RoundedRectangleBorder(borderRadius: shape.extraSmallBorder),
      backgroundColor: scheme.inverseSurface,
      contentTextStyle:
          textTheme.bodyMedium?.copyWith(color: scheme.onInverseSurface),
      actionTextColor: scheme.inversePrimary,
      insetPadding: const EdgeInsets.all(16),
    );

TooltipThemeData appTooltipTheme(
  ColorScheme scheme,
  AppShape shape,
  TextTheme textTheme,
) =>
    TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: shape.extraSmallBorder,
      ),
      textStyle: textTheme.bodySmall?.copyWith(color: scheme.onInverseSurface),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      waitDuration: const Duration(milliseconds: 500),
    );

MenuThemeData appMenuTheme(ColorScheme scheme, AppShape shape) => MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(AppElevation.level2),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: shape.extraSmallBorder),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsetsDirectional.symmetric(vertical: 8),
        ),
      ),
    );

PopupMenuThemeData appPopupMenuTheme(
  ColorScheme scheme,
  AppShape shape,
  TextTheme textTheme,
) =>
    PopupMenuThemeData(
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: AppElevation.level2,
      shape: RoundedRectangleBorder(borderRadius: shape.extraSmallBorder),
      textStyle: textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
      labelTextStyle: WidgetStatePropertyAll(
        textTheme.bodyLarge?.copyWith(color: scheme.onSurface),
      ),
    );

BadgeThemeData appBadgeTheme(ColorScheme scheme, TextTheme textTheme) =>
    BadgeThemeData(
      backgroundColor: scheme.error,
      textColor: scheme.onError,
      textStyle: textTheme.labelSmall,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 4),
    );

ExpansionTileThemeData appExpansionTileTheme(
  ColorScheme scheme,
  AppShape shape,
) =>
    ExpansionTileThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      collapsedBackgroundColor: Colors.transparent,
      iconColor: scheme.primary,
      collapsedIconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      collapsedTextColor: scheme.onSurface,
      shape: RoundedRectangleBorder(borderRadius: shape.mediumBorder),
      collapsedShape: RoundedRectangleBorder(borderRadius: shape.mediumBorder),
      tilePadding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
    );

// ---------------------------------------------------------------------------
// کنترل‌های انتخاب
// ---------------------------------------------------------------------------

SwitchThemeData appSwitchTheme(ColorScheme scheme) => SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return scheme.onSurface.withValues(alpha: 0.38);
        }
        return states.contains(WidgetState.selected)
            ? scheme.onPrimary
            : scheme.outline;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return scheme.surfaceContainerHighest.withValues(alpha: 0.12);
        }
        return states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.surfaceContainerHighest;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? Colors.transparent
            : scheme.outline;
      }),
    );

CheckboxThemeData appCheckboxTheme(ColorScheme scheme, AppShape shape) =>
    CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: shape.extraSmallBorder),
      side: BorderSide(color: scheme.onSurfaceVariant, width: 2),
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return scheme.onSurface.withValues(alpha: 0.38);
        }
        return states.contains(WidgetState.selected)
            ? scheme.primary
            : Colors.transparent;
      }),
      checkColor: WidgetStatePropertyAll(scheme.onPrimary),
      visualDensity: VisualDensity.compact,
    );

RadioThemeData appRadioTheme(ColorScheme scheme) => RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return scheme.onSurface.withValues(alpha: 0.38);
        }
        return states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.onSurfaceVariant;
      }),
      visualDensity: VisualDensity.compact,
    );

SliderThemeData appSliderTheme(ColorScheme scheme) => SliderThemeData(
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withValues(alpha: 0.12),
      valueIndicatorColor: scheme.inverseSurface,
    );

ProgressIndicatorThemeData appProgressTheme(ColorScheme scheme) =>
    ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.secondaryContainer,
      circularTrackColor: scheme.secondaryContainer,
      // اگر Flutter شما قدیمی‌تر است و این پارامتر را نمی‌شناسد، حذفش کنید.
      year2023: false,
    );

// ---------------------------------------------------------------------------
// جدول داده
// ---------------------------------------------------------------------------

DataTableThemeData appDataTableTheme(ColorScheme scheme, TextTheme textTheme) =>
    DataTableThemeData(
      headingRowHeight: 44,
      dataRowMinHeight: 40,
      dataRowMaxHeight: 48,
      columnSpacing: 24,
      horizontalMargin: 16,
      dividerThickness: 1,
      headingRowColor: WidgetStatePropertyAll(
        scheme.surfaceContainerHigh.withValues(alpha: 0.5),
      ),
      headingTextStyle: textTheme.labelMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      dataTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
      dataRowColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return scheme.primary.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.hovered)) {
          return scheme.onSurface.withValues(alpha: 0.025);
        }
        return null;
      }),
    );
