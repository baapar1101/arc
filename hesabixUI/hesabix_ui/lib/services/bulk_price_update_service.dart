import '../core/api_client.dart';

class BulkPriceUpdateService {
  final ApiClient _api;

  BulkPriceUpdateService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  /// پیش‌نمایش تغییرات قیمت گروهی
  Future<Map<String, dynamic>> previewBulkPriceUpdate({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/products/business/$businessId/bulk-price-update/preview',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  /// اعمال تغییرات قیمت گروهی
  Future<Map<String, dynamic>> applyBulkPriceUpdate({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/products/business/$businessId/bulk-price-update/apply',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }
}
