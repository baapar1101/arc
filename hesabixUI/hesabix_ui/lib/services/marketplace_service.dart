import '../core/api_client.dart';

class MarketplaceService {
  final ApiClient _api;
  MarketplaceService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<List<Map<String, dynamic>>> listPlugins() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/marketplace/plugins');
    final body = res.data;
    final items = (body is Map<String, dynamic>) ? body['data'] : body;
    if (items is List) {
      return items.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> purchase({
    required int businessId,
    required int pluginId,
    required int planId,
    int quantity = 1,
  }) async {
    final payload = <String, dynamic>{
      'plugin_id': pluginId,
      'plan_id': planId,
      'quantity': quantity,
    };
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/marketplace/business/$businessId/purchase',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> listOrders({
    required int businessId,
    int page = 1,
    int limit = 20,
  }) async {
    final skip = (page - 1) * limit;
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/marketplace/business/$businessId/orders',
      query: {
        'limit': '$limit',
        'skip': '$skip',
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> listInvoices({
    required int businessId,
    int page = 1,
    int limit = 20,
  }) async {
    final skip = (page - 1) * limit;
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/marketplace/business/$businessId/invoices',
      query: {
        'limit': '$limit',
        'skip': '$skip',
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }
}


