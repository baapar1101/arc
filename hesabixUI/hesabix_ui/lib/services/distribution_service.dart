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
}