import 'package:flutter/material.dart';

/// فونت اصلی و fallback — بدون Noto Sans تا ارقام لاتین جایگزین نشوند.
abstract final class AppFonts {
  static const String faPrimary = 'YekanBakhFaNum';
  static const List<String> faFallback = [
    'Noto Color Emoji',
    'Vazirmatn',
    'NotoSansArabic',
  ];

  static const String enPrimary = 'Roboto';
  static const List<String> enFallback = [
    'Noto Color Emoji',
    'Noto Sans',
    'Roboto',
  ];
}

/// یک نقش از مقیاس تایپ M3.
///
/// قبلاً مقیاس با ضرب در ۰٫۹ ساخته می‌شد. مشکل: `YekanBakhFaNum` ارتفاع x
/// بزرگ‌تری از Roboto دارد، پس ضربِ یکسان روی هر پانزده نقش، line-height را
/// در تیترها باز و در متن بدنه تنگ می‌کند. این جدول هر نقش را صریح تعیین می‌کند.
class _Role {
  final double size;
  final double height; // ضریب ارتفاع خط
  final double tracking; // letterSpacing
  final FontWeight weight;

  const _Role(this.size, this.height, this.tracking, [this.weight = FontWeight.w400]);

  TextStyle style({
    required String family,
    required List<String> fallback,
    required Color color,
  }) =>
      TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: size,
        height: height,
        letterSpacing: tracking,
        fontWeight: weight,
        color: color,
        leadingDistribution: TextLeadingDistribution.even,
      );
}

/// مقیاس فارسی — منطبق بر مقیاس تِیل‌ویندِ دیزاین مرجع
/// (text-5xl/3xl/2xl/xl/lg/base/sm/xs و ۱۱px/۱۰px) با ارتفاع خط بازتر
/// چون حروف فارسی زیرنویس و اعراب دارند.
///
/// دیزاین مرجع برای عدد و عنوان از وزن‌های سنگین (۷۰۰/۸۰۰) استفاده می‌کند؛
/// اینجا هم همان الگو رعایت شده.
const _fa = <String, _Role>{
  'displayLarge': _Role(48, 1.10, 0, FontWeight.w800),
  'displayMedium': _Role(36, 1.14, 0, FontWeight.w800),
  'displaySmall': _Role(30, 1.20, 0, FontWeight.w700),
  'headlineLarge': _Role(27, 1.24, 0, FontWeight.w700),
  'headlineMedium': _Role(24, 1.28, 0, FontWeight.w700),
  'headlineSmall': _Role(20, 1.34, 0, FontWeight.w700),
  'titleLarge': _Role(18, 1.36, 0, FontWeight.w700),
  'titleMedium': _Role(16, 1.44, 0, FontWeight.w600),
  'titleSmall': _Role(14, 1.46, 0, FontWeight.w600),
  'bodyLarge': _Role(14, 1.58, 0),
  'bodyMedium': _Role(13, 1.62, 0),
  'bodySmall': _Role(12, 1.62, 0),
  'labelLarge': _Role(13, 1.42, 0, FontWeight.w600),
  'labelMedium': _Role(11, 1.42, 0, FontWeight.w600),
  'labelSmall': _Role(10, 1.44, 0, FontWeight.w600),
};

/// مقیاس انگلیسی — نزدیک به M3 استاندارد با فشردگی جزئی و tracking اصلی.
const _en = <String, _Role>{
  'displayLarge': _Role(48, 1.10, -0.25, FontWeight.w800),
  'displayMedium': _Role(36, 1.14, 0, FontWeight.w800),
  'displaySmall': _Role(30, 1.20, 0, FontWeight.w700),
  'headlineLarge': _Role(27, 1.24, 0, FontWeight.w700),
  'headlineMedium': _Role(24, 1.28, 0, FontWeight.w700),
  'headlineSmall': _Role(20, 1.33, 0, FontWeight.w700),
  'titleLarge': _Role(18, 1.35, 0, FontWeight.w700),
  'titleMedium': _Role(16, 1.50, 0.15, FontWeight.w600),
  'titleSmall': _Role(14, 1.43, 0.10, FontWeight.w600),
  'bodyLarge': _Role(14, 1.50, 0.15, FontWeight.w400),
  'bodyMedium': _Role(13, 1.43, 0.25),
  'bodySmall': _Role(11, 1.33, 0.40),
  'labelLarge': _Role(13, 1.43, 0.10, FontWeight.w600),
  'labelMedium': _Role(11, 1.33, 0.50, FontWeight.w600),
  'labelSmall': _Role(10, 1.45, 0.50, FontWeight.w600),
};

TextTheme _build(
  Map<String, _Role> scale, {
  required String family,
  required List<String> fallback,
  required Color color,
}) {
  TextStyle s(String key) =>
      scale[key]!.style(family: family, fallback: fallback, color: color);

  return TextTheme(
    displayLarge: s('displayLarge'),
    displayMedium: s('displayMedium'),
    displaySmall: s('displaySmall'),
    headlineLarge: s('headlineLarge'),
    headlineMedium: s('headlineMedium'),
    headlineSmall: s('headlineSmall'),
    titleLarge: s('titleLarge'),
    titleMedium: s('titleMedium'),
    titleSmall: s('titleSmall'),
    bodyLarge: s('bodyLarge'),
    bodyMedium: s('bodyMedium'),
    bodySmall: s('bodySmall'),
    labelLarge: s('labelLarge'),
    labelMedium: s('labelMedium'),
    labelSmall: s('labelSmall'),
  );
}

/// [color] رنگ متن بدنه است — در دیزاین مرجع `slate-200` نه سفید خالص،
/// که تضاد را نرم و خواندن متن طولانی فارسی را راحت‌تر می‌کند.
TextTheme faTextTheme({required Color color}) => _build(
      _fa,
      family: AppFonts.faPrimary,
      fallback: AppFonts.faFallback,
      color: color,
    );

TextTheme enTextTheme({required Color color}) => _build(
      _en,
      family: AppFonts.enPrimary,
      fallback: AppFonts.enFallback,
      color: color,
    );
