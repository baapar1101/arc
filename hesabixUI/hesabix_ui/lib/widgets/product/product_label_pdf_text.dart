// شکل‌دهی حروف فارسی/عربی برای موتور متن بستهٔ pdf (مثل مسیر use_arabic در کتابخانه).
//
// ignore: implementation_imports
import 'package:pdf/src/pdf/font/arabic.dart' as pdf_arabic;

/// متن مناسب برای رندر در PDF؛ بدون نیاز به `--dart-define`.
String shapePdfPersianText(String? value) {
  if (value == null) return '';
  final t = value.trim();
  if (t.isEmpty) return '';
  return pdf_arabic.convert(t);
}
