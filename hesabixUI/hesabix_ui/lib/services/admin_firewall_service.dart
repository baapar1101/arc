import '../core/api_client.dart';

/// API مدیریت فایروال داخلی (فقط مدیر سیستم).
class AdminFirewallService {
  final ApiClient _api;
  AdminFirewallService(this._api);

  Future<Map<String, dynamic>> listRules({bool activeOnly = false}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/firewall/rules',
      query: {'active_only': activeOnly ? 'true' : 'false'},
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> createRule(Map<String, dynamic> body) async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/admin/firewall/rules', data: body);
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> updateRule(int id, Map<String, dynamic> body) async {
    final res = await _api.put<Map<String, dynamic>>('/api/v1/admin/firewall/rules/$id', data: body);
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<void> deleteRule(int id) async {
    await _api.delete<Map<String, dynamic>>('/api/v1/admin/firewall/rules/$id');
  }

  Future<Map<String, dynamic>> banIp({
    required String ip,
    int? durationSeconds,
    String note = '',
    String? pathPrefix,
    String? httpMethods,
    int priority = 10,
  }) async {
    final body = <String, dynamic>{
      'ip': ip,
      'note': note,
      'priority': priority,
    };
    if (durationSeconds != null) {
      body['duration_seconds'] = durationSeconds;
    }
    if (pathPrefix != null && pathPrefix.isNotEmpty) {
      body['path_prefix'] = pathPrefix;
    }
    if (httpMethods != null && httpMethods.isNotEmpty) {
      body['http_methods'] = httpMethods;
    }
    final res = await _api.post<Map<String, dynamic>>('/api/v1/admin/firewall/ban', data: body);
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<int> unbanIp(String ip, {String? onlySource}) async {
    final body = <String, dynamic>{'ip': ip};
    if (onlySource != null) {
      body['only_source'] = onlySource;
    }
    final res = await _api.post<Map<String, dynamic>>('/api/v1/admin/firewall/unban', data: body);
    final data = res.data?['data'] as Map?;
    return (data?['removed_rules'] as num?)?.toInt() ?? 0;
  }

  Future<Map<String, dynamic>> requestLogs({
    int skip = 0,
    int limit = 50,
    String? clientIp,
    int? hours,
  }) async {
    final q = <String, dynamic>{
      'skip': skip.toString(),
      'limit': limit.toString(),
    };
    if (clientIp != null && clientIp.isNotEmpty) {
      q['client_ip'] = clientIp;
    }
    if (hours != null) {
      q['hours'] = hours.toString();
    }
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/firewall/logs/requests',
      query: q,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> auditLogs({
    int skip = 0,
    int limit = 50,
    int? hours,
  }) async {
    final q = <String, dynamic>{
      'skip': skip.toString(),
      'limit': limit.toString(),
    };
    if (hours != null) {
      q['hours'] = hours.toString();
    }
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/firewall/logs/audit',
      query: q,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> reportsSummary({int days = 7}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/firewall/reports/summary',
      query: {'days': days.toString()},
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  /// سیاست نرخ مسیر (فایروال مرکزی / `firewall_rate_policies`)
  Future<Map<String, dynamic>> listRatePolicies() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/firewall/rate-policies');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> createRatePolicy(Map<String, dynamic> body) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/firewall/rate-policies',
      data: body,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> updateRatePolicy(int id, Map<String, dynamic> body) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/firewall/rate-policies/$id',
      data: body,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<void> deleteRatePolicy(int id) async {
    await _api.delete<Map<String, dynamic>>('/api/v1/admin/firewall/rate-policies/$id');
  }
}
