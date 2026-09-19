import 'package:flutter/material.dart';

<<<<<<< HEAD
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
=======
/// تنها منبع حقیقتِ رنگ در برنامه.
///
/// هیچ فایل دیگری خارج از `lib/theme/` اجازهٔ نوشتن `Colors.*` یا `Color(0x…)`
/// را ندارد؛ قانون `raw_material_color` در tool/m3_audit.dart این را تضمین می‌کند.
///
/// پالت از دیزاین‌سیستم پنل ادمین («هُما») گرفته شده: زمینهٔ سرمه‌ای عمیق
/// (ink)، لهجهٔ زمردی (brand)، و سه رنگ کمکی فیروزه‌ای/کهربایی/سرخ‌گلی.
abstract final class AppColorTokens {
  // -------------------------------------------------------------------------
  // پالت پایه — عیناً از tailwind.config.js دیزاین مرجع
  // -------------------------------------------------------------------------

  /// زمینه‌های سرمه‌ای، از تیره‌ترین (پس‌زمینهٔ صفحه) تا روشن‌ترین (لبه‌ها).
  static const Color ink950 = Color(0xFF070B12);
  static const Color ink900 = Color(0xFF0B111D);
  static const Color ink850 = Color(0xFF0E1626);
  static const Color ink800 = Color(0xFF131C2E);
  static const Color ink700 = Color(0xFF1A2438);
  static const Color ink600 = Color(0xFF243149);

  /// زمردی برند — لهجهٔ اصلی رابط.
  static const Color brand50 = Color(0xFFECFDF5);
  static const Color brand100 = Color(0xFFD1FAE5);
  static const Color brand200 = Color(0xFFA7F3D0);
  static const Color brand300 = Color(0xFF6EE7B7);
  static const Color brand400 = Color(0xFF34D399);
  static const Color brand500 = Color(0xFF10B981);
  static const Color brand600 = Color(0xFF059669);
  static const Color brand700 = Color(0xFF047857);

  /// فیروزه‌ای — نقش دوم، برای نمودار و وضعیت خنثای قابل توجه.
  static const Color aqua300 = Color(0xFF67E8F9);
  static const Color aqua400 = Color(0xFF22D3EE);
  static const Color aqua500 = Color(0xFF06B6D4);
  static const Color aqua700 = Color(0xFF0E7490);

  /// کهربایی — هشدار و «در انتظار».
  static const Color amber300 = Color(0xFFFCD34D);
  static const Color amber500 = Color(0xFFF59E0B);
  static const Color amber700 = Color(0xFFB45309);

  /// سرخ‌گلی — خطا، حذف، بدهکار.
  static const Color rose300 = Color(0xFFFDA4AF);
  static const Color rose400 = Color(0xFFFB7185);
  static const Color rose600 = Color(0xFFE11D48);

  /// خاکستری‌های متن، هم‌خانوادهٔ ink.
  static const Color slate50 = Color(0xFFF8FAFC);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate300 = Color(0xFFCBD5E1);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate600 = Color(0xFF475569);

  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);

  /// رنگ پایهٔ برند. وقتی کاربر رنگ سفارشی انتخاب نکرده، پالت صریحِ
  /// دیزاین‌سیستم استفاده می‌شود؛ در غیر این صورت از این بذر تولید می‌شود.
  static const Color defaultSeed = brand500;

  /// بذرهای معنایی — نقاط شروع، نه رنگ نهایی.
  static const Color successSeed = brand500;
  static const Color warningSeed = amber500;
  static const Color infoSeed = aqua500;

  // -------------------------------------------------------------------------
  // ColorScheme صریح — دقیقاً منطبق بر دیزاین مرجع
  // -------------------------------------------------------------------------

  /// تیره: همان چیزی که در مرورگر دیده می‌شود — سرمه‌ای عمیق با لهجهٔ زمردی.
  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,

    primary: brand500,
    onPrimary: ink950,
    primaryContainer: Color(0xFF0C3B2E),
    onPrimaryContainer: brand300,

    secondary: aqua400,
    onSecondary: ink950,
    secondaryContainer: Color(0xFF10323F),
    onSecondaryContainer: aqua300,

    tertiary: amber500,
    onTertiary: ink950,
    tertiaryContainer: Color(0xFF3A2A0B),
    onTertiaryContainer: amber300,

    error: rose400,
    onError: ink950,
    errorContainer: Color(0xFF3D1622),
    onErrorContainer: rose300,

    surface: ink950,
    onSurface: slate200,
    onSurfaceVariant: slate400,

    surfaceContainerLowest: ink950,
    surfaceContainerLow: ink900,
    surfaceContainer: ink850,
    surfaceContainerHigh: ink800,
    surfaceContainerHighest: ink700,
    surfaceDim: ink950,
    surfaceBright: ink700,

    outline: ink600,
    outlineVariant: ink700,

    shadow: black,
    scrim: black,
    surfaceTint: brand500,

    inverseSurface: slate200,
    onInverseSurface: ink900,
    inversePrimary: brand700,
  );

  /// روشن: دیزاین مرجع فقط تیره است؛ این نسخه همان هویت برند را با
  /// زمینهٔ روشن بازسازی می‌کند تا حالت روشن اپ کاربردی بماند.
  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,

    primary: brand600,
    onPrimary: white,
    primaryContainer: brand100,
    onPrimaryContainer: Color(0xFF033D2E),

    secondary: Color(0xFF0891B2),
    onSecondary: white,
    secondaryContainer: Color(0xFFCFFAFE),
    onSecondaryContainer: Color(0xFF0B4A57),

    tertiary: amber700,
    onTertiary: white,
    tertiaryContainer: Color(0xFFFEF3C7),
    onTertiaryContainer: Color(0xFF6B3D05),

    error: rose600,
    onError: white,
    errorContainer: Color(0xFFFFE4E6),
    onErrorContainer: Color(0xFF7F1D3A),

    surface: slate50,
    onSurface: ink900,
    onSurfaceVariant: slate600,

    surfaceContainerLowest: white,
    surfaceContainerLow: slate50,
    surfaceContainer: slate100,
    surfaceContainerHigh: Color(0xFFE9EEF5),
    surfaceContainerHighest: slate200,
    surfaceDim: Color(0xFFE9EEF5),
    surfaceBright: white,

    outline: slate300,
    outlineVariant: slate200,

    shadow: black,
    scrim: black,
    surfaceTint: brand600,

    inverseSurface: ink900,
    onInverseSurface: slate200,
    inversePrimary: brand300,
  );

  /// اگر کاربر رنگ سفارشی نگذاشته باشد، پالت صریح دیزاین‌سیستم برمی‌گردد.
  /// در غیر این صورت M3 پالت را از بذر انتخابی می‌سازد تا امکان
  /// شخصی‌سازی رنگ در «تنظیمات ظاهر» از بین نرود.
>>>>>>> github/Huma
  static ColorScheme schemeFromSeed(Color seed, {required bool dark}) {
    if (seed.toARGB32() == defaultSeed.toARGB32()) {
      return dark ? darkScheme : lightScheme;
    }
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
<<<<<<< HEAD
=======

/// چرخش ملایم فام رنگِ معنایی به سمت رنگ برند.
///
/// معادل سبک‌وزنِ `Blend.harmonize` در material_color_utilities است، بدون
/// افزودن وابستگی.
Color _harmonize(Color design, Color toward, {double amount = 0.15}) {
  final a = HSLColor.fromColor(design);
  final b = HSLColor.fromColor(toward);
  if (b.saturation < 0.08) return design; // برند خاکستری است؛ چیزی برای هماهنگی نیست
  var diff = b.hue - a.hue;
  if (diff > 180) diff -= 360;
  if (diff < -180) diff += 360;
  var hue = (a.hue + diff * amount) % 360;
  if (hue < 0) hue += 360;
  return a.withHue(hue).toColor();
}

/// یک نقش رنگی کامل به سبک M3 — چهار توکنی که Material برای هر نقش تعریف می‌کند.
@immutable
class SemanticRole {
  final Color color;
  final Color onColor;
  final Color container;
  final Color onContainer;

  const SemanticRole({
    required this.color,
    required this.onColor,
    required this.container,
    required this.onContainer,
  });

  /// نقش را از یک بذر می‌سازد و همان الگوریتم تونالِ M3 را به کار می‌گیرد.
  factory SemanticRole.fromSeed(
    Color seed, {
    required Brightness brightness,
    Color? harmonizeWith,
  }) {
    final base =
        harmonizeWith == null ? seed : _harmonize(seed, harmonizeWith);
    final s = ColorScheme.fromSeed(seedColor: base, brightness: brightness);
    return SemanticRole(
      color: s.primary,
      onColor: s.onPrimary,
      container: s.primaryContainer,
      onContainer: s.onPrimaryContainer,
    );
  }

  static SemanticRole lerp(SemanticRole a, SemanticRole b, double t) =>
      SemanticRole(
        color: Color.lerp(a.color, b.color, t)!,
        onColor: Color.lerp(a.onColor, b.onColor, t)!,
        container: Color.lerp(a.container, b.container, t)!,
        onContainer: Color.lerp(a.onContainer, b.onContainer, t)!,
      );
}

/// رنگ‌هایی که Material 3 تعریف نمی‌کند ولی هر نرم‌افزار حسابداری لازم دارد.
///
/// استفاده: `context.semantic.success.container`
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  final SemanticRole success;
  final SemanticRole warning;
  final SemanticRole info;

  /// بدهکار — سرخ‌گلیِ پالت.
  final Color debit;

  /// بستانکار — زمردیِ برند.
  final Color credit;

  /// رنگ ردیف‌های زبرا در جدول‌های داده.
  final Color tableStripe;

  /// پس‌زمینهٔ ردیف انتخاب‌شده.
  final Color tableSelection;

  const AppSemanticColors({
    required this.success,
    required this.warning,
    required this.info,
    required this.debit,
    required this.credit,
    required this.tableStripe,
    required this.tableSelection,
  });

  factory AppSemanticColors.fromScheme(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;

    // وقتی پالت صریح دیزاین‌سیستم فعال است، نقش‌های معنایی هم مستقیم از
    // همان پالت می‌آیند تا با نمودارها و چیپ‌های مرجع یکی باشند.
    final usesDesignPalette = scheme.primary.toARGB32() ==
            AppColorTokens.brand500.toARGB32() ||
        scheme.primary.toARGB32() == AppColorTokens.brand600.toARGB32();

    if (usesDesignPalette) {
      final success = isDark
          ? const SemanticRole(
              color: AppColorTokens.brand400,
              onColor: AppColorTokens.ink950,
              container: Color(0xFF0C3B2E),
              onContainer: AppColorTokens.brand300,
            )
          : const SemanticRole(
              color: AppColorTokens.brand600,
              onColor: AppColorTokens.white,
              container: AppColorTokens.brand100,
              onContainer: Color(0xFF033D2E),
            );

      final warning = isDark
          ? const SemanticRole(
              color: AppColorTokens.amber500,
              onColor: AppColorTokens.ink950,
              container: Color(0xFF3A2A0B),
              onContainer: AppColorTokens.amber300,
            )
          : const SemanticRole(
              color: AppColorTokens.amber700,
              onColor: AppColorTokens.white,
              container: Color(0xFFFEF3C7),
              onContainer: Color(0xFF6B3D05),
            );

      final info = isDark
          ? const SemanticRole(
              color: AppColorTokens.aqua400,
              onColor: AppColorTokens.ink950,
              container: Color(0xFF10323F),
              onContainer: AppColorTokens.aqua300,
            )
          : const SemanticRole(
              color: AppColorTokens.aqua700,
              onColor: AppColorTokens.white,
              container: Color(0xFFCFFAFE),
              onContainer: Color(0xFF0B4A57),
            );

      return AppSemanticColors(
        success: success,
        warning: warning,
        info: info,
        debit: scheme.error,
        credit: success.color,
        tableStripe: Color.alphaBlend(
          (isDark ? AppColorTokens.white : AppColorTokens.brand500)
              .withValues(alpha: isDark ? 0.025 : 0.04),
          scheme.surfaceContainerLow,
        ),
        tableSelection: Color.alphaBlend(
          scheme.primary.withValues(alpha: isDark ? 0.14 : 0.12),
          scheme.surfaceContainer,
        ),
      );
    }

    // مسیر رنگ سفارشیِ کاربر: همان تولید تونال قبلی.
    final brightness = scheme.brightness;
    final success = SemanticRole.fromSeed(
      AppColorTokens.successSeed,
      brightness: brightness,
      harmonizeWith: scheme.primary,
    );
    final warning = SemanticRole.fromSeed(
      AppColorTokens.warningSeed,
      brightness: brightness,
      harmonizeWith: scheme.primary,
    );
    final info = SemanticRole.fromSeed(
      AppColorTokens.infoSeed,
      brightness: brightness,
      harmonizeWith: scheme.primary,
    );

    return AppSemanticColors(
      success: success,
      warning: warning,
      info: info,
      debit: scheme.error,
      credit: success.color,
      tableStripe: Color.alphaBlend(
        scheme.primary.withValues(alpha: 0.035),
        scheme.surfaceContainerLow,
      ),
      tableSelection: scheme.secondaryContainer,
    );
  }

  @override
  AppSemanticColors copyWith({
    SemanticRole? success,
    SemanticRole? warning,
    SemanticRole? info,
    Color? debit,
    Color? credit,
    Color? tableStripe,
    Color? tableSelection,
  }) =>
      AppSemanticColors(
        success: success ?? this.success,
        warning: warning ?? this.warning,
        info: info ?? this.info,
        debit: debit ?? this.debit,
        credit: credit ?? this.credit,
        tableStripe: tableStripe ?? this.tableStripe,
        tableSelection: tableSelection ?? this.tableSelection,
      );

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: SemanticRole.lerp(success, other.success, t),
      warning: SemanticRole.lerp(warning, other.warning, t),
      info: SemanticRole.lerp(info, other.info, t),
      debit: Color.lerp(debit, other.debit, t)!,
      credit: Color.lerp(credit, other.credit, t)!,
      tableStripe: Color.lerp(tableStripe, other.tableStripe, t)!,
      tableSelection: Color.lerp(tableSelection, other.tableSelection, t)!,
    );
  }
}
>>>>>>> github/Huma
