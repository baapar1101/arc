import '../core/api_client.dart';

class CurrencyService {
  final ApiClient _api;

  CurrencyService(ApiClient apiClient) : _api = apiClient;

  Future<List<Map<String, dynamic>>> listCurrencies() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/currencies');
    final body = res.data;
    final items = (body is Map<String, dynamic>) ? body['data'] : body;
    if (items is List) {
      return items
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> listBusinessCurrencies({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/currencies/business/$businessId');
    final body = res.data;
    final items = (body is Map<String, dynamic>) ? body['data'] : body;
    if (items is List) {
      return items
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  /// اضافه کردن ارز جانبی به کسب‌وکار
  Future<Map<String, dynamic>> addBusinessCurrency({
    required int businessId,
    required int currencyId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/currencies',
      data: {'currency_id': currencyId},
    );
    final body = res.data;
    if (body is Map<String, dynamic> && body['success'] == true) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    if (body is Map<String, dynamic>) {
      throw Exception(body['message'] ?? 'خطا در اضافه کردن ارز');
    }
    throw Exception('خطا در اضافه کردن ارز');
  }

  /// حذف ارز جانبی از کسب‌وکار
  Future<void> removeBusinessCurrency({
    required int businessId,
    required int currencyId,
  }) async {
    final res = await _api.delete<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/currencies/$currencyId',
    );
    final body = res.data;
    if (body is Map<String, dynamic> && body['success'] != true) {
      final error = body['error'];
      if (error is Map<String, dynamic>) {
        final code = error['code'] as String?;
        final message = error['message'] as String? ?? 'خطا در حذف ارز';
        throw Exception('$code: $message');
      }
      if (body is Map<String, dynamic>) {
        throw Exception(body['message'] ?? 'خطا در حذف ارز');
      }
      throw Exception('خطا در حذف ارز');
    }
  }

  /// بررسی استفاده ارز در اسناد
  Future<Map<String, dynamic>> checkCurrencyUsage({
    required int businessId,
    required int currencyId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/businesses/$businessId/currencies/$currencyId/usage-check',
    );
    final body = res.data;
    if (body is Map<String, dynamic> && body['success'] == true) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    if (body is Map<String, dynamic>) {
      throw Exception(body['message'] ?? 'خطا در بررسی استفاده ارز');
    }
    throw Exception('خطا در بررسی استفاده ارز');
  }
}


