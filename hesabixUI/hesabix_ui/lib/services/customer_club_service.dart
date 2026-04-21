import '../core/api_client.dart';

/// سرویس API باشگاه مشتریان (`/api/v1/customer-club/...`).
class CustomerClubService {
  final ApiClient _api;

  CustomerClubService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> getSettings({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/customer-club/business/$businessId/settings',
    );
    final body = res.data;
    if (body is Map<String, dynamic>) {
      return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    }
    return const {};
  }

  Future<Map<String, dynamic>> updateSettings({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/customer-club/business/$businessId/settings',
      data: payload,
    );
    final body = res.data;
    if (body is Map<String, dynamic>) {
      return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    }
    return const {};
  }

  Future<Map<String, dynamic>> getPersonBalance({
    required int businessId,
    required int personId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/customer-club/business/$businessId/persons/$personId/balance',
    );
    final body = res.data;
    if (body is Map<String, dynamic>) {
      return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    }
    return const {};
  }

  Future<Map<String, dynamic>> listLedger({
    required int businessId,
    int? personId,
    int limit = 50,
    int skip = 0,
  }) async {
    final query = <String, dynamic>{
      'limit': '$limit',
      'skip': '$skip',
      if (personId != null) 'person_id': '$personId',
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/customer-club/business/$businessId/ledger',
      query: query,
    );
    final body = res.data;
    if (body is Map<String, dynamic>) {
      return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    }
    return const {};
  }

  Future<Map<String, dynamic>> submitAdjustment({
    required int businessId,
    required int personId,
    required double deltaPoints,
    required String description,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/customer-club/business/$businessId/adjustments',
      data: <String, dynamic>{
        'person_id': personId,
        'delta_points': deltaPoints,
        'description': description,
      },
    );
    final body = res.data;
    if (body is Map<String, dynamic>) {
      return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    }
    return const {};
  }

  Future<Map<String, dynamic>> getRfmSummary({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/customer-club/business/$businessId/analytics/rfm/summary',
    );
    final body = res.data;
    if (body is Map<String, dynamic>) {
      return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    }
    return const {};
  }

  Future<Map<String, dynamic>> listRfmPersons({
    required int businessId,
    int skip = 0,
    int limit = 50,
    String? segmentLabel,
    String? q,
    String sort = 'monetary_total',
    String sortDir = 'desc',
  }) async {
    final query = <String, dynamic>{
      'skip': '$skip',
      'limit': '$limit',
      'sort': sort,
      'sort_dir': sortDir,
      if (segmentLabel != null && segmentLabel.trim().isNotEmpty) 'segment_label': segmentLabel.trim(),
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/customer-club/business/$businessId/analytics/rfm/persons',
      query: query,
    );
    final body = res.data;
    if (body is Map<String, dynamic>) {
      return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    }
    return const {};
  }

  Future<Map<String, dynamic>> recalculateRfm({required int businessId}) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/customer-club/business/$businessId/analytics/rfm/recalculate',
      data: const <String, dynamic>{},
    );
    final body = res.data;
    if (body is Map<String, dynamic>) {
      return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    }
    return const {};
  }
}
