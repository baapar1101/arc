import '../core/api_client.dart';

class SystemServicesService {
  final ApiClient _api;
  
  SystemServicesService(this._api);

  /// نام سرویس‌های systemd مجاز (هم‌راستا با بک‌اند)
  Future<List<String>> getAllowedServices() async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/system-services/allowed-services',
    );
    final data = res.data?['data'] as Map?;
    final raw = data?['services'] as List? ?? const [];
    return raw.map((e) => e.toString()).toList();
  }

  /// دریافت لاگ‌های یک سرویس
  Future<Map<String, dynamic>> getServiceLogs({
    required String serviceName,
    int lines = 100,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/system-services/logs',
      query: {
        'service_name': serviceName,
        'lines': lines,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  /// دریافت وضعیت یک سرویس
  Future<Map<String, dynamic>> getServiceStatus({
    required String serviceName,
  }) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/system-services/status',
      query: {
        'service_name': serviceName,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  /// دریافت وضعیت همه سرویس‌ها
  Future<Map<String, dynamic>> getAllServicesStatus() async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/system-services/status/all',
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  /// Restart کردن یک سرویس
  Future<Map<String, dynamic>> restartService({
    required String serviceName,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/system-services/restart',
      query: {
        'service_name': serviceName,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }
}

