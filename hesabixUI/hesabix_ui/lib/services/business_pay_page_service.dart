import 'package:hesabix_ui/core/api_client.dart';

class BusinessPayPageService {
  BusinessPayPageService({ApiClient? apiClient})
      : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<Map<String, dynamic>> getSettings(int businessId) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/pay-page',
    );
    return _data(response.data, 'خطا در دریافت تنظیمات لینک واریز');
  }

  Future<Map<String, dynamic>> updateSettings(
    int businessId,
    Map<String, dynamic> payload,
  ) async {
    final response = await _api.put<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/pay-page',
      data: payload,
    );
    return _data(response.data, 'خطا در ذخیره تنظیمات لینک واریز');
  }

  Future<Map<String, dynamic>> checkUsername(int businessId, String username) async {
    final response = await _api.get<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/pay-page/username-availability',
      query: {'username': username},
    );
    return _data(response.data, 'خطا در بررسی نام کاربری');
  }

  Map<String, dynamic> _data(Map<String, dynamic>? body, String fallback) {
    if (body != null && body['success'] == true && body['data'] is Map) {
      return (body['data'] as Map).cast<String, dynamic>();
    }
    throw Exception(body?['message'] ?? fallback);
  }
}
