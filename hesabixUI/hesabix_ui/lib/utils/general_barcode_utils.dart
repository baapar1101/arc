/// پارس بارکدهای عمومی هم‌تراز با بک‌اند (ویرگول انگلیسی/فارسی و شکست خط).
List<String> parseGeneralBarcodeTokens(String? raw) {
  if (raw == null) return const <String>[];
  var s = raw.trim();
  if (s.isEmpty) return const <String>[];
  s = s.replaceAll(RegExp(r'[\r\n]+'), ',');
  s = s.replaceAll('،', ',');
  final out = <String>[];
  final seen = <String>{};
  for (final part in s.split(',')) {
    final t = part.trim();
    if (t.isEmpty) continue;
    final k = t.toLowerCase();
    if (seen.contains(k)) continue;
    seen.add(k);
    out.add(t);
  }
  return out;
}
