import '../core/api_client.dart';

class MarketplaceService {
  final ApiClient _api;
  MarketplaceService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  Future<List<Map<String, dynamic>>> listPlugins() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/marketplace/plugins');
    final body = res.data;
    final items = (body is Map<String, dynamic>) ? body['data'] : body;
    if (items is List) {
      return items.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> purchase({
    required int businessId,
    required int pluginId,
    required int planId,
    int quantity = 1,
  }) async {
    final payload = <String, dynamic>{
      'plugin_id': pluginId,
      'plan_id': planId,
      'quantity': quantity,
    };
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/marketplace/business/$businessId/purchase',
      data: payload,
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> listOrders({
    required int businessId,
    int page = 1,
    int limit = 20,
  }) async {
    final skip = (page - 1) * limit;
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/marketplace/business/$businessId/orders',
      query: {
        'limit': '$limit',
        'skip': '$skip',
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  Future<Map<String, dynamic>> listInvoices({
    required int businessId,
    int page = 1,
    int limit = 20,
  }) async {
    final skip = (page - 1) * limit;
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/marketplace/business/$businessId/invoices',
      query: {
        'limit': '$limit',
        'skip': '$skip',
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  /// لیست افزونه‌های خریداری شده کسب‌وکار
  Future<List<Map<String, dynamic>>> listBusinessPlugins({
    required int businessId,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/marketplace/business/$businessId/plugins',
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'];
    if (data is List) {
      return data.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  /// شروع دوره trial برای افزونه
  Future<Map<String, dynamic>> startTrial({
    required int businessId,
    required int pluginId,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/marketplace/business/$businessId/plugins/$pluginId/start-trial',
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  // ========== Admin Functions ==========

  /// همگام‌سازی افزونه‌ها و پلن‌های پیش‌فرض سیستم (ادمین)
  Future<Map<String, dynamic>> syncDefaultPlugins() async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/marketplace/plugins/sync-defaults',
    );
    return Map<String, dynamic>.from(res.data?['data'] ?? const {});
  }

  /// لیست تمام افزونه‌ها (برای ادمین)
  Future<List<Map<String, dynamic>>> listAllPlugins({bool? onlyActive}) async {
    final query = <String, dynamic>{};
    if (onlyActive != null) {
      query['only_active'] = onlyActive;
    }
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/marketplace/plugins',
      query: query,
    );
    final body = res.data as Map<String, dynamic>;
    final data = body['data'];
    if (data is List) {
      return data.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const <Map<String, dynamic>>[];
  }

  /// ایجاد افزونه جدید
  Future<Map<String, dynamic>> createPlugin(Map<String, dynamic> data) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/marketplace/plugins',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  /// ویرایش افزونه
  Future<Map<String, dynamic>> updatePlugin(int pluginId, Map<String, dynamic> data) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/marketplace/plugins/$pluginId',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  /// حذف افزونه
  Future<Map<String, dynamic>> deletePlugin(int pluginId) async {
    final res = await _api.delete<Map<String, dynamic>>(
      '/api/v1/admin/marketplace/plugins/$pluginId',
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  /// ایجاد پلن برای افزونه
  Future<Map<String, dynamic>> createPluginPlan(int pluginId, Map<String, dynamic> data) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/marketplace/plugins/$pluginId/plans',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  /// ویرایش پلن
  Future<Map<String, dynamic>> updatePluginPlan(int planId, Map<String, dynamic> data) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/marketplace/plans/$planId',
      data: data,
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  /// حذف پلن
  Future<Map<String, dynamic>> deletePluginPlan(int planId) async {
    final res = await _api.delete<Map<String, dynamic>>(
      '/api/v1/admin/marketplace/plans/$planId',
    );
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map);
  }
}


