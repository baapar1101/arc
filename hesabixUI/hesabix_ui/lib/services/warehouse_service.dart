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
}


