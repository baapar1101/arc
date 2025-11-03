import '../core/api_client.dart';

class KardexService {
  final ApiClient _client;
  KardexService({ApiClient? client}) : _client = client ?? ApiClient();

  Future<Map<String, dynamic>> listLines({
    required int businessId,
    required Map<String, dynamic> queryInfo,
  }) async {
    try {
      final res = await _client.post<Map<String, dynamic>>(
        '/api/v1/kardex/businesses/$businessId/lines',
        data: queryInfo,
      );
      return res.data ?? <String, dynamic>{};
    } catch (e) {
      return {
        'items': <dynamic>[],
        'pagination': {
          'total': 0,
          'page': 1,
          'per_page': queryInfo['take'] ?? 20,
          'total_pages': 0,
          'has_next': false,
          'has_prev': false,
        },
        'query_info': queryInfo,
        'error': e.toString(),
      };
    }
  }
}


