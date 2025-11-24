import '../core/api_client.dart';

class AdminNotificationTemplatesService {
  final ApiClient _api;
  AdminNotificationTemplatesService(this._api);

  Future<Map<String, dynamic>> list({String? eventKey, String? channel, bool? isActive}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/notification-templates',
      query: {
        if (eventKey != null && eventKey.isNotEmpty) 'event_key': eventKey,
        if (channel != null && channel.isNotEmpty) 'channel': channel,
        if (isActive != null) 'is_active': isActive.toString(),
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> create({
    required String eventKey,
    required String channel,
    String? locale,
    String? subject,
    required String body,
    bool isActive = true,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/notification-templates',
      data: {
        'event_key': eventKey,
        'channel': channel,
        if (locale != null) 'locale': locale,
        if (subject != null) 'subject': subject,
        'body': body,
        'is_active': isActive,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<void> update({
    required int id,
    required String eventKey,
    required String channel,
    String? locale,
    String? subject,
    required String body,
    bool isActive = true,
  }) async {
    await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/notification-templates/$id',
      data: {
        'event_key': eventKey,
        'channel': channel,
        if (locale != null) 'locale': locale,
        if (subject != null) 'subject': subject,
        'body': body,
        'is_active': isActive,
      },
    );
  }

  Future<void> delete(int id) async {
    await _api.delete<Map<String, dynamic>>('/api/v1/admin/notification-templates/$id');
  }

  Future<Map<String, dynamic>> preview({
    required String channel,
    String? subject,
    required String body,
    Map<String, dynamic>? context,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/notification-templates/preview',
      data: {
        'channel': channel,
        if (subject != null) 'subject': subject,
        'body': body,
        'context': context ?? const <String, dynamic>{},
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }
}


