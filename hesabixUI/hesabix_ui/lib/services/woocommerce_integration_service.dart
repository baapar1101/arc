import '../core/api_client.dart';

class WoocommerceIntegrationService {
  final ApiClient _api;

  WoocommerceIntegrationService({ApiClient? apiClient})
      : _api = apiClient ?? ApiClient();

  Map<String, dynamic> _dataMap(Map<String, dynamic>? body) {
    if (body == null) return const {};
    final d = body['data'];
    if (d is Map) return Map<String, dynamic>.from(d);
    return const {};
  }

  Future<Map<String, dynamic>> getSettings({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/settings',
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> updateSettings({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/settings',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> testBridge({required int businessId}) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/test',
      data: const <String, dynamic>{},
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> reportsSummary({
    required int businessId,
    String? after,
    String? before,
  }) async {
    final q = <String, dynamic>{
      if (after != null && after.trim().isNotEmpty) 'after': after.trim(),
      if (before != null && before.trim().isNotEmpty) 'before': before.trim(),
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/reports/summary',
      query: q,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> listOrders({
    required int businessId,
    int page = 1,
    int perPage = 20,
    String? status,
    String? after,
    String? before,
    int? customerId,
    String? search,
    String? orderby,
    String? order,
  }) async {
    final q = <String, dynamic>{
      'page': page,
      'per_page': perPage,
      if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
      if (after != null && after.trim().isNotEmpty) 'after': after.trim(),
      if (before != null && before.trim().isNotEmpty) 'before': before.trim(),
      if (customerId != null && customerId > 0) 'customer_id': customerId,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (orderby != null && orderby.trim().isNotEmpty) 'orderby': orderby.trim(),
      if (order != null && order.trim().isNotEmpty) 'order': order.trim(),
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/orders',
      query: q,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> listProducts({
    required int businessId,
    int page = 1,
    int perPage = 20,
    String? search,
  }) async {
    final q = <String, dynamic>{
      'page': page,
      'per_page': perPage,
      if (search != null && search.isNotEmpty) 'search': search,
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/products',
      query: q,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> listCustomers({
    required int businessId,
    int page = 1,
    int perPage = 20,
    String? search,
  }) async {
    final q = <String, dynamic>{
      'page': page,
      'per_page': perPage,
      if (search != null && search.isNotEmpty) 'search': search,
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/customers',
      query: q,
    );
    return _dataMap(res.data);
  }
}
