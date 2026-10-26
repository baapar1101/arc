import 'dart:convert';

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

  /// شناسه اشخاص برای کمپین/خروجی (همان فیلتر سگمنت و جستجو).
  Future<Map<String, dynamic>> listRfmPersonIds({
    required int businessId,
    String? segmentLabel,
    String? q,
    int limit = 5000,
  }) async {
    final query = <String, dynamic>{
      'limit': '$limit',
      if (segmentLabel != null && segmentLabel.trim().isNotEmpty) 'segment_label': segmentLabel.trim(),
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
    };
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/customer-club/business/$businessId/analytics/rfm/person-ids',
      query: query,
    );
    final body = res.data;
    if (body is Map<String, dynamic>) {
      return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    }
    return const {};
  }

  Future<List<Map<String, dynamic>>> listRewards({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/customer-club/business/$businessId/rewards');
    final body = res.data;
    final data = body?['data'];
    return data is Map && data['items'] is List
        ? (data['items'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> saveReward({required int businessId, required Map<String, dynamic> payload, int? rewardId}) async {
    final path = '/api/v1/customer-club/business/$businessId/rewards${rewardId == null ? '' : '/$rewardId'}';
    final res = rewardId == null
        ? await _api.post<Map<String, dynamic>>(path, data: payload)
        : await _api.put<Map<String, dynamic>>(path, data: payload);
    final body = res.data;
    return Map<String, dynamic>.from(body?['data'] as Map? ?? const {});
  }

  Future<List<Map<String, dynamic>>> listCampaigns({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/customer-club/business/$businessId/campaigns');
    final body = res.data;
    final data = body?['data'];
    return data is Map && data['items'] is List
        ? (data['items'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> saveCampaign({required int businessId, required Map<String, dynamic> payload, int? campaignId}) async {
    final path = '/api/v1/customer-club/business/$businessId/campaigns${campaignId == null ? '' : '/$campaignId'}';
    final res = campaignId == null
        ? await _api.post<Map<String, dynamic>>(path, data: payload)
        : await _api.put<Map<String, dynamic>>(path, data: payload);
    final body = res.data;
    return Map<String, dynamic>.from(body?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> previewSegment({required int businessId, required Map<String, dynamic> filters}) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/customer-club/business/$businessId/segments/preview',
      data: <String, dynamic>{'filters': filters, 'limit': 100},
    );
    final body = res.data;
    return Map<String, dynamic>.from(body?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> exportSegment({required int businessId, required Map<String, dynamic> filters}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/customer-club/business/$businessId/segments/export',
      query: <String, dynamic>{'filters': jsonEncode(filters)},
    );
    final body = res.data;
    return Map<String, dynamic>.from(body?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> runCampaign({required int businessId, required int campaignId}) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/customer-club/business/$businessId/campaigns/$campaignId/run',
      data: const <String, dynamic>{},
    );
    final body = res.data;
    return Map<String, dynamic>.from(body?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> getCampaignStats({required int businessId, required int campaignId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/customer-club/business/$businessId/campaigns/$campaignId/stats',
    );
    final body = res.data;
    return Map<String, dynamic>.from(body?['data'] as Map? ?? const {});
  }

  Future<List<Map<String, dynamic>>> listVouchers({required int businessId, int? personId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/customer-club/business/$businessId/vouchers',
      query: <String, dynamic>{if (personId != null) 'person_id': '$personId'},
    );
    final body = res.data;
    final data = body?['data'];
    return data is Map && data['items'] is List
        ? (data['items'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> redeemReward({required int businessId, required int personId, required int rewardId}) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/customer-club/business/$businessId/persons/$personId/rewards/$rewardId/redeem',
      data: const <String, dynamic>{},
    );
    final body = res.data;
    return Map<String, dynamic>.from(body?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> updateMemberConsent({required int businessId, required int personId, required Map<String, dynamic> payload}) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/customer-club/business/$businessId/persons/$personId/consent',
      data: payload,
    );
    final body = res.data;
    return Map<String, dynamic>.from(body?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> getMemberProfile({required int businessId, required int personId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/customer-club/business/$businessId/persons/$personId/profile',
    );
    final body = res.data;
    return Map<String, dynamic>.from(body?['data'] as Map? ?? const {});
  }
}
