import '../core/api_client.dart';
import '../models/production_order_models.dart';

class ProductionOrderService {
  final ApiClient _api;
  ProductionOrderService({ApiClient? apiClient})
    : _api = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> list({
    required int businessId,
    String? status,
    int? productId,
    String? dueFrom,
    String? dueTo,
    int skip = 0,
    int take = 50,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/production/orders/business/$businessId',
      query: <String, dynamic>{
        if (status case final statusValue? when statusValue.isNotEmpty)
          'status': statusValue,
        if (productId case final selectedProductId?)
          'product_id': selectedProductId,
        if (dueFrom case final dueFromValue? when dueFromValue.isNotEmpty)
          'due_from': dueFromValue,
        if (dueTo case final dueToValue? when dueToValue.isNotEmpty)
          'due_to': dueToValue,
        'skip': skip,
        'take': take,
      },
    );
    return res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
  }

  Future<List<ProductionOrder>> listOrders({
    required int businessId,
    String? status,
    int? productId,
    String? dueFrom,
    String? dueTo,
    int skip = 0,
    int take = 50,
  }) async {
    final data = await list(
      businessId: businessId,
      status: status,
      productId: productId,
      dueFrom: dueFrom,
      dueTo: dueTo,
      skip: skip,
      take: take,
    );
    final items = data['items'] as List? ?? const [];
    return items
        .map(
          (e) => ProductionOrder.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  Future<Map<String, dynamic>> getMaterialPlan({
    required int businessId,
    String? dueFrom,
    String? dueTo,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/production/orders/business/$businessId/material-plan',
      query: <String, dynamic>{
        if (dueFrom case final value? when value.isNotEmpty) 'due_from': value,
        if (dueTo case final value? when value.isNotEmpty) 'due_to': value,
      },
    );
    return res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> traceLot({
    required int businessId,
    required String lotCode,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/production/orders/business/$businessId/trace',
      query: <String, dynamic>{'lot_code': lotCode.trim()},
    );
    return res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
  }

  Future<ProductionOrder> getById({
    required int businessId,
    required int orderId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/production/orders/business/$businessId/$orderId',
    );
    final data =
        res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return ProductionOrder.fromJson(data);
  }

  Future<Map<String, dynamic>> getCosting({
    required int businessId,
    required int orderId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/production/orders/business/$businessId/$orderId/costing',
    );
    return res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> refreshCosting({
    required int businessId,
    required int orderId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/production/orders/business/$businessId/$orderId/costing/refresh',
    );
    return res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
  }

  Future<ProductionOrder> updateLots({
    required int businessId,
    required int orderId,
    required int version,
    required List<Map<String, dynamic>> materials,
    required List<Map<String, dynamic>> outputs,
  }) async {
    final res = await _api.patch<Map<String, dynamic>>(
      '/api/v1/production/orders/business/$businessId/$orderId/lots',
      data: <String, dynamic>{
        'version': version,
        'materials': materials,
        'outputs': outputs,
      },
    );
    final data =
        res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return ProductionOrder.fromJson(data);
  }

  Future<ProductionOrder> create({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/production/orders/business/$businessId',
      data: payload,
    );
    final data =
        res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return ProductionOrder.fromJson(data);
  }

  Future<ProductionOrder> update({
    required int businessId,
    required int orderId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.patch<Map<String, dynamic>>(
      '/api/v1/production/orders/business/$businessId/$orderId',
      data: payload,
    );
    final data =
        res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return ProductionOrder.fromJson(data);
  }

  Future<ProductionOrder> _action({
    required int businessId,
    required int orderId,
    required String action,
    required int version,
    String? closeReason,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/production/orders/business/$businessId/$orderId/$action',
      data: <String, dynamic>{
        'version': version,
        if (closeReason case final reasonValue?
            when reasonValue.trim().isNotEmpty)
          'close_reason': reasonValue.trim(),
      },
    );
    final data =
        res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return ProductionOrder.fromJson(data);
  }

  Future<ProductionOrder> release({
    required int businessId,
    required int orderId,
    required int version,
  }) => _action(
    businessId: businessId,
    orderId: orderId,
    action: 'release',
    version: version,
  );

  Future<ProductionOrder> start({
    required int businessId,
    required int orderId,
    required int version,
  }) => _action(
    businessId: businessId,
    orderId: orderId,
    action: 'start',
    version: version,
  );

  Future<ProductionOrder> complete({
    required int businessId,
    required int orderId,
    required int version,
    String? closeReason,
  }) => _action(
    businessId: businessId,
    orderId: orderId,
    action: 'complete',
    version: version,
    closeReason: closeReason,
  );

  Future<ProductionOrder> cancel({
    required int businessId,
    required int orderId,
    required int version,
  }) => _action(
    businessId: businessId,
    orderId: orderId,
    action: 'cancel',
    version: version,
  );
}
