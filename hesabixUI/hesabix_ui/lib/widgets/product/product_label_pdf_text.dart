// شکل‌دهی حروف فارسی/عربی برای موتور متن بستهٔ pdf (مثل مسیر use_arabic در کتابخانه).
//
// ignore: implementation_imports
import 'package:pdf/src/pdf/font/arabic.dart' as pdf_arabic;

final _persianOrArabic = RegExp(r'[\u0600-\u06FF]');

/// متن مناسب برای رندر LTR در PDF؛ بدون نیاز به `--dart-define`.
///
/// `pdf` حروف هر واژه را برای نمایش چپ‌به‌راست شکل می‌دهد اما ترتیب واژه‌ها
/// را عوض نمی‌کند. برای جملهٔ فارسی باید واژه‌ها هم معکوس شوند تا خواننده
/// از راست «اسکن کنید و پرداخت کنید» ببیند، نه «کنید پرداخت و کنید اسکن».
String shapePdfPersianText(String? value) {
  if (value == null) return '';
  final t = value.trim();
  if (t.isEmpty) return '';
  final shaped = pdf_arabic.convert(t);
  if (!_persianOrArabic.hasMatch(t)) return shaped;
  return shaped.split('\n').map(_reverseWords).join('\n');
}

String _reverseWords(String line) {
  if (line.isEmpty) return line;
  final parts = line.split(' ');
  if (parts.length < 2) return line;
  return parts.reversed.join(' ');
}
