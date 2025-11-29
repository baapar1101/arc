import '../core/api_client.dart';

class MonitoringService {
  final ApiClient _api;
  MonitoringService(this._api);

  // Hardware Monitoring

  /// دریافت وضعیت فعلی منابع سخت‌افزاری
  Future<Map<String, dynamic>> getHardwareCurrent() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/monitoring/hardware/current');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  /// دریافت تاریخچه منابع سخت‌افزاری
  Future<List<Map<String, dynamic>>> getHardwareHistory({
    required String metricType,
    String? metricName,
    String? startTime,
    String? endTime,
    int intervalMinutes = 1,
  }) async {
    final params = <String, dynamic>{
      'metric_type': metricType,
      'interval_minutes': intervalMinutes,
    };
    if (metricName != null) params['metric_name'] = metricName;
    if (startTime != null) params['start_time'] = startTime;
    if (endTime != null) params['end_time'] = endTime;

    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/monitoring/hardware/history',
      query: params,
    );
    final data = res.data?['data'] as Map? ?? {};
    final dataList = data['data'] as List? ?? [];
    return dataList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // Services Monitoring

  /// دریافت وضعیت همه سرویس‌ها
  Future<Map<String, dynamic>> getServicesStatus() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/monitoring/services/status');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  /// دریافت وضعیت یک سرویس خاص
  Future<Map<String, dynamic>> getServiceStatus(String serviceName) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/monitoring/services/$serviceName/status',
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  // Performance Monitoring

  /// دریافت خلاصه عملکرد
  Future<Map<String, dynamic>> getPerformanceOverview() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/monitoring/performance/overview');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  /// دریافت آمار endpoint ها
  Future<Map<String, dynamic>> getEndpointPerformance({
    String? method,
    String? path,
  }) async {
    final params = <String, dynamic>{};
    if (method != null) params['method'] = method;
    if (path != null) params['path'] = path;

    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/monitoring/performance/endpoints',
      query: params.isNotEmpty ? params : null,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  /// دریافت endpoint های کند
  Future<Map<String, dynamic>> getSlowEndpoints({int thresholdMs = 1000}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/monitoring/performance/slow-endpoints',
      query: {'threshold_ms': thresholdMs},
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  // Alerts

  /// دریافت لیست هشدارها
  Future<List<Map<String, dynamic>>> getAlerts({
    String? status,
    int limit = 50,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (status != null) params['status'] = status;

    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/monitoring/alerts',
      query: params,
    );
    final data = res.data?['data'] as Map? ?? {};
    final alerts = data['alerts'] as List? ?? [];
    return alerts.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// دریافت هشدارهای فعال
  Future<List<Map<String, dynamic>>> getActiveAlerts({int limit = 50}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/monitoring/alerts/active',
      query: {'limit': limit},
    );
    final data = res.data?['data'] as Map? ?? {};
    final alerts = data['alerts'] as List? ?? [];
    return alerts.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// تایید هشدار
  Future<void> acknowledgeAlert(int alertId) async {
    await _api.post(
      '/api/v1/admin/monitoring/alerts/$alertId/acknowledge',
    );
  }

  /// حل کردن هشدار
  Future<void> resolveAlert(int alertId) async {
    await _api.post(
      '/api/v1/admin/monitoring/alerts/$alertId/resolve',
    );
  }
}

