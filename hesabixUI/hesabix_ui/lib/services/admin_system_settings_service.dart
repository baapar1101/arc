import '../core/api_client.dart';

class AdminSystemSettingsService {
  final ApiClient _api;
  AdminSystemSettingsService(this._api);

  Future<Map<String, dynamic>> getNotificationsConfig() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/system-settings/notifications');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> putNotificationsConfig(Map<String, dynamic> data) async {
    final res = await _api.put<Map<String, dynamic>>('/api/v1/admin/system-settings/notifications', data: data);
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> registerTelegramWebhook() async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/admin/system-settings/notifications/telegram/webhook');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> getSystemConfiguration() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/system-settings/configuration');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> updateSystemConfiguration(Map<String, dynamic> data) async {
    final res = await _api.put<Map<String, dynamic>>('/api/v1/admin/system-settings/configuration', data: data);
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> getRedisConfiguration() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/system-settings/redis');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> updateRedisConfiguration(Map<String, dynamic> data) async {
    final res = await _api.put<Map<String, dynamic>>('/api/v1/admin/system-settings/redis', data: data);
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> testRedisConnection() async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/admin/system-settings/redis/test');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> getNotificationSmsPricing() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/system-settings/notification-sms-pricing');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> setNotificationSmsPricing({
    double? pricePerSms,
    Map<String, double>? eventTypePrices,
  }) async {
    final data = <String, dynamic>{};
    if (pricePerSms != null) {
      data['price_per_sms'] = pricePerSms;
    }
    if (eventTypePrices != null) {
      data['event_type_prices'] = eventTypePrices;
    }
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/system-settings/notification-sms-pricing',
      data: data,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }
}


