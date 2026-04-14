import '../core/api_client.dart';

class AdminScriptsService {
  final ApiClient _api;
  AdminScriptsService(this._api);

  Future<List<Map<String, dynamic>>> listScripts() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/scripts');
    final raw = (res.data?['data'] as Map?)?['items'] as List? ?? const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createRun({
    required String scriptKey,
    required bool dryRun,
    required Map<String, dynamic> params,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/scripts/$scriptKey/runs',
      data: {
        'dry_run': dryRun,
        'params': params,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> listRuns({
    String? scriptKey,
    String? status,
    int take = 50,
    int skip = 0,
  }) async {
    final query = <String, dynamic>{
      'take': take,
      'skip': skip,
      if (scriptKey != null && scriptKey.isNotEmpty) 'script_key': scriptKey,
      if (status != null && status.isNotEmpty) 'status': status,
    };
    final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/scripts/runs', query: query);
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> getRunDetails(int runId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/scripts/runs/$runId');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> cancelRun(int runId) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/admin/scripts/runs/$runId/cancel');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }
}

