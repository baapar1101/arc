import '../core/api_client.dart';

class AdminNotificationEventTypesService {
  final ApiClient _api;
  AdminNotificationEventTypesService(this._api);

  Future<List<Map<String, dynamic>>> list({String? category, String? search}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/notification-event-types',
      query: {
        if (category != null && category.isNotEmpty) 'category': category,
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );
    final items = res.data?['data']?['items'] as List? ?? const [];
    return items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> getByCode(String code) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/admin/notification-event-types/$code',
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> updateDefaults({
    required String code,
    String? defaultSmsTemplate,
    String? defaultEmailTemplate,
    String? defaultEmailSubject,
  }) async {
    final res = await _api.put<Map<String, dynamic>>(
      '/api/v1/admin/notification-event-types/$code',
      data: {
        if (defaultSmsTemplate != null) 'default_sms_template': defaultSmsTemplate,
        if (defaultEmailTemplate != null) 'default_email_template': defaultEmailTemplate,
        if (defaultEmailSubject != null) 'default_email_subject': defaultEmailSubject,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> preview({
    required String code,
    required String channel,
    String? defaultSmsTemplate,
    String? defaultEmailTemplate,
    String? defaultEmailSubject,
    Map<String, dynamic>? context,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/admin/notification-event-types/$code/preview',
      data: {
        'channel': channel,
        if (defaultSmsTemplate != null) 'default_sms_template': defaultSmsTemplate,
        if (defaultEmailTemplate != null) 'default_email_template': defaultEmailTemplate,
        if (defaultEmailSubject != null) 'default_email_subject': defaultEmailSubject,
        'context': context ?? const <String, dynamic>{},
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }
}
