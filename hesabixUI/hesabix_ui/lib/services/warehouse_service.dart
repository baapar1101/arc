import '../core/api_client.dart';
import '../models/warehouse_model.dart';

class WarehouseService {
  final ApiClient _api;
  WarehouseService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<List<Warehouse>> listWarehouses({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/warehouses/business/$businessId');
    final data = res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final items = data['items'] as List<dynamic>? ?? const <dynamic>[];
    return items.map((e) => Warehouse.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<Warehouse> createWarehouse({required int businessId, required Map<String, dynamic> payload}) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/warehouses/business/$businessId', data: payload);
    final data = (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
    return Warehouse.fromJson(data);
  }

  Future<Warehouse> getWarehouse({required int businessId, required int warehouseId}) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/warehouses/business/$businessId/$warehouseId');
    final data = (res.data?['data']?['item'] as Map<String, dynamic>? ?? <String, dynamic>{});
    return Warehouse.fromJson(data);
  }

  Future<Warehouse> updateWarehouse({required int businessId, required int warehouseId, required Map<String, dynamic> payload}) async {
    final res = await _api.put<Map<String, dynamic>>('/api/v1/warehouses/business/$businessId/$warehouseId', data: payload);
    final data = (res.data?['data'] as Map<String, dynamic>? ?? <String, dynamic>{});
    return Warehouse.fromJson(data);
  }

  Future<bool> deleteWarehouse({required int businessId, required int warehouseId}) async {
    final res = await _api.delete<Map<String, dynamic>>('/api/v1/warehouses/business/$businessId/$warehouseId');
    return res.statusCode == 200 && (res.data?['data']?['deleted'] == true);
  }

  Future<Map<String, dynamic>> createFromInvoice({
    required int businessId,
    required int invoiceId,
    Map<String, dynamic>? body,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/from-invoice/$invoiceId',
      data: body ?? const {},
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> postDoc({
    required int businessId,
    required int docId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/$docId/post',
      data: const {},
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> getDoc({
    required int businessId,
    required int docId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/$docId',
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> search({
    required int businessId,
    int page = 1,
    int limit = 20,
    Map<String, dynamic>? filters,
  }) async {
    final body = {
      'take': limit,
      'skip': (page - 1) * limit,
      ...?filters,
    };
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/search',
      data: body,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> createManual({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/create',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> updateDoc({
    required int businessId,
    required int docId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/$docId',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> updateLine({
    required int businessId,
    required int docId,
    required int lineId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/$docId/lines/$lineId',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<bool> deleteDoc({
    required int businessId,
    required int docId,
  }) async {
    final res = await _api.delete<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/$docId',
    );
    return res.statusCode == 200 && (res.data?['data']?['deleted'] == true);
  }

  Future<Map<String, dynamic>> cancelDoc({
    required int businessId,
    required int docId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/warehouse-docs/business/$businessId/$docId/cancel',
      data: const {},
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> getStockReport({
    required int businessId,
    Map<String, dynamic>? query,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/warehouses/business/$businessId/stock-report',
      data: query ?? const {},
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }
}


