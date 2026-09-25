import 'package:flutter/material.dart';

import 'theme_catalog.dart';

class AppColorTokens {
  static Color _onFor(Color bg) =>
      ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
          ? Colors.white
          : const Color(0xFF1A1A1A);

  static Color _adaptForDark(Color c, {required bool dark, double amount = 0.18}) {
    if (!dark) return c;
    return Color.lerp(c, Colors.white, amount) ?? c;
  }

  /// سازگاری با کد قدیمی که فقط seed می‌گرفت.
  static ColorScheme schemeFromSeed(Color seed, {required bool dark}) {
    if (dark) {
      return ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
        surface: const Color(0xFF0F172A),
      ).copyWith(
        primary: seed,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFF1E40AF),
        onPrimaryContainer: const Color(0xFFEFF6FF),
        secondary: const Color(0xFF60A5FA),
        onSecondary: const Color(0xFF08111F),
        secondaryContainer: const Color(0xFF172554),
        onSecondaryContainer: const Color(0xFFDBEAFE),
        surface: const Color(0x8A0F172A),
        surfaceContainerLowest: const Color(0x000A0F1D),
        surfaceContainerLow: const Color(0x4D111827),
        surfaceContainer: const Color(0x66111827),
        surfaceContainerHigh: const Color(0x80172033),
        surfaceContainerHighest: const Color(0x991E293B),
        onSurface: const Color(0xFFF8FAFC),
        onSurfaceVariant: const Color(0xFFCBD5E1),
        outline: const Color(0xFF64748B),
        outlineVariant: const Color(0xFF334155),
        inverseSurface: const Color(0xFFF8FAFC),
        onInverseSurface: const Color(0xFF0F172A),
        inversePrimary: const Color(0xFF93C5FD),
      );
    }

    return ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: const Color(0xFFF8FAFF),
    ).copyWith(
      primary: seed,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFDBEAFE),
      onPrimaryContainer: const Color(0xFF172554),
      secondary: const Color(0xFF2563EB),
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFE0ECFF),
      onSecondaryContainer: const Color(0xFF172554),
      surface: const Color(0x99F8FAFF),
      surfaceContainerLowest: const Color(0x00FFFFFF),
      surfaceContainerLow: const Color(0x59FFFFFF),
      surfaceContainer: const Color(0x70FFFFFF),
      surfaceContainerHigh: const Color(0x8AFFFFFF),
      surfaceContainerHighest: const Color(0xA6FFFFFF),
      onSurface: const Color(0xFF0F172A),
      onSurfaceVariant: const Color(0xFF475569),
      outline: const Color(0xFF94A3B8),
      outlineVariant: const Color(0xFFCBD5E1),
      inverseSurface: const Color(0xFF0F172A),
      onInverseSurface: const Color(0xFFF8FAFC),
      inversePrimary: const Color(0xFF60A5FA),
    );
  }

  static ColorScheme schemeForTheme(AppThemeDefinition def, {required bool dark}) {
    final brightness = dark ? Brightness.dark : Brightness.light;
    final base = ColorScheme.fromSeed(
      seedColor: def.primary,
      brightness: brightness,
    );

    if (def.seedOnly) {
      // Preserve the fork's smoky blue glass scheme for the default theme
      // while still using the upstream theme catalog API.
      return schemeFromSeed(def.primary, dark: dark);
    }

    final primary = _adaptForDark(def.primary, dark: dark, amount: 0.08);
    final secondary = _adaptForDark(def.secondary, dark: dark, amount: 0.22);
    final error = _adaptForDark(def.negative, dark: dark, amount: 0.08);

    final glassSurface = dark
        ? const Color(0x8A0F172A)
        : const Color(0x99F8FAFF);
    final glassLow = dark
        ? const Color(0x4D111827)
        : const Color(0x59FFFFFF);
    final glassContainer = dark
        ? const Color(0x66111827)
        : const Color(0x70FFFFFF);
    final glassHigh = dark
        ? const Color(0x80172033)
        : const Color(0x8AFFFFFF);
    final glassHighest = dark
        ? const Color(0x991E293B)
        : const Color(0xA6FFFFFF);

    return base.copyWith(
      primary: primary,
      onPrimary: _onFor(primary),
      primaryContainer: Color.lerp(primary, base.primaryContainer, 0.55) ?? base.primaryContainer,
      onPrimaryContainer: base.onPrimaryContainer,
      secondary: secondary,
      onSecondary: _onFor(secondary),
      secondaryContainer:
          Color.lerp(secondary, base.secondaryContainer, 0.55) ?? base.secondaryContainer,
      onSecondaryContainer: base.onSecondaryContainer,
      error: error,
      onError: _onFor(error),
      errorContainer: Color.lerp(error, base.errorContainer, 0.55) ?? base.errorContainer,
      onErrorContainer: base.onErrorContainer,
      surface: glassSurface,
      surfaceContainerLowest: Colors.transparent,
      surfaceContainerLow: glassLow,
      surfaceContainer: glassContainer,
      surfaceContainerHigh: glassHigh,
      surfaceContainerHighest: glassHighest,
    );
  }
}
