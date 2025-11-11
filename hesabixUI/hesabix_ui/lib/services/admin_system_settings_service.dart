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
}


