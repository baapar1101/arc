import '../core/api_client.dart';

/// سرویس API افزونه کنترل اموال (`/api/v1/fixed-assets/...`).
class FixedAssetsService {
  final ApiClient _api;

  FixedAssetsService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> getSettings({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/fixed-assets/business/$businessId/settings',
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> updateSettings({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/fixed-assets/business/$businessId/settings',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> getDashboard({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/fixed-assets/business/$businessId/dashboard',
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> updateClass({
    required int businessId,
    required int classId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/fixed-assets/business/$businessId/classes/$classId',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<List<Map<String, dynamic>>> listClasses({
    required int businessId,
    bool includeInactive = false,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/fixed-assets/business/$businessId/classes',
      query: {'include_inactive': '$includeInactive'},
    );
    return _asMapList(_extractData(res.data)['items']);
  }

  Future<List<Map<String, dynamic>>> listLocations({
    required int businessId,
    bool includeInactive = false,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/fixed-assets/business/$businessId/locations',
      query: {'include_inactive': '$includeInactive'},
    );
    return _asMapList(_extractData(res.data)['items']);
  }

  Future<Map<String, dynamic>> createLocation({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/fixed-assets/business/$businessId/locations',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> listAssets({
    required int businessId,
    String? status,
    int? classId,
    String? search,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/fixed-assets/business/$businessId/assets',
      query: {
        if (status != null) 'status': status,
        if (classId != null) 'class_id': '$classId',
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> createAsset({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/fixed-assets/business/$businessId/assets',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> capitalizeAsset({
    required int businessId,
    required int assetId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/fixed-assets/business/$businessId/assets/$assetId/capitalize',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> listRuns({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/fixed-assets/business/$businessId/depreciation-runs',
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> createRun({
    required int businessId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/fixed-assets/business/$businessId/depreciation-runs',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> postRun({
    required int businessId,
    required int runId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/fixed-assets/business/$businessId/depreciation-runs/$runId/post',
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> setAssetIdle({
    required int businessId,
    required int assetId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/fixed-assets/business/$businessId/assets/$assetId/idle',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> resumeAsset({
    required int businessId,
    required int assetId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/fixed-assets/business/$businessId/assets/$assetId/resume',
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> disposeAsset({
    required int businessId,
    required int assetId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/fixed-assets/business/$businessId/assets/$assetId/dispose',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> postSubsequentExpenditure({
    required int businessId,
    required int assetId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/fixed-assets/business/$businessId/assets/$assetId/subsequent-expenditure',
      data: payload,
    );
    return _extractData(res.data);
  }

  Future<Map<String, dynamic>> changeEstimate({
    required int businessId,
    required int assetId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/fixed-assets/business/$businessId/assets/$assetId/estimate-change',
      data: payload,
    );
    return _extractData(res.data);
  }

  Map<String, dynamic> _extractData(Map<String, dynamic>? body) {
    if (body is Map<String, dynamic>) {
      return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    }
    return const {};
  }

  List<Map<String, dynamic>> _asMapList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
}
