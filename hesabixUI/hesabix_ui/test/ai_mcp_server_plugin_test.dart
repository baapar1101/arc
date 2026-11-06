import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/core/business_named_route_locations.dart';
import 'package:hesabix_ui/services/ai_mcp_connections_service.dart';
import 'package:hesabix_ui/widgets/marketplace/plugin_marketplace_utils.dart';

void main() {
  test('AI MCP server plugin is a marketplace integration add-on', () {
    expect(kAiMcpServerPluginCode, 'ai_mcp_server');
    expect(pluginSetupRouteByCode[kAiMcpServerPluginCode], 'business_ai_mcp_connections');
    expect(kPluginMarketplaceCategories.contains('integration'), isTrue);
  });

  test('AI MCP server license follows marketplace active/trial rules', () {
    expect(
      marketplacePluginLicenseActive({
        'plugin_code': kAiMcpServerPluginCode,
        'is_active': true,
      }),
      isTrue,
    );
    expect(
      marketplacePluginLicenseActive({
        'plugin_code': kAiMcpServerPluginCode,
        'is_active': false,
        'is_trial': true,
        'is_expired': false,
      }),
      isTrue,
    );
    expect(
      marketplacePluginLicenseActive({
        'plugin_code': kAiMcpServerPluginCode,
        'is_active': false,
      }),
      isFalse,
    );
    expect(
      activeMarketplacePluginCodes([
        {'plugin_code': kAiMcpServerPluginCode, 'is_active': true},
        {'plugin_code': 'payroll', 'is_active': false},
      ]),
      contains(kAiMcpServerPluginCode),
    );
  });

  test('MCP connections page is a named business route', () {
    final uri = BusinessNamedRoutes.uri(
      businessId: 12,
      tabSlot: 0,
      routeName: 'business_ai_mcp_connections',
    );
    expect(uri.path, '/business/12/tab0/ai/mcp-connections');
  });

  test('MCP connection JSON keeps unrestricted grants distinct from empty allowlists', () {
    final unrestricted = AiMcpConnection.fromJson({
      'id': 1,
      'name': 'ChatGPT',
      'business_id': 4,
      'user_id': 2,
      'user_name': 'Sara',
      'oauth': true,
      'client_kind': 'chatgpt',
      'client_name': 'ChatGPT',
      'scopes': ['ai:tools:read'],
      'write_enabled': false,
      'tool_permissions': null,
      'unrestricted_tools': true,
      'status': 'active',
      'can_manage': true,
    });
    final denyAll = AiMcpConnection.fromJson({
      'id': 2,
      'name': 'ChatGPT',
      'business_id': 4,
      'user_id': 2,
      'user_name': 'Sara',
      'oauth': true,
      'client_kind': 'chatgpt',
      'client_name': 'ChatGPT',
      'scopes': ['ai:tools:read'],
      'write_enabled': false,
      'tool_permissions': <String>[],
      'tool_count': 0,
      'unrestricted_tools': false,
      'status': 'active',
      'can_manage': true,
    });
    expect(unrestricted.unrestrictedTools, isTrue);
    expect(unrestricted.toolPermissions, isNull);
    expect(denyAll.unrestrictedTools, isFalse);
    expect(denyAll.toolPermissions, isEmpty);
  });

  test('unrestricted MCP grants stay unrestricted only when every grantable tool remains selected', () {
    const tools = [
      AiMcpTool(name: 'search_invoices', description: '', category: 'invoices', readOnly: true),
      AiMcpTool(name: 'create_invoice', description: '', category: 'invoices', readOnly: false),
    ];
    expect(
      keepsUnrestrictedMcpGrant(
        originallyUnrestricted: true,
        enableWrites: true,
        tools: tools,
        selected: {'search_invoices', 'create_invoice'},
      ),
      isTrue,
    );
    expect(
      keepsUnrestrictedMcpGrant(
        originallyUnrestricted: true,
        enableWrites: false,
        tools: tools,
        selected: {'search_invoices'},
      ),
      isTrue,
    );
    expect(
      keepsUnrestrictedMcpGrant(
        originallyUnrestricted: true,
        enableWrites: true,
        tools: tools,
        selected: {'search_invoices'},
      ),
      isFalse,
    );
    expect(
      keepsUnrestrictedMcpGrant(
        originallyUnrestricted: false,
        enableWrites: true,
        tools: tools,
        selected: {'search_invoices', 'create_invoice'},
      ),
      isFalse,
    );
  });
}
