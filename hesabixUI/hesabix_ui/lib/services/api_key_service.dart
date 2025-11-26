import '../core/api_client.dart';

class ApiKeyService {
  final ApiClient _api;

  ApiKeyService(this._api);

  /// دریافت لیست کلیدهای API
  Future<Map<String, dynamic>> listApiKeys() async {
    final response = await _api.get('/auth/api-keys');
    return response.data as Map<String, dynamic>;
  }

  /// ایجاد کلید API جدید
  Future<Map<String, dynamic>> createApiKey({
    String? name,
    String? scopes,
    String? expiresAt,
    String? ipWhitelist,
  }) async {
    final data = <String, dynamic>{};
    if (name != null && name.isNotEmpty) data['name'] = name;
    if (scopes != null && scopes.isNotEmpty) data['scopes'] = scopes;
    if (expiresAt != null && expiresAt.isNotEmpty) data['expires_at'] = expiresAt;
    if (ipWhitelist != null && ipWhitelist.isNotEmpty) data['ip_whitelist'] = ipWhitelist;

    final response = await _api.post('/auth/api-keys', data: data);
    return response.data as Map<String, dynamic>;
  }

  /// دریافت جزئیات یک کلید API
  Future<Map<String, dynamic>> getApiKey(int keyId) async {
    final response = await _api.get('/auth/api-keys/$keyId');
    return response.data as Map<String, dynamic>;
  }

  /// ویرایش کلید API
  Future<Map<String, dynamic>> updateApiKey({
    required int keyId,
    String? name,
    String? scopes,
    String? expiresAt,
    String? ipWhitelist,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (scopes != null) data['scopes'] = scopes;
    if (expiresAt != null) data['expires_at'] = expiresAt;
    if (ipWhitelist != null) data['ip_whitelist'] = ipWhitelist;

    final response = await _api.put('/auth/api-keys/$keyId', data: data);
    return response.data as Map<String, dynamic>;
  }

  /// حذف/لغو کلید API
  Future<Map<String, dynamic>> deleteApiKey(int keyId) async {
    final response = await _api.delete('/auth/api-keys/$keyId');
    return response.data as Map<String, dynamic>;
  }
}
