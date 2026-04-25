import '../core/api_client.dart';

/// API چت وب CRM (ویجت، مکالمه، پیام).
class CrmChatService {
  final ApiClient _apiClient;

  CrmChatService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  dynamic _extractData(dynamic response) {
    if (response == null) return <String, dynamic>{};
    final body = response is Map<String, dynamic> ? response : null;
    if (body != null && body['data'] != null) return body['data'];
    return body ?? <String, dynamic>{};
  }

  Future<List<dynamic>> listWidgets({required int businessId}) async {
    final res = await _apiClient.get<dynamic>('/api/v1/crm/businesses/$businessId/chat/widgets');
    final data = _extractData(res.data);
    if (data is Map && data['items'] is List) return data['items'] as List<dynamic>;
    return [];
  }

  Future<Map<String, dynamic>> createWidget({
    required int businessId,
    required String name,
    List<String>? allowedOrigins,
    Map<String, dynamic>? settings,
    bool isActive = true,
  }) async {
    final res = await _apiClient.post<dynamic>(
      '/api/v1/crm/businesses/$businessId/chat/widgets',
      data: {
        'name': name,
        if (allowedOrigins != null) 'allowed_origins': allowedOrigins,
        if (settings != null) 'settings': settings,
        'is_active': isActive,
      },
    );
    final d = _extractData(res.data);
    return d is Map<String, dynamic> ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> updateWidget({
    required int businessId,
    required int widgetId,
    String? name,
    List<String>? allowedOrigins,
    Map<String, dynamic>? settings,
    bool? isActive,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (allowedOrigins != null) body['allowed_origins'] = allowedOrigins;
    if (settings != null) body['settings'] = settings;
    if (isActive != null) body['is_active'] = isActive;
    final res = await _apiClient.patch<dynamic>(
      '/api/v1/crm/businesses/$businessId/chat/widgets/$widgetId',
      data: body,
    );
    final d = _extractData(res.data);
    return d is Map<String, dynamic> ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  Future<List<dynamic>> listConversations({
    required int businessId,
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _apiClient.get<dynamic>(
      '/api/v1/crm/businesses/$businessId/chat/conversations',
      query: {
        if (status != null && status.isNotEmpty) 'status': status,
        'limit': limit,
        'offset': offset,
      },
    );
    final data = _extractData(res.data);
    if (data is Map && data['items'] is List) return data['items'] as List<dynamic>;
    return [];
  }

  Future<List<dynamic>> listMessages({
    required int businessId,
    required int conversationId,
    int limit = 500,
  }) async {
    final res = await _apiClient.get<dynamic>(
      '/api/v1/crm/businesses/$businessId/chat/conversations/$conversationId/messages',
      query: {'limit': limit},
    );
    final data = _extractData(res.data);
    if (data is Map && data['items'] is List) return data['items'] as List<dynamic>;
    return [];
  }

  Future<Map<String, dynamic>> postAgentMessage({
    required int businessId,
    required int conversationId,
    String? body,
    String? fileStorageId,
  }) async {
    final res = await _apiClient.post<dynamic>(
      '/api/v1/crm/businesses/$businessId/chat/conversations/$conversationId/messages',
      data: {
        if (body != null && body.isNotEmpty) 'body': body,
        if (fileStorageId != null && fileStorageId.isNotEmpty) 'file_storage_id': fileStorageId,
      },
    );
    final d = _extractData(res.data);
    return d is Map<String, dynamic> ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getCrmSettings({required int businessId}) async {
    final res = await _apiClient.get<dynamic>('/api/v1/crm/businesses/$businessId/chat/crm-settings');
    final d = _extractData(res.data);
    return d is Map<String, dynamic> ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> updateCrmSettings({
    required int businessId,
    required bool allowWebChatFileUpload,
  }) async {
    final res = await _apiClient.patch<dynamic>(
      '/api/v1/crm/businesses/$businessId/chat/crm-settings',
      data: {'allow_web_chat_file_upload': allowWebChatFileUpload},
    );
    final d = _extractData(res.data);
    return d is Map<String, dynamic> ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> patchConversation({
    required int businessId,
    required int conversationId,
    String? status,
    int? assignedToUserId,
    int? leadId,
    int? personId,
  }) async {
    final body = <String, dynamic>{};
    if (status != null) body['status'] = status;
    if (assignedToUserId != null) body['assigned_to_user_id'] = assignedToUserId;
    if (leadId != null) body['lead_id'] = leadId;
    if (personId != null) body['person_id'] = personId;
    final res = await _apiClient.patch<dynamic>(
      '/api/v1/crm/businesses/$businessId/chat/conversations/$conversationId',
      data: body,
    );
    final d = _extractData(res.data);
    return d is Map<String, dynamic> ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }
}
