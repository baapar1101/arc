import 'dart:typed_data';
import 'dart:collection';

/// LRU Cache برای مدیریت حافظه عکس‌ها
class ProductImageCache {
  final int maxSize;
  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();

  ProductImageCache({this.maxSize = 50});

  /// دریافت عکس از cache
  Uint8List? get(String key) {
    final value = _cache.remove(key);
    if (value != null) {
      // اضافه کردن به انتهای لیست (اخیراً استفاده شده)
      _cache[key] = value;
      return value;
    }
    return null;
  }

  /// اضافه کردن عکس به cache
  void put(String key, Uint8List value) {
    // اگر کلید موجود است، آن را حذف می‌کنیم
    _cache.remove(key);
    
    // اضافه کردن به انتهای لیست
    _cache[key] = value;
    
    // اگر cache پر شده، قدیمی‌ترین را حذف می‌کنیم
    while (_cache.length > maxSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// حذف یک عکس از cache
  void remove(String key) {
    _cache.remove(key);
  }

  /// پاک کردن تمام cache
  void clear() {
    _cache.clear();
  }

  /// تعداد عکس‌های موجود در cache
  int get length => _cache.length;

  /// بررسی وجود کلید در cache
  bool containsKey(String key) => _cache.containsKey(key);
}

/// Singleton instance برای استفاده در کل اپلیکیشن
class GlobalImageCache {
  static final ProductImageCache _instance = ProductImageCache(maxSize: 50);
  static ProductImageCache get instance => _instance;
}

