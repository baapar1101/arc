import 'package:shared_preferences/shared_preferences.dart';

/// ترجیح کاربر برای نوع تخفیف در ردیف‌های اقلام فاکتور (درصدی / مقداری).
/// در افزودن ردیف جدید و بار اول صفحهٔ «افزودن فاکتور» اعمال می‌شود.
class InvoiceLinePreferences {
  InvoiceLinePreferences._();

  static const String _kDiscountType = 'invoice_line_default_discount_type';

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
