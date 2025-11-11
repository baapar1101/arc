import '../core/api_client.dart';

class AnnouncementsService {
  final ApiClient _apiClient;
  AnnouncementsService(this._apiClient);

  // ===== User-facing endpoints =====
  Future<Map<String, dynamic>> listAnnouncements({
    int page = 1,
    int limit = 10,
    String? level, // info|warning|critical
    bool onlyUnread = false,
    String? locale,
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'limit': limit,
      if (level != null && level.isNotEmpty) 'level': level,
      'only_unread': onlyUnread,
      if (locale != null && locale.isNotEmpty) 'locale': locale,
    };
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/api/v1/announcements',
      query: query,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<void> markRead(int id) async {
    await _apiClient.post<Map<String, dynamic>>('/api/v1/announcements/$id/mark-read');
  }

  Future<void> dismiss(int id) async {
    await _apiClient.post<Map<String, dynamic>>('/api/v1/announcements/$id/dismiss');
  }

  // ===== Admin endpoints =====
  Future<Map<String, dynamic>> adminList({
    int page = 1,
    int limit = 20,
    String? level,
    bool? active,
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'limit': limit,
      if (level != null && level.isNotEmpty) 'level': level,
      if (active != null) 'active': active,
    };
    final res = await _apiClient.get<Map<String, dynamic>>(
      '/api/v1/admin/announcements',
      query: query,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> adminCreate(Map<String, dynamic> body) async {
    final res = await _apiClient.post<Map<String, dynamic>>(
      '/api/v1/admin/announcements',
      data: body,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> adminUpdate(int id, Map<String, dynamic> body) async {
    final res = await _apiClient.put<Map<String, dynamic>>(
      '/api/v1/admin/announcements/$id',
      data: body,
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }

  Future<void> adminDelete(int id) async {
    await _apiClient.delete<Map<String, dynamic>>('/api/v1/admin/announcements/$id');
  }

  Future<Map<String, dynamic>> adminPublish(int id, {required bool active, bool? pinned}) async {
    final res = await _apiClient.post<Map<String, dynamic>>(
      '/api/v1/admin/announcements/$id/publish',
      data: {
        'active': active,
        if (pinned != null) 'is_pinned': pinned,
      },
    );
    return Map<String, dynamic>.from(res.data?['data'] as Map? ?? const {});
  }
}


