import '../core/api_client.dart';

class TelegramIntegrationService {
  final ApiClient _api;
  TelegramIntegrationService(this._api);

  Future<Map<String, dynamic>> createLink() async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/integrations/telegram/link');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
    }

  Future<Map<String, dynamic>> getStatus() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/integrations/telegram/status');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<void> unlink() async {
    await _api.delete<Map<String, dynamic>>('/api/v1/integrations/telegram/unlink');
  }
}


