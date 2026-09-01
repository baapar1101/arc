import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'web_utils.dart';

/// کلیدهای ساده localStorage برای لودر HTML (بدون JSON) — قبل از بالا آمدن Flutter.
const String kLoaderLocaleKey = 'hesabix_locale';
const String kLoaderThemeModeKey = 'hesabix_theme_mode';
const String kLoaderBrandKey = 'hesabix_theme_brand';

void syncLoaderLocale(Locale locale) {
  if (!kIsWeb) return;
  setLocalStorageValue(kLoaderLocaleKey, locale.languageCode);
}

void syncLoaderThemeMode(int modeIndex) {
  if (!kIsWeb) return;
  setLocalStorageValue(kLoaderThemeModeKey, modeIndex.toString());
}

void syncLoaderBrandColor(Color color) {
  if (!kIsWeb) return;
  final hex =
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  setLocalStorageValue(kLoaderBrandKey, hex);
}
