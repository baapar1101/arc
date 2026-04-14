import '../core/api_client.dart';

class WalletService {
  final ApiClient _api;
  WalletService(this._api);

  Future<Map<String, dynamic>> getOverview({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>('/businesses/$businessId/wallet');
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<List<Map<String, dynamic>>> listTransactions({
    required int businessId,
    int skip = 0,
    int limit = 50,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final query = <String, dynamic>{
      'skip': '$skip',
      'limit': '$limit',
      if (fromDate != null) 'from_date': fromDate.toIso8601String(),
      if (toDate != null) 'to_date': toDate.toIso8601String(),
    };
    final res = await _api.get<Map<String, dynamic>>('/businesses/$businessId/wallet/transactions', query: query);
    final body = res.data;
    final items = (body is Map<String, dynamic>) ? body['data'] : body;
    if (items is List) {
      return items.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> getMetrics({
    required int businessId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final query = <String, dynamic>{
      if (fromDate != null) 'from_date': fromDate.toIso8601String(),
      if (toDate != null) 'to_date': toDate.toIso8601String(),
    };
    final res = await _api.get<Map<String, dynamic>>('/businesses/$businessId/wallet/metrics', query: query);
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> requestPayout({
    required int businessId,
    required int bankAccountId,
    required double amount,
    String? description,
  }) async {
    final res = await _api.post<Map<String, dynamic>>('/businesses/$businessId/wallet/payouts', data: {
      'bank_account_id': bankAccountId,
      'amount': amount,
      if (description != null && description.isNotEmpty) 'description': description,
    });
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> topUp({
    required int businessId,
    required double amount,
    String? description,
    int? gatewayId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>('/businesses/$businessId/wallet/top-up', data: {
      'amount': amount,
      if (description != null && description.isNotEmpty) 'description': description,
      if (gatewayId != null) 'gateway_id': gatewayId,
    });
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }
}


