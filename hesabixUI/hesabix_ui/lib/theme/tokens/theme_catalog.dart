import 'package:flutter/material.dart';

/// تعریف یک تم رنگی سراسری برنامه.
@immutable
class AppThemeDefinition {
  final String id;
  final String labelFa;
  final String labelEn;
  final Color primary;
  final Color secondary;
  final Color positive;
  final Color negative;
  final Color warning;

  /// اگر true باشد، ColorScheme دقیقاً از [ColorScheme.fromSeed] ساخته می‌شود
  /// تا ظاهر تم پیش‌فرض فعلی حفظ شود.
  final bool seedOnly;

  const AppThemeDefinition({
    required this.id,
    required this.labelFa,
    required this.labelEn,
    required this.primary,
    required this.secondary,
    required this.positive,
    required this.negative,
    required this.warning,
    this.seedOnly = false,
  });

  String labelFor(Locale locale) =>
      locale.languageCode.toLowerCase() == 'fa' ? labelFa : labelEn;
}

/// شناسه تم پیش‌فرض سخت‌کد (Classic Blue فعلی سیستم).
const String kDefaultThemeId = 'classic_blue';

/// فهرست تم‌های مجاز — باید با بک‌اند هم‌تراز بماند.
const List<AppThemeDefinition> kAppThemeCatalog = [
  AppThemeDefinition(
    id: kDefaultThemeId,
    labelFa: 'آبی کلاسیک',
    labelEn: 'Classic Blue',
    primary: Color(0xFF2563EB),
    secondary: Color(0xFF5A6A7A),
    positive: Color(0xFF2E7D32),
    negative: Color(0xFFB3261E),
    warning: Color(0xFFF0B92A),
    seedOnly: true,
  ),
  AppThemeDefinition(
    id: 'turquoise_sea',
    labelFa: 'دریای فیروزه',
    labelEn: 'Turquoise Sea',
    primary: Color(0xFF00A8BD),
    secondary: Color(0xFF4F546D),
    positive: Color(0xFF41B96B),
    negative: Color(0xFFEF2223),
    warning: Color(0xFFF0B92A),
  ),
  AppThemeDefinition(
    id: 'emerald_forest',
    labelFa: 'جنگل زمردی',
    labelEn: 'Emerald Forest',
    primary: Color(0xFF0F766E),
    secondary: Color(0xFF3F4A5A),
    positive: Color(0xFF41B96B),
    negative: Color(0xFFEF2223),
    warning: Color(0xFFF0B92A),
  ),
  AppThemeDefinition(
    id: 'warm_copper',
    labelFa: 'مسی گرم',
    labelEn: 'Warm Copper',
    primary: Color(0xFFB45309),
    secondary: Color(0xFF4F546D),
    positive: Color(0xFF41B96B),
    negative: Color(0xFFEF2223),
    warning: Color(0xFFF0B92A),
  ),
];

const Set<String> kAllowedThemeIds = {
  'classic_blue',
  'turquoise_sea',
  'emerald_forest',
  'warm_copper',
};

AppThemeDefinition themeDefinitionById(String? id) {
  final normalized = (id ?? '').trim().toLowerCase();
  for (final t in kAppThemeCatalog) {
    if (t.id == normalized) return t;
  }
  return kAppThemeCatalog.first;
}

bool isAllowedThemeId(String? id) {
  final normalized = (id ?? '').trim().toLowerCase();
  return kAllowedThemeIds.contains(normalized);
}
