import 'package:flutter/material.dart';
import '../models/settings_category.dart';
import '../models/settings_item.dart';

/// سرویس دسته‌بندی تنظیمات سیستم
class SettingsCategorizationService {
  /// ایجاد دسته‌بندی‌های تنظیمات
  static List<SettingsCategory> getCategories() {
    return [
      // دسته 1: پایه و پیکربندی (Core & Configuration)
      SettingsCategory(
        id: 'core_configuration',
        title: 'settingsCategoryCoreConfiguration',
        description: 'settingsCategoryCoreConfigurationDescription',
        icon: Icons.settings_outlined,
        color: const Color(0xFF4CAF50),
        order: 1,
        items: [
          SettingsItem(
            id: 'system_configuration',
            title: 'systemConfiguration',
            description: 'systemConfigurationDescription',
            icon: Icons.settings_outlined,
            color: const Color(0xFF4CAF50),
            route: '/user/profile/system-settings/configuration',
            categoryId: 'core_configuration',
            order: 1,
          ),
          SettingsItem(
            id: 'share_links',
            title: 'settingsShareLinks',
            description: 'settingsShareLinksDescription',
            icon: Icons.link_outlined,
            color: const Color(0xFF8E24AA),
            route: '/user/profile/system-settings/share-links',
            categoryId: 'core_configuration',
            order: 2,
          ),
          SettingsItem(
            id: 'redis_cache',
            title: 'settingsRedisCache',
            description: 'settingsRedisCacheDescription',
            icon: Icons.memory_outlined,
            color: const Color(0xFFDC143C),
            route: '/user/profile/system-settings/redis',
            categoryId: 'core_configuration',
            order: 3,
          ),
          SettingsItem(
            id: 'firewall',
            title: 'settingsFirewall',
            description: 'settingsFirewallDescription',
            icon: Icons.security_outlined,
            color: const Color(0xFF455A64),
            route: '/user/profile/system-settings/firewall',
            categoryId: 'core_configuration',
            order: 4,
          ),
        ],
      ),

      // دسته 2: ذخیره‌سازی و فایل‌ها (Storage & Files)
      SettingsCategory(
        id: 'storage_files',
        title: 'settingsCategoryStorageFiles',
        description: 'settingsCategoryStorageFilesDescription',
        icon: Icons.cloud_upload_outlined,
        color: const Color(0xFF2196F3),
        order: 2,
        items: [
          SettingsItem(
            id: 'storage_management',
            title: 'storageManagement',
            description: 'storageManagementDescription',
            icon: Icons.cloud_upload_outlined,
            color: const Color(0xFF2196F3),
            route: '/user/profile/system-settings/storage',
            categoryId: 'storage_files',
            order: 1,
          ),
          SettingsItem(
            id: 'storage_plans',
            title: 'settingsStoragePlans',
            description: 'settingsStoragePlansDescription',
            icon: Icons.storage_outlined,
            color: const Color(0xFF00BCD4),
            route: '/user/profile/system-settings/storage-plans',
            categoryId: 'storage_files',
            order: 2,
          ),
          SettingsItem(
            id: 'document_monetization',
            title: 'settingsDocumentMonetization',
            description: 'settingsDocumentMonetizationDescription',
            icon: Icons.layers_outlined,
            color: const Color(0xFF26A69A),
            route: '/user/profile/system-settings/document-monetization',
            categoryId: 'storage_files',
            order: 3,
          ),
          SettingsItem(
            id: 'marketplace_plugins',
            title: 'settingsMarketplacePlugins',
            description: 'settingsMarketplacePluginsDescription',
            icon: Icons.extension_outlined,
            color: const Color(0xFF9C27B0),
            route: '/user/profile/system-settings/marketplace-plugins',
            categoryId: 'storage_files',
            order: 4,
          ),
        ],
      ),

      // دسته 3: مالی و پرداخت (Financial & Payment)
      SettingsCategory(
        id: 'financial_payment',
        title: 'settingsCategoryFinancialPayment',
        description: 'settingsCategoryFinancialPaymentDescription',
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFF009688),
        order: 3,
        items: [
          SettingsItem(
            id: 'wallet_settings',
            title: 'settingsWalletSettings',
            description: 'settingsWalletSettingsDescription',
            icon: Icons.account_balance_wallet_outlined,
            color: const Color(0xFF009688),
            route: '/user/profile/system-settings/wallet',
            categoryId: 'financial_payment',
            order: 1,
          ),
          SettingsItem(
            id: 'currencies_admin',
            title: 'settingsCurrenciesAdmin',
            description: 'settingsCurrenciesAdminDescription',
            icon: Icons.currency_exchange_outlined,
            color: const Color(0xFF00796B),
            route: '/user/profile/system-settings/currencies',
            categoryId: 'financial_payment',
            order: 2,
          ),
          SettingsItem(
            id: 'payment_gateways',
            title: 'settingsPaymentGateways',
            description: 'settingsPaymentGatewaysDescription',
            icon: Icons.payment_outlined,
            color: const Color(0xFF3F51B5),
            route: '/user/profile/system-settings/payment-gateways',
            categoryId: 'financial_payment',
            order: 3,
          ),
          SettingsItem(
            id: 'wallet_payouts_admin',
            title: 'settingsWalletPayoutsAdmin',
            description: 'settingsWalletPayoutsAdminDescription',
            icon: Icons.account_balance_outlined,
            color: const Color(0xFF00695C),
            route: '/user/profile/system-settings/wallet-payouts',
            categoryId: 'financial_payment',
            order: 4,
          ),
        ],
      ),

      // دسته 4: کاربران و کسب و کارها (Users & Businesses)
      SettingsCategory(
        id: 'users_businesses',
        title: 'settingsCategoryUsersBusinesses',
        description: 'settingsCategoryUsersBusinessesDescription',
        icon: Icons.people_outlined,
        color: const Color(0xFFFF9800),
        order: 4,
        items: [
          SettingsItem(
            id: 'user_management',
            title: 'userManagement',
            description: 'userManagementDescription',
            icon: Icons.people_outlined,
            color: const Color(0xFFFF9800),
            route: '/user/profile/system-settings/users',
            categoryId: 'users_businesses',
            order: 1,
          ),
          SettingsItem(
            id: 'businesses_management',
            title: 'settingsBusinessesManagement',
            description: 'settingsBusinessesManagementDescription',
            icon: Icons.business_outlined,
            color: const Color(0xFF1976D2),
            route: '/user/profile/system-settings/businesses',
            categoryId: 'users_businesses',
            order: 2,
          ),
          SettingsItem(
            id: 'support_operators',
            title: 'settingsSupportOperators',
            description: 'settingsSupportOperatorsDescription',
            icon: Icons.support_agent_outlined,
            color: const Color(0xFFE91E63),
            route: '/user/profile/system-settings/support-operators',
            categoryId: 'users_businesses',
            order: 3,
          ),
        ],
      ),

      // دسته 5: ارتباطات (Communications)
      SettingsCategory(
        id: 'communications',
        title: 'settingsCategoryCommunications',
        description: 'settingsCategoryCommunicationsDescription',
        icon: Icons.email_outlined,
        color: const Color(0xFFE91E63),
        order: 5,
        items: [
          SettingsItem(
            id: 'email_settings',
            title: 'emailSettings',
            description: 'emailSettingsDescription',
            icon: Icons.email_outlined,
            color: const Color(0xFFE91E63),
            route: '/user/profile/system-settings/email',
            categoryId: 'communications',
            order: 1,
          ),
          SettingsItem(
            id: 'announcements',
            title: 'settingsAnnouncements',
            description: 'settingsAnnouncementsDescription',
            icon: Icons.notifications_active_outlined,
            color: const Color(0xFF795548),
            route: '/user/profile/system-settings/announcements',
            categoryId: 'communications',
            order: 2,
          ),
          SettingsItem(
            id: 'notifications',
            title: 'settingsNotifications',
            description: 'settingsNotificationsDescription',
            icon: Icons.notifications_outlined,
            color: const Color(0xFF607D8B),
            route: '/user/profile/system-settings/notifications',
            categoryId: 'communications',
            order: 3,
          ),
          SettingsItem(
            id: 'notification_templates',
            title: 'settingsNotificationTemplates',
            description: 'settingsNotificationTemplatesDescription',
            icon: Icons.description_outlined,
            color: const Color(0xFF455A64),
            route: '/user/profile/system-settings/notification-templates',
            categoryId: 'communications',
            order: 4,
          ),
          SettingsItem(
            id: 'notification_moderation',
            title: 'settingsNotificationModeration',
            description: 'settingsNotificationModerationDescription',
            icon: Icons.rule_outlined,
            color: const Color(0xFFFF6F00),
            route: '/user/profile/system-settings/notification-moderation',
            categoryId: 'communications',
            order: 5,
            requiresSuperAdmin: true,
          ),
          SettingsItem(
            id: 'notification_sms_pricing',
            title: 'settingsNotificationSmsPricing',
            description: 'settingsNotificationSmsPricingDescription',
            icon: Icons.price_check_outlined,
            color: const Color(0xFF4CAF50),
            route: '/user/profile/system-settings/notification-sms-pricing',
            categoryId: 'communications',
            order: 6,
            requiresSuperAdmin: true,
          ),
        ],
      ),

      // دسته 6: هوش مصنوعی (Artificial Intelligence)
      SettingsCategory(
        id: 'ai',
        title: 'settingsCategoryAI',
        description: 'settingsCategoryAIDescription',
        icon: Icons.smart_toy_outlined,
        color: const Color(0xFF9C27B0),
        order: 6,
        items: [
          SettingsItem(
            id: 'ai_settings',
            title: 'settingsAISettings',
            description: 'settingsAISettingsDescription',
            icon: Icons.smart_toy_outlined,
            color: const Color(0xFF9C27B0),
            route: '/user/profile/system-settings/ai-settings',
            categoryId: 'ai',
            order: 1,
          ),
          SettingsItem(
            id: 'ai_plans',
            title: 'settingsAIPlans',
            description: 'settingsAIPlansDescription',
            icon: Icons.subscriptions_outlined,
            color: const Color(0xFF673AB7),
            route: '/user/profile/system-settings/ai-plans',
            categoryId: 'ai',
            order: 2,
          ),
          SettingsItem(
            id: 'ai_prompts',
            title: 'settingsAIPrompts',
            description: 'settingsAIPromptsDescription',
            icon: Icons.text_fields_outlined,
            color: const Color(0xFF5E35B1),
            route: '/user/profile/system-settings/ai-prompts',
            categoryId: 'ai',
            order: 3,
          ),
        ],
      ),

      // دسته 7: سرویس‌های خارجی (External Services)
      SettingsCategory(
        id: 'external_services',
        title: 'settingsCategoryExternalServices',
        description: 'settingsCategoryExternalServicesDescription',
        icon: Icons.search_outlined,
        color: const Color(0xFF00ACC1),
        order: 7,
        items: [
          SettingsItem(
            id: 'zohal_services',
            title: 'settingsZohalServices',
            description: 'settingsZohalServicesDescription',
            icon: Icons.search_outlined,
            color: const Color(0xFF00ACC1),
            route: '/user/profile/system-settings/zohal-services',
            categoryId: 'external_services',
            order: 1,
          ),
          SettingsItem(
            id: 'zohal_settings',
            title: 'settingsZohalSettings',
            description: 'settingsZohalSettingsDescription',
            icon: Icons.settings_outlined,
            color: const Color(0xFF00897B),
            route: '/user/profile/system-settings/zohal-settings',
            categoryId: 'external_services',
            order: 2,
          ),
          SettingsItem(
            id: 'tax_product_codes',
            title: 'settingsTaxProductCodes',
            description: 'settingsTaxProductCodesDescription',
            icon: Icons.qr_code_2_outlined,
            color: const Color(0xFF00695C),
            route: '/user/profile/system-settings/tax-product-codes',
            categoryId: 'external_services',
            order: 3,
          ),
        ],
      ),

      // دسته 8: مانیتورینگ و لاگ‌ها (Monitoring & Logs)
      SettingsCategory(
        id: 'monitoring_logs',
        title: 'settingsCategoryMonitoringLogs',
        description: 'settingsCategoryMonitoringLogsDescription',
        icon: Icons.monitor_heart_outlined,
        color: const Color(0xFFFF6B35),
        order: 8,
        items: [
          SettingsItem(
            id: 'system_monitoring',
            title: 'settingsSystemMonitoring',
            description: 'settingsSystemMonitoringDescription',
            icon: Icons.monitor_heart_outlined,
            color: const Color(0xFFFF6B35),
            route: '/user/profile/system-settings/monitoring',
            categoryId: 'monitoring_logs',
            order: 1,
          ),
          SettingsItem(
            id: 'system_logs',
            title: 'systemLogs',
            description: 'systemLogsDescription',
            icon: Icons.analytics_outlined,
            color: const Color(0xFF9C27B0),
            route: '/user/profile/system-settings/logs',
            categoryId: 'monitoring_logs',
            order: 2,
          ),
          SettingsItem(
            id: 'service_logs',
            title: 'settingsServiceLogs',
            description: 'settingsServiceLogsDescription',
            icon: Icons.terminal_outlined,
            color: const Color(0xFF607D8B),
            route: '/user/profile/system-settings/service-logs',
            categoryId: 'monitoring_logs',
            order: 3,
          ),
          SettingsItem(
            id: 'database_backup',
            title: 'settingsDatabaseBackup',
            description: 'settingsDatabaseBackupDescription',
            icon: Icons.backup_outlined,
            color: const Color(0xFF37474F),
            route: '/user/profile/system-settings/database-backup',
            categoryId: 'monitoring_logs',
            order: 4,
            requiresSuperAdmin: true,
          ),
          SettingsItem(
            id: 'system_scripts',
            title: 'settingsSystemScripts',
            description: 'settingsSystemScriptsDescription',
            icon: Icons.playlist_play_outlined,
            color: const Color(0xFF6A1B9A),
            route: '/user/profile/system-settings/scripts',
            categoryId: 'monitoring_logs',
            order: 5,
            requiresSuperAdmin: true,
          ),
        ],
      ),
    ];
  }

  /// دریافت همه آیتم‌های تنظیمات به صورت یک لیست صاف
  static List<SettingsItem> getAllItems() {
    return getCategories().expand((category) => category.items).toList();
  }

  /// جستجو در تنظیمات
  static List<SettingsItem> searchItems(String query, {List<SettingsCategory>? categories}) {
    final searchCategories = categories ?? getCategories();
    final lowerQuery = query.toLowerCase().trim();

    if (lowerQuery.isEmpty) {
      return getAllItems();
    }

    final allItems = searchCategories.expand((category) => category.items).toList();

    return allItems.where((item) {
      // اینجا باید localization استفاده شود، فعلاً فقط بر اساس ID جستجو می‌کنیم
      return item.id.toLowerCase().contains(lowerQuery) ||
          item.title.toLowerCase().contains(lowerQuery) ||
          item.description.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// فیلتر بر اساس دسته
  static List<SettingsItem> filterByCategory(String categoryId) {
    final categories = getCategories();
    final category = categories.firstWhere(
      (cat) => cat.id == categoryId,
      orElse: () => categories.first,
    );
    return category.items;
  }
}

