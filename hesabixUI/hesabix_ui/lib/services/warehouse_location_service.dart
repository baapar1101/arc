import '../core/api_client.dart';

/// چیدمان مکانی انبار (سلسله‌مراتب محل‌ها و قرارگیری کالا).
class WarehouseLocationService {
  final ApiClient _api;
  WarehouseLocationService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> fetchLocationsTree({
    required int businessId,
    required int warehouseId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/warehouses/business/$businessId/$warehouseId/locations',
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> createLocation({
    required int businessId,
    required int warehouseId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/warehouses/business/$businessId/$warehouseId/locations',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> updateLocation({
    required int businessId,
    required int warehouseId,
    required int locationId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/warehouses/business/$businessId/$warehouseId/locations/$locationId',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<bool> deleteLocation({
    required int businessId,
    required int warehouseId,
    required int locationId,
  }) async {
    final res = await _api.delete<Map<String, dynamic>>(
      '/api/v1/warehouses/business/$businessId/$warehouseId/locations/$locationId',
    );
    return res.statusCode == 200 && (res.data?['data']?['deleted'] == true);
  }

  Future<Map<String, dynamic>> listPlacements({
    required int businessId,
    required int warehouseId,
    int? productId,
    int? locationId,
  }) async {
    final q = <String, dynamic>{};
    if (productId != null) q['product_id'] = productId;
    if (locationId != null) q['location_id'] = locationId;
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/warehouses/business/$businessId/$warehouseId/placements',
      query: q.isEmpty ? null : q,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> createPlacement({
    required int businessId,
    required int warehouseId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/warehouses/business/$businessId/$warehouseId/placements',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> updatePlacement({
    required int businessId,
    required int warehouseId,
    required int placementId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/warehouses/business/$businessId/$warehouseId/placements/$placementId',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> fetchPlacementReconciliation({
    required int businessId,
    required int warehouseId,
    String? asOfDate,
  }) async {
    final q = <String, dynamic>{};
    if (asOfDate != null && asOfDate.isNotEmpty) q['as_of_date'] = asOfDate;
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/warehouses/business/$businessId/$warehouseId/placement-reconciliation',
      query: q.isEmpty ? null : q,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<bool> deletePlacement({
    required int businessId,
    required int warehouseId,
    required int placementId,
  }) async {
    final res = await _api.delete<Map<String, dynamic>>(
      '/api/v1/warehouses/business/$businessId/$warehouseId/placements/$placementId',
    );
    return res.statusCode == 200 && (res.data?['data']?['deleted'] == true);
  }
}
