import '../core/api_client.dart';

class SepidarImportService {
  final ApiClient _api;
  SepidarImportService({ApiClient? apiClient})
    : _api = apiClient ?? ApiClient();

  Map<String, dynamic> _data(Map<String, dynamic>? body) => body?['data'] is Map
      ? Map<String, dynamic>.from(body!['data'] as Map)
      : <String, dynamic>{};

  Future<Map<String, dynamic>> settings(int businessId) async => _data(
    (await _api.get<Map<String, dynamic>>(
      '/api/v1/sepidar-import/business/$businessId/settings',
    )).data,
  );
  Future<Map<String, dynamic>> coverage(int businessId) async => _data(
    (await _api.get<Map<String, dynamic>>(
      '/api/v1/sepidar-import/business/$businessId/plugin-coverage',
    )).data,
  );
  Future<Map<String, dynamic>> save(
    int businessId,
    Map<String, dynamic> data,
  ) async => _data(
    (await _api.put<Map<String, dynamic>>(
      '/api/v1/sepidar-import/business/$businessId/settings',
      data: data,
    )).data,
  );
  Future<Map<String, dynamic>> test(int businessId) async => _data(
    (await _api.post<Map<String, dynamic>>(
      '/api/v1/sepidar-import/business/$businessId/test',
    )).data,
  );
  Future<Map<String, dynamic>> sync(int businessId) async => _data(
    (await _api.post<Map<String, dynamic>>(
      '/api/v1/sepidar-import/business/$businessId/sync',
    )).data,
  );
  Future<List<Map<String, dynamic>>> runs(int businessId) async {
    final data = _data(
      (await _api.get<Map<String, dynamic>>(
        '/api/v1/sepidar-import/business/$businessId/runs',
      )).data,
    );
    return (data['items'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}
