import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/widgets/marketplace/plugin_marketplace_utils.dart';
import 'package:hesabix_ui/widgets/marketplace/plugin_status_badge.dart';

void main() {
  test('system-default licenses are identified and excluded from purchase', () {
    expect(
      pluginLicenseIsSystemDefault({'source': kPluginSourceSystemDefault}),
      isTrue,
    );
    expect(pluginLicenseIsSystemDefault({'source': 'grandfather'}), isFalse);
    expect(pluginLicenseIsSystemDefault({'source': 'purchase'}), isFalse);

    expect(pluginIsPurchasable({'purchasable': false}), isFalse);
    expect(pluginIsPurchasable({'name': 'payroll'}), isTrue);
    expect(
      pluginIsPurchasable({'enabled_for_all_businesses': true}),
      isFalse,
    );
    expect(
      pluginIsPurchasable({'purchasable': true, 'enabled_for_all_businesses': false}),
      isTrue,
    );
    expect(
      pluginIsGloballyEnabled({'enabled_for_all_businesses': true}),
      isTrue,
    );
    expect(
      pluginIsGloballyEnabled({'enabled_for_all_businesses': false}, {'globally_enabled': true}),
      isTrue,
    );
    expect(pluginIsGloballyEnabled({'name': 'payroll'}), isFalse);
  });

  test('marketplace license helper still treats active purchase as licensed', () {
    expect(
      marketplacePluginLicenseActive({'is_active': true, 'source': 'purchase'}),
      isTrue,
    );
    expect(
      marketplacePluginLicenseActive({
        'is_active': true,
        'source': kPluginSourceSystemDefault,
      }),
      isTrue,
    );
    expect(marketplacePluginLicenseActive({'is_active': false}), isFalse);
  });

  test('global overlay wins over expired trial in status badge', () {
    expect(
      licenseVisualState({
        'is_trial': true,
        'trial_remaining_days': 0,
        'is_active': true,
        'globally_enabled': true,
      }),
      PluginLicenseVisualState.active,
    );
    expect(
      licenseVisualState({
        'is_trial': true,
        'trial_remaining_days': 0,
        'is_active': false,
      }),
      PluginLicenseVisualState.trialExpired,
    );
    expect(
      licenseVisualState({'is_active': 1, 'is_trial': 0}),
      PluginLicenseVisualState.active,
    );
  });
}
