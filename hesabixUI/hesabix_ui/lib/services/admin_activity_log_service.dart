import '../core/api_client.dart';

/// سرویس مخصوص پنل سوپرادمین برای مشاهده‌ی لاگ فعالیت همه‌ی کسب‌وکارها.
///
/// endpoint اصلی توسط [DataTableWidget] فراخوانی می‌شود و این سرویس
/// فقط برای autocomplete های کنار جدول و گزینه‌های فیلتر استفاده می‌شود.
class AdminActivityLogService {
  AdminActivityLogService(this._api);

  final ApiClient _api;

  /// جستجوی کسب‌وکارها برای dropdown autocomplete.
  Future<List<Map<String, dynamic>>> searchBusinesses({
    String? query,
    int limit = 20,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/activity-logs/filters/businesses',
      query: <String, dynamic>{
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        'limit': limit.toString(),
      },
    );
    return _extractItems(res.data);
  }

  /// جستجوی کاربران؛ اگر [businessId] داده شود، فقط اعضای آن کسب‌وکار.
  Future<List<Map<String, dynamic>>> searchUsers({
    String? query,
    int? businessId,
    int limit = 20,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/activity-logs/filters/users',
      query: <String, dynamic>{
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        if (businessId != null) 'business_id': businessId.toString(),
        'limit': limit.toString(),
      },
    );
    return _extractItems(res.data);
  }

  /// لیست categoryها/actionها/entity_typeها برای dropdownها.
  Future<Map<String, List<String>>> getFilterOptions() async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/activity-logs/filters/options',
    );
    final body = res.data ?? const <String, dynamic>{};
    final data = Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    return <String, List<String>>{
      'categories': _toStringList(data['categories']),
      'actions': _toStringList(data['actions']),
      'entity_types': _toStringList(data['entity_types']),
    };
  }

  /// دریافت جزئیات یک رکورد لاگ (شامل before_data/after_data/extra_info).
  Future<Map<String, dynamic>> getLogDetail(int logId) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/activity-logs/$logId',
    );
    final body = res.data ?? const <String, dynamic>{};
    return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
  }

  static List<Map<String, dynamic>> _extractItems(Map<String, dynamic>? body) {
    if (body == null) return const [];
    final data = Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    final items = (data['items'] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  static List<String> _toStringList(dynamic value) {
    if (value is! List) return const [];
    return value.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList();
  }
}
