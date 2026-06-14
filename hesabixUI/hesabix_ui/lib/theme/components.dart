import 'package:flutter/material.dart';

import 'tokens/extensions.dart';

InputDecorationTheme appInputDecorationTheme(
  ColorScheme scheme,
  AppRadii radii,
  TextTheme textTheme,
) {
  final radius = radii.mdBorder;
  OutlineInputBorder outline(BorderSide side) =>
      OutlineInputBorder(borderRadius: radius, borderSide: side);

  final enabled = outline(BorderSide(color: scheme.outlineVariant, width: 1));
  final focused = outline(BorderSide(color: scheme.primary, width: 1.5));
  final disabled = outline(
    BorderSide(color: scheme.onSurface.withValues(alpha: 0.12), width: 1),
  );
  final error = outline(BorderSide(color: scheme.error, width: 1));
  final focusedError = outline(BorderSide(color: scheme.error, width: 1.5));

  return InputDecorationTheme(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: enabled,
    enabledBorder: enabled,
    focusedBorder: focused,
    disabledBorder: disabled,
    errorBorder: error,
    focusedErrorBorder: focusedError,
    filled: true,
    fillColor: scheme.surfaceContainerHighest,
    hintStyle: textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
    ),
    labelStyle: textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    ),
  );
}

ButtonStyle _baseButtonStyle(ColorScheme scheme, AppRadii radii, TextTheme textTheme) =>
    ButtonStyle(
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
      minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radii.mdBorder)),
      textStyle: WidgetStatePropertyAll(
        textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    );

ElevatedButtonThemeData appElevatedButtonTheme(
  ColorScheme scheme,
  AppRadii radii,
  TextTheme textTheme,
) =>
    ElevatedButtonThemeData(
      style: _baseButtonStyle(scheme, radii, textTheme).copyWith(
        backgroundColor: WidgetStatePropertyAll(scheme.primary),
        foregroundColor: WidgetStatePropertyAll(scheme.onPrimary),
        elevation: const WidgetStatePropertyAll(0),
      ),
    );

FilledButtonThemeData appFilledButtonTheme(
  ColorScheme scheme,
  AppRadii radii,
  TextTheme textTheme,
) =>
    FilledButtonThemeData(
      style: _baseButtonStyle(scheme, radii, textTheme).copyWith(
        backgroundColor: WidgetStatePropertyAll(scheme.primary),
        foregroundColor: WidgetStatePropertyAll(scheme.onPrimary),
      ),
    );

OutlinedButtonThemeData appOutlinedButtonTheme(
  ColorScheme scheme,
  AppRadii radii,
  TextTheme textTheme,
) =>
    OutlinedButtonThemeData(
      style: _baseButtonStyle(scheme, radii, textTheme).copyWith(
        foregroundColor: WidgetStatePropertyAll(scheme.primary),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
      ),
    );

TextButtonThemeData appTextButtonTheme(
  ColorScheme scheme,
  AppRadii radii,
  TextTheme textTheme,
) =>
    TextButtonThemeData(
      style: _baseButtonStyle(scheme, radii, textTheme).copyWith(
        foregroundColor: WidgetStatePropertyAll(scheme.primary),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
      ),
    );

AppBarTheme appAppBarTheme(ColorScheme scheme, TextTheme textTheme) => AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      toolbarHeight: 44,
      titleTextStyle: textTheme.titleMedium?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
    );

CardThemeData appCardTheme(ColorScheme scheme, AppRadii radii) => CardThemeData(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radii.mdBorder,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.65)),
      ),
    );

ListTileThemeData appListTileTheme(ColorScheme scheme, TextTheme textTheme) => ListTileThemeData(
      dense: true,
      visualDensity: VisualDensity.compact,
      minVerticalPadding: 2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      iconColor: scheme.onSurfaceVariant,
      titleTextStyle: textTheme.bodyMedium,
      subtitleTextStyle: textTheme.bodySmall,
    );

NavigationRailThemeData appNavigationRailTheme(ColorScheme scheme, TextTheme textTheme) =>
    NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      selectedIconTheme: IconThemeData(color: scheme.primary, size: 20),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 20),
      selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );

DividerThemeData appDividerTheme(ColorScheme scheme) => DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.55),
      thickness: 1,
      space: 1,
    );

IconButtonThemeData appIconButtonTheme(ColorScheme scheme) => IconButtonThemeData(
      style: IconButton.styleFrom(
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(36, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        iconSize: 20,
        foregroundColor: scheme.onSurfaceVariant,
      ),
    );

DialogThemeData appDialogTheme(ColorScheme scheme, AppRadii radii, TextTheme textTheme) =>
    DialogThemeData(
      backgroundColor: scheme.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: radii.lgBorder),
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onSurface,
      ),
    );

TabBarThemeData appTabBarTheme(ColorScheme scheme, TextTheme textTheme) => TabBarThemeData(
      labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      unselectedLabelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
      indicatorSize: TabBarIndicatorSize.label,
      dividerHeight: 0,
    );

ChipThemeData appChipTheme(ColorScheme scheme, AppRadii radii, TextTheme textTheme) =>
    ChipThemeData(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      labelStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurface),
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: radii.smBorder),
    );

SnackBarThemeData appSnackBarTheme(ColorScheme scheme, AppRadii radii, TextTheme textTheme) =>
    SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: radii.smBorder),
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
      backgroundColor: scheme.inverseSurface,
    );

DataTableThemeData appDataTableTheme(ColorScheme scheme, TextTheme textTheme) =>
    DataTableThemeData(
      headingRowHeight: 36,
      dataRowMinHeight: 36,
      dataRowMaxHeight: 40,
      headingTextStyle: textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
      ),
      dataTextStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onSurface,
      ),
    );
