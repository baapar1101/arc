/// تنظیمات عمومی سرویس نقشه می‌مپس (فاز A — تایل + جستجو).
abstract final class MemapsConfig {
  static const String tileUrlTemplate = 'https://memaps.ir/hot/{z}/{x}/{y}.png';
  static const String tileUrlRetinaTemplate = 'https://memaps.ir/hot/{z}/{x}/{y}@2x.png';
  static const String searchPlacesUrl = 'https://memaps.ir/api/search/places';
  static const String attribution = '© OpenStreetMap · © می‌مپس';

  /// مرکز پیش‌فرض (تهران) وقتی مارکری نیست.
  static const double defaultLat = 35.6892;
  static const double defaultLng = 51.3890;
  static const double defaultZoom = 12;
}
