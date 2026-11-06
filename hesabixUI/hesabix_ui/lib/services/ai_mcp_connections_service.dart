import '../core/api_client.dart';

class AiMcpConnection {
  final int id;
  final String name;
  final int? businessId;
  final int? userId;
  final String userName;
  final String? userEmail;
  final bool oauth;
  final String clientKind;
  final String clientName;
  final List<String> scopes;
  final bool writeEnabled;
  final List<String>? toolPermissions;
  final int? toolCount;
  final bool unrestrictedTools;
  final String? createdAt;
  final String? expiresAt;
  final String? lastUsedAt;
  final bool revoked;
  final bool membershipActive;
  final String status;
  final bool canManage;

  const AiMcpConnection({
    required this.id,
    required this.name,
    required this.businessId,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.oauth,
    required this.clientKind,
    required this.clientName,
    required this.scopes,
    required this.writeEnabled,
    required this.toolPermissions,
    required this.toolCount,
    required this.unrestrictedTools,
    required this.createdAt,
    required this.expiresAt,
    required this.lastUsedAt,
    required this.revoked,
    required this.membershipActive,
    required this.status,
    required this.canManage,
  });

  factory AiMcpConnection.fromJson(Map<String, dynamic> json) {
    return AiMcpConnection(
      id: (json['id'] as num).toInt(),
      name: (json['name'] ?? '').toString(),
      businessId: (json['business_id'] as num?)?.toInt(),
      userId: (json['user_id'] as num?)?.toInt(),
      userName: (json['user_name'] ?? '').toString(),
      userEmail: json['user_email']?.toString(),
      oauth: json['oauth'] == true,
      clientKind: (json['client_kind'] ?? 'oauth').toString(),
      clientName: (json['client_name'] ?? '').toString(),
      scopes: (json['scopes'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
      writeEnabled: json['write_enabled'] == true,
      toolPermissions: json['tool_permissions'] is List
          ? (json['tool_permissions'] as List).map((item) => item.toString()).toList()
          : null,
      toolCount: (json['tool_count'] as num?)?.toInt(),
      unrestrictedTools: json['unrestricted_tools'] == true,
      createdAt: json['created_at']?.toString(),
      expiresAt: json['expires_at']?.toString(),
      lastUsedAt: json['last_used_at']?.toString(),
      revoked: json['revoked'] == true,
      membershipActive: json['membership_active'] != false,
      status: (json['status'] ?? 'active').toString(),
      canManage: json['can_manage'] == true,
    );
  }

  bool get isLive => status == 'active';
}

class AiMcpTool {
  final String name;
  final String description;
  final String category;
  final bool readOnly;

  const AiMcpTool({
    required this.name,
    required this.description,
    required this.category,
    required this.readOnly,
  });

  factory AiMcpTool.fromJson(Map<String, dynamic> json) {
    return AiMcpTool(
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      category: (json['category'] ?? 'other').toString(),
      readOnly: json['read_only'] == true,
    );
  }
}

class AiMcpConnectionCatalog {
  final int connectionId;
  final String status;
  final bool writeEnabled;
  final bool unrestrictedTools;
  final List<String> selected;
  final List<AiMcpTool> tools;
  final bool membershipActive;

  const AiMcpConnectionCatalog({
    required this.connectionId,
    required this.status,
    required this.writeEnabled,
    required this.unrestrictedTools,
    required this.selected,
    required this.tools,
    required this.membershipActive,
  });

  factory AiMcpConnectionCatalog.fromJson(Map<String, dynamic> json) {
    return AiMcpConnectionCatalog(
      connectionId: (json['connection_id'] as num).toInt(),
      status: (json['status'] ?? 'active').toString(),
      writeEnabled: json['write_enabled'] == true,
      unrestrictedTools: json['unrestricted_tools'] == true,
      selected: (json['selected'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
      tools: (json['tools'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => AiMcpTool.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      membershipActive: json['membership_active'] != false,
    );
  }
}

class AiMcpConnectionsList {
  final List<AiMcpConnection> items;
  final Map<String, dynamic> plugin;
  final String serverUrl;
  final bool viewerIsOwner;

  const AiMcpConnectionsList({
    required this.items,
    required this.plugin,
    required this.serverUrl,
    required this.viewerIsOwner,
  });
}

bool keepsUnrestrictedMcpGrant({
  required bool originallyUnrestricted,
  required bool enableWrites,
  required Iterable<AiMcpTool> tools,
  required Set<String> selected,
}) {
  if (!originallyUnrestricted) return false;
  if (tools.isEmpty) return true;
  final requiredNames = tools
      .where((tool) => enableWrites || tool.readOnly)
      .map((tool) => tool.name)
      .toSet();
  return requiredNames.difference(selected).isEmpty &&
      selected.difference(requiredNames).isEmpty;
}

class AiMcpConnectionsService {
  final ApiClient _api;
  AiMcpConnectionsService(this._api);

  Map<String, dynamic> _data(dynamic body) {
    if (body is Map<String, dynamic> && body['data'] is Map<String, dynamic>) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    if (body is Map<String, dynamic>) return body;
    return <String, dynamic>{};
  }

  Future<AiMcpConnectionsList> listConnections({required int businessId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/mcp/connections',
      query: {'business_id': businessId},
    );
    final data = _data(res.data);
    final items = (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => AiMcpConnection.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    return AiMcpConnectionsList(
      items: items,
      plugin: Map<String, dynamic>.from(data['plugin'] as Map? ?? const {}),
      serverUrl: (data['server_url'] ?? '').toString(),
      viewerIsOwner: data['viewer_is_owner'] == true,
    );
  }

  Future<AiMcpConnectionCatalog> getCatalog({required int connectionId}) async {
    final res = await _api.get<Map<String, dynamic>>(
      '/api/v1/ai/mcp/connections/$connectionId/catalog',
    );
    return AiMcpConnectionCatalog.fromJson(_data(res.data));
  }

  Future<AiMcpConnection> updatePermissions({
    required int connectionId,
    required List<String> toolPermissions,
    required bool enableWrites,
    bool unrestrictedTools = false,
  }) async {
    final res = await _api.patch<Map<String, dynamic>>(
      '/api/v1/ai/mcp/connections/$connectionId',
      data: {
        'tool_permissions': toolPermissions,
        'enable_writes': enableWrites,
        'unrestricted_tools': unrestrictedTools,
      },
    );
    return AiMcpConnection.fromJson(_data(res.data));
  }

  Future<void> revoke({required int connectionId}) async {
    await _api.delete<Map<String, dynamic>>(
      '/api/v1/ai/mcp/connections/$connectionId',
    );
  }

  Future<int> revokeAll({required int businessId}) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/api/v1/ai/mcp/connections/revoke-all',
      data: {'business_id': businessId},
    );
    return (_data(res.data)['count'] as num?)?.toInt() ?? 0;
  }
}
