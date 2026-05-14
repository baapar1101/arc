import 'package:shared_preferences/shared_preferences.dart';

/// ترجیح کاربر برای نوع تخفیف در ردیف‌های اقلام فاکتور (درصدی / مقداری).
/// در افزودن ردیف جدید و بار اول صفحهٔ «افزودن فاکتور» اعمال می‌شود.
class InvoiceLinePreferences {
  InvoiceLinePreferences._();

  static const String _kDiscountType = 'invoice_line_default_discount_type';
  static const String _kSecondaryAddRowShortcut = 'invoice_line_secondary_add_row_shortcut';

  /// میان‌بر ثانویهٔ «افزودن یک ردیف» در جدول اقلام (دسکتاپ، وقتی لایهٔ میان‌بر فعال است).
  /// مقادیر مجاز: `f2` | `ctrl_shift_n` | `none`
  static bool isValidSecondaryAddRowShortcut(String? v) =>
      v == 'f2' || v == 'ctrl_shift_n' || v == 'none';

  static Future<String> getSecondaryAddRowShortcut() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kSecondaryAddRowShortcut);
    if (v != null && isValidSecondaryAddRowShortcut(v)) return v;
    return 'f2';
  }

  static Future<void> setSecondaryAddRowShortcut(String shortcut) async {
    if (!isValidSecondaryAddRowShortcut(shortcut)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSecondaryAddRowShortcut, shortcut);
  }

  /// مقدارهای مجاز مطابق [InvoiceLineItem.discountType]
  static bool isValidDiscountType(String? v) =>
      v == 'percent' || v == 'amount';

  /// آخرین انتخاب ذخیره‌شده؛ در نبود مقدار: درصدی (`percent`).
  static Future<String> getDefaultDiscountType() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kDiscountType);
    if (v != null && isValidDiscountType(v)) return v;
    return 'percent';
  }

  static Future<void> setDefaultDiscountType(String discountType) async {
    if (!isValidDiscountType(discountType)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDiscountType, discountType);
  }
}
