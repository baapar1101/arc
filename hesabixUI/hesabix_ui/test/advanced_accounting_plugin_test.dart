import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/widgets/marketplace/plugin_marketplace_utils.dart';

void main() {
  test('advanced accounting plugin is wired into marketplace catalog helpers', () {
    expect(kAdvancedAccountingPluginCode, 'advanced_accounting');
    expect(
      pluginSetupRouteByCode[kAdvancedAccountingPluginCode],
      'business_reports',
    );
    expect(
      kPluginMarketplaceCategories.contains('accounting'),
      isTrue,
    );
    expect(
      kAdvancedAccountingMenuKeys,
      containsAll(<String>{
        'year-end-closing',
        'currency-revaluation',
        'loan-facilities',
        'report-templates',
      }),
    );
    expect(
      kAdvancedAccountingSettingsKeys,
      containsAll(<String>{'backup', 'ftp_backup', 'restore', 'report_templates'}),
    );
    expect(
      kAdvancedAccountingReportKeys,
      containsAll(<String>{
        'trial_balance',
        'balance_sheet',
        'financial_package',
        'general_ledger',
        'journal_ledger',
        'accounts_review',
        'cash_flow',
        'fx_revaluation',
        'pnl_period',
        'pnl_cumulative',
        'ar_aging',
        'ap_aging',
        'person_balances_by_currency',
      }),
    );
  });

  test('advanced accounting license follows marketplace active/trial rules', () {
    expect(
      marketplacePluginLicenseActive({
        'plugin_code': kAdvancedAccountingPluginCode,
        'is_active': true,
      }),
      isTrue,
    );
    expect(
      marketplacePluginLicenseActive({
        'plugin_code': kAdvancedAccountingPluginCode,
        'is_active': false,
        'is_trial': true,
        'is_expired': false,
      }),
      isTrue,
    );
    expect(
      marketplacePluginLicenseActive({
        'plugin_code': kAdvancedAccountingPluginCode,
        'is_active': false,
      }),
      isFalse,
    );
    expect(
      activeMarketplacePluginCodes([
        {'plugin_code': kAdvancedAccountingPluginCode, 'is_active': true},
        {'plugin_code': 'payroll', 'is_active': false},
      ]),
      contains(kAdvancedAccountingPluginCode),
    );
    expect(
      activeMarketplacePluginCodes([
        {
          'plugin_code': kAdvancedAccountingPluginCode,
          'is_active': true,
          'source': kPluginSourceSystemDefault,
          'globally_enabled': true,
        },
      ]),
      contains(kAdvancedAccountingPluginCode),
    );
  });
}
