import 'package:hesabix_ui/core/api_client.dart';

class OpeningBalanceService {
  final ApiClient _apiClient;

  OpeningBalanceService(this._apiClient);

  Future<Map<String, dynamic>?> fetch({required int businessId, int? fiscalYearId}) async {
    final resp = await _apiClient.get(
      '/businesses/$businessId/opening-balance',
      query: {
        if (fiscalYearId != null) 'fiscal_year_id': fiscalYearId,
      },
    );
    if (resp.statusCode == 200) {
      return (resp.data?['data'] as Map<String, dynamic>?) ?? {};
    }
    throw Exception('خطا در دریافت تراز افتتاحیه: ${resp.statusMessage}');
  }

  Future<Map<String, dynamic>> save({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final resp = await _apiClient.put(
      '/businesses/$businessId/opening-balance',
      data: payload,
    );
    if (resp.statusCode == 200) {
      return (resp.data?['data'] as Map<String, dynamic>? ?? {});
    }
    throw Exception('خطا در ذخیره تراز افتتاحیه: ${resp.statusMessage}');
  }

  Future<Map<String, dynamic>> post({required int businessId, int? fiscalYearId}) async {
    final resp = await _apiClient.post(
      '/businesses/$businessId/opening-balance/post',
      data: {
        if (fiscalYearId != null) 'fiscal_year_id': fiscalYearId,
      },
    );
    if (resp.statusCode == 200) {
      return (resp.data?['data'] as Map<String, dynamic>? ?? {});
    }
    throw Exception('خطا در نهایی‌سازی تراز افتتاحیه: ${resp.statusMessage}');
  }

}


