import 'package:flutter/widgets.dart';

/// رشته‌های بخش هشدار in-app (فعلاً بدون وابستگی به فایل arb — در صورت دسترسی به l10n می‌توان به کلیدهای رسمی منتقل کرد).
class InAppNotificationStrings {
  static bool _fa(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    return code.startsWith('fa');
  }

  static String behaviorSectionTitle(BuildContext context) => _fa(context)
      ? 'رفتار هشدار درون‌برنامه‌ای'
      : 'In-app alert behavior';

  static String behaviorSectionSubtitle(BuildContext context) => _fa(context)
      ? 'نحوهٔ نمایش و صدا هنگام رسیدن ناتیفیکیشن جدید.'
      : 'Controls banners and optional sounds when a new in-app notification arrives.';

  static String modeNormal(BuildContext context) => _fa(context) ? 'عادی' : 'Normal';
  static String modeNormalHint(BuildContext context) =>
      _fa(context) ? 'اعلان و در صورت انتخاب، صدا.' : 'Show a banner and optional sound.';

  static String modeSilent(BuildContext context) => _fa(context) ? 'سکوت' : 'Silent';
  static String modeSilentHint(BuildContext context) =>
      _fa(context) ? 'اعلان بدون صدا.' : 'Banner without sound.';

  static String modeDnd(BuildContext context) => _fa(context) ? 'مزاحم نشوید' : 'Do not disturb';
  static String modeDndHint(BuildContext context) => _fa(context)
      ? 'تا تغییر حالت، هیچ اعلان یا صدایی نمایش داده نمی‌شود.'
      : 'No banners or sounds until you change this mode.';

  static String soundToggle(BuildContext context) =>
      _fa(context) ? 'پخش صدا برای اعلان‌های جدید' : 'Play sound for new alerts';

  static String soundPickerLabel(BuildContext context) => _fa(context) ? 'زنگ هشدار' : 'Alert tone';

  static String previewTooltip(BuildContext context) => _fa(context) ? 'پیش‌پخش' : 'Preview';

  static String webSoundHint(BuildContext context) => _fa(context)
      ? 'برخی مرورگرها تا اولین کلیک یا لمس روی صفحه، صدا را مسدود می‌کنند.'
      : 'Some browsers block audio until you click or tap the page once.';

  static String soundOptionDefault(BuildContext context) =>
      _fa(context) ? 'پیش‌فرض (زنگ ۱)' : 'Default (tone 1)';

  static String soundOptionIndex(BuildContext context, int index) =>
      _fa(context) ? 'زنگ $index' : 'Tone $index';
}
