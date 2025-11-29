import '../core/api_client.dart';

class QuickSalesService {
  final ApiClient _api;

  QuickSalesService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  /// دریافت تنظیمات فروش سریع
  Future<Map<String, dynamic>> getSettings({
    required int businessId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/quick-sales/settings',
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  /// به‌روزرسانی تنظیمات فروش سریع
  Future<Map<String, dynamic>> updateSettings({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/quick-sales/settings',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  /// دریافت یا ایجاد مشتری ناشناس
  Future<Map<String, dynamic>> getAnonymousCustomer({
    required int businessId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/quick-sales/anonymous-customer',
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }
}

