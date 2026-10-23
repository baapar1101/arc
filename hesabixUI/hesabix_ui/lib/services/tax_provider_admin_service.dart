import 'package:dio/dio.dart';

import '../core/api_client.dart';

class TaxProviderAdminService {
  final ApiClient _api;

  TaxProviderAdminService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> getFanavaSettings() async {
    final response = await _api.get<Map<String, dynamic>>('/api/v1/admin/tax-providers/fanava');
    return Map<String, dynamic>.from(response.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> saveFanavaSettings(Map<String, dynamic> data) async {
    final response = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/tax-providers/fanava',
      data: data,
    );
    return Map<String, dynamic>.from(response.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> testFanavaConnection() async {
    final response = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/tax-providers/fanava/test-connection',
    );
    return Map<String, dynamic>.from(response.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> getMotamedAsaSettings() async {
    final response = await _api.get<Map<String, dynamic>>('/api/v1/admin/tax-providers/motamed-asa');
    return Map<String, dynamic>.from(response.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> saveMotamedAsaSettings(Map<String, dynamic> data) async {
    final response = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/tax-providers/motamed-asa',
      data: data,
    );
    return Map<String, dynamic>.from(response.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> testMotamedAsaConnection() async {
    final response = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/tax-providers/motamed-asa/test-connection',
    );
    return Map<String, dynamic>.from(response.data?['data'] as Map? ?? const {});
  }
}
