import '../core/api_client.dart';

/// API افزونه پخش مویرگی (`/api/v1/distribution/...`).
class DistributionService {
  final ApiClient _api;

  DistributionService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Map<String, dynamic> _dataMap(Map<String, dynamic>? body) {
    if (body == null) return const {};
    final d = body['data'];
    if (d is Map) return Map<String, dynamic>.from(d);
    return const {};
  }

  Future<Map<String, dynamic>> getSummary({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/summary',
    );
    return _dataMap(res.data);
  }

  Future<List<dynamic>> listTerritories({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/territories',
    );
    final m = _dataMap(res.data);
    final items = m['items'];
    if (items is List) return items;
    return const [];
  }

  Future<List<dynamic>> listRoutes({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/routes',
    );
    final m = _dataMap(res.data);
    final items = m['items'];
    if (items is List) return items;
    return const [];
  }

  Future<List<dynamic>> listRouteStops({required int businessId, required int routeId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/routes/$routeId/stops',
    );
    final m = _dataMap(res.data);
    final items = m['items'];
    if (items is List) return items;
    return const [];
  }

  Future<Map<String, dynamic>> getDailyPlan({
    required int businessId,
    String? planDate,
    int? targetUserId,
  }) async {
    final query = <String, dynamic>{
      if (planDate != null) 'plan_date': planDate,
      if (targetUserId != null) 'target_user_id': '$targetUserId',
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/daily-plan',
      query: query,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> startVisit({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/visits/start',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> completeVisit({
    required int businessId,
    required int visitId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/visits/$visitId/complete',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> cancelVisit({
    required int businessId,
    required int visitId,
    String? reason,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/visits/$visitId/cancel',
      data: <String, dynamic>{if (reason != null) 'reason': reason},
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> listVisits({
    required int businessId,
    String? fromDate,
    String? toDate,
    int limit = 50,
    int skip = 0,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/visits',
      query: <String, dynamic>{
        'limit': '$limit',
        'skip': '$skip',
        if (fromDate != null) 'from_date': fromDate,
        if (toDate != null) 'to_date': toDate,
      },
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> createTerritory({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/territories',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<void> deleteRoute({
    required int businessId,
    required int routeId,
  }) async {
    await _api.delete<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/routes/$routeId',
    );
  }

  Future<Map<String, dynamic>> createRoute({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/routes',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> upsertStop({
    required int businessId,
    required int routeId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/routes/$routeId/stops',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> createAssignment({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/assignments',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> createReturnRequest({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/return-requests',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<List<dynamic>> listReturnRequests({
    required int businessId,
    String? status,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/return-requests',
      query: <String, dynamic>{if (status != null) 'status': status},
    );
    final m = _dataMap(res.data);
    final items = m['items'];
    if (items is List) return items;
    return const [];
  }

  Future<List<dynamic>> listAssignments({
    required int businessId,
    int? routeId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/assignments',
      query: <String, dynamic>{
        if (routeId != null) 'route_id': '$routeId',
      },
    );
    final m = _dataMap(res.data);
    final items = m['items'];
    if (items is List) return items;
    return const [];
  }

  Future<Map<String, dynamic>> resolveReturnRequest({
    required int businessId,
    required int requestId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/return-requests/$requestId/resolve',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> getDistributionSettings({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/settings',
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> updateDistributionSettings({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/settings',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> getReportsDashboard({
    required int businessId,
    required String fromDate,
    required String toDate,
    int? targetUserId,
  }) async {
    final q = <String, dynamic>{
      'from_date': fromDate,
      'to_date': toDate,
      if (targetUserId != null) 'target_user_id': '$targetUserId',
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/reports/dashboard',
      query: q,
    );
    return _dataMap(res.data);
  }

  Future<List<dynamic>> listVans({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/distribution/business/$businessId/vans');
    final m = _dataMap(res.data);
    final items = m['items'];
    return items is List ? items : const [];
  }

  Future<Map<String, dynamic>> createVan({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/vans',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> getMyVanStock({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/vans/my-stock',
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> loadVan({
    required int businessId,
    required int vanId,
    required List<Map<String, dynamic>> lines,
    int? sourceWarehouseId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/vans/$vanId/load',
      data: <String, dynamic>{
        'lines': lines,
        if (sourceWarehouseId != null) 'source_warehouse_id': sourceWarehouseId,
      },
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> optimizeRoute({
    required int businessId,
    required int routeId,
    String? planDate,
    double? startLatitude,
    double? startLongitude,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/routes/$routeId/optimize',
      query: <String, dynamic>{
        if (planDate != null) 'plan_date': planDate,
        if (startLatitude != null) 'start_latitude': '$startLatitude',
        if (startLongitude != null) 'start_longitude': '$startLongitude',
      },
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> getTeamMap({
    required int businessId,
    String? planDate,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/reports/team-map',
      query: <String, dynamic>{if (planDate != null) 'plan_date': planDate},
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> syncOffline({
    required int businessId,
    required String clientBatchId,
    required List<Map<String, dynamic>> actions,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/sync-offline',
      data: <String, dynamic>{
        'client_batch_id': clientBatchId,
        'actions': actions,
      },
    );
    return _dataMap(res.data);
  }

  Future<void> setPersonLocation({
    required int businessId,
    required int personId,
    required double latitude,
    required double longitude,
  }) async {
    await _api.put<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/persons/$personId/location',
      data: <String, dynamic>{'latitude': latitude, 'longitude': longitude},
    );
  }
}