import 'package:flutter/material.dart';

import 'package:hesabix_ui/config/brand_config.dart';

/// مسیر و ویجت لوگوی برند — در حالت روشن با رنگ primary تم رنگ‌آمیزی می‌شود
/// (مگر برند کاستوم با `BRAND_LOGO_TINT=0`).
class BrandLogoAssets {
  BrandLogoAssets._();

  /// لوگوی روشن/سفید (برای پس‌زمینه تیره یا tint با ColorFilter).
  static const String lightSilhouette = 'assets/images/logo-light.png';

  /// لوگوی آبی کلاسیک (سازگاری با وب/لودر؛ ترجیحاً از [BrandLogo] استفاده کنید).
  static const String classicBlue = 'assets/images/logo-blue.png';

  /// مسیر مناسب برای حالت روشن/تیره بدون tint.
  static String assetForBrightness({required bool isDark}) =>
      isDark ? lightSilhouette : classicBlue;
}

/// لوگوی حسابیکس هم‌تراز با تم فعلی.
class BrandLogo extends StatelessWidget {
  final double? width;
  final double? height;
  final BoxFit fit;
  final Color? primaryOverride;

  const BrandLogo({
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.primaryOverride,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = primaryOverride ?? scheme.primary;
    final tint = BrandConfig.tintLogo;

    final asset = tint
        ? BrandLogoAssets.lightSilhouette
        : BrandLogoAssets.assetForBrightness(isDark: isDark);

    final image = Image.asset(
      asset,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        return Icon(
          Icons.account_balance,
          size: (width ?? height ?? 48) * 0.55,
          color: isDark ? scheme.onSurface : primary,
        );
      },
    );

    if (!tint || isDark) {
      return image;
    }

    // رنگ‌آمیزی سیلوئت سفید با primary تم
    return ColorFiltered(
      colorFilter: ColorFilter.mode(primary, BlendMode.srcIn),
      child: image,
    );
  }
}
