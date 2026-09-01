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
    return ColorScheme.fromSeed(
      seedColor: seed,
      brightness: dark ? Brightness.dark : Brightness.light,
    );
  }

  static ColorScheme schemeForTheme(AppThemeDefinition def, {required bool dark}) {
    final brightness = dark ? Brightness.dark : Brightness.light;
    final base = ColorScheme.fromSeed(
      seedColor: def.primary,
      brightness: brightness,
    );

    if (def.seedOnly) {
      return base;
    }

    final primary = _adaptForDark(def.primary, dark: dark, amount: 0.08);
    final secondary = _adaptForDark(def.secondary, dark: dark, amount: 0.22);
    final error = _adaptForDark(def.negative, dark: dark, amount: 0.08);

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
    );
  }
}
