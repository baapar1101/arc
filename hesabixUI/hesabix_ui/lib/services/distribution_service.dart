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

  Future<Map<String, dynamic>> updateTerritory({
    required int businessId,
    required int territoryId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/territories/$territoryId',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<void> deleteTerritory({
    required int businessId,
    required int territoryId,
  }) async {
    await _api.delete<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/territories/$territoryId',
    );
  }

  Future<Map<String, dynamic>> updateRoute({
    required int businessId,
    required int routeId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/routes/$routeId',
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

  Future<void> deleteStop({
    required int businessId,
    required int routeId,
    required int stopId,
  }) async {
    await _api.delete<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/routes/$routeId/stops/$stopId',
    );
  }

  Future<void> deleteAssignment({
    required int businessId,
    required int assignmentId,
  }) async {
    await _api.delete<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/assignments/$assignmentId',
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

  Future<Map<String, dynamic>> updateVan({
    required int businessId,
    required int vanId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/vans/$vanId',
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

  Future<Map<String, dynamic>> getVanStock({
    required int businessId,
    required int vanId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/vans/$vanId/stock',
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

  Future<Map<String, dynamic>> unloadVan({
    required int businessId,
    required int vanId,
    required List<Map<String, dynamic>> lines,
    int? destWarehouseId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/vans/$vanId/unload',
      data: <String, dynamic>{
        'lines': lines,
        if (destWarehouseId != null) 'dest_warehouse_id': destWarehouseId,
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
    bool persist = false,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/routes/$routeId/optimize',
      query: <String, dynamic>{
        if (planDate != null) 'plan_date': planDate,
        if (startLatitude != null) 'start_latitude': '$startLatitude',
        if (startLongitude != null) 'start_longitude': '$startLongitude',
        'persist': persist ? 'true' : 'false',
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

  Future<Map<String, dynamic>> reportLiveLocation({
    required int businessId,
    required double latitude,
    required double longitude,
    int? visitId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/live-location',
      data: <String, dynamic>{
        'latitude': latitude,
        'longitude': longitude,
        if (visitId != null) 'visit_id': visitId,
      },
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> getUserDayTrail({
    required int businessId,
    required int userId,
    String? day,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/users/$userId/day-trail',
      query: <String, dynamic>{if (day != null) 'day': day},
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


  // ─── فاز ۴ ───────────────────────────────────────────────────────────────

  Future<List<dynamic>> listTargets({
    required int businessId,
    int? userId,
    String? periodType,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/targets',
      query: <String, dynamic>{
        if (userId != null) 'user_id': '$userId',
        if (periodType != null) 'period_type': periodType,
      },
    );
    final items = _dataMap(res.data)['items'];
    return items is List ? items : const [];
  }

  Future<Map<String, dynamic>> upsertTarget({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/targets',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<void> deleteTarget({
    required int businessId,
    required int targetId,
  }) async {
    await _api.delete<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/targets/$targetId',
    );
  }

  Future<Map<String, dynamic>> previewSettlement({
    required int businessId,
    String? settlementDate,
    int? targetUserId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/settlements/preview',
      query: <String, dynamic>{
        if (settlementDate != null) 'settlement_date': settlementDate,
        if (targetUserId != null) 'target_user_id': '$targetUserId',
      },
    );
    return _dataMap(res.data);
  }

  Future<List<dynamic>> listSettlements({
    required int businessId,
    String? fromDate,
    String? toDate,
    int? targetUserId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/settlements',
      query: <String, dynamic>{
        if (fromDate != null) 'from_date': fromDate,
        if (toDate != null) 'to_date': toDate,
        if (targetUserId != null) 'target_user_id': '$targetUserId',
      },
    );
    final items = _dataMap(res.data)['items'];
    return items is List ? items : const [];
  }

  Future<Map<String, dynamic>> upsertSettlement({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/settlements',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> confirmSettlement({
    required int businessId,
    required int settlementId,
    bool createReceipt = false,
    int? cashRegisterId,
    int? bankId,
    bool allowVariance = false,
    List<Map<String, dynamic>>? invoiceAllocations,
    List<Map<String, dynamic>>? chequeItems,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/settlements/$settlementId/confirm',
      data: <String, dynamic>{
        'create_receipt': createReceipt,
        if (cashRegisterId != null) 'cash_register_id': cashRegisterId,
        if (bankId != null) 'bank_id': bankId,
        'allow_variance': allowVariance,
        if (invoiceAllocations != null) 'invoice_allocations': invoiceAllocations,
        if (chequeItems != null) 'cheque_items': chequeItems,
      },
    );
    return _dataMap(res.data);
  }

  Future<List<dynamic>> listPersonInvoices({
    required int businessId,
    required int personId,
    int limit = 20,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/persons/$personId/invoices',
      query: <String, dynamic>{'limit': '$limit'},
    );
    final items = _dataMap(res.data)['items'];
    return items is List ? items : const [];
  }

  Future<Map<String, dynamic>> getPersonCreditSummary({
    required int businessId,
    required int personId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/persons/$personId/credit-summary',
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> visitHeartbeat({
    required int businessId,
    required int visitId,
    required double latitude,
    required double longitude,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/visits/$visitId/heartbeat',
      data: {'latitude': latitude, 'longitude': longitude},
    );
    return _dataMap(res.data);
  }

  Future<List<int>> downloadDailyPlanPdf({
    required int businessId,
    String? planDate,
    int? targetUserId,
  }) {
    return _api.downloadPdf(
      '/api/v1/distribution/business/$businessId/daily-plan/pdf',
      query: <String, dynamic>{
        if (planDate != null) 'plan_date': planDate,
        if (targetUserId != null) 'target_user_id': '$targetUserId',
      },
    );
  }

  Future<List<int>> downloadVanLoadingListPdf({
    required int businessId,
    required int vanId,
  }) {
    return _api.downloadPdf(
      '/api/v1/distribution/business/$businessId/vans/$vanId/loading-list/pdf',
    );
  }

  Future<List<int>> downloadSettlementPdf({
    required int businessId,
    required int settlementId,
  }) {
    return _api.downloadPdf(
      '/api/v1/distribution/business/$businessId/settlements/$settlementId/pdf',
    );
  }

  // --- Commercial ---

  Future<List<dynamic>> listOrders({
    required int businessId,
    String? status,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/orders',
      query: <String, dynamic>{if (status != null) 'status': status},
    );
    final d = res.data?['data'];
    return d is List ? d : const [];
  }

  Future<Map<String, dynamic>> createOrder({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/orders',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> confirmOrder({
    required int businessId,
    required int orderId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/orders/$orderId/confirm',
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> getSuggestedOrder({
    required int businessId,
    required int personId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/persons/$personId/suggested-order',
    );
    return _dataMap(res.data);
  }

  Future<List<dynamic>> listPromotions({required int businessId, bool all = false}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/promotions',
      query: <String, dynamic>{if (all) 'all': 'true'},
    );
    final d = res.data?['data'];
    return d is List ? d : const [];
  }

  Future<Map<String, dynamic>> upsertPromotion({
    required int businessId,
    required Map<String, dynamic> payload,
    int? promoId,
  }) async {
    final res = promoId == null
        ? await _api.post<Map<String, dynamic>>(
            '/api/v1/distribution/business/$businessId/promotions',
            data: payload,
          )
        : await _api.put<Map<String, dynamic>>(
            '/api/v1/distribution/business/$businessId/promotions/$promoId',
            data: payload,
          );
    return _dataMap(res.data);
  }

  Future<void> deletePromotion({required int businessId, required int promoId}) async {
    await _api.delete('/api/v1/distribution/business/$businessId/promotions/$promoId');
  }

  Future<List<dynamic>> listDeliveryTrips({required int businessId, String? tripDate}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/delivery-trips',
      query: <String, dynamic>{if (tripDate != null) 'trip_date': tripDate},
    );
    final d = res.data?['data'];
    return d is List ? d : const [];
  }

  Future<Map<String, dynamic>> createDeliveryTrip({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/delivery-trips',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> startDeliveryTrip({
    required int businessId,
    required int tripId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/delivery-trips/$tripId/start',
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> completeDeliveryStop({
    required int businessId,
    required int stopId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/delivery-stops/$stopId/complete',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<List<dynamic>> listLoadPlans({required int businessId, String? planDate}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/load-plans',
      query: <String, dynamic>{if (planDate != null) 'plan_date': planDate},
    );
    final d = res.data?['data'];
    return d is List ? d : const [];
  }

  Future<Map<String, dynamic>> createLoadPlan({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/load-plans',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> confirmLoadPlan({
    required int businessId,
    required int planId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/load-plans/$planId/confirm',
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> getCommercialKpi({
    required int businessId,
    required String fromDate,
    required String toDate,
    int? targetUserId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/reports/commercial-kpi',
      query: <String, dynamic>{
        'from_date': fromDate,
        'to_date': toDate,
        if (targetUserId != null) 'target_user_id': '$targetUserId',
      },
    );
    return _dataMap(res.data);
  }

  Future<List<dynamic>> listCommissionRules({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/commission-rules',
    );
    final d = res.data?['data'];
    return d is List ? d : const [];
  }

  Future<Map<String, dynamic>> upsertCommissionRule({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/commission-rules',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<Map<String, dynamic>> computeCommissionRun({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/commission-runs',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<List<dynamic>> listCommissionRuns({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/commission-runs',
    );
    final d = res.data?['data'];
    return d is List ? d : const [];
  }

  Future<Map<String, dynamic>> createShelfAudit({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/shelf-audits',
      data: payload,
    );
    return _dataMap(res.data);
  }

  Future<List<dynamic>> listShelfAudits({
    required int businessId,
    int? personId,
    int? visitId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/shelf-audits',
      query: <String, dynamic>{
        if (personId != null) 'person_id': '$personId',
        if (visitId != null) 'visit_id': '$visitId',
      },
    );
    final d = res.data?['data'];
    return d is List ? d : const [];
  }

  Future<List<dynamic>> listCustomerAssets({
    required int businessId,
    int? personId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/distribution/business/$businessId/customer-assets',
      query: <String, dynamic>{if (personId != null) 'person_id': '$personId'},
    );
    final d = res.data?['data'];
    return d is List ? d : const [];
  }

  Future<Map<String, dynamic>> upsertCustomerAsset({
    required int businessId,
    required Map<String, dynamic> payload,
    int? assetId,
  }) async {
    final res = assetId == null
        ? await _api.post<Map<String, dynamic>>(
            '/api/v1/distribution/business/$businessId/customer-assets',
            data: payload,
          )
        : await _api.put<Map<String, dynamic>>(
            '/api/v1/distribution/business/$businessId/customer-assets/$assetId',
            data: payload,
          );
    return _dataMap(res.data);
  }
}
