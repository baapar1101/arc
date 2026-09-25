/// تنظیمات پیش‌فرض سرویس می‌مپس (جستجو و مرکز نقشه).
abstract final class MemapsConfig {
  static const String searchPlacesUrl = 'https://memaps.ir/api/search/places';
  static const String usageGuideUrl = 'https://memaps.ir/usage';
  static const String panelUrl = 'https://memaps.ir/';

  /// مرکز پیش‌فرض (تهران) وقتی مارکری نیست.
  static const double defaultLat = 35.6892;
  static const double defaultLng = 51.3890;
  static const double defaultZoom = 12;
}
