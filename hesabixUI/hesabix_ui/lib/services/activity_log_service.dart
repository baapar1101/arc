import '../core/api_client.dart';

class ActivityLogService {
  final ApiClient _api;
  
  ActivityLogService(this._api);

  /// دریافت لاگ‌های فعالیت یک کسب و کار
  Future<Map<String, dynamic>> getBusinessActivityLogs({
    required int businessId,
    String? category,
    String? entityType,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int perPage = 50,
  }) async {
    final query = <String, dynamic>{
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    
    if (category != null && category.isNotEmpty) {
      query['category'] = category;
    }
    if (entityType != null && entityType.isNotEmpty) {
      query['entity_type'] = entityType;
    }
    if (startDate != null) {
      query['start_date'] = startDate.toIso8601String();
    }
    if (endDate != null) {
      query['end_date'] = endDate.toIso8601String();
    }
    
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/activity-logs/business/$businessId',
      query: query,
    );
    
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
  }

  /// دریافت تاریخچه تغییرات یک موجودیت
  Future<Map<String, dynamic>> getEntityActivityLogs({
    required String entityType,
    required int entityId,
    int? businessId,
  }) async {
    final query = <String, dynamic>{};
    if (businessId != null) {
      query['business_id'] = businessId.toString();
    }
    
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/activity-logs/entity/$entityType/$entityId',
      query: query,
    );
    
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
  }

  /// دریافت لاگ‌های فعالیت کاربر جاری
  Future<Map<String, dynamic>> getMyActivityLogs({
    int? businessId,
    int page = 1,
    int perPage = 50,
  }) async {
    final query = <String, dynamic>{
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    
    if (businessId != null) {
      query['business_id'] = businessId.toString();
    }
    
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/activity-logs/user/me',
      query: query,
    );
    
    final body = res.data as Map<String, dynamic>;
    return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
  }
}

