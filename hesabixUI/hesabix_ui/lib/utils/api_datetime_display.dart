/// استخراج رشتهٔ نمایشی تاریخ/زمان از پاسخ API پس از [format_datetime_fields] بک‌اند.
String resolveApiDateTimeDisplay(Map<String, dynamic> map, String key) {
  final formattedKey = '${key}_formatted';
  final rawKey = '${key}_raw';

  final formatted = map[formattedKey];
  if (formatted is Map && formatted['formatted'] != null) {
    final s = formatted['formatted'].toString();
    if (s.isNotEmpty) return s;
  }
  if (formatted is String && formatted.isNotEmpty) return formatted;

  final base = map[key];
  if (base is String && base.isNotEmpty) return base;

  final raw = map[rawKey];
  if (raw is String && raw.isNotEmpty) return raw;

  return '';
}
