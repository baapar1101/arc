import 'package:flutter/widgets.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

/// نام نمایشی محصول در بیلد وب — از `--dart-define` تزریق می‌شود.
///
/// اگر هر دو خالی باشند (حالت پیش‌فرض بیلد)، همان مقادیر l10n / حسابیکس استفاده می‌شود.
class BrandConfig {
  BrandConfig._();

  static const String appNameEn = String.fromEnvironment(
    'APP_NAME_EN',
    defaultValue: '',
  );

  static const String appNameFa = String.fromEnvironment(
    'APP_NAME_FA',
    defaultValue: '',
  );

  static bool get hasCustomName =>
      appNameEn.trim().isNotEmpty || appNameFa.trim().isNotEmpty;

  /// عنوان MaterialApp / مرورگر (ترجیح انگلیسی، سپس فارسی، سپس Hesabix).
  static String get materialTitle {
    final en = appNameEn.trim();
    if (en.isNotEmpty) return en;
    final fa = appNameFa.trim();
    if (fa.isNotEmpty) return fa;
    return 'Hesabix';
  }

  static String resolve({
    required String languageCode,
    required String fallback,
  }) {
    final fa = appNameFa.trim();
    final en = appNameEn.trim();
    if (languageCode.toLowerCase().startsWith('fa')) {
      if (fa.isNotEmpty) return fa;
      if (en.isNotEmpty) return en;
      return fallback;
    }
    if (en.isNotEmpty) return en;
    if (fa.isNotEmpty) return fa;
    return fallback;
  }

  static String resolveForLocale(Locale locale, String fallback) =>
      resolve(languageCode: locale.languageCode, fallback: fallback);

  static String appTitle(AppLocalizations l10n) {
    final code = l10n.localeName;
    return resolve(
      languageCode: code.isNotEmpty ? code : 'en',
      fallback: l10n.appTitle,
    );
  }

  static String mobileLauncherBrandName(AppLocalizations l10n) {
    final code = l10n.localeName;
    return resolve(
      languageCode: code.isNotEmpty ? code : 'en',
      fallback: l10n.mobileLauncherBrandName,
    );
  }
}
