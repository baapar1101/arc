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
}


