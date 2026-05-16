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

  Future<Map<String, dynamic>> controlSyncStats({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/control/sync-stats',
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> controlSettingsSummary({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/control/settings-summary',
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> controlLogs({
    required int businessId,
    int page = 1,
    int perPage = 20,
    String? action,
  }) async {
    final q = <String, dynamic>{
      'page': page,
      'per_page': perPage,
      if (action != null && action.trim().isNotEmpty) 'action': action.trim(),
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/control/logs',
      query: q,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> controlConnection({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/control/connection',
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> controlPlugin({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/control/plugin',
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> postControlSyncProduct({
    required int businessId,
    required int productId,
    int? variationId,
  }) async {
    final body = <String, dynamic>{
      'product_id': productId,
      if (variationId != null && variationId > 0) 'variation_id': variationId,
    };
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/control/sync/product',
      data: body,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> postControlSyncOrders({
    required int businessId,
    required List<int> orderIds,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/control/sync/orders',
      data: <String, dynamic>{'order_ids': orderIds},
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> postControlSyncProducts({
    required int businessId,
    required List<int> productIds,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/control/sync/products',
      data: <String, dynamic>{'product_ids': productIds},
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> postControlSyncCustomers({
    required int businessId,
    required List<int> customerIds,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/control/sync/customers',
      data: <String, dynamic>{'customer_ids': customerIds},
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> controlQueueSnapshot({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/control/queue/snapshot',
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> postControlQueueProcessOnce({required int businessId}) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/control/queue/process-once',
      data: const <String, dynamic>{},
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> postControlPluginUpdateCheck({
    required int businessId,
    bool force = false,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/control/plugin/update-check',
      data: <String, dynamic>{'force': force},
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> postControlSettingsPatch({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/control/settings/patch',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> controlOpeningInventoryStatus({
    required int businessId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/control/opening-inventory/status',
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> controlOpeningInventoryAccounts({
    required int businessId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/control/opening-inventory/accounts',
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> postControlOpeningInventoryPreview({
    required int businessId,
    Map<String, dynamic>? payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/control/opening-inventory/preview',
      data: payload ?? const <String, dynamic>{},
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> postControlOpeningInventoryPrepare({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/control/opening-inventory/prepare',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> postControlOpeningInventoryBatch({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/control/opening-inventory/batch',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> postControlOpeningInventoryFinalize({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/control/opening-inventory/finalize',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> postControlOpeningInventoryCancel({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/woocommerce/business/$businessId/bridge/control/opening-inventory/cancel',
      data: payload,
    );
    return _dataMap(res.data);
  }
}
