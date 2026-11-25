import 'package:dio/dio.dart';

import '../core/api_client.dart';

class AdvancedProductionService {
  final ApiClient _api;

  AdvancedProductionService({ApiClient? apiClient})
    : _api = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> getSettings({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/advanced-production/business/$businessId/settings',
    );
    return _data(res);
  }

  Future<Map<String, dynamic>> updateSettings({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/advanced-production/business/$businessId/settings',
      data: payload,
    );
    return _data(res);
  }

  Future<List<Map<String, dynamic>>> listMaster({
    required int businessId,
    required String kind,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/advanced-production/business/$businessId/masters/$kind',
    );
    final data = _data(res);
    final items = data['items'];
    if (items is List) {
      return items.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> createMaster({
    required int businessId,
    required String kind,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/advanced-production/business/$businessId/masters/$kind',
      data: payload,
    );
    return _data(res);
  }

  Future<Map<String, dynamic>> getDashboard({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/advanced-production/business/$businessId/dashboard',
    );
    return _data(res);
  }

  Map<String, dynamic> _data(Response<Map<String, dynamic>> res) {
    final body = res.data;
    final data = body?['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }
}
