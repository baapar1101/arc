import 'package:flutter/material.dart';

import 'tokens/extensions.dart';

bool _isDark(ColorScheme scheme) => scheme.brightness == Brightness.dark;

InputDecorationTheme appInputDecorationTheme(
  ColorScheme scheme,
  AppRadii radii,
  TextTheme textTheme,
) {
  final radius = BorderRadius.circular(12);
  OutlineInputBorder outline(BorderSide side) =>
      OutlineInputBorder(borderRadius: radius, borderSide: side);

  final enabled = outline(BorderSide(
    color: scheme.onSurface.withValues(alpha: _isDark(scheme) ? 0.20 : 0.14),
    width: 1,
  ));
  final focused = outline(BorderSide(color: scheme.primary, width: 1.5));
  final disabled = outline(
    BorderSide(color: scheme.onSurface.withValues(alpha: 0.08), width: 1),
  );
  final error = outline(BorderSide(color: scheme.error, width: 1));
  final focusedError = outline(BorderSide(color: scheme.error, width: 1.5));

  return InputDecorationTheme(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: enabled,
    enabledBorder: enabled,
    focusedBorder: focused,
    disabledBorder: disabled,
    errorBorder: error,
    focusedErrorBorder: focusedError,
    filled: true,
    fillColor: _isDark(scheme)
        ? Colors.white.withValues(alpha: 0.055)
        : Colors.white.withValues(alpha: 0.72),
    hintStyle: textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
    ),
    labelStyle: textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    ),
    floatingLabelStyle: textTheme.bodyMedium?.copyWith(
      color: scheme.primary,
      fontWeight: FontWeight.w600,
    ),
  );
}

ButtonStyle _baseButtonStyle(ColorScheme scheme, AppRadii radii, TextTheme textTheme) =>
    ButtonStyle(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(0, 42)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      textStyle: WidgetStatePropertyAll(
        textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );

ElevatedButtonThemeData appElevatedButtonTheme(
  ColorScheme scheme,
  AppRadii radii,
  TextTheme textTheme,
) =>
    ElevatedButtonThemeData(
      style: _baseButtonStyle(scheme, radii, textTheme).copyWith(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return scheme.primary.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.hovered)) {
            return Color.lerp(scheme.primary, Colors.black, 0.12);
          }
          return scheme.primary;
        }),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: WidgetStatePropertyAll(
          scheme.primary.withValues(alpha: 0.28),
        ),
      ),
    );

FilledButtonThemeData appFilledButtonTheme(
  ColorScheme scheme,
  AppRadii radii,
  TextTheme textTheme,
) =>
    FilledButtonThemeData(
      style: _baseButtonStyle(scheme, radii, textTheme).copyWith(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return scheme.primary.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.hovered)) {
            return Color.lerp(scheme.primary, Colors.black, 0.12);
          }
          return scheme.primary;
        }),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
      ),
    );

OutlinedButtonThemeData appOutlinedButtonTheme(
  ColorScheme scheme,
  AppRadii radii,
  TextTheme textTheme,
) =>
    OutlinedButtonThemeData(
      style: _baseButtonStyle(scheme, radii, textTheme).copyWith(
        foregroundColor: WidgetStatePropertyAll(scheme.onSurface),
        backgroundColor: WidgetStatePropertyAll(
          scheme.onSurface.withValues(alpha: _isDark(scheme) ? 0.04 : 0.03),
        ),
        side: WidgetStatePropertyAll(
          BorderSide(color: scheme.onSurface.withValues(alpha: 0.18)),
        ),
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
        minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        ),
      ),
    );

AppBarTheme appAppBarTheme(ColorScheme scheme, TextTheme textTheme) => AppBarTheme(
      backgroundColor: _isDark(scheme)
          ? const Color(0xB30F172A)
          : const Color(0xCCFFFFFF),
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      toolbarHeight: 48,
      titleTextStyle: textTheme.titleMedium?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
    );

CardThemeData appCardTheme(ColorScheme scheme, AppRadii radii) => CardThemeData(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      color: _isDark(scheme)
          ? Colors.white.withValues(alpha: 0.075)
          : Colors.white.withValues(alpha: 0.78),
      shadowColor: Colors.black.withValues(alpha: 0.22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _isDark(scheme)
              ? Colors.white.withValues(alpha: 0.14)
              : const Color(0xFF2563EB).withValues(alpha: 0.10),
        ),
      ),
    );

ListTileThemeData appListTileTheme(ColorScheme scheme, TextTheme textTheme) => ListTileThemeData(
      dense: true,
      visualDensity: VisualDensity.compact,
      minVerticalPadding: 4,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      selectedColor: scheme.primary,
      selectedTileColor: scheme.primary.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      titleTextStyle: textTheme.bodyMedium,
      subtitleTextStyle: textTheme.bodySmall,
    );

NavigationRailThemeData appNavigationRailTheme(ColorScheme scheme, TextTheme textTheme) =>
    NavigationRailThemeData(
      backgroundColor: _isDark(scheme)
          ? const Color(0x99111827)
          : const Color(0xCCFFFFFF),
      indicatorColor: scheme.primary.withValues(alpha: 0.18),
      selectedIconTheme: IconThemeData(color: scheme.primary, size: 20),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 20),
      selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );

DividerThemeData appDividerTheme(ColorScheme scheme) => DividerThemeData(
      color: scheme.onSurface.withValues(alpha: 0.10),
      thickness: 1,
      space: 1,
    );

IconButtonThemeData appIconButtonTheme(ColorScheme scheme) => IconButtonThemeData(
      style: ButtonStyle(
        visualDensity: const WidgetStatePropertyAll(VisualDensity.compact),
        minimumSize: const WidgetStatePropertyAll(Size(36, 36)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        iconSize: const WidgetStatePropertyAll(20),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.hovered) ? scheme.primary : scheme.onSurfaceVariant),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.hovered)
                ? scheme.primary.withValues(alpha: 0.10)
                : Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );

DialogThemeData appDialogTheme(ColorScheme scheme, AppRadii radii, TextTheme textTheme) =>
    DialogThemeData(
      backgroundColor: _isDark(scheme)
          ? const Color(0xF2111827)
          : const Color(0xF7FFFFFF),
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: scheme.onSurface.withValues(alpha: 0.12),
        ),
      ),
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onSurface,
      ),
    );

TabBarThemeData appTabBarTheme(ColorScheme scheme, TextTheme textTheme) => TabBarThemeData(
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      unselectedLabelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
      indicatorColor: scheme.primary,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: scheme.onSurface.withValues(alpha: 0.08),
    );

ChipThemeData appChipTheme(ColorScheme scheme, AppRadii radii, TextTheme textTheme) =>
    ChipThemeData(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      labelStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurface),
      backgroundColor: scheme.onSurface.withValues(alpha: 0.055),
      selectedColor: scheme.primary.withValues(alpha: 0.18),
      side: BorderSide(color: scheme.onSurface.withValues(alpha: 0.12)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
    );

SnackBarThemeData appSnackBarTheme(ColorScheme scheme, AppRadii radii, TextTheme textTheme) =>
    SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
      backgroundColor: scheme.inverseSurface.withValues(alpha: 0.96),
    );

DataTableThemeData appDataTableTheme(ColorScheme scheme, TextTheme textTheme) =>
    DataTableThemeData(
      headingRowHeight: 40,
      dataRowMinHeight: 38,
      dataRowMaxHeight: 44,
      headingRowColor: WidgetStatePropertyAll(
        scheme.onSurface.withValues(alpha: 0.045),
      ),
      dividerThickness: 0.5,
      headingTextStyle: textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: scheme.onSurfaceVariant,
      ),
      dataTextStyle: textTheme.bodyMedium?.copyWith(
        color: scheme.onSurface,
      ),
    );
