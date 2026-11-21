import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/widgets/marketplace/plugin_marketplace_utils.dart';

void main() {
  group('marketplace license activation', () {
    test('active paid license is enabled', () {
      expect(marketplacePluginLicenseActive({'is_active': true}), isTrue);
      expect(marketplacePluginLicenseActive({'is_active': 1}), isTrue);
    });

    test('trial is valid only while not expired', () {
      expect(
        marketplacePluginLicenseActive({'is_trial': true, 'is_expired': false}),
        isTrue,
      );
      expect(
        marketplacePluginLicenseActive({'is_trial': true, 'is_expired': true}),
        isFalse,
      );
    });

    test('numeric and string flags are normalized', () {
      expect(marketplaceJsonBool(' TRUE '), isTrue);
      expect(marketplaceJsonBool('0'), isFalse);
      expect(marketplaceJsonBool(1), isTrue);
    });

    test('globally enabled plugin is not separately purchasable', () {
      expect(
        pluginIsPurchasable({'enabled_for_all_businesses': true}),
        isFalse,
      );
      expect(
        pluginIsGloballyEnabled({'enabled_for_all_businesses': true}),
        isTrue,
      );
    });

    test('active codes ignore expired trials and disabled plugins', () {
      final codes = activeMarketplacePluginCodes([
        {'plugin_code': 'a', 'is_active': true},
        {'plugin_code': 'b', 'is_trial': true, 'is_expired': false},
        {'plugin_code': 'c', 'is_trial': true, 'is_expired': true},
        {'plugin_code': 'd', 'is_active': false},
      ]);
      expect(codes, containsAll(['a', 'b']));
      expect(codes, isNot(contains('c')));
      expect(codes, isNot(contains('d')));
    });

    test('CRM-specific and shared setup routes remain registered', () {
      expect(pluginSetupRouteByCode['contracting'], 'business_contracting');
      expect(pluginSetupRouteByCode['digipay_credit'], 'business_digipay');
      expect(pluginSetupRouteByCode['advanced_accounting'], 'business_reports');
      expect(
        pluginSetupRouteByCode.containsKey('ai_mcp_server'),
        isFalse,
      );
    });
  });
}
