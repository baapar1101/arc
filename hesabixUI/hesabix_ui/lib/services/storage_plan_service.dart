import '../core/api_client.dart';

class StoragePlanService {
  final ApiClient _api;
  StoragePlanService(this._api);

  /// لیست پلن‌های ذخیره‌سازی
  Future<List<Map<String, dynamic>>> listPlans({bool? onlyActive}) async {
    final query = <String, dynamic>{};
    if (onlyActive != null) {
      query['only_active'] = onlyActive;
    }
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/storage-plans',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'];
    if (data is List) {
      return data.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  /// دریافت جزئیات یک پلن
  Future<Map<String, dynamic>> getPlan(int planId) async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/storage-plans/$planId');
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  /// ایجاد پلن جدید
  Future<Map<String, dynamic>> createPlan(Map<String, dynamic> data) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/storage-plans',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  /// ویرایش پلن
  Future<Map<String, dynamic>> updatePlan(int planId, Map<String, dynamic> data) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/storage-plans/$planId',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  /// حذف/غیرفعال کردن پلن
  Future<Map<String, dynamic>> deletePlan(int planId) async {
    final res = await _api.delete<Map<String, dynamic>>('/api/v1/admin/storage-plans/$planId');
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }
}

