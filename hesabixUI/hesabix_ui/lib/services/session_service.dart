import '../core/api_client.dart';

class SessionInfo {
  final int id;
  final String deviceName;
  final String? deviceId;
  final String? userAgent;
  final String? ip;
  final bool isCurrent;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final String lastUsedRelative;
  final String? browser;
  final String? os;
  final String? deviceType;

  SessionInfo({
    required this.id,
    required this.deviceName,
    this.deviceId,
    this.userAgent,
    this.ip,
    required this.isCurrent,
    required this.createdAt,
    this.lastUsedAt,
    required this.lastUsedRelative,
    this.browser,
    this.os,
    this.deviceType,
  });

  factory SessionInfo.fromJson(Map<String, dynamic> json) {
    return SessionInfo(
      id: json['id'] as int,
      deviceName: json['device_name'] as String? ?? 'دستگاه نامشخص',
      deviceId: json['device_id'] as String?,
      userAgent: json['user_agent'] as String?,
      ip: json['ip'] as String?,
      isCurrent: json['is_current'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastUsedAt: json['last_used_at'] != null
          ? DateTime.parse(json['last_used_at'] as String)
          : null,
      lastUsedRelative: json['last_used_relative'] as String? ?? 'هرگز',
      browser: json['browser'] as String?,
      os: json['os'] as String?,
      deviceType: json['device_type'] as String?,
    );
  }
}

class SessionService {
  final ApiClient _api;

  SessionService(this._api);

  /// دریافت لیست session های ورود
  Future<List<SessionInfo>> listSessions() async {
    final response = await _api.get<Map<String, dynamic>>('/auth/sessions');
    final body = response.data as Map<String, dynamic>;
    final data = body['data'] as List;
    return data
        .map((e) => SessionInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// حذف یک session
  Future<void> revokeSession(int sessionId) async {
    await _api.delete('/auth/sessions/$sessionId');
  }

  /// حذف تمام session های دیگر (به جز فعلی)
  Future<int> revokeOtherSessions() async {
    final response = await _api.delete<Map<String, dynamic>>('/auth/sessions/others');
    final body = response.data as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>;
    return data['deleted_count'] as int? ?? 0;
  }
}

