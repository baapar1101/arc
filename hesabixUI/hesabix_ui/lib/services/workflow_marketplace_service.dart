import 'package:hesabix_ui/core/api_client.dart';

/// مخزن ورک‌فلو (انتشار و نصب)
class WorkflowMarketplaceService {
  final ApiClient _apiClient;

  WorkflowMarketplaceService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  Future<Map<String, dynamic>> listPackages({
    int skip = 0,
    int take = 20,
    String? search,
    String? tag,
  }) async {
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/workflows/marketplace/packages',
      query: {
        'skip': skip,
        'take': take,
        if (search != null && search.isNotEmpty) 'search': search,
        if (tag != null && tag.isNotEmpty) 'tag': tag,
      },
    );
    return _asMap(res.data?['data']);
  }

  Future<Map<String, dynamic>> getPackage(int packageId) async {
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/workflows/marketplace/packages/$packageId',
    );
    return _asMap(res.data?['data']);
  }

  Future<Map<String, dynamic>> listMyPackages({
    required int businessId,
    int skip = 0,
    int take = 20,
  }) async {
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/businesses/$businessId/workflows/marketplace/my-packages',
      query: {'skip': skip, 'take': take},
    );
    return _asMap(res.data?['data']);
  }

  Future<Map<String, dynamic>> publish({
    required int businessId,
    required int workflowId,
    required String title,
    String? shortDescription,
    String? longDescription,
    List<String>? tags,
    String versionLabel = '1.0.0',
    String? changelog,
  }) async {
    final res = await _apiClient.post<Map<String, dynamic>>(
      '/businesses/$businessId/workflows/marketplace/publish',
      data: {
        'workflow_id': workflowId,
        'title': title,
        'short_description': shortDescription,
        'long_description': longDescription,
        'tags': tags ?? const <String>[],
        'version_label': versionLabel,
        'changelog': changelog,
      },
    );
    return _asMap(res.data?['data']);
  }

  Future<Map<String, dynamic>> install({
    required int businessId,
    required int packageId,
    String? name,
  }) async {
    final res = await _apiClient.post<Map<String, dynamic>>(
      '/businesses/$businessId/workflows/marketplace/install',
      data: {
        'package_id': packageId,
        if (name != null && name.isNotEmpty) 'name': name,
      },
    );
    return _asMap(res.data?['data']);
  }

  /// جزئیات بستهٔ منتشرشده توسط خود کاربر (شامل بسته‌های خارج از انتشار)
  Future<Map<String, dynamic>> getMyPackage({
    required int businessId,
    required int packageId,
  }) async {
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/businesses/$businessId/workflows/marketplace/my-packages/$packageId',
    );
    return _asMap(res.data?['data']);
  }

  Future<Map<String, dynamic>> unpublish({
    required int businessId,
    required int packageId,
  }) async {
    final res = await _apiClient.post<Map<String, dynamic>>(
      '/businesses/$businessId/workflows/marketplace/my-packages/$packageId/unpublish',
      data: const <String, dynamic>{},
    );
    return _asMap(res.data?['data']);
  }

  Future<Map<String, dynamic>> republish({
    required int businessId,
    required int packageId,
  }) async {
    final res = await _apiClient.post<Map<String, dynamic>>(
      '/businesses/$businessId/workflows/marketplace/my-packages/$packageId/republish',
      data: const <String, dynamic>{},
    );
    return _asMap(res.data?['data']);
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return <String, dynamic>{};
  }
}
