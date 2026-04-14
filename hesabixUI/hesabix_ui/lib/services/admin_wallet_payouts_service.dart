import '../core/api_client.dart';

class AdminWalletPayoutsService {
  final ApiClient _api;

  AdminWalletPayoutsService(ApiClient apiClient) : _api = apiClient;

  Future<Map<String, dynamic>> list({
    int skip = 0,
    int limit = 25,
    List<String>? statuses,
    int? businessId,
  }) async {
    final payload = <String, dynamic>{
      'skip': skip,
      'take': limit,
      'filters': <Map<String, dynamic>>[],
    };
    if (statuses != null && statuses.isNotEmpty) {
      payload['filters']!.add({
        'property': 'status',
        'operator': 'in',
        'value': statuses,
      });
    }
    if (businessId != null) {
      payload['filters']!.add({
        'property': 'business_id',
        'operator': '=',
        'value': businessId,
      });
    }
    final res = await _api.post<Map<String, dynamic>>('/admin/wallets/payouts/table', data: payload);
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> getById(int payoutId) async {
    final res = await _api.get<Map<String, dynamic>>('/admin/wallets/payouts/$payoutId');
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> getStats() async {
    final res = await _api.get<Map<String, dynamic>>('/admin/wallets/payouts/stats');
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> settle({
    required int payoutId,
    required DateTime settlementDate,
    required String bankTrackingCode,
    double? feeAmount,
    String? note,
  }) async {
    final payload = <String, dynamic>{
      'settlement_date': settlementDate.toIso8601String(),
      'bank_tracking_code': bankTrackingCode,
      if (feeAmount != null) 'fee_amount': feeAmount,
      if (note != null && note.isNotEmpty) 'note': note,
    };
    final res = await _api.put<Map<String, dynamic>>(
      '/admin/wallets/payouts/$payoutId/settle',
      data: payload,
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }
}

