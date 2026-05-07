/// برچسب کوتاه برای tooltip و suffix مبلغ از نقشهٔ ارز کسب‌کار (API): نماد، یا کد، یا عنوان.
String currencyUnitLabelFromBusinessCurrencyMap(
  Map<String, dynamic> currency, {
  String fallback = 'ریال',
}) {
  for (final key in ['symbol', 'code', 'title']) {
    final v = currency[key]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return fallback;
}

/// اگر ارز با [currencyId] در [cache] پیدا شود برچسب را برمی‌گرداند؛ وگرنه `null`.
String? currencyUnitLabelForBusinessCurrencyIdOrNull(
  int? currencyId,
  List<dynamic>? cache,
) {
  if (currencyId == null || cache == null || cache.isEmpty) return null;
  for (final raw in cache) {
    if (raw is! Map) continue;
    final c = Map<String, dynamic>.from(raw);
    if ((c['id'] as num?)?.toInt() == currencyId) {
      final label = currencyUnitLabelFromBusinessCurrencyMap(c, fallback: '');
      return label.isEmpty ? null : label;
    }
  }
  return null;
}
