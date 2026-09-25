import 'package:flutter/material.dart';

import 'tokens/semantic_colors.dart';
import 'tokens/theme_catalog.dart';

/// رنگ‌های معنایی از Theme؛ با fallback امن وقتی extension موجود نیست.
class SemanticColorResolver {
  SemanticColorResolver._();

  static AppSemanticColors of(BuildContext context) {
    final existing = Theme.of(context).extension<AppSemanticColors>();
    if (existing != null) return existing;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppSemanticColors.fromDefinition(
      themeDefinitionById(kDefaultThemeId),
      isDark: isDark,
      scheme: scheme,
    );
  }

  static Color positive(BuildContext context) => of(context).positive;
  static Color warning(BuildContext context) => of(context).warning;
  static Color negative(BuildContext context) => of(context).negative;
  static Color info(BuildContext context) => of(context).info;
}
