import '../core/api_client.dart';

class UserUiPreferencesService {
  final ApiClient _api;

  UserUiPreferencesService(this._api);

  Future<Map<String, dynamic>> getPreferences() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/profile/ui-preferences');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> putPreferences(Map<String, dynamic> body) async {
    final res = await _api.put<Map<String, dynamic>>('/api/v1/profile/ui-preferences', data: body);
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }
}
