import '../core/api_client.dart';

class BaleIntegrationService {
  final ApiClient _api;
  BaleIntegrationService(this._api);

  Future<Map<String, dynamic>> createLink() async {
    final res = await _api.post<Map<String, dynamic>>('/api/v1/integrations/bale/link');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> getStatus() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/integrations/bale/status');
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<void> unlink() async {
    await _api.delete<Map<String, dynamic>>('/api/v1/integrations/bale/unlink');
  }
}
