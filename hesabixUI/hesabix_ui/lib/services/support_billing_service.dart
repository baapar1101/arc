import '../core/api_client.dart';

class SupportBillingService {
  final ApiClient _api;
  SupportBillingService(this._api);

  Future<Map<String, dynamic>> getEntitlement() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/support/billing/entitlement');
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map? ?? {});
  }

  Future<List<Map<String, dynamic>>> listPlans() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/support/billing/plans');
    final body = res.data as Map<String, dynamic>;
    final data = body['data'];
    if (data is Map && data['items'] is List) {
      return (data['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>?> getSubscription() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/support/billing/subscription');
    final body = res.data as Map<String, dynamic>;
    final data = body['data'];
    if (data == null) return null;
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> listInvoices({int limit = 50, int offset = 0}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/support/billing/invoices',
      query: {'limit': limit, 'offset': offset},
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map? ?? {});
  }

  Future<List<Map<String, dynamic>>> listGateways() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/support/billing/gateways');
    final body = res.data as Map<String, dynamic>;
    final data = body['data'];
    if (data is Map && data['items'] is List) {
      return (data['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> checkout({
    required int planId,
    int? gatewayId,
    String source = 'app',
    String? clientReturnPath,
  }) async {
    final payload = <String, dynamic>{
      'plan_id': planId,
      'source': source,
      'client_return_path': clientReturnPath ?? '/user/profile/support/billing',
    };
    if (gatewayId != null) payload['gateway_id'] = gatewayId;
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/support/billing/checkout',
      data: payload,
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map? ?? {});
  }
}

class AdminSupportBillingService {
  final ApiClient _api;
  AdminSupportBillingService(this._api);

  Future<List<Map<String, dynamic>>> listPlans({bool? onlyActive}) async {
    final query = <String, dynamic>{};
    if (onlyActive != null) query['only_active'] = onlyActive;
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/support-billing/plans',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'];
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> createPlan(Map<String, dynamic> data) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/support-billing/plans',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> updatePlan(int planId, Map<String, dynamic> data) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/support-billing/plans/$planId',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  Future<Map<String, dynamic>> deletePlan(int planId) async {
    final res = await _api.delete<Map<String, dynamic>>(
      '/api/v1/admin/support-billing/plans/$planId',
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map? ?? {});
  }

  Future<Map<String, dynamic>> listInvoices({
    String? status,
    int? userId,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    final query = <String, dynamic>{'limit': limit, 'offset': offset};
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (userId != null) query['user_id'] = userId;
    if (search != null && search.isNotEmpty) query['search'] = search;
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/support-billing/invoices',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map? ?? {});
  }

  Future<Map<String, dynamic>> getStats({String? dateFrom, String? dateTo}) async {
    final query = <String, dynamic>{};
    if (dateFrom != null) query['date_from'] = dateFrom;
    if (dateTo != null) query['date_to'] = dateTo;
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/support-billing/stats',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map? ?? {});
  }

  Future<Map<String, dynamic>> voidInvoice(int invoiceId) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/support-billing/invoices/$invoiceId/void',
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }
}
