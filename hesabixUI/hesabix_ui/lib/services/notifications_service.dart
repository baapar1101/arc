import '../core/api_client.dart';

class NotificationsService {
  final ApiClient _api;
  NotificationsService(this._api);

  Future<Map<String, dynamic>> getSettings() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/notifications/settings');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<void> updateSettings({
    bool? telegramEnabled,
    bool? emailEnabled,
    bool? smsEnabled,
    bool? inappEnabled,
  }) async {
    final body = <String, dynamic>{
      if (telegramEnabled != null) 'telegram_enabled': telegramEnabled,
      if (emailEnabled != null) 'email_enabled': emailEnabled,
      if (smsEnabled != null) 'sms_enabled': smsEnabled,
      if (inappEnabled != null) 'inapp_enabled': inappEnabled,
    };
    await _api.put<Map<String, dynamic>>('/api/v1/notifications/settings', data: body);
  }

  Future<void> sendTest(String channel) async {
    await _api.post<Map<String, dynamic>>('/api/v1/notifications/test', query: {'channel': channel});
  }
}


