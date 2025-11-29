import '../core/api_client.dart';

class YearEndClosingService {
  final ApiClient _apiClient;

  YearEndClosingService(this._apiClient);

  /// دریافت پیش‌نمایش بستن سال مالی
  Future<Map<String, dynamic>> preview({
    required int businessId,
    required int fiscalYearId,
  }) async {
    final resp = await _apiClient.get(
      '/api/v1/business/$businessId/fiscal-years/$fiscalYearId/closing/preview',
    );
    if (resp.statusCode == 200) {
      return (resp.data?['data'] as Map<String, dynamic>?) ?? {};
    }
    throw Exception('خطا در دریافت پیش‌نمایش بستن سال مالی: ${resp.statusMessage}');
  }

  /// بستن سال مالی
  Future<Map<String, dynamic>> close({
    required int businessId,
    required int fiscalYearId,
    required String newFiscalYearTitle,
    bool autoCreateOpeningBalance = true,
  }) async {
    final resp = await _apiClient.post(
      '/api/v1/business/$businessId/fiscal-years/$fiscalYearId/close',
      data: {
        'new_fiscal_year_title': newFiscalYearTitle,
        'auto_create_opening_balance': autoCreateOpeningBalance,
      },
    );
    if (resp.statusCode == 200) {
      return (resp.data?['data'] as Map<String, dynamic>?) ?? {};
    }
    throw Exception('خطا در بستن سال مالی: ${resp.statusMessage}');
  }
}

