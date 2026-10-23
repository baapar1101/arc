import 'package:flutter/widgets.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../core/api_client.dart';
import '../config/app_config.dart';

/// نام نمایشی محصول در بیلد وب و اندروید — از `--dart-define` تزریق می‌شود.
///
/// اگر هر دو خالی باشند (حالت پیش‌فرض بیلد)، همان مقادیر l10n / حسابیکس استفاده می‌شود.
class BrandConfig {
  BrandConfig._();

  static const String _buildNameEn = String.fromEnvironment(
    'APP_NAME_EN',
    defaultValue: 'MarkStreet',
  );

  static const String _buildNameFa = String.fromEnvironment(
    'APP_NAME_FA',
    defaultValue: 'مارک‌استریت',
  );

  static final changes = ValueNotifier<int>(0);
  static String _nameFa = '', _nameEn = '', _logoUrl = '', _tagline = '';
  static String get appNameFa => _nameFa.isEmpty ? _buildNameFa : _nameFa;
  static String get appNameEn => _nameEn.isEmpty ? _buildNameEn : _nameEn;
  static String get logoUrl => _logoUrl;
  static String get tagline => _tagline;
  static Future<void> refresh() async {
    try {
      final res = await ApiClient().get<Map<String, dynamic>>(
        '/api/v1/platform/branding',
      );
      final data = res.data?['data'] as Map? ?? {};
      _nameFa = '${data['name_fa'] ?? ''}';
      _nameEn = '${data['name_en'] ?? ''}';
      _tagline = '${data['tagline'] ?? ''}';
      final logo = '${data['logo_url'] ?? ''}';
      _logoUrl = logo.isEmpty
          ? ''
          : Uri.parse(AppConfig.apiBaseUrl).resolve(logo).toString();
      changes.value++;
    } catch (_) {
      /* Preserve the bundled or last successfully loaded brand. */
    }
  }

  /// وقتی `0`/`false` باشد، [BrandLogo] لوگو را بدون ColorFilter نشان می‌دهد
  /// (مناسب برند کاستوم رنگی مثل سیان روی شفاف).
  static const String _logoTintRaw = String.fromEnvironment(
    'BRAND_LOGO_TINT',
    defaultValue: '0',
  );

  static bool get hasCustomName =>
      appNameEn.trim().isNotEmpty || appNameFa.trim().isNotEmpty;

  static bool get tintLogo {
    final v = _logoTintRaw.trim().toLowerCase();
    return v != '0' && v != 'false' && v != 'no' && v != 'off';
  }

  /// عنوان MaterialApp / مرورگر (ترجیح انگلیسی، سپس فارسی، سپس Hesabix).
  static String get materialTitle {
    final en = appNameEn.trim();
    if (en.isNotEmpty) return en;
    final fa = appNameFa.trim();
    if (fa.isNotEmpty) return fa;
    return 'MarkStreet';
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

  /// نام برند برای زبان داده‌شده (بدون وابستگی به l10n).
  static String displayName({String languageCode = 'fa'}) {
    return resolve(
      languageCode: languageCode,
      fallback: languageCode.toLowerCase().startsWith('fa')
          ? 'مارک‌استریت'
          : 'MarkStreet',
    );
  }

  /// جایگزینی «حسابیکس / Hesabix» وقتی ریبرندینگ فعال است.
  static String rebrand(String input, {String languageCode = 'fa'}) {
    if (!hasCustomName) return input;
    final name = resolve(languageCode: languageCode, fallback: '');
    if (name.isEmpty) return input;
    return input
        .replaceAll('حسابیکس', name)
        .replaceAll('حساب‌یکس', name)
        .replaceAll('Hesabix', name);
  }

  /// جایگزینی نام محصول در متن‌های l10n که «حسابیکس / Hesabix» دارند.
  static String rebrandText(AppLocalizations l10n, String input) {
    final code = l10n.localeName;
    return rebrand(input, languageCode: code.isNotEmpty ? code : 'en');
  }

  static String welcomeTitle(AppLocalizations l10n) =>
      rebrandText(l10n, l10n.welcomeTitle);

  static String welcomeSubtitle(AppLocalizations l10n) =>
      rebrandText(l10n, l10n.welcomeSubtitle);

  static String brandTagline(AppLocalizations l10n) =>
      _tagline.isNotEmpty ? _tagline : rebrandText(l10n, l10n.brandTagline);
}

/// میان‌بر برای جایگزینی برند در رشته‌های l10n.
extension BrandAppLocalizations on AppLocalizations {
  String branded(String input) => BrandConfig.rebrandText(this, input);
}
