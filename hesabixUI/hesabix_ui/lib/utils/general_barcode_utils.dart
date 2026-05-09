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

/// نمایش یک بارکد عمومی (اولین توکن) یا بارکد legacy برای لیست نتایج جستجو.
String? productPrimaryBarcodeForSearchDisplay(
  Map<String, dynamic> product, {
  int maxLen = 56,
}) {
  final tokens = parseGeneralBarcodeTokens(product['general_barcodes']?.toString());
  if (tokens.isNotEmpty) {
    final t = tokens.first;
    if (t.length <= maxLen) return t;
    return '${t.substring(0, maxLen - 1)}…';
  }
  final legacy = product['barcode']?.toString().trim();
  if (legacy == null || legacy.isEmpty) return null;
  if (legacy.length <= maxLen) return legacy;
  return '${legacy.substring(0, maxLen - 1)}…';
}
