import '../core/api_client.dart';

class PayPageAbuseReportsService {
  final ApiClient _apiClient;
  PayPageAbuseReportsService(this._apiClient);

  Future<Map<String, dynamic>> list({
    String? status,
    int take = 30,
    int skip = 0,
  }) async {
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/api/v1/admin/pay-page-abuse-reports',
      query: {
        'take': take,
        'skip': skip,
        if (status != null && status.isNotEmpty) 'status': status,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> update(
    int id, {
    String? status,
    String? adminNote,
  }) async {
    final res = await _apiClient.patch<Map<String, dynamic>>(
      '/api/v1/admin/pay-page-abuse-reports/$id',
      data: {
        'status': ?status,
        'admin_note': ?adminNote,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }
}
