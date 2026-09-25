import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../config/app_config.dart';
import '../../../core/api_client.dart';
import '../../../models/barcode_label/label_design_v1.dart';

/// بارگذاری تصویر المان‌های برچسب برای پیش‌نمایش و چاپ.
class LabelImageResolver {
  LabelImageResolver._();

  static final _businessLogoCache = <int, Uint8List>{};
  static final _urlCache = <String, Uint8List>{};

  static Future<Map<String, Uint8List>> preloadForDesign({
    required LabelDesignDocument design,
    int? businessId,
    List<Map<String, dynamic>>? contexts,
  }) async {
    final out = <String, Uint8List>{};
    if (contexts != null && contexts.isNotEmpty) {
      for (var i = 0; i < contexts.length; i++) {
        for (final el in design.elements) {
          if (el.type != LabelElementType.image || !el.visible) continue;
          final bytes = await resolveElement(
            el,
            context: contexts[i],
            businessId: businessId,
          );
          if (bytes != null && bytes.isNotEmpty) {
            out['${el.id}:$i'] = bytes;
          }
        }
      }
      return out;
    }
    for (final el in design.elements) {
      if (el.type != LabelElementType.image || !el.visible) continue;
      final bytes = await resolveElement(el, businessId: businessId);
      if (bytes != null && bytes.isNotEmpty) {
        out[el.id] = bytes;
      }
    }
    return out;
  }

  static Future<Uint8List?> resolveElement(
    LabelElement el, {
    Map<String, dynamic>? context,
    int? businessId,
  }) async {
    if (el.type != LabelElementType.image) return null;
    final source = (el.props['source'] ?? '').toString();
    switch (source) {
      case 'upload':
        return _fromDataUri(el.props['data_uri']?.toString());
      case 'product.image':
        final url = (context?['product'] as Map?)?['image_url']?.toString() ??
            (context?['product'] as Map?)?['thumbnail_url']?.toString() ??
            (context?['product'] as Map?)?['image']?.toString();
        if (url == null || url.isEmpty) return null;
        if (url.startsWith('data:')) return _fromDataUri(url);
        return _loadUrlBytes(_fullUrl(url));
      case 'business.logo':
        if (businessId == null) return null;
        return _loadBusinessLogo(businessId);
      default:
        return _fromDataUri(el.props['data_uri']?.toString());
    }
  }

  static Uint8List? _fromDataUri(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final s = raw.trim();
    final comma = s.indexOf(',');
    if (!s.startsWith('data:') || comma < 0) return null;
    try {
      return base64Decode(s.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _loadBusinessLogo(int businessId) async {
    if (_businessLogoCache.containsKey(businessId)) {
      return _businessLogoCache[businessId];
    }
    try {
      final api = ApiClient();
      final res = await api.get<Uint8List>(
        '/businesses/$businessId/logo',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = res.data;
      if (bytes == null || bytes.isEmpty) return null;
      _businessLogoCache[businessId] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static void clearCache() {
    _businessLogoCache.clear();
    _urlCache.clear();
  }

  static String? _fullUrl(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    final baseUrl = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$baseUrl${s.startsWith('/') ? s : '/$s'}';
  }

  static Future<Uint8List?> _loadUrlBytes(String? url) async {
    if (url == null || url.isEmpty) return null;
    if (_urlCache.containsKey(url)) return _urlCache[url];
    try {
      final api = ApiClient();
      final res = await api.get<Uint8List>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = res.data;
      if (bytes == null || bytes.isEmpty) return null;
      _urlCache[url] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }
}

/// تبدیل data URI برای ذخیره در طرح پس از انتخاب فایل.
String bytesToDataUri(Uint8List bytes, {String mime = 'image/png'}) {
  return 'data:$mime;base64,${base64Encode(bytes)}';
}
