import '../core/api_client.dart';

class SupportMcpConnection {
  final int id;
  final String name;
  final int? userId;
  final String userName;
  final String? userEmail;
  final String? createdAt;
  final String? expiresAt;
  final String? lastUsedAt;
  final bool revoked;
  final String status;
  final bool canManage;

  const SupportMcpConnection({
    required this.id,
    required this.name,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.createdAt,
    required this.expiresAt,
    required this.lastUsedAt,
    required this.revoked,
    required this.status,
    required this.canManage,
  });

  factory SupportMcpConnection.fromJson(Map<String, dynamic> json) {
    return SupportMcpConnection(
      id: (json['id'] as num).toInt(),
      name: (json['name'] ?? '').toString(),
      userId: (json['user_id'] as num?)?.toInt(),
      userName: (json['user_name'] ?? '').toString(),
      userEmail: json['user_email']?.toString(),
      createdAt: json['created_at']?.toString(),
      expiresAt: json['expires_at']?.toString(),
      lastUsedAt: json['last_used_at']?.toString(),
      revoked: json['revoked'] == true,
      status: (json['status'] ?? 'active').toString(),
      canManage: json['can_manage'] == true,
    );
  }

  bool get isLive => status == 'active';
}

class SupportMcpCreatedConnection {
  final SupportMcpConnection connection;
  final String token;
  final String serverUrl;

  const SupportMcpCreatedConnection({
    required this.connection,
    required this.token,
    required this.serverUrl,
  });
}

class SupportMcpConnectionsList {
  final List<SupportMcpConnection> items;
  final String serverUrl;

  const SupportMcpConnectionsList({
    required this.items,
    required this.serverUrl,
  });
}

class SupportMcpConnectionsService {
  final ApiClient _api;
  SupportMcpConnectionsService(this._api);

  Map<String, dynamic> _data(dynamic body) {
    if (body is Map<String, dynamic> && body['data'] is Map<String, dynamic>) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    if (body is Map<String, dynamic>) return body;
    return <String, dynamic>{};
  }

  Future<SupportMcpConnectionsList> listConnections() async {
    final res = await _api.get<Map<String, dynamic>>('/api/v1/ai/mcp/support/connections');
    final data = _data(res.data);
    final items = (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => SupportMcpConnection.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    return SupportMcpConnectionsList(
      items: items,
      serverUrl: (data['server_url'] ?? '').toString(),
    );
  }

  Future<SupportMcpCreatedConnection> createConnection({String? name}) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/mcp/support/connections',
      data: {'name': name ?? 'اتصال MCP پشتیبانی'},
    );
    final data = _data(res.data);
    return SupportMcpCreatedConnection(
      connection: SupportMcpConnection.fromJson(data),
      token: (data['token'] ?? '').toString(),
      serverUrl: (data['server_url'] ?? '').toString(),
    );
  }

  Future<void> revoke({required int connectionId}) async {
    await _api.delete<Map<String, dynamic>>(
      '/api/v1/ai/mcp/support/connections/$connectionId',
    );
  }
}
