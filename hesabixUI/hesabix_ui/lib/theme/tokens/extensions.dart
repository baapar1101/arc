import 'package:flutter/material.dart';

import 'color_schemes.dart';

// ---------------------------------------------------------------------------
// فاصله — شبکهٔ ۴dp متریال
// ---------------------------------------------------------------------------

@immutable
class AppSpacing extends ThemeExtension<AppSpacing> {
  final double xs; // 4
  final double sm; // 8
  final double md; // 12
  final double lg; // 16
  final double xl; // 24
  final double xxl; // 32

  const AppSpacing({
    this.xs = 4,
    this.sm = 8,
    this.md = 12,
    this.lg = 16,
    this.xl = 24,
    this.xxl = 32,
  });

  EdgeInsetsDirectional get pagePadding => EdgeInsetsDirectional.all(lg);
  EdgeInsetsDirectional get cardPadding => EdgeInsetsDirectional.all(md);
  EdgeInsetsDirectional get sectionGap =>
      EdgeInsetsDirectional.symmetric(vertical: md);

  @override
  AppSpacing copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
  }) =>
      AppSpacing(
        xs: xs ?? this.xs,
        sm: sm ?? this.sm,
        md: md ?? this.md,
        lg: lg ?? this.lg,
        xl: xl ?? this.xl,
        xxl: xxl ?? this.xxl,
      );

  @override
  AppSpacing lerp(ThemeExtension<AppSpacing>? other, double t) {
    if (other is! AppSpacing) return this;
    double l(double a, double b) => a + (b - a) * t;
    return AppSpacing(
      xs: l(xs, other.xs),
      sm: l(sm, other.sm),
      md: l(md, other.md),
      lg: l(lg, other.lg),
      xl: l(xl, other.xl),
      xxl: l(xxl, other.xxl),
    );
  }
}

// ---------------------------------------------------------------------------
// شکل — مقیاس رسمی M3
// https://m3.material.io/styles/shape/shape-scale-tokens
// ---------------------------------------------------------------------------

/// مقیاس منطبق بر دیزاین مرجع: rounded-md/lg/xl/2xl تِیل‌ویند
/// (۶ / ۸ / ۱۲ / ۱۶) به‌علاوهٔ یک پلهٔ بزرگ‌تر برای دیالوگ.
@immutable
class AppShape extends ThemeExtension<AppShape> {
  final double extraSmall; // 6  — چیپ کوچک، اسنک‌بار (rounded-md)
  final double small; // 8  — منو، فیلد ورودی (rounded-lg)
  final double medium; // 12 — دکمهٔ آیکونی، پاپ‌آور (rounded-xl)
  final double large; // 16 — کارت شیشه‌ای، شیت (rounded-2xl)
  final double extraLarge; // 24 — دیالوگ، FAB بزرگ

  const AppShape({
    this.extraSmall = 6,
    this.small = 8,
    this.medium = 12,
    this.large = 16,
    this.extraLarge = 24,
  });

  BorderRadius get extraSmallBorder => BorderRadius.circular(extraSmall);
  BorderRadius get smallBorder => BorderRadius.circular(small);
  BorderRadius get mediumBorder => BorderRadius.circular(medium);
  BorderRadius get largeBorder => BorderRadius.circular(large);
  BorderRadius get extraLargeBorder => BorderRadius.circular(extraLarge);
  BorderRadius get full => BorderRadius.circular(999);

  /// بالای شیت گرد، پایین صاف — الگوی bottom sheet در M3.
  BorderRadius get topLarge => const BorderRadius.vertical(
        top: Radius.circular(24),
      );

  @override
  AppShape copyWith({
    double? extraSmall,
    double? small,
    double? medium,
    double? large,
    double? extraLarge,
  }) =>
      AppShape(
        extraSmall: extraSmall ?? this.extraSmall,
        small: small ?? this.small,
        medium: medium ?? this.medium,
        large: large ?? this.large,
        extraLarge: extraLarge ?? this.extraLarge,
      );

  @override
  AppShape lerp(ThemeExtension<AppShape>? other, double t) {
    if (other is! AppShape) return this;
    double l(double a, double b) => a + (b - a) * t;
    return AppShape(
      extraSmall: l(extraSmall, other.extraSmall),
      small: l(small, other.small),
      medium: l(medium, other.medium),
      large: l(large, other.large),
      extraLarge: l(extraLarge, other.extraLarge),
    );
  }
}

/// نگاشت سازگاری با کد قدیمی. `AppRadii` قبلاً 6/10/14 بود که با M3 نمی‌خواند؛
/// حالا به مقیاس درست اشاره می‌کند تا ۱۱۰۰+ محل استفاده بدون تغییر کامپایل شود.
///
/// در کد جدید از `context.shape` استفاده کنید.
@immutable
class AppRadii extends ThemeExtension<AppRadii> {
  final double sm;
  final double md;
  final double lg;

  const AppRadii({this.sm = 8, this.md = 12, this.lg = 16});

  BorderRadius get smBorder => BorderRadius.circular(sm);
  BorderRadius get mdBorder => BorderRadius.circular(md);
  BorderRadius get lgBorder => BorderRadius.circular(lg);

  @override
  AppRadii copyWith({double? sm, double? md, double? lg}) =>
      AppRadii(sm: sm ?? this.sm, md: md ?? this.md, lg: lg ?? this.lg);

  @override
  AppRadii lerp(ThemeExtension<AppRadii>? other, double t) {
    if (other is! AppRadii) return this;
    double l(double a, double b) => a + (b - a) * t;
    return AppRadii(sm: l(sm, other.sm), md: l(md, other.md), lg: l(lg, other.lg));
  }
}

// ---------------------------------------------------------------------------
// ارتفاع — در M3 ارتفاع عمدتاً با لایهٔ رنگ نشان داده می‌شود، نه سایه
// https://m3.material.io/styles/elevation/tokens
// ---------------------------------------------------------------------------

abstract final class AppElevation {
  static const double level0 = 0;
  static const double level1 = 1;
  static const double level2 = 3;
  static const double level3 = 6;
  static const double level4 = 8;
  static const double level5 = 12;
}

/// لایهٔ سطح متناظر با هر ارتفاع. به‌جای `BoxShadow` از این استفاده کنید.
extension SurfaceTiers on ColorScheme {
  Color surfaceAtElevation(double elevation) {
    if (elevation <= 0) return surfaceContainerLowest;
    if (elevation <= AppElevation.level1) return surfaceContainerLow;
    if (elevation <= AppElevation.level2) return surfaceContainer;
    if (elevation <= AppElevation.level3) return surfaceContainerHigh;
    return surfaceContainerHighest;
  }
}

// ---------------------------------------------------------------------------
// سطوح دیزاین‌سیستم — کارت شیشه‌ای، درخشش برند، گرادیان‌ها
//
// اینها معادل کلاس‌های `.glass-card` / `.shadow-glow` / `.stat-icon` در
// دیزاین مرجع‌اند. چون M3 برای «شیشه» توکنی ندارد، اینجا تعریف می‌شوند.
// استفاده: `context.surfaces.glassCard` , `context.surfaces.glow`
// ---------------------------------------------------------------------------

@immutable
class AppSurfaces extends ThemeExtension<AppSurfaces> {
  /// پس‌زمینهٔ نیمه‌شفاف کارت (معادل `bg-ink-850/70`).
  final Color glassFill;

  /// لبهٔ بسیار کم‌رنگ کارت (معادل `border-white/[0.06]`).
  final Color glassBorder;

  /// لبهٔ کارت در حالت hover / تأکید (معادل `border-brand-500/25`).
  final Color glassBorderAccent;

  /// سایهٔ نرم زیر کارت (معادل `shadow-card`).
  final List<BoxShadow> cardShadow;

  /// سایهٔ برجستهٔ hover (معادل `shadow-lift`).
  final List<BoxShadow> liftShadow;

  /// هالهٔ زمردی دور عناصر فعال (معادل `shadow-glow`).
  final List<BoxShadow> glow;

  /// گرادیان کنش اصلی (معادل `from-brand-500 to-brand-600`).
  final LinearGradient brandGradient;

  /// گرادیان محو برای پس‌زمینهٔ بخش‌های تأکیدی.
  final LinearGradient brandWashGradient;

  const AppSurfaces({
    required this.glassFill,
    required this.glassBorder,
    required this.glassBorderAccent,
    required this.cardShadow,
    required this.liftShadow,
    required this.glow,
    required this.brandGradient,
    required this.brandWashGradient,
  });

  factory AppSurfaces.fromScheme(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    final primary = scheme.primary;

    return AppSurfaces(
      glassFill: scheme.surfaceContainer.withValues(alpha: isDark ? 0.72 : 0.86),
      glassBorder: (isDark ? scheme.onSurface : scheme.outline)
          .withValues(alpha: isDark ? 0.06 : 0.5),
      glassBorderAccent: primary.withValues(alpha: isDark ? 0.25 : 0.35),
      cardShadow: [
        BoxShadow(
          color: scheme.shadow.withValues(alpha: isDark ? 0.55 : 0.08),
          blurRadius: 30,
          offset: const Offset(0, 8),
          spreadRadius: -12,
        ),
      ],
      liftShadow: [
        BoxShadow(
          color: scheme.shadow.withValues(alpha: isDark ? 0.7 : 0.14),
          blurRadius: 45,
          offset: const Offset(0, 20),
          spreadRadius: -15,
        ),
      ],
      glow: [
        BoxShadow(
          color: primary.withValues(alpha: 0.45),
          blurRadius: 24,
          spreadRadius: -6,
        ),
      ],
      brandGradient: LinearGradient(
        begin: AlignmentDirectional.centerStart,
        end: AlignmentDirectional.centerEnd,
        colors: [primary, scheme.surfaceTint],
      ),
      brandWashGradient: LinearGradient(
        begin: AlignmentDirectional.centerStart,
        end: AlignmentDirectional.centerEnd,
        colors: [
          primary.withValues(alpha: isDark ? 0.15 : 0.12),
          primary.withValues(alpha: 0),
        ],
      ),
    );
  }

  /// قاب آمادهٔ کارت شیشه‌ای — به‌جای ساختن دستی `BoxDecoration` در صفحات.
  BoxDecoration glassCard(BorderRadius radius, {bool accent = false}) =>
      BoxDecoration(
        color: glassFill,
        borderRadius: radius,
        border: Border.all(color: accent ? glassBorderAccent : glassBorder),
        boxShadow: cardShadow,
      );

  @override
  AppSurfaces copyWith({
    Color? glassFill,
    Color? glassBorder,
    Color? glassBorderAccent,
    List<BoxShadow>? cardShadow,
    List<BoxShadow>? liftShadow,
    List<BoxShadow>? glow,
    LinearGradient? brandGradient,
    LinearGradient? brandWashGradient,
  }) =>
      AppSurfaces(
        glassFill: glassFill ?? this.glassFill,
        glassBorder: glassBorder ?? this.glassBorder,
        glassBorderAccent: glassBorderAccent ?? this.glassBorderAccent,
        cardShadow: cardShadow ?? this.cardShadow,
        liftShadow: liftShadow ?? this.liftShadow,
        glow: glow ?? this.glow,
        brandGradient: brandGradient ?? this.brandGradient,
        brandWashGradient: brandWashGradient ?? this.brandWashGradient,
      );

  @override
  AppSurfaces lerp(ThemeExtension<AppSurfaces>? other, double t) {
    if (other is! AppSurfaces) return this;
    return AppSurfaces(
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      glassBorderAccent:
          Color.lerp(glassBorderAccent, other.glassBorderAccent, t)!,
      cardShadow: BoxShadow.lerpList(cardShadow, other.cardShadow, t)!,
      liftShadow: BoxShadow.lerpList(liftShadow, other.liftShadow, t)!,
      glow: BoxShadow.lerpList(glow, other.glow, t)!,
      brandGradient:
          LinearGradient.lerp(brandGradient, other.brandGradient, t)!,
      brandWashGradient:
          LinearGradient.lerp(brandWashGradient, other.brandWashGradient, t)!,
    );
  }
}

// ---------------------------------------------------------------------------
// حرکت — توکن‌های easing و duration در M3
// https://m3.material.io/styles/motion/easing-and-duration/tokens-specs
// ---------------------------------------------------------------------------

@immutable
class AppMotion extends ThemeExtension<AppMotion> {
  // easing
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);
  static const Curve emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);
  static const Curve standard = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve standardDecelerate = Cubic(0.0, 0.0, 0.0, 1.0);
  static const Curve standardAccelerate = Cubic(0.3, 0.0, 1.0, 1.0);

  /// منحنی «فنری» دیزاین مرجع — `cubic-bezier(.22,1,.36,1)`.
  static const Curve spring = Cubic(0.22, 1.0, 0.36, 1.0);

  // duration
  final Duration short; // ریزتعامل: ripple، hover
  final Duration medium; // ورود/خروج جزء
  final Duration long; // گذار صفحه
  final Duration extraLong; // گذار بزرگ تمام‌صفحه

  const AppMotion({
    this.short = const Duration(milliseconds: 150),
    this.medium = const Duration(milliseconds: 300),
    this.long = const Duration(milliseconds: 450),
    this.extraLong = const Duration(milliseconds: 600),
  });

  @override
  AppMotion copyWith({
    Duration? short,
    Duration? medium,
    Duration? long,
    Duration? extraLong,
  }) =>
      AppMotion(
        short: short ?? this.short,
        medium: medium ?? this.medium,
        long: long ?? this.long,
        extraLong: extraLong ?? this.extraLong,
      );

  @override
  AppMotion lerp(ThemeExtension<AppMotion>? other, double t) => this;
}

// ---------------------------------------------------------------------------
// اندازهٔ آیکون
// ---------------------------------------------------------------------------

abstract final class AppIconSize {
  static const double dense = 18;
  static const double small = 20;
  static const double standard = 24;
  static const double large = 40;
  static const double display = 48;
}

// ---------------------------------------------------------------------------
// کلاس اندازهٔ پنجره — پایهٔ چیدمان تطبیقی M3
// https://m3.material.io/foundations/layout/applying-layout/window-size-classes
// ---------------------------------------------------------------------------

enum WindowSizeClass {
  compact, // < 600  — موبایل عمودی → NavigationBar پایین
  medium, // 600-839 — تبلت عمودی → NavigationRail جمع‌شده
  expanded, // 840-1199 — تبلت افقی → NavigationRail باز
  large, // 1200-1599 — دسکتاپ → Drawer دائمی
  extraLarge; // >= 1600 — نمایشگر بزرگ → Drawer + پنل کمکی

  static WindowSizeClass fromWidth(double width) {
    if (width < 600) return WindowSizeClass.compact;
    if (width < 840) return WindowSizeClass.medium;
    if (width < 1200) return WindowSizeClass.expanded;
    if (width < 1600) return WindowSizeClass.large;
    return WindowSizeClass.extraLarge;
  }

  bool get isCompact => this == WindowSizeClass.compact;
  bool get usesBottomNav => this == WindowSizeClass.compact;
  bool get usesRail =>
      this == WindowSizeClass.medium || this == WindowSizeClass.expanded;
  bool get usesPermanentDrawer =>
      this == WindowSizeClass.large || this == WindowSizeClass.extraLarge;

  /// حاشیهٔ کناری پیشنهادی M3 برای هر کلاس.
  double get margin => switch (this) {
        WindowSizeClass.compact => 16,
        WindowSizeClass.medium => 24,
        _ => 24,
      };

  /// حداکثر تعداد ستون شبکه.
  int get columns => switch (this) {
        WindowSizeClass.compact => 4,
        WindowSizeClass.medium => 8,
        _ => 12,
      };
}

// ---------------------------------------------------------------------------
// رنگ‌های shell — نگه‌داشته شده برای سازگاری با کد موجود
// ---------------------------------------------------------------------------

@immutable
class AppShellColors extends ThemeExtension<AppShellColors> {
  final Color topBarBackground;
  final Color topBarForeground;
  final Color dashboardBackground;

  const AppShellColors({
    required this.topBarBackground,
    required this.topBarForeground,
    required this.dashboardBackground,
  });

  static AppShellColors fromScheme(ColorScheme scheme, {required bool isDark}) {
    // در دیزاین مرجع نوار بالا یک لایه روشن‌تر از پس‌زمینهٔ صفحه است
    // (`bg-ink-900/85`) و خودِ صفحه تیره‌ترین لایه می‌ماند.
    return AppShellColors(
      topBarBackground: scheme.surfaceContainerLow,
      topBarForeground: scheme.onSurface,
      dashboardBackground: scheme.surface,
    );
  }

  @override
  AppShellColors copyWith({
    Color? topBarBackground,
    Color? topBarForeground,
    Color? dashboardBackground,
  }) =>
      AppShellColors(
        topBarBackground: topBarBackground ?? this.topBarBackground,
        topBarForeground: topBarForeground ?? this.topBarForeground,
        dashboardBackground: dashboardBackground ?? this.dashboardBackground,
      );

  @override
  AppShellColors lerp(ThemeExtension<AppShellColors>? other, double t) {
    if (other is! AppShellColors) return this;
    return AppShellColors(
      topBarBackground: Color.lerp(topBarBackground, other.topBarBackground, t)!,
      topBarForeground: Color.lerp(topBarForeground, other.topBarForeground, t)!,
      dashboardBackground:
          Color.lerp(dashboardBackground, other.dashboardBackground, t)!,
    );
  }
}

// ---------------------------------------------------------------------------
// دسترسی راحت از BuildContext
// ---------------------------------------------------------------------------

extension AppThemeExtensions on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get texts => Theme.of(this).textTheme;

  AppSpacing get appSpacing =>
      Theme.of(this).extension<AppSpacing>() ?? const AppSpacing();
  AppShape get shape =>
      Theme.of(this).extension<AppShape>() ?? const AppShape();
  AppMotion get motion =>
      Theme.of(this).extension<AppMotion>() ?? const AppMotion();

  AppSemanticColors get semantic =>
      Theme.of(this).extension<AppSemanticColors>() ??
      AppSemanticColors.fromScheme(Theme.of(this).colorScheme);

  /// سطوح دیزاین‌سیستم: کارت شیشه‌ای، درخشش برند، گرادیان‌ها.
  AppSurfaces get surfaces =>
      Theme.of(this).extension<AppSurfaces>() ??
      AppSurfaces.fromScheme(Theme.of(this).colorScheme);

  @Deprecated('از context.shape استفاده کنید')
  AppRadii get appRadii =>
      Theme.of(this).extension<AppRadii>() ?? const AppRadii();

  AppShellColors get shellColors =>
      Theme.of(this).extension<AppShellColors>() ??
      AppShellColors.fromScheme(
        Theme.of(this).colorScheme,
        isDark: Theme.of(this).brightness == Brightness.dark,
      );

  /// کلاس اندازهٔ پنجرهٔ فعلی. جایگزین بررسی دستی عرض.
  WindowSizeClass get windowSize =>
      WindowSizeClass.fromWidth(MediaQuery.sizeOf(this).width);
}
