import '../core/api_client.dart';

class BulkDefaultWarehouseService {
  final ApiClient _api;
  BulkDefaultWarehouseService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> preview({
    required int businessId,
    required List<int> productIds,
    required int? defaultWarehouseId,
    required String applyScope,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/products/business/$businessId/bulk-default-warehouse/preview',
      data: {
        'ids': productIds,
        'default_warehouse_id': defaultWarehouseId,
        'apply_scope': applyScope,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> apply({
    required int businessId,
    required List<int> productIds,
    required int? defaultWarehouseId,
    required String applyScope,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/products/business/$businessId/bulk-default-warehouse/apply',
      data: {
        'ids': productIds,
        'default_warehouse_id': defaultWarehouseId,
        'apply_scope': applyScope,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }
}


