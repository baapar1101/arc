import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'web_utils.dart';

/// کلیدهای ساده localStorage برای لودر HTML (بدون JSON) — قبل از بالا آمدن Flutter.
const String kLoaderLocaleKey = 'hesabix_locale';
const String kLoaderThemeModeKey = 'hesabix_theme_mode';

void syncLoaderLocale(Locale locale) {
  if (!kIsWeb) return;
  setLocalStorageValue(kLoaderLocaleKey, locale.languageCode);
}

void syncLoaderThemeMode(int modeIndex) {
  if (!kIsWeb) return;
  setLocalStorageValue(kLoaderThemeModeKey, modeIndex.toString());
}
