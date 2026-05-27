import 'package:flutter/material.dart';

/// توکن‌های بصری چت AI — الهام از رابط‌های مدرن (ChatGPT، Claude).
abstract final class AIChatDesign {
  static const double contentMaxWidth = 768;
  static const double sidebarWidth = 280;
  static const double composerRadius = 26;
  static const double chipRadius = 20;
  static const double cardRadius = 22;
  static const Duration layoutTransition = Duration(milliseconds: 380);
  static const Duration fadeTransition = Duration(milliseconds: 280);

  static bool showPersistentSidebar(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 1024;

  static bool isCompactWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 720;

  static BoxDecoration pageBackground(ThemeData theme, {required bool isDark}) {
    final scheme = theme.colorScheme;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [
                scheme.surface,
                Color.alphaBlend(scheme.primary.withValues(alpha: 0.06), scheme.surface),
              ]
            : [
                scheme.surface,
                Color.alphaBlend(scheme.primary.withValues(alpha: 0.04), scheme.surfaceContainerLowest),
              ],
      ),
    );
  }

  static BoxDecoration composerDecoration(ThemeData theme, {required bool focused}) {
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? scheme.surfaceContainerHigh : scheme.surface,
      borderRadius: BorderRadius.circular(composerRadius),
      border: Border.all(
        color: focused
            ? scheme.primary.withValues(alpha: 0.45)
            : scheme.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.55),
        width: focused ? 1.5 : 1,
      ),
      boxShadow: [
        BoxShadow(
          color: scheme.shadow.withValues(alpha: isDark ? 0.35 : 0.08),
          blurRadius: focused ? 28 : 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  static BoxDecoration chipDecoration(ThemeData theme) {
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark
          ? scheme.surfaceContainerHigh
          : scheme.surfaceContainerHighest.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(chipRadius),
      border: Border.all(
        color: scheme.outlineVariant.withValues(alpha: 0.45),
      ),
    );
  }

  static BoxDecoration elevatedCard(
    ThemeData theme, {
    double alpha = 0.78,
    Color? accent,
  }) {
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return BoxDecoration(
      color: (isDark ? scheme.surfaceContainerHigh : scheme.surface)
          .withValues(alpha: alpha),
      borderRadius: BorderRadius.circular(cardRadius),
      border: Border.all(
        color: (accent ?? scheme.outlineVariant).withValues(
          alpha: accent == null ? 0.42 : 0.22,
        ),
      ),
      boxShadow: [
        BoxShadow(
          color: scheme.shadow.withValues(alpha: isDark ? 0.22 : 0.07),
          blurRadius: 28,
          offset: const Offset(0, 14),
        ),
      ],
    );
  }

  static BoxDecoration subtlePanel(ThemeData theme, {Color? accent}) {
    final scheme = theme.colorScheme;
    return BoxDecoration(
      color: (accent ?? scheme.surfaceContainerHighest).withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: (accent ?? scheme.outlineVariant).withValues(alpha: 0.18),
      ),
    );
  }

  static TextStyle? greetingStyle(ThemeData theme) {
    return theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.5,
      height: 1.25,
    );
  }

  static TextStyle? subtitleStyle(ThemeData theme) {
    return theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.5,
    );
  }
}
