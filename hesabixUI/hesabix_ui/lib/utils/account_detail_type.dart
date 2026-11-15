/// تشخیص نوع تفصیل موردنیاز برای حساب انتخاب‌شده در طرف‌حساب نوع «حساب».
///
/// حساب‌های کنترلی شخص‌محور (دریافتنی، پرداختنی، جاری شرکا، سهامدار و …)
/// بعد از انتخاب حساب باید تفصیل شخص بگیرند. برگ‌های تفصیلی با نام شخص
/// (مثل `2050301 ـ محمد`) این الگو را ندارند تا انتخاب مجدد شخص اجباری نشود.
String? accountDetailTypeFor({
  String? name,
  String? accountType,
  String? code,
}) {
  final t = (accountType ?? '').trim().toLowerCase();
  if (t == 'product') return 'product';

  final n = (name ?? '').toLowerCase();
  final c = (code ?? '').trim();

  bool nameHas(List<String> parts) =>
      parts.any((p) => p.isNotEmpty && n.contains(p.toLowerCase()));

  if (t == 'person' ||
      nameHas(const [
        'دریافتنی',
        'پرداختنی',
        'مشتری',
        'تامین',
        'جاری شرکا',
        'جاری شرکاء',
        'سهامدار',
      ]) ||
      c == '20503') {
    return 'person';
  }
  if (nameHas(const ['موجودی', 'کالا', 'انبار'])) return 'product';
  if (t == 'bank' || n.contains('بانک')) return 'bank_account';
  if (t == 'cash_register' || n.contains('صندوق')) return 'cash_register';
  if (t == 'petty_cash' || n.contains('تنخواه')) return 'petty_cash';
  if (t == 'check' || n.contains('چک')) return 'check';
  return null;
}

bool isPersonControlAccount({
  String? name,
  String? accountType,
  String? code,
}) {
  return accountDetailTypeFor(
        name: name,
        accountType: accountType,
        code: code,
      ) ==
      'person';
}
