import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../models/settings_category.dart';
import '../models/settings_item.dart';
import '../utils/localization_helper.dart';

/// دسته‌بندی هاب پنل مدیر سیستم.
///
/// دسته‌های روزمره باز هستند؛ بقیه جمع‌اند تا صفحه با ده‌ها کارت شلوغ نشود.
class SettingsCategorizationService {
  static const Set<String> expandedByDefault = {
    'operations',
    'users_businesses',
    'financial_payment',
  };

  static const List<String> _quickAccessIds = [
    'operations_home',
    'user_management',
    'system_configuration',
    'wallet_directory',
    'payment_gateways',
    'system_monitoring',
  ];

  static List<SettingsCategory> getCategories() {
    return [
      _operations(),
      _usersAndSupport(),
      _finance(),
      _communications(),
      _ai(),
      _filesAndPlugins(),
      _externalServices(),
      _infrastructure(),
      _monitoring(),
      _maintenance(),
    ];
  }

  static List<SettingsCategory> visibleCategories({required bool isSuperAdmin}) {
    return getCategories()
        .where((category) => isSuperAdmin || !category.requiresSuperAdmin)
        .map((category) {
          final items = category.items
              .where((item) => isSuperAdmin || !item.requiresSuperAdmin)
              .toList();
          return category.copyWith(items: items);
        })
        .where((category) => category.items.isNotEmpty)
        .toList();
  }

  static List<SettingsItem> quickAccessItems(List<SettingsCategory> categories) {
    final byId = <String, SettingsItem>{
      for (final category in categories)
        for (final item in category.items) item.id: item,
    };
    return [
      for (final id in _quickAccessIds)
        if (byId.containsKey(id)) byId[id]!,
    ];
  }

  static bool isExpandedByDefault(String categoryId) =>
      expandedByDefault.contains(categoryId);

  static List<SettingsItem> getAllItems() {
    return getCategories().expand((category) => category.items).toList();
  }

  static List<SettingsItem> searchItems(
    String query, {
    required AppLocalizations t,
    List<SettingsCategory>? categories,
  }) {
    final searchCategories = categories ?? getCategories();
    final lowerQuery = query.toLowerCase().trim();
    if (lowerQuery.isEmpty) return [];

    final out = <SettingsItem>[];
    for (final category in searchCategories) {
      final categoryHit =
          LocalizationHelper.categoryMatchesSearch(t, category, lowerQuery);
      for (final item in category.items) {
        if (categoryHit ||
            LocalizationHelper.itemMatchesSearch(t, item, lowerQuery)) {
          out.add(item);
        }
      }
    }
    return out;
  }

  static SettingsCategory _operations() {
    return SettingsCategory(
      id: 'operations',
      title: 'settingsCategoryOperationsHome',
      description: 'settingsCategoryOperationsHomeDescription',
      icon: Icons.speed_outlined,
      color: const Color(0xFF1565C0),
      order: 0,
      items: [
        _item(
          id: 'operations_home',
          title: 'systemAdminOpsHomeTitle',
          description: 'systemAdminOpsHomeDescription',
          icon: Icons.speed_outlined,
          color: const Color(0xFF1565C0),
          route: '/user/profile/system-settings/operations',
          categoryId: 'operations',
          order: 1,
        ),
        _item(
          id: 'admin_audit',
          title: 'systemAdminAuditTitle',
          description: 'systemAdminAuditDescription',
          icon: Icons.fact_check_outlined,
          color: const Color(0xFF455A64),
          route: '/user/profile/system-settings/audit-log',
          categoryId: 'operations',
          order: 2,
        ),
        _item(
          id: 'admin_schedules',
          title: 'systemAdminSchedulesTitle',
          description: 'systemAdminSchedulesDescription',
          icon: Icons.schedule_outlined,
          color: const Color(0xFF00838F),
          route: '/user/profile/system-settings/schedules',
          categoryId: 'operations',
          order: 3,
        ),
      ],
    );
  }

  static SettingsCategory _usersAndSupport() {
    return SettingsCategory(
      id: 'users_businesses',
      title: 'settingsCategoryUsersBusinesses',
      description: 'settingsCategoryUsersBusinessesDescription',
      icon: Icons.people_outlined,
      color: const Color(0xFFFF9800),
      order: 1,
      items: [
        _item(
          id: 'user_management',
          title: 'userManagement',
          description: 'userManagementDescription',
          icon: Icons.people_outlined,
          color: const Color(0xFFFF9800),
          route: '/user/profile/system-settings/users',
          categoryId: 'users_businesses',
          order: 1,
        ),
        _item(
          id: 'businesses_management',
          title: 'settingsBusinessesManagement',
          description: 'settingsBusinessesManagementDescription',
          icon: Icons.business_outlined,
          color: const Color(0xFF1976D2),
          route: '/user/profile/system-settings/businesses',
          categoryId: 'users_businesses',
          order: 2,
          requiresSuperAdmin: true,
        ),
        _item(
          id: 'support_operators',
          title: 'settingsSupportOperators',
          description: 'settingsSupportOperatorsDescription',
          icon: Icons.support_agent_outlined,
          color: const Color(0xFFE91E63),
          route: '/user/profile/system-settings/support-operators',
          categoryId: 'users_businesses',
          order: 3,
          requiresSuperAdmin: true,
        ),
        _item(
          id: 'support_plans',
          title: 'settingsSupportPlans',
          description: 'settingsSupportPlansDescription',
          icon: Icons.card_membership_outlined,
          color: const Color(0xFF00897B),
          route: '/user/profile/system-settings/support-plans',
          categoryId: 'users_businesses',
          order: 4,
        ),
        _item(
          id: 'support_billing_stats',
          title: 'settingsSupportBillingStats',
          description: 'settingsSupportBillingStatsDescription',
          icon: Icons.bar_chart_outlined,
          color: const Color(0xFF5C6BC0),
          route: '/user/profile/system-settings/support-billing-stats',
          categoryId: 'users_businesses',
          order: 5,
        ),
        _item(
          id: 'system_reports',
          title: 'settingsSystemReports',
          description: 'settingsSystemReportsDescription',
          icon: Icons.assessment_outlined,
          color: const Color(0xFF455A64),
          route: '/user/profile/system-settings/reports',
          categoryId: 'users_businesses',
          order: 6,
        ),
      ],
    );
  }

  static SettingsCategory _finance() {
    return SettingsCategory(
      id: 'financial_payment',
      title: 'settingsCategoryFinancialPayment',
      description: 'settingsCategoryFinancialPaymentDescription',
      icon: Icons.account_balance_wallet_outlined,
      color: const Color(0xFF009688),
      order: 2,
      items: [
        _item(
          id: 'wallet_settings',
          title: 'settingsWalletSettings',
          description: 'settingsWalletSettingsDescription',
          icon: Icons.account_balance_wallet_outlined,
          color: const Color(0xFF009688),
          route: '/user/profile/system-settings/wallet',
          categoryId: 'financial_payment',
          order: 1,
        ),
        _item(
          id: 'wallet_directory',
          title: 'systemAdminWalletsTitle',
          description: 'systemAdminWalletsDescription',
          icon: Icons.account_balance_outlined,
          color: const Color(0xFF00695C),
          route: '/user/profile/system-settings/wallets',
          categoryId: 'financial_payment',
          order: 2,
        ),
        _item(
          id: 'currencies_admin',
          title: 'settingsCurrenciesAdmin',
          description: 'settingsCurrenciesAdminDescription',
          icon: Icons.currency_exchange_outlined,
          color: const Color(0xFF00796B),
          route: '/user/profile/system-settings/currencies',
          categoryId: 'financial_payment',
          order: 2,
        ),
        _item(
          id: 'fx_providers_admin',
          title: 'settingsFxProvidersAdmin',
          description: 'settingsFxProvidersAdminDescription',
          icon: Icons.cloud_sync_outlined,
          color: const Color(0xFF00897B),
          route: '/user/profile/system-settings/fx-providers',
          categoryId: 'financial_payment',
          order: 3,
        ),
        _item(
          id: 'payment_gateways',
          title: 'settingsPaymentGateways',
          description: 'settingsPaymentGatewaysDescription',
          icon: Icons.payment_outlined,
          color: const Color(0xFF3F51B5),
          route: '/user/profile/system-settings/payment-gateways',
          categoryId: 'financial_payment',
          order: 4,
        ),
        _item(
          id: 'wallet_payouts_admin',
          title: 'settingsWalletPayoutsAdmin',
          description: 'settingsWalletPayoutsAdminDescription',
          icon: Icons.account_balance_outlined,
          color: const Color(0xFF00695C),
          route: '/user/profile/system-settings/wallet-payouts',
          categoryId: 'financial_payment',
          order: 5,
        ),
        _item(
          id: 'pay_page_domain',
          title: 'settingsPayPageDomain',
          description: 'settingsPayPageDomainDescription',
          icon: Icons.qr_code_2_outlined,
          color: const Color(0xFF00838F),
          route: '/user/profile/system-settings/pay-page',
          categoryId: 'financial_payment',
          order: 6,
        ),
        _item(
          id: 'pay_page_abuse_reports',
          title: 'settingsPayPageAbuseReports',
          description: 'settingsPayPageAbuseReportsDescription',
          icon: Icons.report_gmailerrorred_outlined,
          color: const Color(0xFFC62828),
          route: '/user/profile/system-settings/pay-page-abuse',
          categoryId: 'financial_payment',
          order: 7,
        ),
      ],
    );
  }

  static SettingsCategory _communications() {
    return SettingsCategory(
      id: 'communications',
      title: 'settingsCategoryCommunications',
      description: 'settingsCategoryCommunicationsDescription',
      icon: Icons.email_outlined,
      color: const Color(0xFFE91E63),
      order: 3,
      items: [
        _item(
          id: 'email_settings',
          title: 'emailSettings',
          description: 'emailSettingsDescription',
          icon: Icons.email_outlined,
          color: const Color(0xFFE91E63),
          route: '/user/profile/system-settings/email',
          categoryId: 'communications',
          order: 1,
        ),
        _item(
          id: 'announcements',
          title: 'settingsAnnouncements',
          description: 'settingsAnnouncementsDescription',
          icon: Icons.notifications_active_outlined,
          color: const Color(0xFF795548),
          route: '/user/profile/system-settings/announcements',
          categoryId: 'communications',
          order: 2,
        ),
        _item(
          id: 'notifications',
          title: 'systemAdminNotificationChannelsTitle',
          description: 'systemAdminNotificationChannelsDescription',
          icon: Icons.notifications_outlined,
          color: const Color(0xFF607D8B),
          route: '/user/profile/system-settings/notifications',
          categoryId: 'communications',
          order: 3,
        ),
        _item(
          id: 'notification_templates',
          title: 'settingsNotificationTemplates',
          description: 'settingsNotificationTemplatesDescription',
          icon: Icons.description_outlined,
          color: const Color(0xFF455A64),
          route: '/user/profile/system-settings/notification-templates',
          categoryId: 'communications',
          order: 4,
        ),
        _item(
          id: 'notification_event_defaults',
          title: 'settingsNotificationEventDefaults',
          description: 'settingsNotificationEventDefaultsDescription',
          icon: Icons.article_outlined,
          color: const Color(0xFF5D4037),
          route: '/user/profile/system-settings/notification-event-defaults',
          categoryId: 'communications',
          order: 5,
        ),
        _item(
          id: 'notification_moderation',
          title: 'settingsNotificationModeration',
          description: 'settingsNotificationModerationDescription',
          icon: Icons.rule_outlined,
          color: const Color(0xFFFF6F00),
          route: '/user/profile/system-settings/notification-moderation',
          categoryId: 'communications',
          order: 6,
          requiresSuperAdmin: true,
        ),
        _item(
          id: 'notification_sms_pricing',
          title: 'settingsNotificationSmsPricing',
          description: 'settingsNotificationSmsPricingDescription',
          icon: Icons.price_check_outlined,
          color: const Color(0xFF4CAF50),
          route: '/user/profile/system-settings/notification-sms-pricing',
          categoryId: 'communications',
          order: 7,
          requiresSuperAdmin: true,
        ),
      ],
    );
  }

  static SettingsCategory _ai() {
    return SettingsCategory(
      id: 'ai',
      title: 'settingsCategoryAI',
      description: 'settingsCategoryAIDescription',
      icon: Icons.smart_toy_outlined,
      color: const Color(0xFF9C27B0),
      order: 4,
      items: [
        _item(
          id: 'ai_hub',
          title: 'systemAdminAiHubTitle',
          description: 'systemAdminAiHubDescription',
          icon: Icons.smart_toy_outlined,
          color: const Color(0xFF9C27B0),
          route: '/user/profile/system-settings/ai',
          categoryId: 'ai',
          order: 1,
        ),
      ],
    );
  }

  static SettingsCategory _filesAndPlugins() {
    return SettingsCategory(
      id: 'storage_files',
      title: 'settingsCategoryStorageFiles',
      description: 'settingsCategoryStorageFilesDescription',
      icon: Icons.cloud_upload_outlined,
      color: const Color(0xFF2196F3),
      order: 5,
      items: [
        _item(
          id: 'storage_management',
          title: 'storageManagement',
          description: 'storageManagementDescription',
          icon: Icons.cloud_upload_outlined,
          color: const Color(0xFF2196F3),
          route: '/user/profile/system-settings/storage',
          categoryId: 'storage_files',
          order: 1,
        ),
        _item(
          id: 'storage_plans',
          title: 'settingsStoragePlans',
          description: 'settingsStoragePlansDescription',
          icon: Icons.storage_outlined,
          color: const Color(0xFF00BCD4),
          route: '/user/profile/system-settings/storage-plans',
          categoryId: 'storage_files',
          order: 2,
        ),
        _item(
          id: 'document_monetization',
          title: 'settingsDocumentMonetization',
          description: 'settingsDocumentMonetizationDescription',
          icon: Icons.layers_outlined,
          color: const Color(0xFF26A69A),
          route: '/user/profile/system-settings/document-monetization',
          categoryId: 'storage_files',
          order: 3,
        ),
        _item(
          id: 'marketplace_plugins',
          title: 'settingsMarketplacePlugins',
          description: 'settingsMarketplacePluginsDescription',
          icon: Icons.extension_outlined,
          color: const Color(0xFF9C27B0),
          route: '/user/profile/system-settings/marketplace-plugins',
          categoryId: 'storage_files',
          order: 4,
        ),
        _item(
          id: 'license_expiry',
          title: 'systemAdminLicensesTitle',
          description: 'systemAdminLicensesDescription',
          icon: Icons.event_busy_outlined,
          color: const Color(0xFFEF6C00),
          route: '/user/profile/system-settings/license-expiry',
          categoryId: 'storage_files',
          order: 5,
        ),
        _item(
          id: 'share_links',
          title: 'settingsShareLinks',
          description: 'settingsShareLinksDescription',
          icon: Icons.link_outlined,
          color: const Color(0xFF8E24AA),
          route: '/user/profile/system-settings/share-links',
          categoryId: 'storage_files',
          order: 5,
        ),
      ],
    );
  }

  static SettingsCategory _externalServices() {
    return SettingsCategory(
      id: 'external_services',
      title: 'settingsCategoryExternalServices',
      description: 'settingsCategoryExternalServicesDescription',
      icon: Icons.hub_outlined,
      color: const Color(0xFF00ACC1),
      order: 6,
      items: [
        _item(
          id: 'zohal_services',
          title: 'settingsZohalServices',
          description: 'settingsZohalServicesDescription',
          icon: Icons.search_outlined,
          color: const Color(0xFF00ACC1),
          route: '/user/profile/system-settings/zohal-services',
          categoryId: 'external_services',
          order: 1,
        ),
        _item(
          id: 'zohal_settings',
          title: 'settingsZohalSettings',
          description: 'settingsZohalSettingsDescription',
          icon: Icons.tune_outlined,
          color: const Color(0xFF00897B),
          route: '/user/profile/system-settings/zohal-settings',
          categoryId: 'external_services',
          order: 2,
        ),
        _item(
          id: 'zohal_statistics',
          title: 'settingsZohalStatistics',
          description: 'settingsZohalStatisticsDescription',
          icon: Icons.insights_outlined,
          color: const Color(0xFF006064),
          route: '/user/profile/system-settings/zohal-statistics',
          categoryId: 'external_services',
          order: 3,
        ),
        _item(
          id: 'tax_product_codes',
          title: 'settingsTaxProductCodes',
          description: 'settingsTaxProductCodesDescription',
          icon: Icons.qr_code_2_outlined,
          color: const Color(0xFF00695C),
          route: '/user/profile/system-settings/tax-product-codes',
          categoryId: 'external_services',
          order: 4,
        ),
        _item(
          id: 'tax_providers',
          title: 'settingsTaxProviders',
          description: 'settingsTaxProvidersDescription',
          icon: Icons.account_tree_outlined,
          color: const Color(0xFF00695C),
          route: '/user/profile/system-settings/tax-providers',
          categoryId: 'external_services',
          order: 5,
        ),
        _item(
          id: 'tax_provider_motamed_asa',
          title: 'settingsMotamedAsa',
          description: 'settingsMotamedAsaDescription',
          icon: Icons.verified_outlined,
          color: const Color(0xFF00695C),
          route: '/user/profile/system-settings/tax-provider-motamed-asa',
          categoryId: 'external_services',
          order: 6,
        ),
      ],
    );
  }

  static SettingsCategory _infrastructure() {
    return SettingsCategory(
      id: 'core_configuration',
      title: 'settingsCategoryCoreConfiguration',
      description: 'settingsCategoryCoreConfigurationDescription',
      icon: Icons.settings_outlined,
      color: const Color(0xFF4CAF50),
      order: 7,
      items: [
        _item(
          id: 'system_configuration',
          title: 'systemConfiguration',
          description: 'systemConfigurationDescription',
          icon: Icons.settings_outlined,
          color: const Color(0xFF4CAF50),
          route: '/user/profile/system-settings/configuration',
          categoryId: 'core_configuration',
          order: 1,
        ),
        _item(
          id: 'redis_cache',
          title: 'settingsRedisCache',
          description: 'settingsRedisCacheDescription',
          icon: Icons.memory_outlined,
          color: const Color(0xFFDC143C),
          route: '/user/profile/system-settings/redis',
          categoryId: 'core_configuration',
          order: 2,
        ),
        _item(
          id: 'firewall',
          title: 'settingsFirewall',
          description: 'settingsFirewallDescription',
          icon: Icons.security_outlined,
          color: const Color(0xFF455A64),
          route: '/user/profile/system-settings/firewall',
          categoryId: 'core_configuration',
          order: 3,
        ),
      ],
    );
  }

  static SettingsCategory _monitoring() {
    return SettingsCategory(
      id: 'monitoring_logs',
      title: 'settingsCategoryMonitoringLogs',
      description: 'settingsCategoryMonitoringLogsDescription',
      icon: Icons.monitor_heart_outlined,
      color: const Color(0xFFFF6B35),
      order: 8,
      items: [
        _item(
          id: 'system_monitoring',
          title: 'settingsSystemMonitoring',
          description: 'settingsSystemMonitoringDescription',
          icon: Icons.monitor_heart_outlined,
          color: const Color(0xFFFF6B35),
          route: '/user/profile/system-settings/monitoring',
          categoryId: 'monitoring_logs',
          order: 1,
        ),
        _item(
          id: 'hscript_runs',
          title: 'systemAdminHscriptTitle',
          description: 'systemAdminHscriptDescription',
          icon: Icons.code_outlined,
          color: const Color(0xFF5E35B1),
          route: '/user/profile/system-settings/hscript-runs',
          categoryId: 'monitoring_logs',
          order: 2,
        ),
        _item(
          id: 'service_logs',
          title: 'settingsServiceLogs',
          description: 'settingsServiceLogsDescription',
          icon: Icons.terminal_outlined,
          color: const Color(0xFF607D8B),
          route: '/user/profile/system-settings/service-logs',
          categoryId: 'monitoring_logs',
          order: 2,
        ),
        _item(
          id: 'business_activity_logs',
          title: 'settingsBusinessActivityLogs',
          description: 'settingsBusinessActivityLogsDescription',
          icon: Icons.history_outlined,
          color: const Color(0xFF6A1B9A),
          route: '/user/profile/system-settings/business-activity-logs',
          categoryId: 'monitoring_logs',
          order: 3,
        ),
      ],
    );
  }

  static SettingsCategory _maintenance() {
    return SettingsCategory(
      id: 'maintenance',
      title: 'settingsCategoryMaintenance',
      description: 'settingsCategoryMaintenanceDescription',
      icon: Icons.warning_amber_outlined,
      color: const Color(0xFFC62828),
      order: 9,
      items: [
        _item(
          id: 'notification_outbox',
          title: 'systemAdminOutboxTitle',
          description: 'systemAdminOutboxDescription',
          icon: Icons.sms_failed_outlined,
          color: const Color(0xFFC62828),
          route: '/user/profile/system-settings/notification-outbox',
          categoryId: 'maintenance',
          order: 0,
          tags: const ['danger'],
          requiresSuperAdmin: true,
        ),
        _item(
          id: 'database_backup',
          title: 'settingsDatabaseBackup',
          description: 'settingsDatabaseBackupDescription',
          icon: Icons.backup_outlined,
          color: const Color(0xFFC62828),
          route: '/user/profile/system-settings/database-backup',
          categoryId: 'maintenance',
          order: 1,
          tags: const ['danger'],
          requiresSuperAdmin: true,
        ),
        _item(
          id: 'legacy_database_import',
          title: 'settingsLegacyDatabaseImport',
          description: 'settingsLegacyDatabaseImportDescription',
          icon: Icons.move_up_outlined,
          color: const Color(0xFFC62828),
          route: '/user/profile/system-settings/legacy-import',
          categoryId: 'maintenance',
          order: 2,
          tags: const ['danger'],
          requiresSuperAdmin: true,
        ),
        _item(
          id: 'system_scripts',
          title: 'settingsSystemScripts',
          description: 'settingsSystemScriptsDescription',
          icon: Icons.playlist_play_outlined,
          color: const Color(0xFFC62828),
          route: '/user/profile/system-settings/scripts',
          categoryId: 'maintenance',
          order: 3,
          tags: const ['danger'],
          requiresSuperAdmin: true,
        ),
      ],
    );
  }

  static SettingsItem _item({
    required String id,
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required String route,
    required String categoryId,
    required int order,
    List<String> tags = const [],
    bool requiresSuperAdmin = false,
  }) {
    return SettingsItem(
      id: id,
      title: title,
      description: description,
      icon: icon,
      color: color,
      route: route,
      categoryId: categoryId,
      order: order,
      tags: tags,
      requiresSuperAdmin: requiresSuperAdmin,
    );
  }
}
