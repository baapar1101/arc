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
    bool? baleEnabled,
    bool? emailEnabled,
    bool? smsEnabled,
    bool? inappEnabled,
    String? inappAlertMode,
    bool? inappSoundEnabled,
    String? inappSoundAssetId,
  }) async {
    final body = <String, dynamic>{
      if (telegramEnabled != null) 'telegram_enabled': telegramEnabled,
      if (baleEnabled != null) 'bale_enabled': baleEnabled,
      if (emailEnabled != null) 'email_enabled': emailEnabled,
      if (smsEnabled != null) 'sms_enabled': smsEnabled,
      if (inappEnabled != null) 'inapp_enabled': inappEnabled,
      if (inappAlertMode != null) 'inapp_alert_mode': inappAlertMode,
      if (inappSoundEnabled != null) 'inapp_sound_enabled': inappSoundEnabled,
      if (inappSoundAssetId != null) 'inapp_sound_asset_id': inappSoundAssetId,
    };
    await _api.put<Map<String, dynamic>>('/api/v1/notifications/settings', data: body);
  }

  Future<void> sendTest(String channel) async {
    await _api.post<Map<String, dynamic>>('/api/v1/notifications/test', query: {'channel': channel});
  }

  /// دریافت تاریخچه ناتیفیکیشن‌های کاربر
  /// queryInfo: اطلاعات کوئری شامل فیلترها، مرتب‌سازی و صفحه‌بندی
  Future<Map<String, dynamic>> getHistory(Map<String, dynamic> queryInfo) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/notifications/history',
      data: queryInfo,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }
}


