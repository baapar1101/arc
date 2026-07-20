/// ابزارهای کمکی استخراج اسکریپت HScript از پاسخ AI / کلیپ‌بورد.
class HScriptCodeExtract {
  HScriptCodeExtract._();

  static final RegExp _fence = RegExp(
    r'```(?:hscript|python|py)?\s*\n([\s\S]*?)```',
    multiLine: true,
  );

  /// استخراج اولین بلوک کد؛ اگر fence نبود کل متن تمیز برگردانده می‌شود.
  static String? extract(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;
    final match = _fence.firstMatch(text);
    if (match != null) {
      return match.group(1)?.trim();
    }
    // اگر شبیه اسکریپت HScript باشد
    if (text.contains('report.') || text.contains('invoices.') || text.contains('def ')) {
      return text;
    }
    return null;
  }
}
