/// شناسه‌های ثابت صدا که با سرور (`inapp_sound_asset_id`) هماهنگ است.
class NotificationSoundCatalog {
  NotificationSoundCatalog._();

  static const String defaultId = 'default';

  /// مسیر کامل در bundle، با پیشوند `assets/`.
  static String assetBundlePath(String soundAssetId) => 'assets/${assetSourceSubpath(soundAssetId)}';

  /// مسیر نسبی داخل پوشهٔ assets، بدون پیشوند `assets/` (برای URI یا نام فایل).
  /// فایل‌ها: `assets/sounds/s(1).mp3` … در pubspec ثبت شده باشند.
  static String assetSourceSubpath(String soundAssetId) {
    final effective = soundAssetId == defaultId ? 's_1' : soundAssetId;
    final m = RegExp(r'^s_(\d+)$').firstMatch(effective);
    if (m != null) {
      final n = int.tryParse(m.group(1)!);
      if (n != null && n >= 1 && n <= 27) {
        return 'sounds/s($n).mp3';
      }
    }
    return 'sounds/s(1).mp3';
  }

  static Iterable<String> get selectableIds sync* {
    yield defaultId;
    for (var i = 1; i <= 27; i++) {
      yield 's_$i';
    }
  }
}
