import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/widgets/marketplace/plugin_marketplace_utils.dart';

void main() {
  test('AI MCP server plugin is a marketplace integration add-on', () {
    expect(kAiMcpServerPluginCode, 'ai_mcp_server');
    expect(pluginSetupRouteByCode.containsKey(kAiMcpServerPluginCode), isFalse);
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
}
